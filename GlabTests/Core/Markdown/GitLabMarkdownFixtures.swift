import Foundation

enum GitLabMarkdownFixtures {
    static let small = """
    # Release readiness

    Validate **bold**, *emphasis*, ~~removed~~, `inline code`, and an
    [external link](https://example.com/docs).

    - [x] API contract
    - [ ] Simulator verification
    - [~] Physical-device verification

    See #42, !17, and @reviewer.
    """

    static let mixedSection = """
    ## Deployment checklist

    A paragraph with **strong text**, *emphasis*, ~~obsolete text~~,
    `git status`, [project docs](/help), and [a fragment](#activity).

    1. Prepare
       - [x] Build
       - [ ] Test
       - [~] Ship to a physical device
    2. Review #42 with !17 and @reviewer

    > Keep the rollout small and observable.

    ```swift
    struct Release {
        let identifier: Int
    }
    ```

    | Item | Owner | State |
    |:-----|:-----:|------:|
    | Parser | iOS | Ready |
    | Renderer | UI | Pending |

    ![GitLab mark](/uploads/gitlab-mark.png)

    ---
    """

    static let medium = Array(
        repeating: mixedSection,
        count: 24
    )
    .joined(separator: "\n\n")

    static let large = Array(
        repeating: mixedSection,
        count: 200
    )
    .joined(separator: "\n\n")

    static let malformedAndUnsupported = """
    <!-- issue template instructions must stay hidden -->
    # Visible heading

    [unfinished link](https://example.com

    ```mermaid
    graph TD
      A --> B
    ```

    <details>
    <summary>Server-only layout</summary>
    Hidden in a raw HTML layout.
    </details>
    """
}
