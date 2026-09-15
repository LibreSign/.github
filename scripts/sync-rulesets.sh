#!/usr/bin/env bash
set -euo pipefail

ORG="${ORG:?ORG must be set}"
RULESET_FILE="${RULESET_FILE:-.github/rulesets/default-branches.json}"
RULESET_NAME="$(jq -r '.name' "$RULESET_FILE")"
NEXTCLOUD_BOT="${NEXTCLOUD_BOT:-nextcloud-bot}"
NEXTCLOUD_BOT_ID="$(gh api "users/$NEXTCLOUD_BOT" --jq '.id')"

gh api \
  --paginate \
  '/installation/repositories?per_page=100' \
  --jq '.repositories[] |
    select(.owner.login == "'"$ORG"'") |
    select(.archived == false) |
    select(.visibility == "public") |
    .name' |
while read -r repo; do
  echo "=== $ORG/$repo ==="

  effective_ruleset_file="$RULESET_FILE"
  temporary_ruleset_file=""

  if gh api "repos/$ORG/$repo/contents/appinfo/info.xml" --silent >/dev/null 2>&1; then
    echo "Nextcloud app detected; allowing $NEXTCLOUD_BOT to bypass the ruleset"

    temporary_ruleset_file="$(mktemp)"
    jq \
      --argjson bot_id "$NEXTCLOUD_BOT_ID" \
      '.bypass_actors += [{
        actor_id: $bot_id,
        actor_type: "User",
        bypass_mode: "always"
      }]' \
      "$RULESET_FILE" > "$temporary_ruleset_file"
    effective_ruleset_file="$temporary_ruleset_file"
  fi

  ruleset_id="$(
    gh api "repos/$ORG/$repo/rulesets" \
      --jq ".[] | select(.name == \"$RULESET_NAME\") | .id" \
      2>/dev/null |
      head -n 1
  )"

  if [ -z "$ruleset_id" ]; then
    echo "Creating ruleset"

    gh api \
      --method POST \
      "repos/$ORG/$repo/rulesets" \
      -H 'Accept: application/vnd.github+json' \
      --input "$effective_ruleset_file"
  else
    echo "Updating ruleset $ruleset_id"

    gh api \
      --method PUT \
      "repos/$ORG/$repo/rulesets/$ruleset_id" \
      -H 'Accept: application/vnd.github+json' \
      --input "$effective_ruleset_file"
  fi

  if [ -n "$temporary_ruleset_file" ]; then
    rm -f "$temporary_ruleset_file"
  fi
done
