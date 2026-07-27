# Glab OAuth setup

Last updated: 2026-07-27

Glab uses GitLab's Authorization Code flow with PKCE. Authentication happens in
GitLab's web page, so username/password, 2FA, LDAP, SAML, and other
instance-configured sign-in methods remain between the user and GitLab. Glab
never asks for or receives the user's password.

## Application settings

Use these values for every GitLab OAuth application:

| Setting | Value |
| --- | --- |
| Name | `Glab` |
| Redirect URI | `glab://oauth/callback` |
| Scope | `api` |
| Client type | Public/native (non-confidential) |
| PKCE method | `S256` |

The redirect URI must match exactly. If the GitLab version shows a
**Confidential** checkbox, leave it off. Glab uses PKCE and does not accept,
store, or embed a client secret.

The `api` scope is required because the MVP will both read data and complete
Todos. GitLab's `read_api` scope cannot perform that write operation.

## GitLab.com

Register Glab once under **Edit profile > Access > Applications > Add new
application**, using the settings above. Copy the resulting Application ID, but
not the secret.

Keep the Application ID outside the committed project value. Set the
`GLAB_GITLAB_COM_OAUTH_APPLICATION_ID` user-defined build setting in a local
Xcode configuration, or pass it to a development build:

```sh
xcodebuild \
  -project Glab.xcodeproj \
  -scheme Glab \
  GLAB_GITLAB_COM_OAUTH_APPLICATION_ID=<application-id>
```

The value is expanded into the app's Info.plist at build time. An Xcode scheme
environment variable with the same name is also supported for local
development. The Application ID is public client metadata, but keeping the
project default empty prevents one developer's registration from silently
becoming the release configuration.

## Self-managed GitLab

A self-managed OAuth application belongs to that GitLab instance. A
GitLab.com Application ID cannot be reused on another host.

Choose the registration level allowed by the organization:

- A user can register a user-owned application under **Edit profile > Access >
  Applications** when the instance permits user-created applications.
- A group owner can register a group-owned application under the group's
  **Settings > Applications**.
- An administrator can register one instance-wide application under **Admin >
  Applications** and share its Application ID with users. GitLab's current
  administrator instructions recommend marking such an application trusted;
  trusted applications skip the per-user authorization prompt, so this should
  follow the organization's security policy.

Use the common application settings above. Copy only the Application ID into
Glab's self-managed setup screen. The Application ID is saved as non-secret
configuration for that host; access and refresh tokens are saved in Keychain.

The MVP requires an HTTPS host whose certificate is trusted by iOS. HTTP,
custom certificate authorities, and client-certificate authentication are not
supported.

## Troubleshooting

- **Unknown Application ID:** confirm that the ID came from the selected GitLab
  host, not GitLab.com or a different self-managed instance.
- **Redirect URI mismatch:** set the registered URI to
  `glab://oauth/callback`, including the lowercase scheme and path.
- **Application registration unavailable:** ask a group owner or administrator
  to register a shared application, or use Glab's personal access token
  fallback.
- **Authorization denied or cancelled:** start sign-in again and approve the
  requested `api` scope.
- **Refresh rejected:** the grant may have expired or been revoked; sign in
  again.
- **Instance unreachable:** verify the HTTPS URL, network/VPN access, and
  certificate trust in Safari before retrying.

## Security boundaries

- Access tokens and refresh tokens are stored only in Keychain.
- OAuth Application IDs are non-secret and may be stored in UserDefaults.
- Client secrets are never used by the iOS app.
- Credentials must not be placed in source files, committed `.env` files,
  logs, fixtures, screenshots, analytics, or documentation.

See GitLab's official [OAuth API documentation][oauth] for the PKCE exchange
and refresh contract, and [OAuth provider documentation][provider] for
application registration and ownership options.

[oauth]: https://docs.gitlab.com/api/oauth2/
[provider]: https://docs.gitlab.com/integration/oauth_provider/
