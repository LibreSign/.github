#!/usr/bin/env bash
set -euo pipefail

DEFAULT_RULESET_FILE=".github/rulesets/default-branches.json"
NEXTCLOUD_BOT="nextcloud-bot"
NEXTCLOUD_BOT_ID="20296731"
CHECK_ONLY=false
TARGET_REPOSITORY=""

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

  if gh api "repos/$ORG/$repo/contents/appinfo/info.xml" --silent >/dev/null 2>"$error_file"; then
    rm -f "$error_file"
    return 0
  fi

  if grep -q 'HTTP 404' "$error_file"; then
    rm -f "$error_file"
    return 1
  fi

  echo "Failed to detect whether $ORG/$repo is a Nextcloud app:" >&2
  cat "$error_file" >&2
  rm -f "$error_file"
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
  gh api "repos/$ORG/$repo/rulesets" \
    --jq '.[] | select(.name == $name) | .id' \
    -f name="$RULESET_NAME" \
    2>/dev/null |
    head -n 1
}

normalize_ruleset() {
  jq -S '{name, target, enforcement, bypass_actors, conditions, rules}'
}

ruleset_has_drift() {
  local repo="$1"
  local ruleset_id="$2"
  local desired_file="$3"
  local current desired

  current="$(gh api "repos/$ORG/$repo/rulesets/$ruleset_id" | normalize_ruleset)"
  desired="$(normalize_ruleset < "$desired_file")"

  [ "$current" != "$desired" ]
}

sync_repository() {
  local repo="$1"
  local desired_file ruleset_id

  echo "=== $ORG/$repo ==="

  desired_file="$(mktemp)"
  trap 'rm -f "$desired_file"' RETURN
  build_ruleset "$repo" > "$desired_file"

  ruleset_id="$(find_ruleset_id "$repo")"

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

  if ! ruleset_has_drift "$repo" "$ruleset_id" "$desired_file"; then
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

  local failed=0 repo
  while read -r repo; do
    [ -n "$repo" ] || continue
    if ! sync_repository "$repo"; then
      failed=1
    fi
  done < <(list_repositories)

  return "$failed"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
