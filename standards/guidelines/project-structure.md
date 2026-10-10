# Project structure

Read this file before you add a class, a package, a module or a dependency, and
before you edit `pom.xml` or `application*.yml`.

The structure is a layered architecture. It fits a service with one bounded context and mostly
CRUD logic. A service that needs another architecture records it in an ADR in
`projects/<name>/docs/adr/` and lists the rules below that it replaces. Tags: see
`../GUIDELINES.md`, "How to read a rule".

## Packages and layers

The **base package** is the package of the class annotated `@SpringBootApplication`. Below it,
each production class sits in exactly one **layer package**. A layer package is a package
segment with one of these names:

| Layer | Holds |
|---|---|
| `web` | `@RestController` classes, request and response records, `@RestControllerAdvice`, web mappers |
| `service` | `@Service` classes: use cases, transactions, orchestration |
| `domain` | Entities, value objects, domain exceptions, domain events, domain logic |
| `repository` | Spring Data repository interfaces and custom query classes |
| `client` | Outbound adapters: HTTP clients of other services, with their own DTOs |
| `config` | `@Configuration` and `@ConfigurationProperties` classes |

The layer segment can come first (`com.example.orders.web.OrderController`) or after a feature
segment (`com.example.orders.invoice.web.InvoiceController`). One service uses one of the two
forms.

- **STRUCT-1** `archunit` — Every production class sits in a layer package, except the
  `@SpringBootApplication` class, which sits in the base package.
- **STRUCT-2** `archunit` — A layer uses only the layers that this table allows:

  | Layer | May use |
  |---|---|
  | `web` | `service`, `domain`, `config` |
  | `service` | `domain`, `repository`, `client`, `config` |
  | `repository` | `domain` |
  | `client` | `domain`, `config` |
  | `domain` | — |
  | `config` | every layer |

- **STRUCT-3** `archunit` — An annotated class sits in its layer: `@RestController`,
  `@Controller` and `@RestControllerAdvice` in `web`; `@Service` in `service`; `@Repository` and
  every subtype of Spring Data `Repository` in `repository`; `@Entity` and `@Embeddable` in
  `domain`; `@Configuration` and `@ConfigurationProperties` in `config`.
- **STRUCT-4** `archunit` — The feature packages directly below the base package have no
  dependency cycle.
- **STRUCT-5** `review` — Make a class package-private when no other package uses it.

## Build

- **STRUCT-6** `review` — A service is a multi-module Maven reactor with one `*-container` module
  that starts the application: the shape that the kit scripts assume (`kit/README.md`,
  "Requirements and limits"). A service that does not fit records the gap in an ADR.
- **STRUCT-7** `review` — Let the Spring Boot parent or BOM manage dependency versions. Do not
  give a version to a managed dependency. Put every other version in `<properties>`.
- **STRUCT-8** `review` — A dependency that only tests use has `test` scope.
- **STRUCT-9** `review` — Add a dependency only when CORE-5 allows it. Say in the PR description
  why the dependency is needed.

## Configuration

- **STRUCT-10** `review` — `application.yml` holds the defaults. A profile file
  (`application-<profile>.yml`) holds only what differs for that profile.
- **STRUCT-11** `review` — No secret is in a committed configuration file. Read secrets from
  environment variables or a secret store.
- **STRUCT-12** `review` — Bind a group of settings to a `@ConfigurationProperties` record with
  `@Validated`. Do not spread `@Value` over many classes.
- **STRUCT-13** `review` — A new property has a default or makes startup fail with a clear
  message. A service never starts with a missing required value.
