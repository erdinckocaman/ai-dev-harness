# Java coding conventions

Status: draft. Read this file for any `.java` file, main or test.

Target: Java 21 or later, Spring Boot 3 or later. Tags: see `../GUIDELINES.md`, "How to read a
rule". The `checkstyle` and `archunit` rules apply to the files that `check.sh` scans; ArchUnit
reads the production classes only, unless a rule says otherwise.

## Format

- **JAVA-1** `checkstyle` — A line has 120 characters or fewer. Exempt: `package` and `import`
  lines, and a line whose only long token is a URL.
- **JAVA-2** `checkstyle` — Indent with 4 spaces. A file contains no tab character.
- **JAVA-3** `checkstyle` — A line has no trailing whitespace. A file ends with a newline.
- **JAVA-4** `checkstyle` — Use braces for every `if`, `else`, `for`, `while` and `do` body, also
  for a body of one line.
- **JAVA-5** `checkstyle` — Do not use a wildcard import (`import x.y.*;`). Remove an unused or a
  redundant import.
- **JAVA-6** `checkstyle` — A file declares one top-level type.

## Names

- **JAVA-7** `checkstyle` — Types are `UpperCamelCase`. Methods, fields, parameters and local
  variables are `lowerCamelCase`. A `static final` constant is `UPPER_SNAKE_CASE`. A package name
  is lowercase letters and digits only, with no underscore.
- **JAVA-8** `checkstyle` — Write an abbreviation as a word: `HttpClient`, `orderId`, not
  `HTTPClient`, `orderID`. No two capital letters follow each other in a name, except in a
  constant.
- **JAVA-9** `review` — A name says what a thing is or does, not how. A boolean reads as a
  question: `isActive`, `hasItems`. Do not name a class `*Helper`, `*Util` or `*Manager` when a
  domain name exists.

## Classes and methods

- **JAVA-10** `checkstyle` — A method has 50 lines or fewer, blank lines not counted.
- **JAVA-11** `checkstyle` — A method or a constructor has 6 parameters or fewer. An overriding
  method is exempt.
- **JAVA-12** `checkstyle` — A class that overrides `equals` also overrides `hashCode`.
- **JAVA-13** `checkstyle` — Compare strings with `equals`, not with `==` or `!=`.
- **JAVA-14** `review` — A class has one responsibility. When you need "and" to describe it,
  split it.
- **JAVA-15** `review` — Make a field `final` when it does not change. Use a `record` for a DTO, a
  value object, a command and an event.
- **JAVA-16** `archunit` — Inject dependencies through the constructor. No field has
  `@Autowired`, `@Inject` or `@Value`. A test class is exempt.

## Null and empty values

- **JAVA-17** `review` — A lookup that can find nothing returns `Optional<T>`. Do not use
  `Optional` as a field, a parameter or a collection element.
- **JAVA-18** `review` — A method that returns a collection returns an empty collection, never
  `null`.
- **JAVA-19** `review` — Validate input at the boundary (request types, message listeners,
  configuration properties). Inside the service, trust the types.

## Lombok and mapping

- **JAVA-20** `review` — Lombok is allowed for `@Getter`, `@RequiredArgsConstructor`, `@Builder`
  and `@Slf4j`. Do not use `@Data`, `@EqualsAndHashCode` or `@ToString` on a JPA entity. Prefer a
  `record` to `@Value`.
- **JAVA-21** `archunit` — Map between types with plain code or MapStruct. Do not use a
  reflection-based mapper: no dependency on `org.modelmapper..`, `org.dozer..`, or a call to
  `BeanUtils.copyProperties`.

## Comments

- **JAVA-22** `review` — A comment says why, not what. Delete a comment that repeats the code.
- **JAVA-23** `review` — Do not commit commented-out code. Do not write a `TODO` without a ticket
  reference.
- **JAVA-24** `review` — Write Javadoc for the public API of a shared library module. A service
  class needs no Javadoc. A test has no Javadoc.

## Language features

- **JAVA-25** `review` — Use `var` only when the type is clear from the right side of the
  assignment.
- **JAVA-26** `review` — Prefer a `switch` expression over a `switch` statement. Over a sealed
  type or an enum, list every case and leave out `default`, so that the compiler reports a new
  case.
- **JAVA-27** `review` — Use streams for a transformation that reads as one pipeline. Use a loop
  when the stream needs side effects or nested lambdas.
