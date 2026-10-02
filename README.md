# avijitsinha.com reverse proxy

This nginx service is the public entry point for `avijitsinha.com` and the
legacy `beta.avijitsinha.com` host. It routes each application path to its own
Cloud Run service and serves the Firebase Authentication helper files under
`/__/auth/`.

The production proxy serves the homepage, Music Training and Firebase
Authentication helper files. The retired common Account API/UI and hosted
Routine Dashboard paths return `404` at the public edge and never reach an
upstream. Cookies are stripped before the static homepage and Music Training
upstreams. The query-safe access-log format never records query strings. The
beta host remains a legacy Music Training route only and is not a Dashboard
deployment target.

Run its routing and log-safety contract with Docker:

```sh
./tests/proxy-contract.sh
```

The test builds the repository image, replaces the production upstreams with a
local fixture inside the temporary container, sends requests through nginx,
and removes its temporary image and container when finished.
