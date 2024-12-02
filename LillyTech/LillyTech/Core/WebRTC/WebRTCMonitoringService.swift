import WebRTC
import OSLog

protocol StatisticsReportProviding {
    var statistics: [String: RTCStatistics] { get }
}

extension RTCStatisticsReport: StatisticsReportProviding {}

protocol WebRTCMonitoringDelegate: AnyObject {
    func connectionStateDidChange(_ state: WebRTCConnectionState)
    func connectionQualityDidChange(_ metrics: ConnectionQualityMetrics)
}

final class WebRTCMonitoringService {
    weak var delegate: WebRTCMonitoringDelegate?
    private let logger = Logger(subsystem: "com.Transearly.LillyTech", category: "WebRTCMonitoring")
    internal var statsTimer: Timer? // Changed from private to internal
    private weak var peerConnection: PeerConnectionBase?
    
    private(set) var currentState: WebRTCConnectionState = .new {
        didSet {
            if oldValue != self.currentState {
                self.logger.debug("Connection state changed: \(String(describing: self.currentState))")
                self.delegate?.connectionStateDidChange(self.currentState)
            }
        }
    }
    
    init(peerConnection: PeerConnectionBase) {
        self.peerConnection = peerConnection
        startMonitoring()
    }
    
    func startMonitoring() {
        statsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
    }
    
    func stopMonitoring() {
        statsTimer?.invalidate()
        statsTimer = nil
    }
    
    func updateConnectionState(_ rtcState: RTCPeerConnectionState) {
        currentState = WebRTCConnectionState(from: rtcState)
    }
    
    private func updateStats() {
        peerConnection?.statistics { [weak self] report in
            guard let self = self else { return }
            
            var bitrate: Double = 0
            var packetLoss: Double = 0
            var roundTripTime: TimeInterval = 0
            
            // Process outbound RTP statistics
            for (_, stats) in report.statistics {
                switch stats.type {
                case "outbound-rtp":
                    if let bytesSent = stats.values["bytesSent"] as? NSNumber {
                        bitrate = bytesSent.doubleValue * 8 / 1000
                    }
                    if let packetsLostNum = stats.values["packetsLost"] as? NSNumber {
                        packetLoss = packetsLostNum.doubleValue
                    }
                case "candidate-pair":
                    if let rttNum = stats.values["currentRoundTripTime"] as? NSNumber {
                        roundTripTime = rttNum.doubleValue
                    }
                default:
                    break
                }
            }
            
            let metrics = ConnectionQualityMetrics(
                bitrate: bitrate,
                packetLoss: packetLoss,
                roundTripTime: roundTripTime
            )
            
            self.delegate?.connectionQualityDidChange(metrics)
        }
    }
}
