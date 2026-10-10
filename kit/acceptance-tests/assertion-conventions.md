# Assertion conventions (hurl house style)

Every entry in an acceptance suite follows this house style, so the files read
consistently and changes are mechanical. Chosen approach: **field-level** success checks +
**ProblemDetail** structural error checks. No JSON-schema validation, no assertions on localized
message text. A project's own README lists the fields it asserts for each of its resources.

## 1. Every entry

The expected status is the **status line** — it is an assertion, not documentation:

```hurl
GET {{baseUrl}}/api/v1/items/{{itemId}}
HTTP 200
```

Where a body is expected, add the content-type check as the first assert:

```hurl
[Asserts]
header "Content-Type" contains "json"
```

`contains "json"` (not `"application/json"`) is deliberate: it matches both
`application/json` and the `application/problem+json` that Spring's `ProblemDetail` emits, so
success and error entries share one line.

### Naming, which hurl does not have

`pm.test` names (`<METHOD> <path> -> <expectation>`) have no hurl equivalent — hurl reports a
failure as *file + line + actual vs. expected*. The replacement is a **numbered comment above
each entry**, in exactly the old naming shape:

```hurl
# 4. PUT /items/{id} -> 200 updated
```

The number matches `--from-entry` / `--to-entry`, so a reported line number, the comment, and
the entry selector all line up.

## 2. Success bodies — field-level

Assert (a) the fields the suite *captures* exist and have the right type, and (b) the values
the API *echoes back* match what was sent or what an earlier entry captured. Captures come
first, then asserts:

```hurl
HTTP 201
[Captures]
itemKey: jsonpath "$.key"
itemId: jsonpath "$.id"
itemVersion: jsonpath "$.version"
staleVersion: jsonpath "$.version"
[Asserts]
header "Content-Type" contains "json"
jsonpath "$.id" isString
jsonpath "$.key" matches "^acc-test\\."
jsonpath "$.status" == "ACTIVE"
jsonpath "$.version" isInteger
```

A project's field checklist names, per resource, the fields whose presence and type every entry
asserts and the **echoed** fields whose value it compares. A server-set value (a status, a
sequence-minted id) is compared to the value the contract fixes, or asserted by shape when its
digits are not predictable. On an idempotent repeat call, assert the same fields as on the first
call: the repeat returning the same state is the contract, not an accident.

hurl-specific notes:

- **Create cannot echo-check a minted key.** A key minted by `{{newUuid}}` inside the body
  cannot be referenced twice, so create asserts the shape (`matches "^acc-test\\."`) and the
  exact echo check moves to the get entry, against the value captured off the create response.
  The `acc-test.` prefix keeps every row a suite creates on a shared database identifiable.
- **`contains` on a wildcard JSONPath.** `jsonpath "$.content[*].key" contains "{{itemKey}}"`
  is the membership check. When the query matches exactly one row, hurl coerces the one-element
  nodeset to a scalar and `contains` degrades to a substring check on the same string — still
  correct here, since the compared value is the whole key. Use `contains`, not the deprecated
  `includes`.
- **Address a list element by its key, never by its index.** Localizations are asserted through a
  JSONPath **filter** on the locale, because the order of the collection in the response is not
  part of the contract:

  ```hurl
  jsonpath "$.localizations[?(@.locale=='en')].id" == "{{enLocalizationId}}"
  ```

  Inner strings take single quotes (the query itself is double-quoted). The one-element nodeset
  coerces to a scalar, so the same expression works in `[Captures]` and with `==` / `!=`. Pair it
  with `jsonpath "$.localizations" count == 2` — a filter that matches nothing is silently absent,
  so the row count is what pins "and nothing else". Absence is asserted with a negated wildcard:
  `jsonpath "$.localizations[*].locale" not contains "tr"`.

## 3. Error bodies — ProblemDetail, inlined

All 4xx return RFC-9110 `ProblemDetail` (`type`, `title`, `status`, `detail`, `instance`).
Assert structure, **never** the `detail` text (it is i18n-translated → locale-brittle).

The newman collection shared one `assertProblem(code)` helper, `eval`'d from a collection
variable. **hurl has no functions**, so the same four asserts are inlined at each error entry —
verbose, but explicit and greppable:

```hurl
HTTP 409
[Asserts]
header "Content-Type" contains "json"
jsonpath "$.status" == 409
jsonpath "$.type" contains "409"
jsonpath "$.detail" isString
jsonpath "$.detail" matches ".+"
```

`matches ".+"` is the non-empty check (hurl has no string-length predicate); the `detail` text
itself is never compared. The block appears once per error case, with only the code substituted.
Change one, change all.

## 4. Response time

Off — acceptance is about correctness, not latency. hurl can assert it (`duration < 5000`) if
that ever changes. The one timing option in use is a per-entry `[Options] max-time` guard on an
entry that can stall (a synchronous call to a slow dependency, for one), which exists to bound a hang, not to
police speed. `[Options] max-time` is in **milliseconds** unless a unit is given — always write
it as `15s`, never `15`.
