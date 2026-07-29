# P3-05 Engineering Plan — Create New Issues

## Status

- Existing-code audit: complete
- Official API research: complete
- Planning: complete
- Test implementation: pending
- Production implementation: pending
- Verification: pending
- Deep review: pending

This plan must be committed and pushed before any P3-05 test or production
code is changed.

## Outcome

A user can open a compact native issue composer from Home, select a project in
the active account, enter a required title and raw GitLab Flavored Markdown
description, optionally select existing labels and project members, mark the
issue confidential, set a due date, and submit exactly one create request.

After GitLab returns an authoritative issue, Glab clears the protected draft,
invalidates affected cached reads, dismisses the composer, and navigates
directly to the native issue detail identified by the returned project ID and
issue IID.

## Success criteria

- Project search uses the active account and paginates server results.
- Project-scoped labels and members paginate without leaking across projects
  or accounts.
- Changing projects preserves project-independent form fields and clears
  labels and assignees that are not valid in the new project.
- Title validation, Markdown limits, due-date formatting, label encoding, and
  Free versus paid assignee request shapes are deterministic and unit tested.
- The form is protected by an account-scoped draft and survives dismissal,
  relaunch, failed submission, and delivery-unknown submission.
- Read-only credentials can inspect the flow and metadata but cannot send a
  write request.
- Duplicate taps and automatic mutation retries cannot create duplicate
  issues.
- A response whose delivery or identity is uncertain never clears the draft
  or navigates to an assumed issue.
- Confirmed success routes to the returned native issue and does not leave
  affected response-cache entries authoritative.
- The compact UI remains usable with the keyboard, VoiceOver, Dynamic Type,
  dark and light appearance, long Markdown, and large metadata sets.

## Scope decisions and non-goals

- P3-05 creates only the default GitLab `issue` type.
- The initial form supports only the fields named in the phase document:
  title, description, existing labels, assignees, confidentiality, and an
  optional due date.
- Milestones, epics, weights, health, severity, issue templates, linked
  discussions, time tracking, attachments, and custom work-item fields are
  deferred.
- Existing labels can be assigned. P3-05 does not expose free-form label
  creation even though GitLab's create endpoint can create a missing label.
- Existing project members can be assigned. P3-05 never searches the global
  user directory and never adds a user to a project.
- Glab does not claim to know every project-specific permission in advance.
  The app-level access mode prevents a known read-only write, while GitLab
  remains authoritative for role, project feature, and confidentiality
  permissions.
- Project selection is limited to projects returned for the authenticated
  user's membership. A project may still reject issue creation if Issues are
  disabled or the user's role cannot create one.
- No idempotency-key behavior is assumed because the documented endpoint does
  not provide one.
- No production API mutation is required for routine UI verification. The
  iPhone 17 Pro Simulator uses deterministic model/service stubs for write
  states and the configured read-only account for live read paths. If a live
  create smoke test later becomes necessary, it must use only the authorized
  demo project, remain unassigned, contain no human mentions, and be announced
  before execution.

## Existing-code audit

### Architecture and state ownership

- The app uses small `@MainActor @Observable` feature models with injected,
  `Sendable` typed services. P3-05 fits this existing MV architecture.
- P3-05 does not justify MVI, TCA, a coordinator, or a generic CRUD repository.
  One issue-creation model owns the form, project search, selected-project
  metadata, draft lifecycle, submission state, and success callback.
- SwiftUI owns presentation and Home owns the navigation path. Networking,
  cache invalidation, and protected persistence stay outside the view.
- The signed-in shell is recreated for `GitLabAccountID`, but every async
  result still needs account and generation checks so a late request from a
  previous project or account cannot mutate the current form.

### Project identity, loading, and search

- `GitLabProject` already decodes the stable numeric ID, namespaced path,
  display name, avatar, visibility, and last activity needed by a picker.
- `LiveGitLabProjectLoader` already paginates recent and starred project lists
  through the shared typed client and account-scoped response cache.
- `ProjectsView` searches only already-loaded pages and navigates to project
  detail, so it cannot be reused unchanged as the creation picker.
- P3-05 should reuse `GitLabProject`, the existing project-row presentation
  where practical, and the shared pagination response types. It needs a
  server-search endpoint and selection behavior rather than a parallel project
  model or a copy of the entire projects screen.

### Issue models, detail, and routing

- `GitLabIssue` already decodes every field required from the authoritative
  create response and exposes `GitLabIssueRoute(projectID:issueIID:)`.
- `GitLabNativeRoute.issue` and `HomeView.nativeDestination` already navigate
  to the complete native issue detail.
- `LiveGitLabIssueLoader` and the detail model already perform the exact
  follow-up reads. P3-05 must route with the returned issue instead of parsing
  or guessing a web URL.
- The assigned-issues and Home projections are separately cached. Creation
  must invalidate their known reads; an in-memory refresh can happen after
  navigation without delaying the success transition.

### Markdown and editor reuse

- The existing Markdown renderer parses away from the main actor, coalesces
  identical renders, and bounds cached source cost.
- The resource editor already establishes the Edit/Preview interaction,
  maximum description length, keyboard behavior, and safe rendering request
  identity.
- P3-05 should reuse the renderer, validation constant, and small shared editor
  presentation components only where they already represent the same
  behavior. It must not instantiate a second Markdown parser or force a render
  on every keystroke.
- The creation model is not a special case of the existing resource editor:
  creation has no baseline resource, conflict preflight, or known route for
  ambiguous-delivery reconciliation. Reusing that editor state machine would
  create false assumptions and forwarding-only abstractions.

### Drafts and account lifecycle

- Discussion and resource-edit draft stores already provide the required
  pattern: account-scoped keys, redacted descriptions, revision ordering,
  hashed file names, size limits, atomic writes, complete file protection,
  debounced persistence, and account-removal cleanup.
- Neither existing draft shape can safely represent a selected project,
  creation metadata, or an issue whose submission delivery is unknown.
- P3-05 needs a focused issue-creation draft store. It may share only proven
  mechanical helpers if that avoids literal duplication without changing the
  existing stores.
- Authentication expiry preserves existing drafts; deliberate account removal
  deletes them. Creation drafts must follow the same lifecycle.

### Transport, access, and mutation certainty

- `GitLabAPIRequest.post` produces a typed JSON request that requires explicit
  read or write access.
- `GitLabSessionClient` automatically retries only `GET`. A create `POST`
  receives one transport attempt.
- OAuth proactive refresh may occur before a known-expired write. Reactive
  refresh after the write is not a safe retry.
- `GitLabMutationDeliveryCertainty` already classifies validation,
  authentication, permission, and not-found responses as rejected, while
  rate limits, server failures, connectivity, cancellation, decoding, and
  transport failures are delivery unknown.
- P3-05 should reuse that classification. A failed decode after a successful
  HTTP response is delivery unknown because GitLab might already have created
  the issue.

### Response cache and loaded projections

- Cache keys contain the canonical account plus normalized request URL, so
  project metadata is naturally isolated by account, project ID, query, and
  page.
- `invalidateCachedResponse` removes an exact cached read and cancels an older
  coalesced read so it cannot repopulate stale content.
- Known affected reads after issue creation are the assigned-issues list, Home
  assigned-issue preview, recent-project list, and Home recent-project
  preview. Assigned projections are invalidated even when the result is not
  assigned to the current user; this is a bounded conservative choice.
- The newly created exact issue detail has no prior cache entry. The
  authoritative response can be presented immediately while the native detail
  model performs its normal exact load.
- Global search does not use the persistent response cache and Todos are not
  created by issue creation, so neither gets speculative mutation logic.

## Official GitLab contracts

### Create an issue

GitLab's
[Create an issue](https://docs.gitlab.com/api/issues/#create-an-issue)
contract is:

`POST /projects/:id/issues`

- `title` is required.
- `description` is optional and limited to 1,048,576 characters.
- `labels` is an optional comma-separated string. Missing names create labels,
  which is why P3-05 sends only values chosen from loaded existing labels.
- `confidential` is an optional Boolean and defaults to `false`.
- `due_date` is optional and uses `YYYY-MM-DD`.
- `assignee_id` is the single-assignee field documented for GitLab Free.
- `assignee_ids` is the multiple-assignee array documented for Premium and
  Ultimate.
- A successful response is the complete created issue.
- A project with Issues disabled can return `403`.
- Create requests can be rate limited.

### Project selection

GitLab's
[List all projects](https://docs.gitlab.com/api/projects/#list-all-projects)
endpoint is:

`GET /projects`

P3-05 uses `membership=true`, `archived=false`, `simple=true`, a bounded
`per_page`, and optional `search`. Results are paginated. Project-specific
create permission remains server-authoritative because membership and access
level do not prove that Issues are enabled or that all project rules permit
creation.

### Existing labels

GitLab's
[List all project labels](https://docs.gitlab.com/api/labels/#list-all-project-labels)
endpoint is:

`GET /projects/:id/labels`

It is available on Free, Premium, and Ultimate across GitLab.com,
self-managed, and Dedicated. It is paginated and includes ancestor-group
labels by default. P3-05 requests no issue/MR counts and treats the newer
`archived` field as optional for compatibility with older self-managed
instances.

### Assignable project users

GitLab's
[List all members of a project](https://docs.gitlab.com/api/project_members/#list-all-members-of-a-project)
endpoint is:

`GET /projects/:id/members/all`

It is paginated and includes direct, inherited, invited, and ancestor-group
access visible to the authenticated user. When a user has multiple membership
paths, GitLab returns the effective highest access level. P3-05 deduplicates by
numeric user ID and offers only active decoded users.

### Tier limitation

The ordinary project, member, metadata, and issue endpoints do not expose a
reliable normal-user Premium/Ultimate capability flag. The License API is
administrator-restricted, and the Metadata API's `enterprise` Boolean does not
distinguish Free from a paid Enterprise Edition plan.

P3-05 therefore follows the documented request shapes without inventing tier
detection:

- no selected assignee omits both fields;
- one selected assignee sends `assignee_id`;
- two or more selected assignees send `assignee_ids`.

The UI explains that multiple assignment requires Premium or Ultimate.
GitLab remains authoritative if an instance rejects the selected shape. A
rejected submission preserves the draft and lets the user reduce the
selection; Glab never retries by silently changing assignees.

## Architecture and type design

### Feature boundary

Add a focused issue-creation feature containing:

- value-semantic form, draft, metadata, and result types;
- typed endpoint factories;
- one live service for project search, project metadata, creation, and exact
  affected-read invalidation;
- one protected draft-store protocol with in-memory and file-backed
  implementations;
- one `@MainActor @Observable` creation model;
- compact SwiftUI composer, project picker, label picker, and assignee picker
  views.

The live service accepts `any GitLabPaginatedSessionRequestSending`. The model
accepts protocols, API access, account identity, an account-current closure,
and an authoritative-success callback. Tests replace each dependency without
networking or disk.

### Project and metadata values

Use `GitLabProject` as the selected project. Add only the missing small values:

- `GitLabProjectLabel`: stable ID, name, color, optional text color,
  description, and optional archived state;
- `GitLabProjectMember`: numeric ID, username, name, active/blocked state, and
  avatar URL, or reuse `GitLabAPIUser` when no member-specific field is needed;
- generic or focused page values carrying items and `nextPageURL`.

Identity and debug descriptions must redact project names, usernames, issue
content, and URLs where existing redaction rules do.

### Endpoint factories

Add tested endpoint builders:

1. project search:
   - `GET /projects`
   - read access
   - membership, archived, simple, order, page-size, and optional normalized
     search query
2. project labels:
   - `GET /projects/:id/labels`
   - read access
   - `with_counts=false`, inherited labels, and bounded page size
3. project members:
   - `GET /projects/:id/members/all`
   - read access
   - bounded page size
4. issue creation:
   - `POST /projects/:id/issues`
   - write access
   - typed JSON body
   - response `GitLabIssue`

Path components use numeric project IDs. Next-page URLs pass through the
existing same-host pagination trust checks.

### Create body and validation

Add a value-semantic create form/body builder with these rules:

- Title is invalid only when it is empty after whitespace trimming. The exact
  user-entered title is otherwise preserved.
- Description is optional in the request when empty and shares the existing
  1,048,576-character boundary.
- Selected label names preserve the server-provided spelling, are stable and
  deduplicated, and encode as one comma-separated field.
- No assignee omits both assignee fields; one uses `assignee_id`; multiple use
  `assignee_ids`. Both fields can never appear in one request.
- Confidentiality is always encoded explicitly for deterministic drafts and
  bodies.
- An absent due date is omitted. A selected date is converted with a fixed
  Gregorian calendar, stable locale, and UTC time zone to `YYYY-MM-DD`, so
  device locale or daylight-saving changes cannot shift the day.
- Project selection is required before submission.
- Construction failure happens before a transport call and is a definite
  rejection.

Endpoint tests decode the JSON body to compare semantics rather than relying
on dictionary key order.

## Project search and metadata loading

### Search

- The picker starts with the first membership page ordered by recent activity.
- A nonempty query uses server-side project search rather than filtering only
  loaded pages.
- Input is debounced. A monotonically increasing search generation rejects a
  late response from an older query.
- Pagination follows the current query's trusted `nextPageURL`. Changing the
  query cancels or invalidates the previous pagination generation.
- Duplicate project IDs across pages are suppressed.
- Cancellation is not shown as an error. Authentication failures pass to
  `AppSession` through the existing account-aware handler.

### Selected-project metadata

- Selecting a project starts label and member loads concurrently.
- Each metadata kind paginates independently and exposes loaded, loading,
  partial, unavailable, and retry states.
- The response cache uses the existing `.projects` policy. Exact request URLs
  make cached values account- and project-scoped.
- A project-selection generation is captured before every request. Results
  apply only if the active account and selected numeric project ID still
  match.
- Changing projects cancels in-flight requests, clears label and assignee
  selection immediately, and never displays stale metadata from the previous
  project.
- Cached first pages may appear immediately and revalidate through the shared
  stale-while-revalidate path. Additional pages retain the existing
  pagination trust boundary.
- Failure to load labels or members does not block a minimal issue. The form
  explains that the optional field is unavailable and still permits title-only
  creation when write access exists.

## Draft contract

### Identity and contents

There is one current new-issue draft per `GitLabAccountID`. The protected draft
contains:

- selected project ID plus enough display identity to restore or re-resolve it;
- exact title and description;
- selected existing label names;
- selected assignee IDs;
- confidentiality and optional due-date components;
- monotonically increasing revision;
- whether a submission has delivery-unknown state;
- a redacted deterministic submission fingerprint used only to detect whether
  the form changed after an uncertain attempt.

The key contains only the canonical account identity. Storage file names hash
length-prefixed identity components and contain no host, username, token,
project name, title, Markdown, or label text.

### Project changes

When the user selects a different project:

- title, description, confidentiality, and due date are preserved;
- label and assignee selection are cleared because their identity is
  project-scoped;
- the draft's selected project is replaced;
- previous metadata work is cancelled and the new project loads independently.

Restoring a draft resolves the saved project against the current account. If
the project is no longer available, the content remains but project selection
is cleared and the user is told to choose another project.

### Persistence behavior

- Restore completes before Create becomes enabled.
- User changes increment a revision and debounce protected persistence.
- Dismissal synchronously flushes the latest revision or keeps the sheet open
  with a storage error.
- Empty pristine forms remove the draft.
- Definite submission rejection keeps the editable draft but clears any
  pending-submission marker.
- Delivery unknown persists the full draft and pending marker before showing
  recovery actions.
- Only an authoritative valid issue response removes the draft.
- Deliberate account removal deletes creation drafts; authentication expiry
  preserves them.

The file implementation uses a bounded binary property list, atomic writes,
complete file protection, record versioning, digest validation, invalid-record
discard, and redacted errors, matching the established safety properties.

## Creation state machine

The observable model exposes explicit phases without a second navigation
owner:

1. restoring draft
2. editing
3. loading or retrying project metadata
4. submitting
5. rejected and editable
6. delivery unknown and blocked
7. authoritative success

### Submit

1. Require restored draft, current account, selected project, valid form,
   write access, no active submission, and no unresolved unknown delivery.
2. Persist the exact current draft.
3. Build the immutable submission body and fingerprint.
4. Mark the draft as pending before transport so process termination after
   the send cannot make a second attempt look safe.
5. Send exactly one typed `POST`.
6. Accept success only when the decoded issue has positive IDs and its
   `projectID` equals the selected project ID.
7. Invalidate known affected reads.
8. Remove the draft.
9. invoke the authoritative-success callback with the returned issue.
10. Dismiss and append `GitLabNativeRoute.issue(issue.route)` to Home's path.

Create is disabled during the operation. A second tap, a second Swift task, or
a late result from an old account/project cannot start or publish another
submission.

### Definite rejection

For local validation, read-only access, authentication, permission,
not-found, GitLab validation, or request-construction failure:

- no automatic retry occurs;
- the form remains intact;
- the pending marker is cleared and persisted;
- the relevant field or recovery message is shown;
- authentication failure follows the existing account transition.

### Delivery unknown

For rate limits, server errors, connectivity, cancellation after the write
could have started, transport, invalid/decoding response, or mismatched
authoritative identity:

- the draft and submission fingerprint remain protected;
- Create remains blocked;
- Glab explains that GitLab may already have created the issue;
- recovery offers project/global issue search and a refresh path;
- Glab never treats a title match as authoritative confirmation;
- the user must explicitly confirm that they checked GitLab before enabling a
  new attempt;
- a changed form produces a new fingerprint but does not silently clear the
  warning.

Because there is no returned route and no documented idempotency key, P3-05
cannot implement the exact delivery check used by resource editing. This
limitation is visible rather than hidden behind a retry.

## Cache invalidation and routing

On authoritative success, the live service invalidates:

- `GitLabIssueEndpoints.assignedIssues`;
- `HomeDashboardEndpoints.assignedIssues`;
- `GitLabProjectEndpoints.projects(for: .recent)`;
- `HomeDashboardEndpoints.recentProjects`.

The callback may refresh already-loaded Home and assigned-issue models after
navigation. It must not delay routing or insert an issue into assigned work
unless the returned assignee IDs prove that it belongs there.

The composer does not manufacture a detail resource from form input. It passes
the returned `GitLabIssue` to the callback and routes with `issue.route`.
Malformed or cross-project responses are delivery unknown and never navigate.

## Compact SwiftUI design

### Home entry point

- Add a new-issue icon beside Search in one trailing toolbar group so the two
  obvious actions share a compact Liquid Glass pill on iOS 26.
- The icon receives a full accessibility label and hint; visible text is not
  repeated in the toolbar.
- Read-only accounts may open the composer to inspect or recover a draft, but
  the form shows a concise read-only callout and disables Create.

### Composer

- Present one native sheet with a `NavigationStack`, inline title, Cancel, and
  Create toolbar actions.
- Keep the first screen compact: project row, title field, Edit/Preview
  Markdown area, and a collapsed metadata summary.
- Labels, assignees, confidentiality, and due date use compact disclosure or
  pushed selection screens instead of large permanent cards.
- Project, label, and assignee pickers use searchable paginated lists with
  checkmarks and no redundant explanatory text.
- Project-independent text survives project switching; a concise confirmation
  explains that labels and assignees will be cleared when they are selected.
- Progress appears only beside the operation it represents. Metadata failures
  remain inline and do not replace the whole form.
- The keyboard's submit affordance cannot bypass validation or unknown-delivery
  blocking.

### Accessibility

- Every icon-only action has a label, hint, identifier, and at least a 44-point
  interaction target even when the visible glass is compact.
- Title validation is associated with the title field and announced.
- Selected labels and assignees expose selected state and a useful count.
- Confidentiality and due date expose value and state, not color alone.
- Progress, read-only, submission failure, and delivery-unknown transitions
  are announced without repeatedly stealing focus.
- Accessibility Dynamic Type replaces dense horizontal rows with vertical
  layouts and allows unbounded critical text.
- VoiceOver focus moves to the authoritative issue detail only after confirmed
  success.

## Test-first plan

### Endpoint and value tests

Write failing tests before implementation for:

- project search path, access, query normalization, and pagination;
- labels and inherited-member endpoint paths and read access;
- minimal title-only create body;
- complete description, Unicode, Markdown, labels, confidentiality, and due
  date body;
- no, one, and multiple assignee shapes, proving mutual exclusion of
  `assignee_id` and `assignee_ids`;
- exact description maximum and maximum-plus-one validation;
- whitespace-only title and missing-project validation;
- stable locale-independent due-date encoding;
- JSON construction failure and write-access requirement;
- `400`, `401`, `403`, `404`, `409`, `422`, `429`, server, cancellation,
  connectivity, decoding, and transport certainty.

### Service and cache tests

Write failing tests for:

- project, label, and member pagination through trusted next-page URLs;
- cached first metadata pages and forced refresh;
- account/project-specific cache keys;
- one and only one create send;
- no GET-style automatic retry for POST;
- authoritative issue return;
- affected cache invalidation after confirmed success;
- no success invalidation after definite rejection;
- conservative invalidation after delivery unknown where the write may have
  landed;
- no token, body, title, Markdown, or member content in descriptions/debug
  descriptions.

### Draft-store tests

Write failing in-memory and file-store tests for:

- account isolation;
- revision ordering;
- round-trip of every field and delivery-unknown marker;
- atomic latest-draft persistence;
- empty-pristine cleanup;
- maximum file size and malformed, wrong-version, wrong-digest, symlink, or
  mismatched-key rejection;
- complete file protection;
- redacted storage paths and descriptions;
- per-account removal without affecting another account.

### Model tests

Write failing tests for:

- draft restoration before editing;
- local edits made while restore is in flight;
- project search debounce, cancellation, pagination, and stale-query results;
- project change preserving independent fields and clearing labels/assignees;
- independent label/member loading, pagination, partial failure, and retry;
- stale metadata rejection after rapid project changes;
- title/description validation;
- read-only gating with zero writes;
- failed persistence with zero writes;
- duplicate-tap prevention;
- cancellation before send versus after a possibly delivered send;
- definite rejection preserving the form and allowing correction;
- rate limit and every other delivery-unknown class blocking resubmission;
- explicit retry acknowledgement after the user checks GitLab;
- response project/identity mismatch;
- authoritative success order: invalidate, clear draft, callback;
- authoritative success still clears the draft and publishes the returned
  route if noncritical cache cleanup is cancelled;
- account switch rejecting every late search, metadata, and create result;
- authentication failure handoff.

### Routing and presentation tests

Write focused tests for:

- success callback producing the exact returned issue route;
- no route on rejection or unknown delivery;
- compact Home toolbar action and read-only presentation semantics;
- metadata summary values and selection counts;
- accessibility labels, selected states, validation, and unknown-delivery
  recovery actions;
- Markdown preview requests using exact draft content and active account.

## Simulator verification

Use the reusable `.deriveddata/Glab` directory and the iPhone 17 Pro Simulator.
Do not use the physical iPhone for development testing.

Perform one focused interaction pass after the feature is coherent:

- open and dismiss an empty composer;
- restore a saved account draft;
- search and paginate projects;
- switch projects while metadata is loading;
- verify label/member pagination and partial-error recovery;
- enter long Unicode Markdown and switch Edit/Preview;
- exercise keyboard dismissal and title validation;
- inspect minimal and complete forms with deterministic services;
- inspect read-only state using the configured self-managed read-only account;
- exercise rejected, rate-limited, delivery-unknown, and authoritative-success
  stubs;
- verify success routes to the returned native issue detail;
- inspect default and accessibility Dynamic Type, VoiceOver reading order,
  dark and light appearance, and compact/large device orientation as relevant.

Tap every visible action. Capture screenshots for the normal composer,
expanded metadata, read-only state, delivery-unknown recovery, and routed
success. Shut down extra simulators after verification.

## Final quality gates

At feature close:

1. run focused endpoint, metadata, draft, model, cache, and routing tests;
2. run the complete test suite serialized on the iPhone 17 Pro Simulator;
3. build Release for the Simulator using `.deriveddata/Glab`;
4. run Xcode static analysis;
5. validate the privacy manifest and bundled resources;
6. scan tracked files and the Release bundle for credential values and
   credential identifiers;
7. inspect the production diff for forced crashes/casts, debug output,
   accidental content logging, and test-only seams;
8. record exact commands and results in this document and the Phase 3
   checklist.

## Deep review checklist

After implementation and verification, review every P3-05 change for:

- duplicate create delivery or accidental mutation retry;
- lost, cross-account, or prematurely cleared drafts;
- unsafe unknown-delivery recovery;
- stale search or metadata results after project/account changes;
- invalid Free/Premium assignee assumptions;
- incorrect title, Markdown, label, or due-date encoding;
- loading all metadata eagerly or failing to paginate;
- account/project cache leakage or incomplete invalidation;
- navigation from form input rather than the authoritative response;
- permission or read-only UI that disagrees with transport;
- cancellation, task ownership, actor-isolation, or generation races;
- duplicated project-row, Markdown editor, protected-file, or error
  presentation code;
- oversized UI, redundant text, ungrouped obvious actions, and inaccessible
  icon-only controls;
- sensitive project, issue, member, or credential content in logs,
  descriptions, storage identifiers, file names, or tests;
- bad code, unnecessary abstractions, dead code, and code that needs
  refactoring.

Record every material finding below before editing a repair. For each finding:

1. describe impact and reproduction;
2. write a focused repair plan;
3. add a regression test;
4. implement the smallest repair;
5. rerun focused and complete verification;
6. repeat this review until no material finding remains.

## Deep review findings

Pending implementation.

## Ordered implementation

1. Commit and push this plan with no P3-05 production or test changes.
2. Add failing endpoint, validation, metadata, and service tests.
3. Implement typed project search, labels, members, creation, and invalidation.
4. Add failing protected draft-store tests, then implement the store and wire
   account cleanup.
5. Add failing creation-model tests, then implement restore, search, metadata,
   validation, submission, unknown delivery, and authoritative success.
6. Add focused routing/presentation tests, then implement the compact Home
   entry point and composer/picker UI.
7. Run focused tests and one complete Simulator interaction pass.
8. Run final quality gates.
9. Perform and record the deep review, write repair plans before any fixes,
   fix every material finding, and repeat verification/review.
10. Mark P3-05 and each Phase 3 subtask complete only when all evidence is
    recorded and the final review is clean.
