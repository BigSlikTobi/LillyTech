import WebRTC

protocol WebRTCConfigurable {
    var configuration: RTCConfiguration { get }
    var defaultConstraints: RTCMediaConstraints { get }
}

struct WebRTCConfiguration: WebRTCConfigurable {
    private let stunServers = [
        "stun:stun.l.google.com:19302",
        "stun:stun1.l.google.com:19302",
        "stun:stun2.l.google.com:19302",
        "stun:stun3.l.google.com:19302",
        "stun:stun4.l.google.com:19302"
    ]
    
    var configuration: RTCConfiguration {
        let config = RTCConfiguration()
        config.iceServers = stunServers.map { urlString in
            RTCIceServer(urlStrings: [urlString])
        }
        
        // Configure connection policies
        config.bundlePolicy = .maxBundle
        config.rtcpMuxPolicy = .require
        config.tcpCandidatePolicy = .disabled
        config.continualGatheringPolicy = .gatherContinually
        config.keyType = .ECDSA
        
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
}
