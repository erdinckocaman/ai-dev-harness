# Unit testing

Read this file with `testing-strategy.md` when you write a unit test.

A unit test proves the logic of one class, fast and without infrastructure. Tags: see
`../GUIDELINES.md`, "How to read a rule".

- **UNIT-1** `review` — A unit test starts no Spring context. It has no `@SpringBootTest`, no
  slice annotation, and no `@ExtendWith(SpringExtension.class)`.
- **UNIT-2** `review` — Create the class under test with `new` in the test, and pass its
  collaborators through the constructor.
- **UNIT-3** `review` — A unit test does no I/O: no database, no file system, no network, no
  wait. One test runs in less than 100 ms.
- **UNIT-4** `review` — Replace a collaborator with a test double only at a boundary that the
  service owns: a repository, a client, a publisher, a `Clock`. Do not mock a value object, a
  record, a collection, or the class under test.
- **UNIT-5** `review` — Do not mock a type that you do not own (a third-party API). Wrap it in a
  class that you own, and mock the wrapper.
- **UNIT-6** `review` — Use Mockito through `@ExtendWith(MockitoExtension.class)`, which fails on
  an unused stub. Do not use `@MockitoBean` in a unit test.
- **UNIT-7** `review` — Assert on the result or on the state that a caller can see. Verify an
  interaction only when the interaction is the behavior (for example, a message is sent). Do not
  verify every call the implementation makes.
- **UNIT-8** `review` — Prefer a hand-written fake (an in-memory repository) to a mock when the
  test needs more than two stubs of the same collaborator.
- **UNIT-9** `review` — Test every branch of the logic: each rule, each boundary value, each
  error that the method throws.
