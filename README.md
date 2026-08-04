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

### Sticky strategies

`sticky-strategy` controls how a sticky comment is updated on later runs (the
first run always posts `comment`/`comment-path`):

- **`edit-append`** (default) — edit the single comment in place, silently (no
  notification on edits). If `reply-path` is set, later runs **append** it below
  the existing body, so the original header stays put and updates accumulate
  underneath (a running log).
- **`edit-latest`** — edit in place, silently, but keep the header and show only
  the **newest** `reply-path` (no history; the comment stays a fixed size).
- **`replace`** — each run posts a **new** comment and **deletes** the previous one,
  so only the latest remains *and* every run notifies (a new comment always
  notifies). `reply-path` is ignored in this mode.

```yaml
steps:
  - label: "Update deploy comment"
    command: "./render-header.sh > /tmp/header.md && ./render-update.sh > /tmp/update.md"
    plugins:
      - NeelamAggarwal/github-pr-comment#v0.1.0:
          pr: "$UPSTREAM_PULL_REQUEST"
          repo: "acme/backend"
          token-env: "GITHUB_API_TOKEN"
          sticky: true
          sticky-strategy: edit-append   # or edit-latest to keep only the newest reply
          comment-path: "/tmp/header.md"   # posted on the first run (the header)
          reply-path: "/tmp/update.md"     # added on every run after the first
```

```yaml
steps:
  - label: "Refresh deploy comment (notify each time)"
    command: "./render-comment.sh > /tmp/comment.md"
    plugins:
      - NeelamAggarwal/github-pr-comment#v0.1.0:
          pr: "$UPSTREAM_PULL_REQUEST"
          repo: "acme/backend"
          token-env: "GITHUB_API_TOKEN"
          sticky: true
          sticky-strategy: replace
          comment-path: "/tmp/comment.md"
```

### Opt-in notifications via a label

Use `notify-label` to make notifications opt-in per PR: the plugin updates the
comment **silently** (using the configured strategy) unless the target PR carries
the label, in which case it switches to `replace` so every run notifies. Handy for
letting individuals opt into pings without spamming everyone.

```yaml
steps:
  - label: "Deploy comment"
    command: "./render-comment.sh > /tmp/comment.md"
    plugins:
      - NeelamAggarwal/github-pr-comment#v0.1.0:
          pr: "$UPSTREAM_PULL_REQUEST"
          repo: "acme/backend"
          token-env: "GITHUB_API_TOKEN"
          sticky: true
          sticky-strategy: edit-append          # silent by default
          notify-label: "notify-deploys-on-pr"  # add this label to the PR to get pings
          comment-path: "/tmp/comment.md"
```

## Configuration

| Option         | Required | Default                        | Description                                                                 |
| -------------- | -------- | ------------------------------ | --------------------------------------------------------------------------- |
| `comment`         | one of\* | —                              | Literal markdown body to post.                                              |
| `comment-path`    | one of\* | —                              | Path to a file whose contents are posted, read at runtime.                  |
| `reply-path`      | no       | —                              | File added to a sticky comment on later runs (`edit-append`/`edit-latest`), read at runtime. |
| `pr`              | no       | `$BUILDKITE_PULL_REQUEST`      | PR number to comment on.                                                     |
| `repo`            | no       | `$BUILDKITE_PULL_REQUEST_REPO` | Target repo as `owner/name` or a git/https URL.                             |
| `token-env`       | no       | `GITHUB_TOKEN`                 | Name of the env var holding the GitHub token (used as a Bearer token).      |
| `expand`          | no       | `false`                        | Expand `$VAR` in the body using the runtime environment (requires envsubst).|
| `sticky`          | no       | `false`                        | Edit a single comment in place across runs instead of posting a new one.    |
| `sticky-key`      | no       | `default`                      | Distinguishes independent sticky comments on the same PR.                   |
| `sticky-strategy` | no       | `edit-append`                  | `edit-append` (in place, silent; appends `reply-path` as a log), `edit-latest` (in place, silent; keeps only the newest `reply-path`), or `replace` (new comment + delete old, notifies). |
| `notify-label`    | no       | —                              | If set, force `replace` (notifies) only when the target PR has this label; else use the configured strategy. Requires `sticky`. |

\* Exactly one of `comment` or `comment-path` must be provided.

## Behavior

- **Non-PR builds** (`pr` empty or `"false"`) are skipped silently.
- A **missing token** logs a warning and skips — it never fails the build.
- A **failed API call** logs a warning with the HTTP status and response body, and
  does **not** fail the build.
- With **`sticky: true`**, a hidden marker is appended to the body so subsequent
  runs locate the same comment. `edit-append` (default) and `edit-latest` edit in
  place (silent); `replace` posts a new comment and deletes the previous one
  (notifies each run).
- With **`reply-path` set**, `edit-append` appends it below the existing comment
  (header + full history preserved) and `edit-latest` keeps the header but shows
  only the newest reply.
- The **first run** for a sticky key always posts `comment`/`comment-path`;
  `reply-path` only applies from the second run onward.
- With **`notify-label` set**, the PR's labels are checked at runtime; the label
  being present forces `replace` (notifies), otherwise the configured strategy is
  used. A failed lookup leaves the strategy unchanged.

## Authentication

The token (from `token-env`, default `GITHUB_TOKEN`) needs permission to comment on
issues/PRs in the target repository. For cross-repo commenting, that means write
access to the *target* repo, not the repo being built.

## Requirements

`bash`, `curl`, and either `jq` or `python3` for JSON encoding (and `envsubst`
from `gettext` when using `expand: true`).

## License

MIT — see [LICENSE](LICENSE).
