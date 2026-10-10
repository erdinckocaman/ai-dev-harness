# Database and Flyway migrations

Read this file before you write SQL, a Flyway migration, a JPA entity or a
repository query.

The examples use PostgreSQL. For another engine, use its equivalent type. Tags: see
`../GUIDELINES.md`, "How to read a rule".

## Names

- **DB-1** `review` — Tables and columns are lowercase `snake_case`. A table name is a plural
  noun (`orders`, `order_items`); the plural also avoids reserved words such as `order` and
  `user`.
- **DB-2** `review` — The primary key column is `id`. A foreign key column is
  `<referenced entity>_id`, for example `order_id`.
- **DB-3** `review` — Name every constraint and index yourself: `pk_<table>`,
  `fk_<table>_<column>`, `uq_<table>_<columns>`, `ck_<table>_<rule>`, `ix_<table>_<columns>`.

## Keys and types

- **DB-4** `review` — Every table has a primary key. The key is a `uuid` that the application
  sets, time-ordered (version 7) where the library supports it.
- **DB-5** `review` — Every foreign key column has an index, unless it is the first column of
  another index.
- **DB-6** `review` — A column is `NOT NULL` unless "no value" has a meaning in the domain.
- **DB-7** `review` — Use `text` for a string. Add a length limit (`varchar(n)` or a `CHECK`) only
  when the domain has a real limit, and name its source in the migration.
- **DB-8** `review` — Money and other exact numbers are `numeric(p, s)`, never `real` or
  `double precision`. A fixed set of values is `text` with a `CHECK` constraint, not a database
  enum type.
- **DB-9** `review` — A moment is `timestamptz`; a date is `date` (TIME-9). A table that the
  service updates has `created_at` and `updated_at`, both `timestamptz NOT NULL`.
- **DB-10** `review` — Use `jsonb` only for data that the service stores and returns whole, and
  does not query by its fields.

## Flyway migrations

- **DB-11** `commit-check` — A migration file is
  `src/main/resources/db/migration/V<yyyyMMddHHmm>__<description>.sql`. The version is the UTC
  time of creation; it does not collide between branches. `<description>` is lowercase
  `snake_case`. Set `spring.flyway.out-of-order=true`, so that a migration from a branch that
  merges later than a newer one still runs.
- **DB-12** `commit-check` — Never change, rename or delete a migration that the default branch
  has. Fix a mistake with a new migration.
- **DB-13** `review` — One migration makes one logical change. Do not mix a schema change with a
  large data change.
- **DB-14** `review` — A migration is compatible with the version of the service that runs while
  it is applied. To rename or remove a column: add the new one, write both, move the readers,
  then drop the old one in a later release.
- **DB-15** `review` — A migration that changes an existing table starts with
  `SET lock_timeout = '10s';`, so that a blocked migration fails fast and does not block traffic.
- **DB-16** `review` — Create an index on a large existing table with
  `CREATE INDEX CONCURRENTLY`, alone in its own migration that Flyway runs outside a transaction.
- **DB-17** `review` — Use a repeatable migration (`R__`) only for views and functions. Do not use
  undo migrations; roll back with a new forward migration.

## JPA and queries

- **DB-18** `review` — Hibernate never changes the schema: `spring.jpa.hibernate.ddl-auto` is
  `validate` or `none`.
- **DB-19** `review` — Set `spring.jpa.open-in-view=false`.
- **DB-20** `review` — Map every `@ManyToOne` and `@OneToOne` with `fetch = FetchType.LAZY`. Load
  what a list needs in one query (a fetch join or an entity graph). Do not load in a loop.
- **DB-21** `archunit` — Put `@Transactional` only on classes and methods in the `service`
  layer. Mark a read-only use case `@Transactional(readOnly = true)`.
- **DB-22** `review` — Bind every value as a parameter. Never build SQL or JPQL by string
  concatenation with input.
- **DB-23** `review` — A query that can return many rows is paged. Its order ends with a unique
  column, so that pages are stable.
- **DB-24** `review` — An entity that two users can update at the same time has a
  `version bigint NOT NULL` column mapped with `@Version`. A version conflict returns `409`.
