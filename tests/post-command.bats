#!/usr/bin/env bats

# Network-free tests covering the early-exit guards. The happy path performs a
# real GitHub API call and is intentionally not exercised here.

setup() {
  HOOK="${BATS_TEST_DIRNAME}/../hooks/post-command"
  unset BUILDKITE_PULL_REQUEST BUILDKITE_PULL_REQUEST_REPO
  unset BUILDKITE_PLUGIN_GITHUB_PR_COMMENT_PR
  unset BUILDKITE_PLUGIN_GITHUB_PR_COMMENT_REPO
  unset BUILDKITE_PLUGIN_GITHUB_PR_COMMENT_TOKEN_ENV
  unset BUILDKITE_PLUGIN_GITHUB_PR_COMMENT_COMMENT
  unset BUILDKITE_PLUGIN_GITHUB_PR_COMMENT_COMMENT_PATH
  unset BUILDKITE_PLUGIN_GITHUB_PR_COMMENT_STICKY
  unset BUILDKITE_PLUGIN_GITHUB_PR_COMMENT_STICKY_KEY
}

@test "skips when there is no PR number" {
  export BUILDKITE_PULL_REQUEST="false"
  run "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no pull request number; skipping."* ]]
}

@test "skips when the repo cannot be parsed" {
  export BUILDKITE_PLUGIN_GITHUB_PR_COMMENT_PR="123"
  export BUILDKITE_PLUGIN_GITHUB_PR_COMMENT_REPO="not-a-repo"
  run "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"could not parse owner/name"* ]]
}

@test "parses a git URL and then skips on missing token" {
  export BUILDKITE_PLUGIN_GITHUB_PR_COMMENT_PR="123"
  export BUILDKITE_PLUGIN_GITHUB_PR_COMMENT_REPO="git://github.com:acme/backend.git"
  export BUILDKITE_PLUGIN_GITHUB_PR_COMMENT_TOKEN_ENV="DOES_NOT_EXIST_TOKEN"
  run "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"\$DOES_NOT_EXIST_TOKEN is not set; skipping."* ]]
}

@test "skips when token env is unset (owner/name form)" {
  export BUILDKITE_PLUGIN_GITHUB_PR_COMMENT_PR="123"
  export BUILDKITE_PLUGIN_GITHUB_PR_COMMENT_REPO="acme/backend"
  export BUILDKITE_PLUGIN_GITHUB_PR_COMMENT_TOKEN_ENV="DOES_NOT_EXIST_TOKEN"
  run "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"is not set; skipping."* ]]
}

@test "skips when comment-path does not exist" {
  export BUILDKITE_PLUGIN_GITHUB_PR_COMMENT_PR="123"
  export BUILDKITE_PLUGIN_GITHUB_PR_COMMENT_REPO="acme/backend"
  export BUILDKITE_PLUGIN_GITHUB_PR_COMMENT_TOKEN_ENV="FAKE_TOKEN"
  export FAKE_TOKEN="x"
  export BUILDKITE_PLUGIN_GITHUB_PR_COMMENT_COMMENT_PATH="/tmp/does-not-exist-$$.md"
  run "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not found; skipping."* ]]
}

@test "skips when neither comment nor comment-path is set" {
  export BUILDKITE_PLUGIN_GITHUB_PR_COMMENT_PR="123"
  export BUILDKITE_PLUGIN_GITHUB_PR_COMMENT_REPO="acme/backend"
  export BUILDKITE_PLUGIN_GITHUB_PR_COMMENT_TOKEN_ENV="FAKE_TOKEN"
  export FAKE_TOKEN="x"
  run "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"one of 'comment' or 'comment-path' is required"* ]]
}

@test "sticky still honors guards (skips on missing token)" {
  export BUILDKITE_PLUGIN_GITHUB_PR_COMMENT_PR="123"
  export BUILDKITE_PLUGIN_GITHUB_PR_COMMENT_REPO="acme/backend"
  export BUILDKITE_PLUGIN_GITHUB_PR_COMMENT_TOKEN_ENV="DOES_NOT_EXIST_TOKEN"
  export BUILDKITE_PLUGIN_GITHUB_PR_COMMENT_STICKY="true"
  export BUILDKITE_PLUGIN_GITHUB_PR_COMMENT_COMMENT="hi"
  run "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"is not set; skipping."* ]]
}
