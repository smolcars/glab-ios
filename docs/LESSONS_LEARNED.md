# Lessons Learned

- SwiftUI `.searchable` can mount its glass late and replace the navigation layout while focused. Use the shared `GitLabSearchField` in a stable `safeAreaInset`.
- Keyboard dismissal can briefly leave stale safe-area space. Ignore the bottom keyboard safe area and dismiss interactively from scrolling.
- GitLab API ordering is not guaranteed. Sort branches locally and pin the default branch first.
- Paginated lists cannot pin an item that has not loaded. Fetch the default branch separately and merge it into page one.
- Source width calculations must expand tabs to the same tab stops used for display or long lines will clip.
