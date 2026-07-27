# Glab for iOS

Glab is an unofficial, native iPhone client for GitLab. It is built with
SwiftUI and the GitLab REST API, with a visual direction inspired by the
focused, dense workflows of the GitHub iOS app.

Glab is an independent project and is not affiliated with, endorsed by, or
sponsored by GitLab.

## Current status

Glab is under active MVP development. The current app includes:

- GitLab.com and self-managed instance support.
- Personal access token sign-in with read-only `read_api` detection.
- OAuth Authorization Code with PKCE, including self-managed instance setup,
  token refresh, and the instance's normal username/password, 2FA, or SSO web
  login.
- Secure credential storage in the iOS Keychain.
- A native Home/Todos shell and Home work previews.
- Paginated assigned-issue browsing, local filtering, and native issue
  details.
- Paginated assigned and review-requested merge-request browsing with native
  read-only details.
- Paginated recent and starred project browsing with local filtering and safe
  GitLab web routing.
- A paginated pending/done Todos inbox with issue/merge-request filters,
  resilient unknown target handling, and a reliable-count tab badge.
- Native issue/merge-request Todo routing, safe browser fallbacks for other
  targets, and optimistic single/all completion with rollback.
- Read/write request declarations that prevent a `read_api` session from
  sending unsupported mutations.

Resilience, accessibility, and privacy hardening are the next MVP phase. The
ordered scope and acceptance criteria live in
[the MVP checklist](docs/MVP.md).

GitLab.com OAuth logic is implemented, but its clean-install live callback
remains an explicit release-verification item until a real public Application
ID is configured. See [OAuth setup](docs/OAUTH_SETUP.md).

## Requirements

- macOS with an Xcode release that includes the iOS 26 SDK.
- iOS 26 or newer.
- A GitLab.com account or an HTTPS self-managed GitLab instance whose
  certificate is trusted by iOS.

## Build and run

Open `Glab.xcodeproj` in Xcode, choose the `Glab` scheme and an iPhone
Simulator, then run the app.

The equivalent command-line build is:

```sh
xcodebuild \
  -project Glab.xcodeproj \
  -scheme Glab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  build
```

Run the unit tests with normal simulator signing enabled so the Keychain tests
have their required application identity:

```sh
xcodebuild \
  -project Glab.xcodeproj \
  -scheme Glab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  test
```

If iOS 26.5 is not installed, replace the destination OS with an available iOS
26 runtime.

## Authentication

The sign-in screen offers two paths:

1. **Continue with GitLab** uses OAuth with PKCE. Authentication happens on the
   selected GitLab host, so Glab never receives a password or 2FA code.
2. **Use an access token** accepts a personal access token as a fallback.

The complete MVP needs the GitLab `api` scope to mark Todos done. A personal
access token with only `read_api` can still sign in and browse; write controls
will remain disabled with an explanation.

OAuth applications are registered per GitLab instance. A self-managed
instance therefore needs its own public Glab OAuth Application ID. Follow
[the OAuth setup guide](docs/OAUTH_SETUP.md) for the redirect URI, PKCE, scope,
and self-managed registration choices.

## Security

- Access tokens and OAuth refresh tokens are stored only in Keychain.
- Glab does not request, receive, or store a GitLab password or 2FA code.
- Client secrets are not used by this native OAuth client.
- Local `.env` files, Xcode user data, build products, and Derived Data are
  ignored by Git.
- Secrets must not be committed, logged, placed in fixtures, or included in
  screenshots.

## Project documentation

- [MVP checklist and API contract](docs/MVP.md)
- [Engineering plan](docs/ENGINEERING_PLAN.md)
- [OAuth setup](docs/OAUTH_SETUP.md)
- [Focused code audit](docs/CODE_AUDIT.md)

## License

Glab is available under the [MIT License](LICENSE).
