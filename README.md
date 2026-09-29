# avijitsinha.com reverse proxy

This nginx service is the public entry point for `avijitsinha.com` and
`beta.avijitsinha.com`. It routes each application path to its own Cloud Run
service and serves the Firebase Authentication helper files under `/__/auth/`.

The beta Routine Dashboard route is prepared locally at
`/routine/dashboard/`. It strips that public prefix before proxying, rejects
the internal worker path, and uses a query-safe access-log format. The route
has not been deployed.

Run its routing and log-safety contract with Docker:

```sh
./tests/proxy-contract.sh
```

The test builds the repository image, replaces only the absent beta upstream
with a local fixture inside the temporary container, sends requests through
nginx, and removes its temporary image and container when finished.
