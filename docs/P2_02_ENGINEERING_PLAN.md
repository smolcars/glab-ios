# P2-02 engineering plan: native Markdown descriptions

Last updated: 2026-07-28

Status: planned. No application code has been changed for this feature yet.
Glab has never shipped, so the owner has explicitly allowed breaking internal
API, cache-format, and local-schema changes when they produce a simpler or
safer implementation.

## Outcome

Render issue and merge-request descriptions as responsive native SwiftUI
content without contacting GitLab's Markdown API and without parsing Markdown
from a SwiftUI `body`.

The first supported GitLab Flavored Markdown subset is:

- paragraphs, soft and hard line breaks;
- headings levels 1 through 6 and thematic breaks;
- bold, emphasis, strikethrough, and inline code;
- ordered, unordered, nested, and read-only task lists, including GitLab's
  complete (`[x]`), incomplete (`[ ]`), and inapplicable (`[~]`) states;
- block quotes;
- fenced code blocks and their language hint, shown as selectable monospaced
  text without syntax highlighting;
- pipe tables with left, center, and right alignment;
- safe absolute, root-relative, fragment, and best-effort path-relative links;
- safe, lazily loaded Markdown images with useful alternative text;
- same-project issue (`#123`), merge-request (`!123`), and user (`@name`)
  references when they are plain text rather than code or an existing link.

Unsupported diagrams, math, multimedia, raw HTML layouts, includes, custom
emoji, footnotes, description lists, cross-project reference expansion, and
server-specific extensions remain readable as text or an explicit fallback.
The existing compact Open in GitLab action remains the fidelity escape hatch.

## Inspected current state

- `GitLabIssue` and `GitLabMergeRequest` already decode the raw optional
  `description`, project ID, IID, references, and `web_url`.
- Issue and merge-request detail screens currently call
  `GitLabDescriptionFormatter.attributedString(_:)` directly from their
  SwiftUI `body`.
- That formatter synchronously removes template comments and fence/heading
  markers, then asks Foundation for
  `.inlineOnlyPreservingWhitespace` output. It renders basic inline emphasis
  but deliberately loses block structure, list semantics, table cells, code
  metadata, image identity, and heading accessibility.
- Each detail screen is already inside one vertical `ScrollView`; the Markdown
  renderer must contribute lazy blocks to that scroll rather than create a
  nested vertical scroll.
- Detail resources already use an account-partitioned, encrypted-at-rest raw
  response cache. A parsed-document cache is complementary and must not
  duplicate the raw API response on disk.
- Existing `AsyncImage` use has no byte limit and cannot authenticate a
  private GitLab upload. It is not sufficient for Markdown images.
- `GitLabWebURL` already rejects non-HTTPS and credential-bearing URLs. The
  Markdown link resolver should preserve that security boundary and add
  relative resolution.
- Account switching destroys the signed-in feature tree. Every Markdown
  request must still carry the explicit account ID so cached or late results
  cannot cross accounts.

## GitLab contracts and fidelity boundary

GitLab Flavored Markdown uses CommonMark as its core, adds GitHub Flavored
Markdown features such as tables and task lists, and adds GitLab-specific
references and extensions. GitLab's Markdown API can render the server's exact
HTML, but GitLab documents that endpoint as available for testing and not
ready for production use. It also requires an authenticated network request.
P2-02 therefore does not call it.

Description content continues to come from the existing project issue and
merge-request detail endpoints:

- `GET /projects/:id/issues/:issue_iid`
- `GET /projects/:id/merge_requests/:merge_request_iid`

Sources:

- [GitLab Flavored Markdown](https://docs.gitlab.com/user/markdown/)
- [GitLab GLFM development guidelines](https://docs.gitlab.com/development/gitlab_flavored_markdown/)
- [GitLab Markdown API](https://docs.gitlab.com/api/markdown/)
- [GitLab Issues API](https://docs.gitlab.com/api/issues/)
- [GitLab Merge requests API](https://docs.gitlab.com/api/merge_requests/)

## Parser selection and benchmark

Three approaches were considered with Release builds on the development Mac:

| Candidate | Small, 524 B | Medium, 15,720 B | Large, 131,000 B | Decision |
| --- | ---: | ---: | ---: | --- |
| Foundation inline-only | 0.31 ms | 4.24 ms | 32.80 ms | Reject: current approach loses block structure |
| Foundation full Markdown | 0.22 ms | 7.62 ms | 70.12 ms | Select |
| `swift-markdown` 0.8.0 AST | 0.15 ms | 4.28 ms | 35.35 ms | Defer: faster large parse, but adds a package and cmark-gfm binary |

Values are median wall-clock parse time over 20 iterations; large Foundation
full-Markdown p95 was 71.68 ms. These are parser-selection measurements, not
device baselines.

Foundation full Markdown was selected because:

- it is already shipped with the iOS 26 deployment target and adds no binary,
  package-resolution, or maintenance surface;
- its presentation intents preserve headings, nested list/list-item identity,
  quotes, code-block language, tables, links, images, and inline styles;
- its measured cost is below one frame for typical descriptions and about
  70 ms only for the deliberately large fixture;
- parsing will run away from the main actor once per cache miss, and large
  output will render as lazy blocks.

`swift-markdown` is the documented fallback if final iPhone 17 Pro
measurements show that Foundation misses the performance budget. A WebView is
rejected because HTML generation, sanitization, sizing, accessibility, theme
coordination, and scroll bridging would add risk and would not remove the
server-fidelity problem.

## Architecture

Keep the existing Model-View architecture. Add one focused Markdown pipeline
shared by issue and merge-request details:

```text
GitLabMarkdownDescriptionView (@MainActor)
  -> GitLabMarkdownModel (@Observable, request/generation owner)
  -> GitLabMarkdownRendering (Sendable protocol)
  -> GitLabMarkdownRenderer (actor; cache and in-flight coalescing)
  -> @concurrent Foundation parser
  -> immutable GitLabMarkdownDocument
  -> LazyVStack of native block views
```

The signed-in shell creates account-bound Markdown services and injects them
through SwiftUI environment. The renderer still receives an explicit account
and resource identity on every request. Tests can inject controlled renderers
and image loaders without global state.

### Immutable render model

The parser publishes value types conforming to `Equatable` and `Sendable`.
The document contains ordered blocks, not Foundation parser nodes:

- heading(level, inline content);
- paragraph(inline content);
- ordered/unordered list with nested items and optional task state;
- quote containing blocks;
- fenced code(language hint, literal text);
- table(columns, header cells, body rows);
- image(alt text, resolved safe URL);
- thematic break;
- unsupported(label, readable source excerpt).

Inline content retains Foundation attributes for emphasis, strong,
strikethrough, inline code, and sanitized links. Parser AST or mutable
Foundation objects never escape into view state.

### Isolation and cancellation

- Markdown parsing is an explicit `@concurrent` async operation.
- The parser checks cancellation before normalization, between constructed
  blocks, and before publishing. Foundation's one synchronous parse call
  cannot be interrupted internally, so cancellation is checked immediately
  after it returns.
- The renderer actor owns cache mutation and coalesces identical in-flight
  requests.
- The main-actor model owns only request identity and presentation state. A
  generation token prevents a late request from publishing over newer
  content, even if its Foundation parse did not observe cancellation in time.
- Cancellation restores the prior rendered document when the same resource is
  being refreshed, otherwise returns to idle. It is never shown as an error.
- No parser, hash calculation, image decode, or reference scanning runs from a
  SwiftUI `body`.

### Parsed-document cache

Use a bounded in-memory LRU owned by the renderer actor. The key contains:

- `GitLabAccountID`;
- resource kind plus project ID and IID;
- SHA-256 of the exact normalized source;
- an integer renderer-format version.

The key never contains a token, OAuth secret, username, description text, or
raw private host. Changing content produces a new key. Changing renderer
behavior increments the version. Account or resource changes cannot hit the
old entry.

The initial policy is at most 32 documents and 2 MiB of normalized source
cost, evicting least-recently-used entries until both limits are satisfied.
A single document larger than the byte budget can be rendered but is not
cached. Parsed documents are not persisted: the existing raw response disk
cache already avoids the API round trip, and benchmark results do not justify
a second private on-disk representation yet.

When an entry for a resource is replaced, stale content-hash variants for that
same account/resource are removed. Account teardown releases its shell-owned
renderer and image cache.

### Link and reference safety

The parser retains existing links, then resolves them using the resource's
validated web URL:

- absolute links must be HTTPS and must not contain URL credentials;
- root-relative links resolve against the account's exact GitLab origin;
- fragment-only links resolve against the resource web page;
- path-relative links resolve against the project root as a best effort;
- malformed links, non-HTTPS schemes, credential-bearing URLs, and missing
  resource context remain noninteractive readable text;
- access tokens are never appended to URLs;
- external links never receive GitLab authorization headers.

The project root is derived only from a validated issue or merge-request
`web_url` with the expected `/-/issues/:iid` or
`/-/merge_requests/:iid` suffix. Plain-text `#number`, `!number`, and
`@username` references are linked only outside code and existing links.
Cross-project references remain readable but unexpanded in this slice because
accurate authorization-aware expansion requires GitLab's server-side
reference pipeline. P2-09 will decide which safe GitLab links route natively.

### Images

Markdown images are separate lazy blocks rather than attachments inside
`Text`.

- Load only validated HTTPS URLs.
- Add the current session's authentication header only for the exact canonical
  GitLab origin; never send it to external hosts.
- Revalidate every redirect and strip GitLab authorization before an external
  redirect.
- Require an image MIME type and enforce a 5 MiB downloaded-byte limit even
  when `Content-Length` is absent or false.
- Bound decoded image dimensions to 16 megapixels and downsample for the
  rendered width before publication.
- Keep a memory-only image cache capped at 24 images and 24 MiB.
- Present a neutral loading placeholder and a retryable, alt-text-preserving
  failure view. Missing alt text receives the label “Markdown image.”
- Respect image aspect ratio while capping initial height so a pathological
  image cannot monopolize the screen.

External image retrieval is expected Markdown behavior, but no GitLab
credential, cookie, or account identifier is included in that request.

## Rendering, accessibility, and fallback

- The existing detail `ScrollView` owns scrolling. A `LazyVStack` creates
  Markdown block views as needed.
- Headings use native font hierarchy and accessibility heading traits.
- Lists expose one semantic item per row; task symbols have Complete,
  Incomplete, or Inapplicable labels and remain read-only.
- Quotes use a leading rule and grouped accessibility content.
- Code is selectable, horizontally scrollable inside its own block, and
  labeled with the language when present.
- Tables use one horizontal scroll region, a visible header treatment, column
  alignment, and row/cell accessibility labels. Column widths are calculated
  once from bounded content rather than with nested geometry feedback.
- Links use the tint and remain individually actionable through attributed
  text.
- Images expose their alt text and loading/failure status.
- Reduce Motion introduces no special path because parsing and block
  insertion have no decorative animation.
- Malformed Markdown falls back to literal selectable text.
- Mermaid, PlantUML, Kroki, math, multimedia, includes, and raw HTML show a
  compact unsupported-format notice plus readable source. The screen's
  existing Open in GitLab action is the exact-rendering escape hatch.

Template HTML comments are removed before parsing. Other HTML is never
executed, interpreted as a view, or loaded into a WebView.

## Performance fixtures and budgets

Add deterministic fixtures:

- **small:** about 0.5 KiB and all common inline styles;
- **medium:** about 15 KiB with headings, nested/task lists, quotes, links,
  images, code, tables, strike, and GitLab references;
- **large:** about 128 KiB by repeating mixed blocks, including long code and
  wide tables;
- **malformed/unsupported:** unterminated fences/links plus HTML, Mermaid,
  math, and media constructs.

Record XCTest metric or signpost measurements on the iPhone 17 Pro Simulator
for cold parse, warm cache hit, first meaningful render, scrolling, and memory.
Initial acceptance budgets:

- small cold parse p95 below 10 ms;
- medium cold parse p95 below 25 ms;
- large cold parse p95 below 150 ms;
- warm parsed-cache hit p95 below 2 ms;
- no main-thread parser work;
- responsive continuous scrolling without repeated parse signposts;
- renderer and image caches remain within their explicit count/cost limits.

Simulator numbers will be recorded as baselines, not treated as physical-device
performance guarantees.

## Test-first implementation slices

### Slice 1: render model, parser, and safe links

First write failing Swift Testing coverage for:

- every supported block and inline syntax;
- nested ordered/unordered lists and all three task states;
- code language/literal preservation and table alignments;
- absolute, root-relative, fragment, and path-relative links;
- unsafe schemes, URL credentials, malformed URLs, and no-context links;
- same-project issue/MR/user references outside code and existing links;
- image URL and alternative-text extraction;
- template-comment removal, malformed input, and unsupported fallback;
- deterministic heading, task, code, table, link, and image accessibility
  labels.

Then implement immutable values, normalization, URL/reference resolution, and
the Foundation parser. Run focused tests and commit the buildable slice.

### Slice 2: asynchronous model and bounded cache

First write failing tests for:

- account/resource/content/version key isolation;
- cache hit, LRU promotion, count/cost eviction, oversized bypass, and stale
  hash replacement;
- identical in-flight request coalescing;
- cancellation before parse, after Foundation parse, and before publication;
- an uncancellable late renderer result never replacing a newer request.

Then implement the `@concurrent` parser boundary, renderer actor, cache, and
main-actor model. Run focused tests plus Thread Sanitizer where practical and
commit the slice.

### Slice 3: native block UI

Replace both raw description views with the shared lazy renderer. Implement
paragraphs, headings, lists/tasks, quotes, code, tables, thematic breaks,
safe links, loading/failure states, and unsupported notices. Preserve empty
description behavior and the Open in GitLab action.

Build and inspect representative issue and merge-request fixtures on the
iPhone 17 Pro Simulator in light/dark appearance, portrait/landscape, default
and accessibility Dynamic Type, and rapid navigation. Fix visual defects and
commit the slice.

### Slice 4: bounded remote images

First write failing redirect, origin/authentication, MIME, byte-limit,
dimension-limit, cancellation, cache, and alt-label tests using controlled
transports. Then add the lazy image loader and view, integrate image blocks,
and verify success/failure/rotation/Dynamic Type in the Simulator. Never use a
physical device and never make a write API request.

### Slice 5: measurements, deep review, and completion

Run the small/medium/large baselines, focused tests, complete test suite,
static analysis, source privacy scan, and Simulator UI matrix. Record results
below.

Then deeply review all P2-02 code for unsafe HTML or links, authentication
leakage, repeated parsing, incorrect task/list/table identity, unbounded
caches, main-actor work, cancellation races, image decompression spikes,
duplication, and unnecessary abstraction. Record material findings and a
repair plan before editing, add regressions, implement all fixes, rerun the
verification matrix, and only then mark P2-02 complete.

## Non-goals

- Exact server-side GitLab HTML parity.
- Calling `POST /markdown` or requesting `render_html`.
- Editing descriptions or toggling task-list items.
- Syntax-highlighted code.
- Rendering or executing raw HTML, JavaScript, Mermaid, PlantUML, Kroki,
  multimedia players, or LaTeX.
- Fetching referenced issue/MR titles or expanding authorization-sensitive
  cross-project references.
- Native deep-link routing, which belongs to P2-09.
- Persisting parsed documents or decoded images to disk.

## Verification record

To be completed during implementation.

## Deep-review findings and repair plan

To be completed after implementation and before feature completion.
