# LillyTech

Real-time translation application using WebRTC for iOS.

## Project Status

- [x] Repository setup
- [x] Project structure configuration
- [x] WebRTC integration
- [x] Basic logging system
- [ ] Translation feature
- [ ] User interface
- [ ] Testing suite completion

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
├── Features/
│   ├── Translation/
│   ├── Settings/
│   └── Common/
├── Core/
│   └── Logger.swift
└── Resources/
```

## Setup Instructions

1. Clone the repository
2. Open `LillyTech.xcodeproj`
3. Build and run

## Development

- Branch from `develop` for new features
- Follow commit message format: `<type>: <description>`
- Create pull requests for feature merges

## Testing

Run tests using:
- Xcode: `⌘U`
- Command line: `xcodebuild test`

Current test coverage:
- Package integration tests
- Logger functionality
- WebRTC initialization

## Documentation

Additional documentation can be found in:
- [GitHub Workflow Guide](docs/workflow.md)
- [Project Structure](docs/structure.md)
- [Development Guidelines](docs/guidelines.md)