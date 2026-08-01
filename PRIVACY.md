# Glab Privacy Policy

Effective date: July 27, 2026

Glab is an unofficial, open-source iPhone client for GitLab. This policy
describes how the Glab app handles information.

## Data Glab handles

Glab connects directly from your device to the GitLab instance you choose. It
requests the account and work data needed to provide the app's features, such
as your profile, projects, issues, merge requests, and Todos. This information
is shown to you in the app.

OAuth access and refresh tokens or a personal access token are stored in the
device-bound iOS Keychain. Glab never receives your GitLab password, 2FA code,
or SSO credentials because GitLab handles web authentication.

## Collection and tracking

The Glab project does not operate an application server and does not collect
your GitLab data, credentials, diagnostics, usage data, or identifiers. The app
contains no advertising, analytics, telemetry, or tracking SDKs and does not
track you across apps or websites.

## Services you choose to contact

- Your selected GitLab instance receives API and OAuth requests needed to
  provide Glab's features. That instance's operator controls its own data
  practices and privacy policy.
- Avatar images and links opened outside Glab are requested from their
  displayed destination through iOS. Credentials are never added to those
  requests.
- Apple provides the operating system, Keychain, networking, and App Store
  services used by the app. Apple's own policies apply to those services.

Glab does not sell or share personal data with the project maintainer or
advertising companies.

## Storage, retention, and deletion

Glab keeps credentials in Keychain until you sign out or remove the app's data.
Signing out removes the stored GitLab session and credentials. Non-secret
self-managed OAuth application configuration may remain as an app preference
until it is replaced or the app is deleted.

Glab does not intentionally create a persistent offline copy of GitLab API
response bodies. iOS and its networking components can maintain transient
system caches. Deleting Glab removes its app container; you can separately
revoke an OAuth grant or personal access token from your GitLab account.

If you enable new Todo alerts, iOS may periodically let Glab contact your
GitLab instance directly in the background. Glab stores the per-account opt-in,
an opaque account key, and previously observed Todo IDs in its local app
container so old Todos are not reported as new. Alert text is generic and is
scheduled locally through iOS; no Glab-operated server or Apple Push
Notification service receives your GitLab credentials or Todo content.

Glab cannot delete information held by a GitLab instance because the project
does not control that service. Use the account and privacy controls supplied
by your GitLab administrator or GitLab.com for server-side access, correction,
export, and deletion requests.

## Changes and questions

Material changes to this policy will be published in this repository with an
updated effective date. For questions or privacy concerns, open an issue in
the [Glab repository](https://github.com/smolcars/glab-ios/issues).
