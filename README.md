# avijitsinha.com reverse proxy

This nginx service is the public entry point for `avijitsinha.com` and the
legacy `beta.avijitsinha.com` host. It routes each application path to its own
Cloud Run service and serves the Firebase Authentication helper files under
`/__/auth/`.

The production common Account and Routine Dashboard routes are prepared at
`https://avijitsinha.com/account/` and
`https://avijitsinha.com/routine/dashboard/`. Account UI and API paths are
preserved, while the Dashboard's public prefix is stripped before proxying.
Both services' internal-only paths are rejected at the public edge. Common
session cookies reach only Account and Dashboard; they are stripped before
static homepage and Music Training upstreams. The query-safe access-log format
never records query strings. The beta host remains a legacy Music Training
route only and is not a Dashboard deployment target.

Run its routing and log-safety contract with Docker:

```sh
./tests/proxy-contract.sh
```

The test builds the repository image, replaces only the absent production upstream
with a local fixture inside the temporary container, sends requests through
nginx, and removes its temporary image and container when finished.
