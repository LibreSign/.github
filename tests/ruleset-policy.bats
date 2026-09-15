#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RULESET_FILE="$REPO_ROOT/.github/rulesets/default-branches.json"
}

@test "ruleset JSON is valid" {
  run jq -e . "$RULESET_FILE"
  [ "$status" -eq 0 ]
}

@test "ruleset is active and protects default and stable branches" {
  run jq -e '
    .enforcement == "active" and
    (.conditions.ref_name.include | index("~DEFAULT_BRANCH") != null) and
    (.conditions.ref_name.include | index("refs/heads/stable*") != null)
  ' "$RULESET_FILE"

  [ "$status" -eq 0 ]
}

@test "ruleset prevents deletion and non-fast-forward updates" {
  run jq -e '
    ([.rules[].type] | index("deletion") != null) and
    ([.rules[].type] | index("non_fast_forward") != null)
  ' "$RULESET_FILE"

  [ "$status" -eq 0 ]
}

@test "pull requests require approval, CODEOWNERS and resolved threads" {
  run jq -e '
    .rules[] |
    select(.type == "pull_request") |
    .parameters.required_approving_review_count >= 1 and
    .parameters.require_code_owner_review == true and
    .parameters.required_review_thread_resolution == true
  ' "$RULESET_FILE"

  [ "$status" -eq 0 ]
}

@test "organization admins can bypass only through pull requests" {
  run jq -e '
    [.bypass_actors[] |
      select(.actor_type == "OrganizationAdmin" and .bypass_mode == "pull_request")
    ] | length == 1
  ' "$RULESET_FILE"

  [ "$status" -eq 0 ]
}
