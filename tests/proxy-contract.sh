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

sed \
    -e 's#https://music-training-553636919043.us-west1.run.app/#http://127.0.0.1:8081/#' \
    -e 's#https://avijitsinha-com-553636919043.us-west1.run.app/#http://127.0.0.1:8081/#' \
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
    --header 'Host: avijitsinha.com' \
    "$base_url/music/training/intervals/"; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 30 ]; then
        fail 'nginx did not become ready'
    fi
    sleep 0.1
done

music_redirect_response=$(curl --http1.1 --silent --include \
    --header 'Host: avijitsinha.com' \
    "$base_url/music/training")
assert_contains "$music_redirect_response" 'HTTP/1.1 308 Permanent Redirect' \
    'slashless Music Training path did not return 308'
assert_contains "$music_redirect_response" 'Location: /music/training/intervals/' \
    'slashless Music Training path did not use its canonical route'

music_response=$(curl --http1.1 --silent --include \
    --header 'Host: avijitsinha.com' \
    --header 'Cookie: avijitsinha_session=must_not_reach_music' \
    "$base_url/music/training/intervals/")
assert_contains "$music_response" 'HTTP/1.1 200 OK' \
    'Music Training request did not reach the fixture upstream'
assert_not_contains "$music_response" 'must_not_reach_music' \
    'common session cookie reached the static Music Training upstream'

homepage_response=$(curl --http1.1 --silent --include \
    --header 'Host: avijitsinha.com' \
    --header 'Cookie: avijitsinha_session=must_not_reach_homepage' \
    "$base_url/")
assert_contains "$homepage_response" 'HTTP/1.1 200 OK' \
    'homepage request did not reach the fixture upstream'
assert_not_contains "$homepage_response" 'must_not_reach_homepage' \
    'common session cookie reached the static homepage upstream'

for retired_path in \
    '/account' \
    '/account/' \
    '/account/app.js' \
    '/api/account' \
    '/api/account/' \
    '/api/account/me' \
    '/internal/account' \
    '/internal/account/' \
    '/internal/account/sessions:authorize' \
    '/routine/dashboard' \
    '/routine/dashboard/' \
    '/routine/dashboard/internal' \
    '/routine/dashboard/internal/' \
    '/routine/dashboard/internal/sync/calendar' \
    '/routine/dashboard//internal/sync/calendar' \
    '/routine/dashboard/api/../internal/sync/calendar'; do
    retired_response=$(curl --http1.1 --path-as-is --silent --include \
        --header 'Host: avijitsinha.com' \
        "$base_url$retired_path")
    assert_contains "$retired_response" 'HTTP/1.1 404 Not Found' \
        "retired path was not denied: $retired_path"
    assert_not_contains "$retired_response" 'X-Observed-Uri:' \
        "retired path reached an upstream: $retired_path"
done

curl --http1.1 --silent --output /dev/null \
    --header 'Host: avijitsinha.com' \
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
assert_not_contains "$container_logs" 'production_query_must_not_log' \
    'production-host query value appeared in container logs'

printf 'Reverse-proxy contract passed.\n'
