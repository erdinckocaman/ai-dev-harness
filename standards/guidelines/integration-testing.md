# Integration testing

Status: draft. Read this file with `testing-strategy.md` when you write a slice test or an
integration test.

An integration test proves that the parts work together: the Spring wiring, the database, the
HTTP layer, the calls to other services. Tags: see `../GUIDELINES.md`, "How to read a rule".

## Infrastructure

- **IT-1** `review` — Run the same database engine, at the same major version, as production,
  in Testcontainers. Do not use H2 or another in-memory substitute.
- **IT-2** `review` — Connect containers with `@ServiceConnection`. Do not hard-code a host, a
  port or a JDBC URL.
- **IT-3** `review` — Declare the containers once, in one `@TestConfiguration` class that the
  tests `@Import`. Every test class that uses the same configuration shares one Spring context.
- **IT-4** `review` — Each extra `@MockitoBean`, `@TestPropertySource` or profile creates a new
  context. Add one only when the test needs it. Use `@DirtiesContext` only with a comment that
  says why.
- **IT-5** `review` — The schema comes from the Flyway migrations, as in production. Do not use
  `spring.jpa.hibernate.ddl-auto=create` or `create-drop` in a test.

## Slice tests

- **IT-6** `review` — Test a controller with `@WebMvcTest(<Controller>.class)` and a
  `@MockitoBean` for each service it calls. Assert the status, the headers and the JSON body,
  error responses included.
- **IT-7** `review` — Test a repository query with `@DataJpaTest`, against the Testcontainers
  database. Spring Boot 3.4 and later keep a `@ServiceConnection` database by default; before
  3.4, add `@AutoConfigureTestDatabase(replace = Replace.NONE)`.

## Full integration tests

- **IT-8** `review` — Use `@SpringBootTest(webEnvironment = RANDOM_PORT)` and call the API over
  HTTP when the test proves a flow end to end.
- **IT-9** `review` — Stub every other service with WireMock. Do not call a real external
  system. Test the timeout, the error status and the malformed response of each client.
- **IT-10** `review` — Each test creates the data it needs and does not rely on data from another
  test. Clean the tables before each test, or use unique keys. In a `RANDOM_PORT` test,
  `@Transactional` on the test does not roll back the server's work.
- **IT-11** `review` — Assert on what a caller can observe: the HTTP response, the data read back
  through the API or a repository, the request that a stub received.
- **IT-12** `review` — Wait for asynchronous work with Awaitility and a timeout of a few seconds.
