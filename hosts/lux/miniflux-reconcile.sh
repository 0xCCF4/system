#!/usr/bin/env bash
# Reconcile Miniflux's subscriptions with the feed list that Nix owns.
#
# The list is rendered at evaluation time and bind-mounted read-only at $desired. This
# script lists the instance once and aborts if that fails, so a broken API or a
# half-started container can never read as "every feed was removed". Afterwards it
# creates missing categories, moves feeds whose category changed, and deletes every feed
# that is not in the list -- Miniflux deletes the feed's entries with it.
#
# Feed URLs are compared with trailing slashes stripped, since Miniflux may store either.
# Miniflux stores a feed under the URL it reaches after redirects, so each listed URL is
# also resolved here: a feed stored under either form counts as listed. If a URL cannot be
# resolved, nothing is deleted in this run (a stored redirect target would look unlisted).

set -o errexit -o nounset -o pipefail

readonly desired="${MINIFLUX_DESIRED_FILE:-/etc/miniflux-feeds.json}"
readonly base="${MINIFLUX_URL:-http://127.0.0.1:8080}"
readonly credentials="${MINIFLUX_CREDENTIALS:-/run/secrets/miniflux-admin-credentials}"

if ! [ -r "$desired" ]; then
  echo "$desired: feed list is not readable" >&2
  exit 1
fi

if ! [ -r "$credentials" ]; then
  echo "$credentials: admin credentials are not readable" >&2
  exit 1
fi

set -o allexport
# shellcheck source=/dev/null
. "$credentials"
set +o allexport

if [ -z "${ADMIN_USERNAME:-}" ] || [ -z "${ADMIN_PASSWORD:-}" ]; then
  echo "$credentials: ADMIN_USERNAME or ADMIN_PASSWORD is empty" >&2
  exit 1
fi

auth=(--user "${ADMIN_USERNAME}:${ADMIN_PASSWORD}")

api() {
  curl --silent --show-error --fail --max-time 60 "${auth[@]}" \
    --header 'Content-Type: application/json' "$@"
}

# The unit is ordered after miniflux.service, but the API may still be starting up.
for _ in $(seq 1 30); do
  if curl --silent --fail --max-time 5 "$base/healthcheck" > /dev/null; then
    break
  fi
  sleep 2
done

# The single listing everything below depends on: if this fails, nothing is deleted.
feeds_json="$(api "$base/v1/feeds")"
categories_json="$(api "$base/v1/categories")"

declare -A category_ids=()
while IFS=$'\t' read -r id title; do
  category_ids["$title"]="$id"
done < <(jq --raw-output '.[] | [.id, .title] | @tsv' <<< "$categories_json")

while IFS= read -r title; do
  if [ -z "${category_ids[$title]:-}" ]; then
    echo "category: creating '$title'"
    id="$(api --request POST "$base/v1/categories" \
      --data "$(jq --null-input --compact-output --arg title "$title" '{title: $title}')" \
      | jq --raw-output '.id')"
    category_ids["$title"]="$id"
  fi
done < <(jq --raw-output \
  '[.[] | .category | select(. != null)] | unique | .[]' "$desired")

declare -A feed_ids=() feed_categories=()
while IFS=$'\t' read -r id url category; do
  feed_ids["$url"]="$id"
  feed_categories["$url"]="$category"
done < <(jq --raw-output \
  '.[] | [.id, (.feed_url | sub("/+$"; "")), (.category.title // "")] | @tsv' <<< "$feeds_json")

# Where each listed URL ends up after redirects (as Miniflux would store it).
declare -A wanted=() effective=()
resolved_all=1
while IFS= read -r url; do
  wanted["$url"]=1
  if target="$(curl --silent --location --output /dev/null --max-time 20 \
    --write-out '%{url_effective}' "$url")" && [ -n "$target" ]; then
    target="${target%/}"
    effective["$url"]="$target"
    wanted["$target"]=1
    if [ "$target" != "$url" ]; then
      echo "feed: '$url' redirects to '$target', consider listing that URL"
    fi
  else
    echo "feed: could not resolve '$url', no deletions in this run" >&2
    resolved_all=0
  fi
done < <(jq --raw-output 'unique_by(.url)[] | .url | sub("/+$"; "")' "$desired")

failed=0
while IFS=$'\t' read -r url category; do
  # bash associative arrays reject the empty string as a key
  wanted_id=""
  if [ -n "$category" ]; then
    wanted_id="${category_ids[$category]:-}"
    if [ -z "$wanted_id" ]; then
      echo "category '$category' of '$url' has no id after creation" >&2
      exit 1
    fi
  fi
  # stored under the listed URL, or under where it redirects to
  stored="$url"
  if [ -z "${feed_ids[$stored]:-}" ] && [ -n "${effective[$url]:-}" ]; then
    stored="${effective[$url]}"
  fi
  if [ -n "${feed_ids[$stored]:-}" ]; then
    # Existing feed: only touch it when the list names a different category.
    if [ -n "$category" ] && [ "$category" != "${feed_categories[$stored]:-}" ]; then
      echo "feed: moving '$url' to '$category'"
      if ! api --request PUT "$base/v1/feeds/${feed_ids[$stored]}" \
        --data "$(jq --null-input --compact-output --argjson category_id "$wanted_id" '{category_id: $category_id}')" \
        > /dev/null; then
        echo "feed: moving '$url' failed, continuing" >&2
        failed=$((failed + 1))
      fi
    fi
  else
    echo "feed: adding '$url'"
    if [ -n "$wanted_id" ]; then
      payload="$(jq --null-input --compact-output --arg url "$url" --argjson category_id "$wanted_id" \
        '{feed_url: $url, category_id: $category_id}')"
    else
      payload="$(jq --null-input --compact-output --arg url "$url" '{feed_url: $url}')"
    fi
    # Miniflux fetches the feed right away: one unreachable or broken feed must not keep
    # the others from being added
    if ! api --request POST "$base/v1/feeds" --data "$payload" > /dev/null; then
      echo "feed: adding '$url' failed, continuing" >&2
      failed=$((failed + 1))
    fi
  fi
done < <(jq --raw-output \
  'unique_by(.url)[] | [(.url | sub("/+$"; "")), (.category // "")] | @tsv' "$desired")

removed=0
while IFS= read -r url; do
  if [ "$resolved_all" -ne 1 ]; then
    break
  fi
  if [ -z "${wanted[$url]:-}" ]; then
    echo "feed: deleting '$url' and its entries (no longer in the Nix list)"
    api --request DELETE "$base/v1/feeds/${feed_ids[$url]}" > /dev/null
    removed=$((removed + 1))
  fi
done < <(jq --raw-output \
  '.[] | .feed_url | sub("/+$"; "")' <<< "$feeds_json")

echo "reconciled: ${#feed_ids[@]} feeds were there, $removed deleted, $failed failed"
# failures stay visible (systemctl --failed); the next run retries them
if [ "$failed" -gt 0 ]; then
  exit 1
fi
