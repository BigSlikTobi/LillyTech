import WebRTC
import Foundation

protocol WebRTCConnectionMonitorDelegate: AnyObject {
    func connectionQualityDidChange(_ quality: WebRTCConnectionMonitor.ConnectionQuality)
    func connectionStateDidChange(_ state: RTCPeerConnectionState)
}

final class WebRTCConnectionMonitor {
    enum ConnectionQuality: String {
        case excellent
        case good
        case fair
        case poor
        case failed
    }
    
    struct ConnectionMetrics {
        let roundTripTime: TimeInterval
        let packetLoss: Double
        let jitter: TimeInterval
        let timestamp: Date
    }
    
    weak var delegate: WebRTCConnectionMonitorDelegate?
    private let logger = AppLogger.shared.webrtc
    private let connection: PeerConnection
    private let metricsQueue = DispatchQueue(label: "com.lillytech.webrtc.metrics")
    
    private var connectionHistory: [RTCPeerConnectionState] = []
    private var metricsHistory: [ConnectionMetrics] = []
    private var currentQuality: ConnectionQuality = .good
    private var monitoringTimer: Timer?
    
    init(connection: PeerConnection) {
        self.connection = connection
        setupMonitoring()
    }
    
    private func setupMonitoring() {
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.collectMetrics()
        }
    }
    
    private func collectMetrics() {
        connection.statistics { [weak self] report in
            self?.processStatistics(report)
        }
    }
    
    private func processStatistics(_ report: RTCStatisticsReport) {
        metricsQueue.async { [weak self] in
            guard let self = self else { return }
            
            var rtt: TimeInterval = 0
            var packetLoss: Double = 0
            var jitter: TimeInterval = 0
            
            report.statistics.forEach { _, stats in
                if stats.type == "candidate-pair" {
                    rtt = TimeInterval(stats.values["currentRoundTripTime"] as? Double ?? 0)
                } else if stats.type == "inbound-rtp" {
                    packetLoss = stats.values["packetsLost"] as? Double ?? 0
                    jitter = TimeInterval(stats.values["jitter"] as? Double ?? 0)
                }
            }
            
            let metrics = ConnectionMetrics(
                roundTripTime: rtt,
                packetLoss: packetLoss,
                jitter: jitter,
                timestamp: Date()
            )
            
            self.updateMetrics(metrics)
        }
    }
    
    private func updateMetrics(_ metrics: ConnectionMetrics) {
        metricsHistory.append(metrics)
        if metricsHistory.count > 50 {
            metricsHistory.removeFirst()
        }
        
        let quality = calculateConnectionQuality(metrics)
        if quality != currentQuality {
            currentQuality = quality
            DispatchQueue.main.async {
                self.delegate?.connectionQualityDidChange(quality)
            }
        }
    }
    
    private func calculateConnectionQuality(_ metrics: ConnectionMetrics) -> ConnectionQuality {
        // RTT thresholds (ms)
        let rttExcellent = 0.1
        let rttGood = 0.2
        let rttFair = 0.3
        
        // Packet loss thresholds (%)
        let lossExcellent = 0.5
        let lossGood = 2.0
        let lossFair = 5.0
        
        if metrics.roundTripTime <= rttExcellent && metrics.packetLoss <= lossExcellent {
            return .excellent
        } else if metrics.roundTripTime <= rttGood && metrics.packetLoss <= lossGood {
            return .good
        } else if metrics.roundTripTime <= rttFair && metrics.packetLoss <= lossFair {
            return .fair
        } else if connection.connectionState == .failed {
            return .failed
        } else {
            return .poor
        }
    }
    
    func updateConnectionState(_ state: RTCPeerConnectionState) {
        connectionHistory.append(state)
        if connectionHistory.count > 20 {
            connectionHistory.removeFirst()
        }
        
        logger.info("""
            Connection state changed:
            Current: \(state.rawValue)
            History: \(connectionHistory.map { $0.rawValue })
            Quality: \(currentQuality.rawValue)
            """, category: AppLogger.shared.general)
    }
    
    
    func stop() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        metricsHistory.removeAll()
        connectionHistory.removeAll()
    }
    
    deinit {
        stop()
    }
}
