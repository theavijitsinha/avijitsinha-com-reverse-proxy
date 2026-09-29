#!/bin/sh

set -eu

repository_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
temporary_dir=$(mktemp -d)
container_name="reverse-proxy-contract-$$"
image_tag="reverse-proxy-contract:$$"

cleanup() {
    docker rm --force "$container_name" >/dev/null 2>&1 || true
    docker image rm --force "$image_tag" >/dev/null 2>&1 || true
    rm -rf "$temporary_dir"
}

trap cleanup EXIT INT TERM

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    haystack=$1
    needle=$2
    description=$3

    printf '%s' "$haystack" | grep -F "$needle" >/dev/null || fail "$description"
}

assert_not_contains() {
    haystack=$1
    needle=$2
    description=$3

    if printf '%s' "$haystack" | grep -F "$needle" >/dev/null; then
        fail "$description"
    fi
}

sed 's#https://routine-dashboard-beta-553636919043.us-west1.run.app/#http://127.0.0.1:8081/#' \
    "$repository_dir/nginx.conf" > "$temporary_dir/nginx.conf"

docker build --quiet --tag "$image_tag" "$repository_dir" >/dev/null

docker run --detach --rm \
    --name "$container_name" \
    --publish 127.0.0.1::8080 \
    --volume "$temporary_dir/nginx.conf:/etc/nginx/conf.d/nginx.conf:ro" \
    --volume "$repository_dir/tests/mock-upstream.conf:/etc/nginx/conf.d/mock-upstream.conf:ro" \
    "$image_tag" >/dev/null

published_address=$(docker port "$container_name" 8080/tcp)
base_url="http://$published_address"

attempt=0
until curl --fail --silent --output /dev/null \
    --header 'Host: beta.avijitsinha.com' \
    "$base_url/routine/dashboard"; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 30 ]; then
        fail 'nginx did not become ready'
    fi
    sleep 0.1
done

redirect_response=$(curl --http1.1 --silent --include \
    --header 'Host: beta.avijitsinha.com' \
    "$base_url/routine/dashboard")
assert_contains "$redirect_response" 'HTTP/1.1 308 Permanent Redirect' \
    'slashless dashboard path did not return 308'
assert_contains "$redirect_response" 'Location: /routine/dashboard/' \
    'slashless dashboard path did not use a safe relative redirect'

proxied_response=$(curl --http1.1 --silent --include \
    --header 'Host: beta.avijitsinha.com' \
    "$base_url/routine/dashboard/api/me?fixture_query=retained_upstream")
assert_contains "$proxied_response" 'HTTP/1.1 200 OK' \
    'dashboard request did not reach the fixture upstream'
assert_contains "$proxied_response" 'X-Observed-Uri: /api/me?fixture_query=retained_upstream' \
    'dashboard prefix was not stripped before proxying'
assert_contains "$proxied_response" 'X-Observed-Host: beta.avijitsinha.com' \
    'external host was not forwarded'
assert_contains "$proxied_response" 'X-Observed-Forwarded-Proto: http' \
    'request scheme was not forwarded'

for internal_path in \
    '/routine/dashboard/internal' \
    '/routine/dashboard/internal/' \
    '/routine/dashboard/internal/sync/calendar' \
    '/routine/dashboard//internal/sync/calendar' \
    '/routine/dashboard/api/../internal/sync/calendar'; do
    internal_response=$(curl --http1.1 --path-as-is --silent --include \
        --header 'Host: beta.avijitsinha.com' \
        "$base_url$internal_path")
    assert_contains "$internal_response" 'HTTP/1.1 404 Not Found' \
        "internal path was not denied: $internal_path"
    assert_not_contains "$internal_response" 'X-Observed-Uri:' \
        "internal path reached the upstream: $internal_path"
done

curl --http1.1 --silent --output /dev/null \
    --header 'Host: beta.avijitsinha.com' \
    "$base_url/routine/dashboard/api/integrations/google/calendar/callback?code=oauth_code_must_not_log&state=oauth_state_must_not_log"

curl --http1.1 --silent --output /dev/null \
    --header 'Host: avijitsinha.com' \
    "$base_url/__/auth/not-found?production_query_must_not_log"

container_logs=$(docker logs "$container_name" 2>&1)
assert_contains "$container_logs" \
    '"GET /routine/dashboard/api/integrations/google/calendar/callback HTTP/1.1"' \
    'normalized OAuth callback path was absent from the access log'
assert_not_contains "$container_logs" 'oauth_code_must_not_log' \
    'OAuth code query value appeared in container logs'
assert_not_contains "$container_logs" 'oauth_state_must_not_log' \
    'OAuth state query value appeared in container logs'
assert_not_contains "$container_logs" 'fixture_query=retained_upstream' \
    'ordinary query value appeared in container logs'
assert_not_contains "$container_logs" 'production_query_must_not_log' \
    'production-host query value appeared in container logs'

printf 'Reverse-proxy contract passed.\n'
