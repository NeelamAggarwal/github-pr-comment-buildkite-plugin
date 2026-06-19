# github-pr-comment-buildkite-plugin

A [Buildkite plugin](https://buildkite.com/docs/plugins) that posts a comment to a
GitHub pull request — including a PR that lives in a **different repository** than
the one being built.

It runs as a `post-command` hook, so the comment body, target repo, and PR number
are resolved from the **runtime** environment. This is the key difference from
plugins that take a static `comment:` config: values produced by the build, or set
in a pipeline `env:` block, are not available at pipeline-upload time, but they are
available at runtime when this hook executes.

## Why cross-repo?

Some pipelines are triggered by a build in another repository. The triggered build
may want to comment back on the *originating* PR, whose number arrives as a custom
env var and whose repository is not `BUILDKITE_PULL_REQUEST_REPO`. Pass `pr` and
`repo` explicitly to target it.

## Examples

### Same-repo comment

```yaml
steps:
  - command: ./run-tests.sh
    plugins:
      - NeelamAggarwal/github-pr-comment#v0.1.0:
          comment: "Tests passed ✅"
```

Defaults to `$BUILDKITE_PULL_REQUEST` / `$BUILDKITE_PULL_REQUEST_REPO` and
`$GITHUB_TOKEN`.

### Cross-repo comment with a dynamic body (runtime env)

```yaml
steps:
  - label: "Comment on upstream PR"
    command: "true"
    plugins:
      - NeelamAggarwal/github-pr-comment#v0.1.0:
          pr: "$UPSTREAM_PULL_REQUEST"
          repo: "acme/backend"
          token-env: "GITHUB_API_TOKEN"
          expand: true
          comment: |
            ### Build complete

            - **URL:** $$DEPLOY_URL
            - **Status:** $$DEPLOY_STATUS
```

`$$` escapes Buildkite's upload-time interpolation so the literal `$DEPLOY_URL`
reaches the hook, where `expand: true` resolves it against the runtime environment
via `envsubst`.

### Body from a file

```yaml
steps:
  - label: "Comment on PR"
    command: "./render-comment.sh > /tmp/comment.md"
    plugins:
      - NeelamAggarwal/github-pr-comment#v0.1.0:
          pr: "$UPSTREAM_PULL_REQUEST"
          repo: "acme/backend"
          token-env: "GITHUB_API_TOKEN"
          comment-path: "/tmp/comment.md"
```

### Sticky comment (edit in place across runs)

```yaml
steps:
  - label: "Comment on upstream PR"
    command: "true"
    plugins:
      - NeelamAggarwal/github-pr-comment#v0.1.0:
          pr: "$UPSTREAM_PULL_REQUEST"
          repo: "acme/backend"
          token-env: "GITHUB_API_TOKEN"
          sticky: true
          comment: "Build `$$BUILD_TAG` deployed."
```

With `sticky: true`, the first run posts a comment and later runs **edit that same
comment** instead of stacking new ones. The plugin finds its previous comment via a
hidden marker it embeds in the body. Because GitHub does **not** send notifications
for comment *edits*, subscribers are pinged once (on the initial post) and updates
after that are silent. Use `sticky-key` to keep multiple independent sticky comments
on the same PR (e.g. one per environment).

## Configuration

| Option         | Required | Default                        | Description                                                                 |
| -------------- | -------- | ------------------------------ | --------------------------------------------------------------------------- |
| `comment`      | one of\* | —                              | Literal markdown body to post.                                              |
| `comment-path` | one of\* | —                              | Path to a file whose contents are posted, read at runtime.                  |
| `pr`           | no       | `$BUILDKITE_PULL_REQUEST`      | PR number to comment on.                                                     |
| `repo`         | no       | `$BUILDKITE_PULL_REQUEST_REPO` | Target repo as `owner/name` or a git/https URL.                             |
| `token-env`    | no       | `GITHUB_TOKEN`                 | Name of the env var holding the GitHub token (used as a Bearer token).      |
| `expand`       | no       | `false`                        | Expand `$VAR` in the body using the runtime environment (requires envsubst).|
| `sticky`       | no       | `false`                        | Edit a single comment in place across runs instead of posting a new one.    |
| `sticky-key`   | no       | `default`                      | Distinguishes independent sticky comments on the same PR.                   |

\* Exactly one of `comment` or `comment-path` must be provided.

## Behavior

- **Non-PR builds** (`pr` empty or `"false"`) are skipped silently.
- A **missing token** logs a warning and skips — it never fails the build.
- A **failed API call** logs a warning with the HTTP status and response body, and
  does **not** fail the build.
- With **`sticky: true`**, a hidden marker is appended to the body so subsequent
  runs locate and **edit** the same comment. Comment edits do not trigger GitHub
  notifications, so redeploys update silently.

## Authentication

The token (from `token-env`, default `GITHUB_TOKEN`) needs permission to comment on
issues/PRs in the target repository. For cross-repo commenting, that means write
access to the *target* repo, not the repo being built.

## Requirements

`bash`, `curl`, and either `jq` or `python3` for JSON encoding (and `envsubst`
from `gettext` when using `expand: true`).

## License

MIT — see [LICENSE](LICENSE).
