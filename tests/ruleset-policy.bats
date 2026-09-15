#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  BASE_RULESET_FILE="$REPO_ROOT/.github/rulesets/default-branches.json"
  GITHUB_CI_RULESET_FILE="$REPO_ROOT/.github/rulesets/libresign-github-ci.json"
}

@test "managed ruleset JSON files are valid" {
  run jq -e . "$BASE_RULESET_FILE" "$GITHUB_CI_RULESET_FILE"
  [ "$status" -eq 0 ]
}

@test "base ruleset is active and protects default and stable branches" {
  run jq -e '
    .enforcement == "active" and
    (.conditions.ref_name.include | index("~DEFAULT_BRANCH") != null) and
    (.conditions.ref_name.include | index("refs/heads/stable*") != null)
  ' "$BASE_RULESET_FILE"

  [ "$status" -eq 0 ]
}

@test "base ruleset prevents deletion and non-fast-forward updates" {
  run jq -e '
    ([.rules[].type] | index("deletion") != null) and
    ([.rules[].type] | index("non_fast_forward") != null)
  ' "$BASE_RULESET_FILE"

  [ "$status" -eq 0 ]
}

@test "base pull request policy requires approval, CODEOWNERS and resolved threads" {
  run jq -e '
    .rules[] |
    select(.type == "pull_request") |
    .parameters.required_approving_review_count >= 1 and
    .parameters.require_code_owner_review == true and
    .parameters.required_review_thread_resolution == true
  ' "$BASE_RULESET_FILE"

  [ "$status" -eq 0 ]
}

@test "organization admins can bypass base policy only through pull requests" {
  run jq -e '
    [.bypass_actors[] |
      select(.actor_type == "OrganizationAdmin" and .bypass_mode == "pull_request")
    ] | length == 1
  ' "$BASE_RULESET_FILE"

  [ "$status" -eq 0 ]
}

@test ".github CI policy applies only to the default branch" {
  run jq -e '
    .enforcement == "active" and
    .conditions.ref_name.include == ["~DEFAULT_BRANCH"] and
    .conditions.ref_name.exclude == []
  ' "$GITHUB_CI_RULESET_FILE"

  [ "$status" -eq 0 ]
}

@test ".github CI policy requires every security and test check" {
  run jq -e '
    .rules[] |
    select(.type == "required_status_checks") |
    .parameters.strict_required_status_checks_policy == true and
    ([.parameters.required_status_checks[].context] | sort) == ([
      "Ruleset sync behavior and policy",
      "ShellCheck",
      "actionlint",
      "zizmor"
    ] | sort)
  ' "$GITHUB_CI_RULESET_FILE"

  [ "$status" -eq 0 ]
}
