# MVP-12 engineering plan: Todos inbox

Last updated: 2026-07-27

## Outcome

Replace the placeholder Todos tab with a read-only, paginated inbox. The inbox
defaults to pending Todos, lets the user switch between pending and done, and
can narrow the server request to issues or merge requests without hiding future
or less common target types from the unfiltered view.

MVP-12 does not mark Todos done or route them to native details. Those are
explicitly deferred to MVP-13, after API requests declare and enforce their
read/write capability.

## Assumptions and API contract

- The instance is already represented by an authenticated
  `GitLabSessionClient`; this phase adds no authentication behavior.
- Initial pages use `GET /todos` with `state=pending` or `state=done` and
  `per_page=20`.
- The target filter is named `type` in GitLab's request contract. Issue and
  merge-request filters send `type=Issue` and `type=MergeRequest`; the All
  filter omits `type`.
- Later pages follow GitLab's response `Link` URL rather than constructing page
  numbers.
- Todo identity is the globally unique Todo `id`.
- Decode the Todo ID, optional project, optional author, action name, target
  type, small polymorphic target summary, validated target URL, body, state,
  and created/updated timestamps.
- The documented target types are `Issue`, `MergeRequest`, `Commit`, `Epic`,
  `DesignManagement::Design`, `AlertManagement::Alert`, `Project`, `Namespace`,
  `Vulnerability`, and `WikiPage::Meta`.
- The documented action names are `assigned`, `mentioned`, `build_failed`,
  `marked`, `approval_required`, `unmergeable`, `directly_addressed`,
  `merge_train_removed`, and `member_access_requested`.
- Both target type and action name use lossless unknown cases. A new GitLab
  value must not reject the page and must remain visible in All.
- Project, author, and target containers are optional because not every target
  shape supplies every container. Rows use explicit neutral fallbacks instead
  of inventing missing GitLab data.
- A row title prefers `target.title`, then `target.name`, then the Todo body,
  and finally “Untitled Todo.” Body text is omitted when it merely repeats the
  title.
- API-provided target URLs are exposed only when they are HTTPS, host-bearing,
  and contain no URL credentials. MVP-12 decodes and tests the URL but does not
  make the row interactive.
- The Todos tab shows an integer pending badge only when the unfiltered pending
  resource has a reliable count. Prefer GitLab's valid nonnegative `X-Total`
  response header; when it is unavailable, use the loaded row count only after
  pagination proves the collection is complete. Do not infer a total from a
  partial page.

Sources:

- [GitLab To-Do List API](https://docs.gitlab.com/api/todos/)
- [GitLab REST pagination](https://docs.gitlab.com/api/rest/#pagination)

## Architecture

Keep the established SwiftUI Model-View boundaries:

- `GitLabTodoState` and `GitLabTodoTargetFilter` own request values and
  user-facing control copy.
- `GitLabTodoTargetType` and `GitLabTodoAction` decode documented and unknown
  values and own their compact row presentation.
- `GitLabTodo` decodes only the inbox contract and supplies tested title/body,
  project, author, time, and safe-URL presentation values.
- `GitLabTodoEndpoints` builds initial list requests.
- `GitLabTodoLoading` is the test seam; the live loader delegates to
  `GitLabPaginatedSessionRequestSending`.
- Each state/filter query reuses
  `GitLabPaginatedResourceModel<GitLabTodo, Int>` for loading, refresh,
  de-duplication, pagination, cancellation, and error behavior.
- `TodosModel` owns the selected state/filter and caches the small query models
  so switching controls does not discard already loaded pages. It also derives
  the pending tab badge from the unfiltered pending model.
- `SignedInShellView` owns one `TodosModel`, passes it to `TodosView`, and reads
  its optional reliable badge count.
- `TodosView` displays native segmented controls and dense inbox rows. System
  tab/navigation/picker materials provide the iOS 26 glass treatment; content
  rows remain readable system list content rather than decorative glass cards.

Adding an optional parsed total count to the existing response metadata and
generic resource page is justified by the badge acceptance criterion. No other
feature needs to change its UI or behavior.

## Test-first implementation order

### 1. Response metadata, endpoint, and decoding contract

Write failing tests for:

- valid, missing, negative, and malformed `X-Total` headers;
- pending/done requests and All/Issue/MergeRequest `type` queries;
- every documented target type and action plus unknown values;
- a representative Todo with project, author, target, body, timestamps, and a
  safe target URL;
- missing project, author, target, body, and URL data;
- deterministic title/body/project/author fallbacks;
- rejection of unsafe target URLs.

Then add only the response fields, enums, and endpoint builders needed to pass.

### 2. Loader and inbox state

Write failing tests for:

- passing the selected state/filter into the initial request;
- following the server-provided next-page URL and propagating total count;
- de-duplicating by Todo ID;
- switching and caching pending/done and target-filter resources;
- retained-content refresh failures, next-page retry, cancellation, and
  authentication failures through the shared pagination engine;
- badge derivation from `X-Total`, a completely loaded collection, a partial
  collection, and a failed refresh.

Then implement the live loader, thin paginated adapter, and `TodosModel`.

### 3. UI and shell integration

Build:

- Pending/Done and All/Issues/Merge Requests controls;
- dense rows showing target icon/type, action, project, title, distinct body,
  author, and relative update time;
- pull to refresh, pagination, empty states, retained-content refresh errors,
  and retryable incremental failures;
- an exact pending badge on the Todos tab only when the model exposes one.

Do not add local search, completion controls, mark-all confirmation, optimistic
updates, native detail routing, or browser routing in this phase.

## Verification gates

1. Focused response metadata, endpoint, and decoding tests pass.
2. Focused loader/model tests pass.
3. The complete signed unit-test suite passes on iPhone 17 Pro, iOS 26.5.
4. Xcode static analysis reports no code findings.
5. With the existing simulator session, Pending/Done and all three target
   filters, refresh, pagination, and tab switching are exercised without any
   mutation request.
6. Populated and empty/error states are visually inspected in light and dark
   appearance, including long text and the optional badge.
7. The implementation is committed to `master` in small, passing increments.
