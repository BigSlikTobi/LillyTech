import Foundation
import AVFAudio
import OSLog
import Combine
import UIKit

/// Errors specific to audio session management
public enum AudioSessionError: Error {
    case configurationFailed(underlying: Error)
    case activationFailed(underlying: Error)
    case deactivationFailed(underlying: Error)
    case invalidState(description: String)
    case permissionDenied
    case routeChangeFailed(reason: String)
    case categorySettingFailed(category: AVAudioSession.Category, error: Error)
    case modeSettingFailed(mode: AVAudioSession.Mode, error: Error)
    case mediaServerReset
}

/// Extends `AudioSessionError` to conform to the `LocalizedError` protocol,
/// providing localized error descriptions for audio session-related issues.
extension AudioSessionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .configurationFailed(let error):
            return "Failed to configure audio session: \(error.localizedDescription)"
        case .activationFailed(let error):
            return "Failed to activate audio session: \(error.localizedDescription)"
        case .deactivationFailed(let error):
            return "Failed to deactivate audio session: \(error.localizedDescription)"
        case .invalidState(let description):
            return "Invalid audio session state: \(description)"
        case .permissionDenied:
            return "Microphone permission denied"
        case .routeChangeFailed(let reason):
            return "Audio route change failed: \(reason)"
        case .categorySettingFailed(let category, let error):
            return "Failed to set audio category \(category): \(error.localizedDescription)"
        case .modeSettingFailed(let mode, let error):
            return "Failed to set audio mode \(mode): \(error.localizedDescription)"
        case .mediaServerReset:
            return "Audio session interrupted by media server reset"
        }
    }
}

/// Protocol defining the core functionality for managing audio sessions in a WebRTC context
public protocol AudioSessionManaging {
    /// Starts the audio session with appropriate configuration for voice chat
    /// - Returns: Success or failure with associated error
    func start() -> Result<Void, AudioSessionError>
    
    /// Stops the audio session and releases resources
    /// - Returns: Success or failure with associated error
    func stop() -> Result<Void, AudioSessionError>
    
    /// Configures the audio session specifically for WebRTC voice chat
    /// Sets up appropriate category, mode, and options for VoIP calls
    /// - Returns: Success or failure with associated error
    func configureForVoiceChat() -> Result<Void, AudioSessionError>
    
    /// Handles audio session interruptions (e.g., phone calls, Siri)
    /// - Parameter notification: System notification containing interruption details
    func handleInterruption(notification: Notification)
    
    /// Handles audio route changes (e.g., headphones connected/disconnected)
    /// - Parameter notification: System notification containing route change details
    func handleRouteChange(notification: Notification)
}

// Extension to provide default implementation for notification handling
public extension AudioSessionManaging {
    func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            _ = stop()
        case .ended:
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            
            if options.contains(.shouldResume) {
                _ = start()
            }
        @unknown default:
            break
        }
    }
    
    /// Handles audio route changes by responding to the provided notification.
    /// - Parameter notification: The notification containing information about the route change.
    func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable:
            _ = configureForVoiceChat()
        default:
            break
        }
    }
}

// MARK: - Protocols for Dependency Injection
protocol AudioSessionProtocol {
    func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) throws
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
    var isOtherAudioPlaying: Bool { get }
    func requestRecordPermission(_ response: @escaping (Bool) -> Void)
    var currentRoute: AVAudioSessionRouteDescription { get }
}

// Extend AVAudioSession to conform to AudioSessionProtocol
extension AVAudioSession: AudioSessionProtocol {}

// Extend AppLogger to conform to LoggerProtocol
extension AppLogger: LoggerProtocol {}

/// Manages the audio session, handling configuration and control of audio-related functionalities within the app.
final class AudioSessionManager {
    // MARK: - Dependencies
    private let audioSession: AudioSessionProtocol
    private let logger: LoggerProtocol
    private var isConfigured = false

    // MARK: - Initialization
    init(audioSession: AudioSessionProtocol = AVAudioSession.sharedInstance(),
         logger: LoggerProtocol = AppLogger.shared) {
        self.audioSession = audioSession
        self.logger = logger
    }

    // MARK: - Public Methods

    /// Configures the audio session for the application. This includes setting the
    /// appropriate audio category, mode, and handling any potential errors that 
    /// may occur during the configuration process.
    func configureAudioSession() throws {
        guard !isConfigured else { return }
        
        do {
            try audioSession.setCategory(.playAndRecord,
                                       mode: .voiceChat,
                                       options: [.allowBluetooth, .defaultToSpeaker])
            try audioSession.setActive(true, options: [])
            isConfigured = true
            logger.debug("Audio session configured successfully", category: AppLogger.shared.network)
        } catch {
            logger.error("Failed to configure audio session: \(error.localizedDescription)", 
                          category: AppLogger.shared.network)
            throw error
        }
    }
    
    /**
     Deactivates the audio session.
     
     This function attempts to deactivate the current audio session. 
     It performs necessary cleanup and ensures that the audio session is properly released. 
     If the deactivation fails, an error is thrown.
     
     - Throws: An error describing why the audio session could not be deactivated.
     */
    func deactivateAudioSession() throws {
        guard isConfigured else { return }
        
        do {
            try audioSession.setActive(false, options: [])
            isConfigured = false
            logger.debug("Audio session deactivated", category: AppLogger.shared.network)
        } catch {
            logger.error("Failed to deactivate audio session: \(error.localizedDescription)", 
                          category: AppLogger.shared.network)
            throw error
        }
    }
    
    // MARK: - State Methods
    var isSessionActive: Bool {
        audioSession.isOtherAudioPlaying
    }
    
    /// Requests permission to record audio from the user.
    ///
    /// - Parameter completion: A closure that is called with a Boolean value
    ///   indicating whether the permission was granted.
    func requestRecordPermission(_ completion: @escaping (Bool) -> Void) {
        audioSession.requestRecordPermission { granted in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                completion(granted)
                self.logger.info("Microphone permission \(granted ? "granted" : "denied")", 
                             category: AppLogger.shared.network)
            }
        }
    }
}

/// Extension of `AudioSessionManager` to conform to the `AudioSessionManaging` protocol.
/// This extension implements the necessary methods and properties to manage audio sessions,
/// ensuring proper configuration and handling of audio-related functionalities within the application.
extension AudioSessionManager: AudioSessionManaging {
    func start() -> Result<Void, AudioSessionError> {
        do {
            try configureAudioSession()
            return .success(())
        } catch let error as AudioSessionError {
            logger.error("Audio session start failed: \(error.localizedDescription)", category: AppLogger.shared.network)
            return .failure(error)
        } catch {
            let wrappedError = AudioSessionError.activationFailed(underlying: error)
            logger.error("Audio session start failed: \(wrappedError.localizedDescription)", category: AppLogger.shared.network)
            return .failure(wrappedError)
        }
    }
    
    /// Stops the audio session and returns a `Result` indicating whether the operation was successful 
    /// or failed with an `AudioSessionError`.
    /// - Returns: A `Result` with `Void` on success or an `AudioSessionError` on failure.
    func stop() -> Result<Void, AudioSessionError> {
        do {
            try deactivateAudioSession()
            return .success(())
        } catch let error as AudioSessionError {
            logger.error("Audio session stop failed: \(error.localizedDescription)", category: AppLogger.shared.network)
            return .failure(error)
        } catch {
            let wrappedError = AudioSessionError.deactivationFailed(underlying: error)
            logger.error("Audio session stop failed: \(wrappedError.localizedDescription)", category: AppLogger.shared.network)
            return .failure(wrappedError)
        }
    }
    
    /// Configures the audio session for voice chat usage.
    ///
    /// - Returns: A `Result` indicating success or an `AudioSessionError`.
    func configureForVoiceChat() -> Result<Void, AudioSessionError> {
        do {
            try audioSession.setCategory(.playAndRecord,
                                       mode: .voiceChat,
                                       options: [.allowBluetooth, .defaultToSpeaker])
            return .success(())
        } catch {
            let wrappedError = AudioSessionError.configurationFailed(underlying: error)
            logger.error("Voice chat configuration failed: \(wrappedError.localizedDescription)", category: AppLogger.shared.network)
            return .failure(wrappedError)
        }
    }
}

/// Manages and publishes audio session state changes for WebRTC applications
final class AudioSessionState: ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var isActive = false
    @Published private(set) var currentRoute = AVAudioSession.sharedInstance().currentRoute
    @Published private(set) var interruptionType: AVAudioSession.InterruptionType?
    
    // MARK: - Private Properties
    private let audioSession = AVAudioSession.sharedInstance()
    private var cancellables = Set<AnyCancellable>()
    
    // Remove logger property as we'll use AppLogger.shared
    
    // MARK: - Initialization
    init() {
        setupNotificationObservers()
        setupLifecycleObservers()
        AppLogger.shared.info("Audio session state initialized", category: AppLogger.shared.audio)
    }
    
    // MARK: - Private Methods

    /// Sets up observers for various audio session notifications.
    private func setupNotificationObservers() {
        // Route change notifications
        NotificationCenter.default
            .publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] notification in
                guard let self = self else { return }
                self.handleRouteChange(notification)
            }
            .store(in: &cancellables)
        
        // Interruption notifications
        NotificationCenter.default
            .publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notification in
                guard let self = self else { return }
                self.handleInterruption(notification)
            }
            .store(in: &cancellables)
        
        // Media server reset notifications
        NotificationCenter.default
            .publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.handleMediaServerReset()
            }
            .store(in: &cancellables)
    }
    
    /// Handles changes to the audio route in response to system notifications.
    ///
    /// - Parameter notification: The notification object containing details about the route change.
    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            AppLogger.shared.error("Invalid route change notification data", category: AppLogger.shared.audio)
            return
        }
        
        currentRoute = audioSession.currentRoute
        AppLogger.shared.info("Audio route changed: \(self.routeChangeDescription(reason))", 
                      category: AppLogger.shared.audio)
    }
    
    /// Handles audio session interruptions by managing the necessary state and resources.
    /// - Parameter notification: The notification detailing the interruption event.
    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            AppLogger.shared.error("Invalid interruption notification data", category: AppLogger.shared.audio)
            return
        }
        
        interruptionType = type
        isActive = type != .began
        AppLogger.shared.info("Audio session interruption: \(self.interruptionDescription(type))", 
                      category: AppLogger.shared.audio)
    }
    
    /// Handles the media server reset by reinitializing the audio session and restoring necessary settings.
    private func handleMediaServerReset() {
        isActive = audioSession.isOtherAudioPlaying
        currentRoute = audioSession.currentRoute
        AppLogger.shared.warning("Media server reset occurred", category: AppLogger.shared.audio)
    }
}
/// Extension to provide additional functionality for managing audio session state changes.
extension AudioSessionState {
    // MARK: - Lifecycle Notification Setup
    private func setupLifecycleObservers() {
        // Background notification
        NotificationCenter.default
            .publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.handleBackgroundTransition()
            }
            .store(in: &cancellables)
        
        // Foreground notification
        NotificationCenter.default
            .publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.handleForegroundTransition()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Private Lifecycle Methods

    /// Handles the transition to the background by deactivating the audio session.
    private func handleBackgroundTransition() {
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            isActive = false
            AppLogger.shared.info("Audio session deactivated for background", category: AppLogger.shared.audio)
        } catch {
            AppLogger.shared.error("Failed to deactivate audio session for background", 
                          category: AppLogger.shared.audio)
        }
    }
    
    /// Handles the transition to the foreground by reactivating the audio session.
    private func handleForegroundTransition() {
        do {
            try audioSession.setActive(true)
            isActive = true
            currentRoute = audioSession.currentRoute
            AppLogger.shared.info("Audio session reactivated for foreground", 
                          category: AppLogger.shared.audio)
        } catch {
            AppLogger.shared.error("Failed to reactivate audio session for foreground", 
                          category: AppLogger.shared.audio)
        }
    }
    
    /// Provides a human-readable description of the route change reason. 
    private func routeChangeDescription(_ reason: AVAudioSession.RouteChangeReason) -> String {
        switch reason {
        case .newDeviceAvailable:
            return "New audio device became available"
        case .oldDeviceUnavailable:
            return "Audio device became unavailable"
        case .categoryChange:
            return "Audio session category changed"
        case .override:
            return "Route overridden"
        case .wakeFromSleep:
            return "Device woke from sleep"
        case .noSuitableRouteForCategory:
            return "No suitable route found for category"
        case .routeConfigurationChange:
            return "Route configuration changed"
        case .unknown:
            return "Unknown route change"
        @unknown default:
            return "Unexpected route change"
        }
    }
    
    /// Provides a human-readable description of the audio session interruption type.
    private func interruptionDescription(_ type: AVAudioSession.InterruptionType) -> String {
        switch type {
        case .began:
            return "Interruption began"
        case .ended:
            return "Interruption ended"
        @unknown default:
            return "Unknown interruption"
        }
    }
}