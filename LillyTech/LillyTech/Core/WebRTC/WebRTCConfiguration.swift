import WebRTC
import Foundation

protocol WebRTCConfigurable {
    var configuration: RTCConfiguration { get }
    var defaultConstraints: RTCMediaConstraints { get }
}

/// Represents a single STUN/TURN server configuration
struct ICEServer {
    let urls: [String]
    let region: Region
    let priority: Int
    let timeout: TimeInterval
    let healthCheckInterval: TimeInterval
    let gatheringTimeout: TimeInterval
    
    enum Region: String {
        case northAmerica = "NA"
        case europe = "EU"
        case asiaPacific = "APAC"
        case global = "GLOBAL"
    }
    
    // Add monitoring metrics
    class Metrics {
        let atomicResponseTime = AtomicProperty<TimeInterval>(0)
        let atomicSuccessRate = AtomicProperty<Double>(100)
        let atomicLastCheck = AtomicProperty<Date>(Date())
        let atomicIsHealthy = AtomicProperty<Bool>(true)
    }
    
    var metrics: Metrics = Metrics()
    
    init(urls: [String], region: Region, priority: Int, timeout: TimeInterval, 
         healthCheckInterval: TimeInterval, gatheringTimeout: TimeInterval = 5.0) {
        self.urls = urls
        self.region = region
        self.priority = priority
        self.timeout = timeout
        self.healthCheckInterval = healthCheckInterval
        self.gatheringTimeout = gatheringTimeout
    }
}

struct WebRTCConfiguration: WebRTCConfigurable {
    /// Default gathering timeout in seconds
    let defaultGatheringTimeout: TimeInterval = 5.0
    
    /// Ordered list of ICE servers with geographical distribution and health monitoring
    private let iceServers: [ICEServer] = [
        ICEServer(
            urls: ["stun:stun.l.google.com:19302"],
            region: .global,
            priority: 100,
            timeout: 3.0,
            healthCheckInterval: 30.0
        ),
        ICEServer(
            urls: ["stun:stun1.l.google.com:19302"],
            region: .northAmerica,
            priority: 90,
            timeout: 3.0,
            healthCheckInterval: 30.0
        ),
        ICEServer(
            urls: ["stun:stun2.l.google.com:19302"],
            region: .europe,
            priority: 80,
            timeout: 3.0,
            healthCheckInterval: 30.0
        ),
        ICEServer(
            urls: ["stun:stun3.l.google.com:19302"],
            region: .asiaPacific,
            priority: 70,
            timeout: 3.0,
            healthCheckInterval: 30.0
        ),
        ICEServer(
            urls: ["stun:stun4.l.google.com:19302"],
            region: .asiaPacific,
            priority: 60,
            timeout: 3.0,
            healthCheckInterval: 30.0
        )
    ]
    
    var configuration: RTCConfiguration {
        let config = RTCConfiguration()
        
        // Convert ICEServer array to RTCIceServer array with prioritization
        config.iceServers = iceServers
            .sorted { $0.priority > $1.priority }
            .map { server in
                RTCIceServer(urlStrings: server.urls)
            }
        
        // Set ICE timeout interval for the entire configuration
        config.iceConnectionReceivingTimeout = Int32(iceServers.first?.timeout ?? 3.0)
        
        // Configure connection policies
        config.bundlePolicy = .maxBundle
        config.rtcpMuxPolicy = .require
        config.tcpCandidatePolicy = .disabled
        config.continualGatheringPolicy = .gatherOnce
        config.keyType = .ECDSA
        
        // Set gathering policy
        config.continualGatheringPolicy = .gatherOnce
        
        // Ice transport policy
        config.iceTransportPolicy = .all
        
        return config
    }
    
    var defaultConstraints: RTCMediaConstraints {
        return RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "false"
            ],
            optionalConstraints: [
                "DtlsSrtpKeyAgreement": "true",
                "RtpDataChannels": "true"
            ]
        )
    }
    
    // Add monitoring extension
    class ServerMonitor {
        private let logger = AppLogger.shared.webrtc
        private let checkInterval: TimeInterval = 30.0
        private let healthyThreshold: Double = 0.8
        private var monitoringTimer: Timer?
        
        func startMonitoring(servers: [ICEServer]) {
            monitoringTimer?.invalidate()
            monitoringTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
                self?.checkServers(servers)
            }
            logger.info("WebRTC server monitoring started", category: AppLogger.shared.general)
        }
        
        private func checkServers(_ servers: [ICEServer]) {
            for server in servers {
                Task {
                    let startTime = Date()
                    do {
                        try await checkServerHealth(server)
                        let responseTime = Date().timeIntervalSince(startTime)
                        updateMetrics(server, responseTime: responseTime, success: true)
                    } catch {
                        updateMetrics(server, responseTime: 0, success: false)
                    }
                }
            }
        }
        
        internal func updateMetrics(_ server: ICEServer, responseTime: TimeInterval, success: Bool) {
            server.metrics.atomicResponseTime.set(responseTime)
            
            let currentRate = server.metrics.atomicSuccessRate.get()
            let newRate = (currentRate * 0.7) + (success ? 30 : 0)
            server.metrics.atomicSuccessRate.set(newRate)
            server.metrics.atomicLastCheck.set(Date())
            
            let isHealthy = newRate >= (healthyThreshold * 100)
            let wasHealthy = server.metrics.atomicIsHealthy.get()
            
            if isHealthy != wasHealthy {
                server.metrics.atomicIsHealthy.set(isHealthy)
                logger.warning("Server \(server.urls.first ?? "unknown") health changed to \(isHealthy ? "healthy" : "unhealthy")", category: AppLogger.shared.general)
            }
            
            logger.debug("""
                Server metrics updated:
                URL: \(server.urls.first ?? "unknown")
                Response Time: \(responseTime)ms
                Success Rate: \(newRate)%
                Health: \(isHealthy ? "healthy" : "unhealthy")
                """, category: AppLogger.shared.general)
        }
        
        private func checkServerHealth(_ server: ICEServer) async throws {
            // Implement actual health check logic here
            // This could involve:
            // 1. STUN binding request
            // 2. DNS resolution check
            // 3. Basic connectivity test
        }
        
        func stopMonitoring() {
            monitoringTimer?.invalidate()
            monitoringTimer = nil
            logger.info("WebRTC server monitoring stopped", category: AppLogger.shared.general)
        }
    }
    
    private var monitor: ServerMonitor?
    
    mutating func startMonitoring() {
        monitor = ServerMonitor()
        monitor?.startMonitoring(servers: iceServers)
    }
    
    mutating func stopMonitoring() {
        monitor?.stopMonitoring()
        monitor = nil
    }
}

/// Extension to handle server health monitoring and selection
private extension WebRTCConfiguration {
    /// Strategy for selecting optimal ICE servers based on:
    /// - Geographic proximity to client
    /// - Current server health status
    /// - Server response times
    /// - Regional failover preferences
    ///
    /// The selection process follows these steps:
    /// 1. Filter out unhealthy or timing-out servers
    /// 2. Prioritize servers in the client's region
    /// 3. Include at least one server from each region for redundancy
    /// 4. Maintain the global servers as fallback
    ///
    /// Health checks are performed periodically using the configured
    /// healthCheckInterval to ensure server availability.
    func selectOptimalServers() -> [ICEServer] {
        // Implementation would go here
        // This is just the structure for documentation
        return iceServers
    }
}

// Add atomic property wrapper for thread safety
final class AtomicProperty<T> {
    private var value: T
    private let queue = DispatchQueue(label: "com.lillytech.atomic")
    
    init(_ value: T) {
        self.value = value
    }
    
    func get() -> T {
        queue.sync { value }
    }
    
    func set(_ newValue: T) {
        queue.sync { value = newValue }
    }
}
