# LillyTech

Real-time translation application using WebRTC for iOS.

## Project Status

### Completed ✅
- Repository setup and project structure
- WebRTC integration
- Basic logging system
- Initial testing infrastructure
- Core WebRTC service implementation

### In Progress 🚧
- Translation feature
- User interface implementation
- Signaling server integration

## Requirements

- iOS 15.0+
- Xcode 15+
- Swift 5.9+

## Dependencies

- WebRTC ([stasel/WebRTC](https://github.com/stasel/WebRTC.git))
- OSLog (System Framework)

## Project Structure

```
LillyTech/
├── App/
│   └── LillyTechApp.swift
├── Features/
│   ├── Translation/
│   ├── Settings/
│   └── Common/
├── Core/
│   ├── Logger/
│   │   └── AppLogger.swift
│   └── WebRTC/
│       ├── WebRTCService.swift
│       └── WebRTCServiceImpl.swift
└── Resources/
```

## Setup Instructions

1. Clone the repository
```bash
git clone [repository-url]
```

2. Open `LillyTech.xcodeproj`
3. Build and run

## Development

### Branch Strategy
- Branch from `develop` for new features
- Create pull requests for feature merges
- Follow commit message format: `<type>: <description>`

### Testing
Run tests using:
- Xcode: `⌘U`
- Command line: `xcodebuild test`

Current test coverage includes:
- WebRTC service integration tests
- Logger functionality tests
- Basic UI tests
- Core functionality unit tests

## Logging

The application uses OSLog for system-integrated logging with different categories:
- General: Application-wide logs
- Network: WebRTC and connection logs
- UI: Interface-related logs

## WebRTC Implementation

Current WebRTC features:
- Peer connection management
- Audio session handling
- Connection state management
- SDP offer/answer process
- ICE candidate handling

## Documentation

Additional documentation:
- [GitHub Workflow Guide](docs/workflow.md)
- [Project Structure](docs/structure.md)
- [Development Guidelines](docs/guidelines.md)

## Next Steps

1. Signaling Server Integration
   - WebSocket connection
   - Connection state management
   - Signaling protocol

2. Audio Stream Implementation
   - Audio capture
   - Stream processing
   - Translation integration

3. User Interface Development
   - Main interface
   - Connection controls
   - Status indicators
