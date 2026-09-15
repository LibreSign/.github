#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=../scripts/sync-rulesets.sh
  source "$REPO_ROOT/scripts/sync-rulesets.sh"

  ORG="LibreSign"
  RULESET_FILE="$REPO_ROOT/.github/rulesets/default-branches.json"
  RULESET_NAME="$(jq -r '.name' "$RULESET_FILE")"
  CHECK_ONLY=false
  TARGET_REPOSITORY=""
  TEMP_FILES=()
}

@test "Nextcloud apps receive the pinned nextcloud-bot bypass" {
  gh() {
    return 0
  }

  result="$(build_ruleset libresign 2>/dev/null)"

  [ "$(jq '[.bypass_actors[] | select(.actor_type == "User" and .actor_id == 20296731 and .bypass_mode == "always")] | length' <<< "$result")" -eq 1 ]
}

@test "non-Nextcloud repositories do not receive the bot bypass" {
  gh() {
    echo "gh: Not Found (HTTP 404)" >&2
    return 1
  }

  result="$(build_ruleset docs)"

  [ "$(jq '[.bypass_actors[] | select(.actor_type == "User" and .actor_id == 20296731)] | length' <<< "$result")" -eq 0 ]
}

@test "unexpected errors while detecting a Nextcloud app fail closed" {
  gh() {
    echo "gh: Resource not accessible (HTTP 403)" >&2
    return 1
  }

  run build_ruleset libresign

  [ "$status" -eq 2 ]
  [[ "$output" == *"Failed to detect whether LibreSign/libresign is a Nextcloud app"* ]]
}

@test "server errors while detecting a Nextcloud app fail closed" {
  gh() {
    echo "gh: Server Error (HTTP 500)" >&2
    return 1
  }

  run build_ruleset libresign

  [ "$status" -eq 2 ]
}

@test "adding the bot bypass is idempotent" {
  fixture="$(mktemp)"
  TEMP_FILES+=("$fixture")
  jq '.bypass_actors += [{actor_id: 20296731, actor_type: "User", bypass_mode: "always"}]' \
    "$RULESET_FILE" > "$fixture"
  RULESET_FILE="$fixture"

  gh() {
    return 0
  }

  result="$(build_ruleset libresign 2>/dev/null)"

  [ "$(jq '[.bypass_actors[] | select(.actor_type == "User" and .actor_id == 20296731)] | length' <<< "$result")" -eq 1 ]
}

@test "repository targeting only accepts repositories from the selected organization" {
  TARGET_REPOSITORY="LibreCodeCoop/profile_fields"

  run list_repositories

  [ "$status" -eq 2 ]
  [[ "$output" == *"Repository must belong to LibreSign"* ]]
}

@test "repository targeting returns only the selected repository name" {
  TARGET_REPOSITORY="LibreSign/libresign"

  run list_repositories

  [ "$status" -eq 0 ]
  [ "$output" = "libresign" ]
}

@test "normalization ignores GitHub API defaults not managed by this policy" {
  desired="$(normalize_ruleset < "$RULESET_FILE")"
  current="$(
    jq '
      .bypass_actors[0].actor_id = null |
      (.rules[] | select(.type == "pull_request") | .parameters) += {
        required_reviewers: [],
        dismissal_restriction: {enabled: false, allowed_actors: []},
        require_extra_approval_for_unattributed_changes: true
      }
    ' "$RULESET_FILE" | normalize_ruleset
  )"

  [ "$current" = "$desired" ]
}
