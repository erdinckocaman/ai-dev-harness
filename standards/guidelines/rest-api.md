# REST API

Status: draft. Read this file before you add or change an HTTP endpoint, a request or response
type, or a status code. Review entry point: the "Review checklist" section at the end.

Tags: see `../GUIDELINES.md`, "How to read a rule". Error bodies: `error-handling-and-logging.md`.
Date and time values: `time-and-time-zones.md`.

## Resources and paths

- **REST-1** `review` — A path names resources with plural nouns: `/orders`,
  `/orders/{orderId}/items`. Use a verb only for an action that is not create, read, update or
  delete, as a `POST` sub-resource: `POST /orders/{orderId}/cancellation`.
- **REST-2** `review` — A path segment is lowercase kebab-case. A query parameter and a JSON
  field are `lowerCamelCase`.
- **REST-3** `review` — Every path starts with the major version: `/api/v1/…`. A breaking
  change gets a new major version (REST-16).
- **REST-4** `archunit` — Map a handler method with `@GetMapping`, `@PostMapping`,
  `@PutMapping`, `@PatchMapping` or `@DeleteMapping`. Use `@RequestMapping` only on the class.
- **REST-5** `review` — An ID in a path or a body is an opaque string or a UUID. Do not expose a
  sequential database key.
- **REST-6** `review` — A URL holds no secret and no personal data. Send them in a header or the
  body.

## Methods and status codes

- **REST-7** `review` — `GET` reads and changes nothing. `PUT` replaces and is idempotent.
  `PATCH` changes part of a resource. `DELETE` is idempotent. `POST` creates or runs an action.
- **REST-8** `review` — Return these statuses, and no other unless the PR description says why:

  | Status | When |
  |---|---|
  | `200 OK` | A read or an update with a body |
  | `201 Created` | A `POST` that creates; set the `Location` header |
  | `204 No Content` | A success with no body |
  | `400 Bad Request` | Input fails validation or cannot be read |
  | `401 Unauthorized` | No or invalid authentication |
  | `403 Forbidden` | The caller may not do this |
  | `404 Not Found` | The resource does not exist, or the caller may not know it exists |
  | `409 Conflict` | The request conflicts with the current state (duplicate, wrong state, stale version) |
  | `500 Internal Server Error` | An unexpected failure |
  | `503 Service Unavailable` | A dependency is down; set `Retry-After` when known |

- **REST-9** `review` — An error never returns `2xx`. A success never carries an error object.

## Request and response types

- **REST-10** `archunit` — A controller never takes or returns a JPA entity. The parameters and
  the return type of a public `@RestController` method are not annotated `@Entity`. The review
  also checks generic types, such as `List<Order>` and `ResponseEntity<Order>`.
- **REST-11** `review` — Request and response types are records in the `web` layer. One request
  type per operation; do not reuse a create request for an update.
- **REST-12** `review` — Validate a request body with `@Valid` and Bean Validation constraints on
  the record. Put constraints on path and query parameters too.
- **REST-13** `review` — A list endpoint pages its result: query parameters `page` (from 0) and
  `size` (default 20, maximum 100: `spring.data.web.pageable.max-page-size=100`), and
  `sort=<field>,asc|desc`. The response is the Spring Data `PagedModel`:
  `{"content": [...], "page": {"size", "number", "totalElements", "totalPages"}}`. Return
  `new PagedModel<>(page)`, or set `pageSerializationMode = VIA_DTO` on
  `@EnableSpringDataWebSupport`. Do not serialize a `PageImpl`.
- **REST-14** `review` — Leave a field that has no value out of the JSON:
  `spring.jackson.default-property-inclusion=non_null`. An empty list is `[]`, never left out.

## Compatibility

- **REST-15** `review` — Within a major version, make only additive changes: a new endpoint, a
  new optional request field, a new response field.
- **REST-16** `review` — Removing or renaming a field, changing its type or meaning, making an
  optional field required, or changing a status code is a breaking change. It needs a new major
  version or an agreed migration with every client.
- **REST-17** `review` — Ignore unknown fields in a request. Do not enable
  `FAIL_ON_UNKNOWN_PROPERTIES`.
- **REST-18** `review` — Update the project's hurl acceptance suite in the same change
  (`kit/WORKFLOW.md`, close-out table).

## Review checklist

Walk this list for every changed endpoint. Mark each item pass or fail in the review.

1. Path, method and naming follow REST-1 to REST-4.
2. No sequential key, secret or personal data in the URL (REST-5, REST-6).
3. Each outcome returns the status of REST-8; no error with `2xx` (REST-9).
4. No entity in or out; request and response are web-layer records (REST-10, REST-11).
5. Input is validated; a validation failure returns `400` with a Problem Details body (REST-12,
   ERR-8).
6. A list endpoint pages and sorts as REST-13 says.
7. Date and time fields follow TIME-8.
8. The change is additive, or it is a new major version (REST-15, REST-16).
9. The hurl suite covers the new or changed contract (REST-18).
