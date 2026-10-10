# Time and time zones

Status: draft. Read this file before you create, parse, store or return a date, a time or a
timestamp, call `now()`, or pick a time zone.

Tags: see `../GUIDELINES.md`, "How to read a rule".

## Types

- **TIME-1** `archunit` — Use `java.time` only. Do not depend on `java.util.Date`,
  `java.util.Calendar`, `java.util.TimeZone`, `java.sql.Date`, `java.sql.Time`,
  `java.sql.Timestamp`, `java.text.SimpleDateFormat` or `org.joda.time..`.
- **TIME-2** `review` — Pick the type by what the value means:

  | Meaning | Java type | Example |
  |---|---|---|
  | A moment on the time line | `Instant` | an order was placed |
  | A calendar date with no time | `LocalDate` | a birth date, a due date |
  | A time of day with no date | `LocalTime` | a shop opens at 09:00 |
  | A local date and time in a named zone, in the future | `LocalDateTime` plus a `ZoneId`, stored apart | a meeting at 09:00 in a city |
  | An amount of time | `Duration` or `Period` | a timeout, a contract term |

- **TIME-3** `review` — A `LocalDateTime` never holds a moment. When you have a moment, use
  `Instant`. Use `OffsetDateTime` or `ZonedDateTime` only to read or write a value at a boundary.

## The current time

- **TIME-4** `archunit` — Production code reads the current time from an injected
  `java.time.Clock`. It does not call a `now()` method without a `Clock` argument, and does not
  call `System.currentTimeMillis()`. Measure an elapsed time with `System.nanoTime()`.
- **TIME-5** `review` — Define one `Clock` bean (`Clock.systemUTC()`) in `config`. Tests replace
  it with a fixed clock.

## Time zones

- **TIME-6** `archunit` — Do not use the default time zone of the JVM: no
  `ZoneId.systemDefault()` and no `TimeZone.getDefault()`.
- **TIME-7** `review` — When a rule depends on a local day ("today", "end of the month"), name
  the zone in configuration or in a constant, and compute with it:
  `LocalDate.now(clock.withZone(zone))`.

## Storage and transport

- **TIME-8** `review` — In JSON, a moment is an ISO-8601 string in UTC with a `Z`:
  `"2026-10-08T07:30:00Z"`. A date is `"2026-10-08"`. Do not send an epoch number. Accept an
  input with any offset and convert it to `Instant`.
- **TIME-9** `review` — In the database, a moment is a timestamp column with time zone
  (`timestamptz` in PostgreSQL). A date is `date`. Do not store a moment in a timestamp column
  without time zone.
- **TIME-10** `review` — Run the JVM and the database session in UTC as a safety net
  (`hibernate.jdbc.time_zone=UTC`). The code does not depend on it.
- **TIME-11** `review` — Tests use `Clock.fixed(...)` and assert on exact values. A test never
  compares with the real current time.
- **TIME-12** `review` — Format and parse with the `DateTimeFormatter.ISO_*` constants. A custom
  pattern sets the locale explicitly (`Locale.ROOT` for a machine-readable value).
