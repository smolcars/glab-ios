# Glab iOS Engineering Plan

Last updated: 2026-07-27

This plan describes how to implement the ordered product checklist in
[MVP.md](MVP.md). The first unchecked MVP item is always the only active
delivery item.

## 1. Technical baseline

- Product: Glab, an iPhone-only GitLab client.
- Toolchain: Xcode 26.6 and Swift 6.3.
- Deployment target: iOS 26.0.
- Primary verification device: iPhone 17 Pro running iOS 26.5.
- UI: SwiftUI, using native navigation, tabs, sheets, lists, materials, and
  Liquid Glass behavior.
- Unit tests: Swift Testing.
- External dependencies: none for the MVP unless a later item demonstrates a
  concrete need that cannot be met cleanly with Apple frameworks.
- Provisional bundle identifier: `com.glab.ios`. Confirm the final identifier
  and signing team before distribution.

## 2. Architecture decision

Use SwiftUI Model-View (MV) with dependency injection.

This is the smallest architecture that makes ownership and test seams explicit:

- SwiftUI views describe presentation and route user actions.
- A focused `@Observable` model owns each feature's screen state and async
  orchestration.
- Protocol-backed services own side effects such as HTTP, OAuth, Keychain, and
  opening external URLs.
- The app entry point is the composition root for live dependencies.
- Tests construct feature models with deterministic fakes.

Do not add forwarding-only view models, a global service locator, TCA, Clean
Architecture layers, or separate packages during the MVP. Escalate only if a
specific feature develops a state machine or cross-feature dependency pressure
that MV cannot express clearly.

### State and concurrency

- UI-owned state and feature models are `@MainActor`.
- Immutable API/domain values conform to `Sendable` where they cross isolation
  boundaries.
- Shared mutable session and token-refresh coordination use a dedicated actor.
- Child work uses structured concurrency and propagates cancellation.
- The compiler uses complete strict-concurrency checking.

### Dependency direction

```text
GlabApp / composition root
        |
        +--> Features (Auth, Home, Todos, Issues, Merge Requests, Projects)
        |         |
        |         +--> Core protocols and domain values
        |
        +--> Live infrastructure (REST, OAuth, Keychain, system URL opener)
                  |
                  +--> Core protocols and domain values

GlabTests --> Features + Core through fakes/stubbed transport
```

Feature code must not depend directly on a singleton network client, Keychain,
or `UIApplication`.

## 3. Repository layout

Start with one application target and one unit-test target:

```text
Glab.xcodeproj
Glab/
  App/
  Core/
    API/
    Authentication/
    DesignSystem/
    Models/
  Features/
    Authentication/
    Home/
    Todos/
    Issues/
    MergeRequests/
    Projects/
GlabTests/
  Core/
  Features/
docs/
```

Only create a directory when its MVP item introduces code for it. MVP-01 begins
with `App/` and one smoke test; empty speculative directories are not created.

## 4. Delivery sequence

The canonical details and acceptance criteria remain in `MVP.md`.

1. **Project foundation (MVP-01)**
   Create the app/test targets and shared scheme, build, test, and launch.
2. **Core boundary (MVP-02–03)**
   Add the injected REST transport, endpoint/error/pagination behavior, account
   model, and secure credential store.
3. **Authentication vertical slices (MVP-04–06)**
   Complete personal-token sign-in first, then GitLab.com and configured
   self-managed OAuth with PKCE, refresh, launch restoration, and sign out.
4. **Native app shell (MVP-07)**
   Add Home and Todos tabs with independent navigation stacks. Let standard
   SwiftUI surfaces adopt Liquid Glass automatically.
5. **Read workflows (MVP-08–12)**
   Deliver Home, Issues, Merge Requests, Projects, and the Todos inbox one
   feature at a time.
6. **First mutation (MVP-13)**
   Add Todo completion only after read workflows and credential capabilities
   are stable.
7. **Hardening and release proof (MVP-14–15)**
   Complete resilience, accessibility, privacy, clean-install authentication,
   and the final device matrix.

Each item must leave the main branch buildable and all tests passing before the
next item begins.

## 5. Testing strategy

Use Swift Testing for all new unit tests:

- Test names describe behavior.
- Tests arrange their own state and may run in parallel.
- `#require` unwraps values needed by later assertions; `#expect` checks
  independent behavior.
- Async tests use deterministic continuations, fakes, or confirmations rather
  than sleeps.
- Networking tests use an injected `URLSession`/`URLProtocol` transport and
  never contact a live GitLab host.
- Authentication tests never store real credentials or print test tokens.
- Core error, cancellation, and malformed-response paths receive dedicated
  tests.

XCUITest is not added until an MVP flow requires repeatable UI automation.
Simulator launch and visual inspection remain mandatory for every UI item.

### Per-item verification gate

Run:

```sh
xcodebuild build \
  -project Glab.xcodeproj \
  -scheme Glab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'

xcodebuild test \
  -project Glab.xcodeproj \
  -scheme Glab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'
```

Then install and launch the built application with `simctl`, inspect the screen,
and capture a screenshot when presentation changed.

## 6. Liquid Glass and visual rules

- Standard `TabView`, navigation bars, toolbars, sheets, and controls are the
  default because the current SDK gives these native Liquid Glass behavior.
- Custom glass is limited to functional navigation or action controls. It is
  not a card background or general decoration.
- Group related custom glass controls in one `GlassEffectContainer`.
- Apply layout and appearance before `glassEffect`.
- Interactive glass is used only on real controls.
- Test Reduce Motion, Reduce Transparency, Increased Contrast, Dynamic Type,
  light appearance, and dark appearance.
- Preserve the hierarchy and density of the GitHub references while using
  GitLab terminology, icons, and semantic colors.

## 7. API and authentication boundaries

- Build all REST URLs from a normalized HTTPS GitLab host and `/api/v4`.
- Use OAuth Bearer headers or GitLab's recommended `PRIVATE-TOKEN` header.
- Store access and refresh tokens only in Keychain.
- GitLab.com OAuth uses Glab's registered public Application ID.
- Self-managed OAuth uses the same PKCE implementation with a user-provided
  host and that instance's shared Glab Application ID.
- Username/password, 2FA, LDAP, and SAML remain inside GitLab's browser login;
  Glab never receives those credentials.
- A personal access token remains the fallback when an instance has not
  registered Glab for OAuth.
- Follow server-provided pagination links and treat unknown Todo types/actions
  as displayable values rather than decoding failures.

## 8. Security and privacy gate

Before an authentication item is complete:

- No secret appears in source control, `UserDefaults`, logs, debug
  descriptions, errors, analytics, fixtures, or screenshots.
- OAuth validates `state`, uses a new PKCE verifier for every attempt, and never
  embeds a client secret.
- Redirect and external target URLs are validated before opening.
- Refresh attempts are coalesced and retry an API request at most once.
- Sign out removes Keychain and in-memory credential material.

## 9. Known engineering risks

| Risk | Mitigation |
|---|---|
| Self-managed OAuth requires per-instance registration | Provide concise admin setup and retain token fallback. |
| Todo completion requires broad `api` scope | Explain it before authorization and support read-only token sessions. |
| GitLab responses contain optional and evolving fields | Decode defensively and test unknown enum-like strings. |
| GitLab.com may omit pagination totals | Use returned next links and avoid UI that requires exact totals. |
| OAuth refresh races can invalidate sessions | Centralize refresh in an actor and coalesce callers. |
| GitLab Markdown is broad and server-specific | Keep MVP details readable and defer full-fidelity rendering. |

## 10. Definition of done

An MVP item is done only when:

1. Its implementation and core-logic tests are complete.
2. The shared scheme builds without warnings.
3. All unit tests pass on iPhone 17 Pro, iOS 26.5.
4. Changed UI has been launched and inspected in Simulator.
5. The item is marked complete in `MVP.md`.
6. No later checklist item was implemented speculatively.
