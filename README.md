# avijitsinha.com reverse proxy

This nginx service is the public entry point for `avijitsinha.com` and the
legacy `beta.avijitsinha.com` host. It routes each application path to its own
Cloud Run service and serves the Firebase Authentication helper files under
`/__/auth/`.

The production Routine Dashboard route is prepared locally at
`https://avijitsinha.com/routine/dashboard/`. It strips that public prefix
before proxying, rejects the internal worker path, and uses a query-safe
access-log format. The route has not been deployed. The beta host remains a
legacy Music Training route only and is not a Dashboard deployment target.

Run its routing and log-safety contract with Docker:

```sh
./tests/proxy-contract.sh
```

The test builds the repository image, replaces only the absent production upstream
with a local fixture inside the temporary container, sends requests through
nginx, and removes its temporary image and container when finished.
