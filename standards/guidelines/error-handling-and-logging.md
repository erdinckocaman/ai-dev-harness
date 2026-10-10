# Error handling and logging

Status: draft. Read this file before you throw, catch or map an exception, add a log line, or
call another service.

Tags: see `../GUIDELINES.md`, "How to read a rule".

## Exceptions

- **ERR-1** `archunit` — Do not throw `Exception`, `RuntimeException`, `Throwable` or `Error`.
  Throw a type that names the failure.
- **ERR-2** `review` — Use unchecked exceptions. A domain failure is its own class in the
  `domain` layer, named after the condition: `OrderNotFoundException`,
  `InsufficientStockException`.
- **ERR-3** `checkstyle` — A `catch` block is not empty. An empty block is allowed only when the
  variable is named `ignored` or `expected`.
- **ERR-4** `review` — Catch an exception only to recover, to add context, or to translate it at
  a layer boundary. Otherwise let it propagate.
- **ERR-5** `review` — When you translate or wrap an exception, pass the original as the cause.
- **ERR-6** `review` — Catch `Exception` or `Throwable` only at a boundary that must keep
  running: a scheduled job, a message listener. Log the error there.
- **ERR-7** `archunit` — `service` and `domain` do not depend on `org.springframework.web..`.
  They do not throw `ResponseStatusException` and do not see a client exception. The `client`
  layer translates `RestClientException` and its subtypes into the service's own exceptions.

## Error responses

- **ERR-8** `review` — Every `4xx` and `5xx` response has an RFC 9457 Problem Details body
  (`application/problem+json`) with `type`, `title`, `status`, `detail` and `instance`, plus:
  - `errorCode` — a stable, `UPPER_SNAKE_CASE` code for the failure, for example
    `ORDER_NOT_FOUND`. A released code never changes its meaning.
  - `errors` — for a validation failure only: a list of `{"field", "message"}`.
- **ERR-9** `review` — One `@RestControllerAdvice` maps exceptions to responses. It extends
  `ResponseEntityExceptionHandler`, so the framework's own exceptions get the same body. A
  controller has no `try`/`catch` to build an error response.
- **ERR-10** `review` — A `500` response says only that an unexpected error happened. It carries
  no exception message, no stack trace, no SQL and no class name.

## Calls to other services

- **ERR-11** `review` — Every outbound call sets a connect timeout and a read timeout. Do not
  rely on a library default.
- **ERR-12** `review` — Retry only an idempotent call, with a bounded number of attempts and a
  backoff. Do not retry a `4xx` response, except `429`.
- **ERR-13** `review` — When a dependency fails, return `503` or a documented fallback. Do not
  return `500` for a failure that you expected.

## Logging

- **ERR-14** `archunit` — Log through SLF4J. Do not use `java.util.logging`, `System.out`,
  `System.err` or `printStackTrace()`.
- **ERR-15** `review` — Declare the logger as
  `private static final Logger log = LoggerFactory.getLogger(<Class>.class)`, or use Lombok
  `@Slf4j`.
- **ERR-16** `review` — Use placeholders: `log.info("Order {} created", orderId)`. Do not
  concatenate strings. Pass the exception as the last argument, not `e.getMessage()`.
- **ERR-17** `review` — Use the levels this way:

  | Level | When |
  |---|---|
  | `ERROR` | An unexpected failure that a person must look at. Include the stack trace. |
  | `WARN` | A handled problem that can become a failure: a retry, a fallback, a rejected input that should not happen |
  | `INFO` | A business event or a lifecycle event: an order is placed, a job starts and ends |
  | `DEBUG` | Detail for diagnosis. Off in production by default. |

- **ERR-18** `review` — Log an exception once, where it is handled. Do not log and rethrow. A
  `4xx` caused by the client is logged at `INFO` or `WARN`, without a stack trace.
- **ERR-19** `review` — Never log a secret, a token, a password, a full request or response body,
  or personal data (name, e-mail address, phone number, card number, address).
- **ERR-20** `review` — Each log line carries the trace ID of the request (Micrometer Tracing in
  the MDC). Do not invent a second correlation mechanism.
- **ERR-21** `review` — Do not log at `INFO` or above inside a loop over the items of a request.
