#!/usr/bin/env bash
set -euo pipefail

ORG="${ORG:?ORG must be set}"
RULESET_FILE="${RULESET_FILE:-.github/rulesets/default-branches.json}"
RULESET_NAME="$(jq -r '.name' "$RULESET_FILE")"

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
      --input "$RULESET_FILE"

    continue
  fi

  echo "Updating ruleset $ruleset_id"

  gh api \
    --method PUT \
    "repos/$ORG/$repo/rulesets/$ruleset_id" \
    -H 'Accept: application/vnd.github+json' \
    --input "$RULESET_FILE"
done
