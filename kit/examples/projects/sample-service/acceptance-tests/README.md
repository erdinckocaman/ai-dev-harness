# orders-service — acceptance tests

Conventions: `../../../kit/acceptance-tests/README.md` (running, gating) and
`assertion-conventions.md` (house style).

## Suites

| Suite | Covers |
|---|---|
| `items` | Create, read, update and archive an item; the not-found error |

## Gated blocks

| Variable | Gate | Why |
|---|---|---|
| `skipItemArchive` | `@requires 1.2.0` | `POST /items/{id}/archive` shipped in 1.2.0 |
| `skipStoreUnavailable` | `@requires-env store-unavailable` | Asserts the 503 that only a target with its store stopped returns |

## Fields asserted

`item`: `id` (string), `key` (string, `acc-test.` prefix), `version` (integer); echoed `name`,
`status`.
