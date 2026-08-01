# Glab for iOS

Glab is an unofficial, native iPhone client for GitLab, built with SwiftUI.

[![Join the Glab beta on TestFlight](https://img.shields.io/badge/TestFlight-Join_the_Beta-0D96F6?logo=testflight&logoColor=white)](https://testflight.apple.com/join/bXG8kPeS)

## Features

- GitLab.com and self-managed GitLab support
- OAuth and personal access token sign-in
- Projects, issues, merge requests, commits, and pipelines
- Todos, search, discussions, mentions, and reactions
- Credentials stored securely in the iOS Keychain
- Dynamic Type and VoiceOver support

## Requirements

- iOS 26 or newer
- GitLab.com or GitLab 15.5 or newer
- Xcode with the iOS 26 SDK to build locally

## Build locally

Open `Glab.xcodeproj`, select the `Glab` scheme and an iPhone Simulator, then
run the app.

```sh
xcodebuild \
  -project Glab.xcodeproj \
  -scheme Glab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

For self-managed OAuth configuration, see the
[OAuth setup guide](docs/OAUTH_SETUP.md).

## Privacy

Glab does not collect analytics or tracking data. See the
[privacy policy](PRIVACY.md) for details.

Glab is an independent project and is not affiliated with, endorsed by, or
sponsored by GitLab.

## License

[MIT](LICENSE)
