# Lessons Learned

- SwiftUI `.searchable` can mount its glass late and replace the navigation layout while focused. Use the shared `GitLabSearchField` in a stable `safeAreaInset`.
- Keyboard dismissal can briefly leave stale safe-area space. Ignore the bottom keyboard safe area and dismiss interactively from scrolling.
- GitLab API ordering is not guaranteed. Sort branches locally and pin the default branch first.
- Paginated lists cannot pin an item that has not loaded. Fetch the default branch separately and merge it into page one.
- Source width calculations must expand tabs to the same tab stops used for display or long lines will clip.
- Project README names and formats vary. Use GitLab's `readme_url` instead of guessing `README.md`.
- Repository Markdown links resolve from the file directory. Load relative images through the raw-file API, not blob pages.
- Markdown parsers may leave README HTML visible. Test HTML-heavy files and keep a raw fallback.
- HTML attributed strings often hard-code black text. Apply dynamic label colors in the view and verify dark mode.
- Keep Markdown images in the authenticated app pipeline. Decode SVGs before passing them to SwiftUI.
- Modern SVG badges can embed SVG logos with `href`. Normalize them before SwiftDraw decoding.
- Observe incoming navigation on the stack, not an off-screen root destination.
- Route same-instance GitLab blob links to the native file viewer.
- Avoid wrapping one tall Markdown document in a `LazyVStack`; estimated heights make the scroll indicator jump.
- Highlight a complete source document before splitting it into display lines so multiline strings and comments keep their context.
- Skip whole-document highlighting when displayed lines are truncated because removed delimiters can corrupt later token state.
- Diff highlighting should retain shared attributed hunk text plus line ranges instead of copying one attributed string per row.
- Snapshot every Todo page before completing items; mutating an offset-paginated queue mid-load can skip entries.
