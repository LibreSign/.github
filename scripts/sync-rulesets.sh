#!/usr/bin/env bash
set -euo pipefail

DEFAULT_RULESET_FILE=".github/rulesets/default-branches.json"
NEXTCLOUD_BOT="nextcloud-bot"
NEXTCLOUD_BOT_ID="20296731"
CHECK_ONLY=false
TARGET_REPOSITORY=""
TEMP_FILES=()

cleanup() {
  if [ "${#TEMP_FILES[@]}" -gt 0 ]; then
    rm -f "${TEMP_FILES[@]}"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Usage: sync-rulesets.sh [--check] [--repo OWNER/REPO]

Options:
  --check             Report drift without changing repository rulesets.
  --repo OWNER/REPO   Sync only one repository instead of all public repositories.
  -h, --help          Show this help.
EOF
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --check)
        CHECK_ONLY=true
        ;;
      --repo)
        [ "$#" -ge 2 ] || { echo "--repo requires OWNER/REPO" >&2; return 2; }
        TARGET_REPOSITORY="$2"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage >&2
        return 2
        ;;
    esac
    shift
  done
}

list_repositories() {
  if [ -n "$TARGET_REPOSITORY" ]; then
    case "$TARGET_REPOSITORY" in
      "$ORG"/*) printf '%s\n' "${TARGET_REPOSITORY#*/}" ;;
      *) echo "Repository must belong to $ORG: $TARGET_REPOSITORY" >&2; return 2 ;;
    esac
    return
  fi

  gh api \
    --paginate \
    '/installation/repositories?per_page=100' \
    --jq '.repositories[] |
      select(.owner.login == "'"$ORG"'") |
      select(.archived == false) |
      select(.visibility == "public") |
      .name'
}

is_nextcloud_app() {
  local repo="$1"
  local error_file
  error_file="$(mktemp)"
  TEMP_FILES+=("$error_file")

  if gh api "repos/$ORG/$repo/contents/appinfo/info.xml" --silent >/dev/null 2>"$error_file"; then
    return 0
  fi

  if grep -q 'HTTP 404' "$error_file"; then
    return 1
  fi

  echo "Failed to detect whether $ORG/$repo is a Nextcloud app:" >&2
  cat "$error_file" >&2
  return 2
}

build_ruleset() {
  local repo="$1"
  local detection_status=0

  if is_nextcloud_app "$repo"; then
    echo "Nextcloud app detected; allowing $NEXTCLOUD_BOT to bypass the ruleset" >&2
    jq \
      --argjson bot_id "$NEXTCLOUD_BOT_ID" \
      '.bypass_actors = (
        .bypass_actors
        + [{actor_id: $bot_id, actor_type: "User", bypass_mode: "always"}]
        | unique_by([.actor_type, .actor_id])
      )' \
      "$RULESET_FILE"
    return
  else
    detection_status=$?
  fi

  if [ "$detection_status" -eq 1 ]; then
    cat "$RULESET_FILE"
    return
  fi

  return "$detection_status"
}

find_ruleset_id() {
  local repo="$1"
  gh api "repos/$ORG/$repo/rulesets" |
    jq -r --arg name "$RULESET_NAME" '.[] | select(.name == $name) | .id' |
    head -n 1
}

normalize_ruleset() {
  jq -S '
    {
      name,
      target,
      enforcement,
      bypass_actors: [
        .bypass_actors[] |
        {
          actor_id: (if .actor_type == "OrganizationAdmin" then null else .actor_id end),
          actor_type,
          bypass_mode
        }
      ] | sort_by([.actor_type, .actor_id]),
      conditions,
      rules: [
        .rules[] |
        if .type == "pull_request" then
          {
            type,
            parameters: {
              allowed_merge_methods: .parameters.allowed_merge_methods,
              dismiss_stale_reviews_on_push: .parameters.dismiss_stale_reviews_on_push,
              require_code_owner_review: .parameters.require_code_owner_review,
              require_last_push_approval: .parameters.require_last_push_approval,
              required_approving_review_count: .parameters.required_approving_review_count,
              required_review_thread_resolution: .parameters.required_review_thread_resolution
            }
          }
        else
          {type}
        end
      ]
    }
  '
}

ruleset_has_drift() {
  local repo="$1"
  local ruleset_id="$2"
  local desired_file="$3"
  local current desired

  if ! current="$(gh api "repos/$ORG/$repo/rulesets/$ruleset_id" | normalize_ruleset)"; then
    return 2
  fi
  if ! desired="$(normalize_ruleset < "$desired_file")"; then
    return 2
  fi

  [ "$current" != "$desired" ]
}

sync_repository() {
  local repo="$1"
  local desired_file ruleset_id drift_status

  echo "=== $ORG/$repo ==="

  desired_file="$(mktemp)"
  TEMP_FILES+=("$desired_file")
  if ! build_ruleset "$repo" > "$desired_file"; then
    return $?
  fi

  if ! ruleset_id="$(find_ruleset_id "$repo")"; then
    echo "Failed to read rulesets for $ORG/$repo" >&2
    return 2
  fi

  if [ -z "$ruleset_id" ]; then
    if [ "$CHECK_ONLY" = true ]; then
      echo "DRIFT: ruleset is missing"
      return 1
    fi

    echo "Creating ruleset"
    gh api \
      --method POST \
      "repos/$ORG/$repo/rulesets" \
      -H 'Accept: application/vnd.github+json' \
      --input "$desired_file"
    return
  fi

  if ruleset_has_drift "$repo" "$ruleset_id" "$desired_file"; then
    drift_status=0
  else
    drift_status=$?
  fi

  if [ "$drift_status" -eq 2 ]; then
    echo "Failed to compare ruleset for $ORG/$repo" >&2
    return 2
  fi

  if [ "$drift_status" -eq 1 ]; then
    echo "OK: ruleset is up to date"
    return
  fi

  if [ "$CHECK_ONLY" = true ]; then
    echo "DRIFT: ruleset differs from desired configuration"
    return 1
  fi

  echo "Updating ruleset $ruleset_id"
  gh api \
    --method PUT \
    "repos/$ORG/$repo/rulesets/$ruleset_id" \
    -H 'Accept: application/vnd.github+json' \
    --input "$desired_file"
}

main() {
  ORG="${ORG:?ORG must be set}"
  RULESET_FILE="${RULESET_FILE:-$DEFAULT_RULESET_FILE}"
  RULESET_NAME="$(jq -r '.name' "$RULESET_FILE")"

  parse_args "$@"

  local failed=0 repo repositories
  if ! repositories="$(list_repositories)"; then
    return $?
  fi

  while read -r repo; do
    [ -n "$repo" ] || continue
    if ! sync_repository "$repo"; then
      failed=1
    fi
  done <<< "$repositories"

  return "$failed"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
