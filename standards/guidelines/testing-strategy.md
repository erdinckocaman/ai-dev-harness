# Testing strategy

Read this file before you write, move or delete a test. Then read
`unit-testing.md` or `integration-testing.md` for the kind of test you write.

Tags: see `../GUIDELINES.md`, "How to read a rule". The `checkstyle` rules here apply to the
test sources.

## Which kind of test

| Kind | Proves | Tool | Guideline |
|---|---|---|---|
| Unit | Logic of one class in `domain` or `service` | JUnit 5, Mockito, AssertJ; no Spring | `unit-testing.md` |
| Slice | One layer with its Spring wiring: a controller, a repository query | `@WebMvcTest`, `@DataJpaTest` | `integration-testing.md` |
| Integration | A flow across layers, with the real database and stubbed neighbors | `@SpringBootTest`, Testcontainers, WireMock | `integration-testing.md` |
| Acceptance | The HTTP contract of a running instance | hurl suites in `projects/<name>/acceptance-tests/` | `kit/acceptance-tests/README.md` |

- **TEST-1** `review` — Test at the lowest level that proves the behavior. Put a branch of
  business logic in a unit test. Use an integration test for what only the wiring, the database
  or the HTTP layer can show.
- **TEST-2** `review` — Test behavior through the public interface of the class or the API.
  Do not test a private method. Do not assert on internal state.
- **TEST-3** `review` — A bug fix starts with a test that fails on the bug.

## Names and shape

- **TEST-4** `review` — Name a test class after what it tests: `<ClassUnderTest>Test` for a unit
  or slice test. For an integration test, follow the service's existing convention. In a new
  service, use `<Feature>IT` and run it with the Maven Failsafe plugin.
- **TEST-5** `review` — A test method name states the condition and the expected result:
  `rejectsOrderWhenStockIsEmpty`. Do not name a test after the method alone (`testCreate`).
- **TEST-6** `review` — A test checks one behavior. Separate arrange, act and assert with a blank
  line. Group the tests of one method or one scenario in a `@Nested` class when a class has many.
- **TEST-7** `review` — Use `@ParameterizedTest` for one behavior over many inputs. Do not loop in
  a test body.

## Tools

- **TEST-8** `checkstyle` — Use JUnit 5 only. A test imports nothing from `org.junit.` outside
  `org.junit.jupiter.` and `org.junit.platform.`.
- **TEST-9** `checkstyle` — Assert with AssertJ. Do not import `org.junit.jupiter.api.Assertions`
  or `org.hamcrest.`. Use `assertThatThrownBy` or `assertThatExceptionOfType` for exceptions.
- **TEST-10** `checkstyle` — Do not call `Thread.sleep` in a test. Wait for an asynchronous
  result with Awaitility and a bounded timeout.

## Independence and determinism

- **TEST-11** `review` — A test does not depend on another test or on the run order. Do not use
  `@TestMethodOrder`. A test does not change static or shared state that it does not reset.
- **TEST-12** `review` — A test gives the same result every run: inject a fixed `Clock`
  (TIME-11), seed every random source, and call no real external system.
- **TEST-13** `review` — Build test data with a builder or a factory method in the test sources.
  Give each test only the fields that matter to it. Use no real personal data.
- **TEST-14** `review` — There is no numeric coverage gate. Every new public behavior and every
  error path that a caller can see has a test.
