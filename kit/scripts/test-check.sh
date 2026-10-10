#!/usr/bin/env bash
# Tests for check.sh at its outer seam: exit status and output.
#
# Builds a small Spring-Boot-shaped Maven repository in a temp folder (sources compiled with
# javac against annotation stubs, so no Spring download), with a branch one commit ahead of
# origin/main and a project folder whose service.env points at it. Each case copies that
# fixture, seeds a violation, runs check.sh and asserts the exit status and the rule ID in the
# output. Two cases seed one violation of every Checkstyle and every ArchUnit rule, each in its
# own file, and assert each rule ID on its file in one run.
#
# Usage: kit/scripts/test-check.sh
# Needs java (21 or later), javac, mvn and git. The first run downloads the Maven dependencies
# of kit/checks/.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
check="$here/check.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
pass=0 fail=0
export MS_KIT_PROJECTS_DIR="$tmp/projects"
mkdir -p "$MS_KIT_PROJECTS_DIR"

# --- Fixture ----------------------------------------------------------------------------------

# put <file> — writes stdin to <file>, creating its folder.
put() { mkdir -p "$(dirname "$1")"; cat > "$1"; }

stub() { # stub <fully qualified annotation name>
  local fqn="$1" pkg="${1%.*}" name="${1##*.}"
  put "$tmp/stubs-src/$(echo "$fqn" | tr . /).java" <<EOF
package $pkg;

public @interface $name {
    String[] value() default {};
}
EOF
}
for a in org.springframework.boot.autoconfigure.SpringBootApplication \
  org.springframework.stereotype.Service \
  org.springframework.web.bind.annotation.RestController \
  org.springframework.web.bind.annotation.RequestMapping \
  org.springframework.web.bind.annotation.GetMapping \
  org.springframework.transaction.annotation.Transactional \
  org.springframework.beans.factory.annotation.Autowired \
  jakarta.persistence.Entity \
  lombok.Getter; do
  stub "$a"
done
put "$tmp/stubs-src/org/springframework/data/jpa/repository/JpaRepository.java" <<'EOF'
package org.springframework.data.jpa.repository;

public interface JpaRepository<T, I> {
}
EOF
put "$tmp/stubs-src/org/modelmapper/ModelMapper.java" <<'EOF'
package org.modelmapper;

public class ModelMapper {

    public <D> D map(Object source, Class<D> type) {
        return null;
    }
}
EOF
put "$tmp/stubs-src/org/springframework/web/server/ResponseStatusException.java" <<'EOF'
package org.springframework.web.server;

public class ResponseStatusException extends RuntimeException {
}
EOF
mkdir -p "$tmp/stubs"
javac --release 21 -d "$tmp/stubs" $(find "$tmp/stubs-src" -name '*.java') || exit 1

# compile <repo> — compiles src/main/java into target/classes, as `mvn compile` would.
compile() {
  rm -rf "$1/target/classes"
  mkdir -p "$1/target/classes"
  javac --release 21 -cp "$tmp/stubs" -d "$1/target/classes" $(find "$1/src/main/java" -name '*.java')
}

commit() { # commit <repo> <message> — commits every change with that message.
  git -C "$1" add -A && git -C "$1" commit -q --no-verify -m "$2"
}

tpl="$tmp/template"
main="$tpl/src/main/java/com/example/orders"
put "$tpl/pom.xml" <<'EOF'
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>orders-service</artifactId>
  <version>1.0.0</version>
</project>
EOF
put "$main/OrdersApplication.java" <<'EOF'
package com.example.orders;

import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class OrdersApplication {

    public static void main(String[] args) {
        // Spring Boot starts here in a real service.
    }
}
EOF
put "$main/domain/Order.java" <<'EOF'
package com.example.orders.domain;

public record Order(String name) {
}
EOF
put "$main/domain/OrderNotFoundException.java" <<'EOF'
package com.example.orders.domain;

public class OrderNotFoundException extends RuntimeException {

    public OrderNotFoundException(String id) {
        super("no order " + id);
    }
}
EOF
put "$main/service/OrderService.java" <<'EOF'
package com.example.orders.service;

import com.example.orders.domain.Order;
import com.example.orders.domain.OrderNotFoundException;
import org.springframework.stereotype.Service;

@Service
public class OrderService {

    public Order find(String id) {
        if (id.isEmpty()) {
            throw new OrderNotFoundException(id);
        }
        return new Order(id);
    }
}
EOF
put "$tpl/src/test/java/com/example/orders/service/OrderServiceTest.java" <<'EOF'
package com.example.orders.service;

import org.junit.jupiter.api.Test;

class OrderServiceTest {

    @Test
    void returnsOrderWhenIdIsGiven() {
        new OrderService().find("1");
    }
}
EOF
put "$tpl/src/main/resources/db/migration/V202601010000__create_orders.sql" <<'EOF'
CREATE TABLE orders (id VARCHAR(36) PRIMARY KEY);
EOF
put "$tpl/.gitignore" <<'EOF'
target/
EOF
git -C "$tpl" init -q -b main
git -C "$tpl" config user.email test@example.com
git -C "$tpl" config user.name test
commit "$tpl" "chore: initial service"
git -C "$tpl" update-ref refs/remotes/origin/main main
git -C "$tpl" checkout -q -b feature
put "$main/web/OrderController.java" <<'EOF'
package com.example.orders.web;

import com.example.orders.service.OrderService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/orders")
public class OrderController {

    private final OrderService orderService;

    public OrderController(OrderService orderService) {
        this.orderService = orderService;
    }

    @GetMapping
    public String find(String id) {
        return orderService.find(id).name();
    }
}
EOF
commit "$tpl" "feat(orders): add the order lookup endpoint

The endpoint returns the name of one order. See
https://example.com/a/very/long/link/that/is/longer/than/seventy-two/characters/in/total"
compile "$tpl" || exit 1

# new_case <name> [service.env extra line] — copies the fixture; prints the repo path.
new_case() {
  local repo="$tmp/cases/$1"
  mkdir -p "$tmp/cases" "$MS_KIT_PROJECTS_DIR/$1"
  cp -Rp "$tpl" "$repo"
  {
    echo "SOURCE_REPO=$repo"
    echo "DEFAULT_BRANCH=main"
    [ -z "${2:-}" ] || echo "$2"
  } > "$MS_KIT_PROJECTS_DIR/$1/service.env"
  echo "$repo"
}

# expect <exit> <case> <text the output must contain> — runs check.sh on the case.
expect() {
  local want="$1" name="$2" text="$3" out got
  out="$("$check" --project "$name" 2>&1)"; got=$?
  if [ "$got" -eq "$want" ] && printf '%s\n' "$out" | grep -qF -- "$text"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s: want exit %s with "%s", got %s\n%s\n\n' "$name" "$want" "$text" "$got" "$out"
  fi
}

# --- Cases ------------------------------------------------------------------------------------

started=$(date +%s)

new_case clean > /dev/null
expect 0 clean "All checks passed"

# The layer names live only in architecture.properties: rename three layers there and in the
# packages, and the ArchUnit runner still passes the clean service and finds a breach.
renamed="$tmp/renamed-layers.properties"
sed -E -e 's/(^|[.=,])service([,=]|$)/\1application\2/g' \
  -e 's/(^|[.=,])repository([,=]|$)/\1store\2/g' -e 's/(^|[.=,])domain([,=]|$)/\1model\2/g' \
  "$here/../../standards/checks/architecture.properties" > "$renamed"
r=$(new_case renamed-layers)
src="$r/src/main/java/com/example/orders"
mv "$src/service" "$src/application"
mv "$src/domain" "$src/model"
for f in $(find "$r/src" -name '*.java'); do
  sed -i '' -e 's/com\.example\.orders\.service/com.example.orders.application/g' \
    -e 's/com\.example\.orders\.domain/com.example.orders.model/g' "$f"
done
put "$src/store/OrderStore.java" <<'EOF'
package com.example.orders.store;

import com.example.orders.model.Order;
import org.springframework.data.jpa.repository.JpaRepository;

public interface OrderStore extends JpaRepository<Order, String> {
}
EOF
put "$src/application/OrderWriter.java" <<'EOF'
package com.example.orders.application;

import org.springframework.transaction.annotation.Transactional;

@Transactional
public class OrderWriter {

    @Transactional
    public void write() {
        // Writes in one transaction.
    }
}
EOF
compile "$r"
archunit() { # archunit <properties> <classes dir> — runs the ArchUnit runner directly.
  java -Dorg.slf4j.simpleLogger.defaultLogLevel=warn \
    -cp "$here/../checks/target/classes:$(cat "$here/../checks/target/classpath.txt")" \
    dev.aidevharness.checks.ArchitectureCheck "$1" "$2" 2>&1
}
out="$(archunit "$renamed" "$r/target/classes")"; got=$?
if [ "$got" -eq 0 ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); printf 'FAIL renamed layers pass: got %s\n%s\n\n' "$got" "$out"; fi
put "$src/web/OrderAudit.java" <<'EOF'
package com.example.orders.web;

import org.springframework.transaction.annotation.Transactional;

@Transactional
public class OrderAudit {
}
EOF
compile "$r"
out="$(archunit "$renamed" "$r/target/classes")"; got=$?
if [ "$got" -eq 1 ] && printf '%s\n' "$out" | grep -q '^DB-21  .*OrderAudit.*application'; then
  pass=$((pass + 1))
else
  fail=$((fail + 1)); printf 'FAIL renamed layers find a breach: got %s\n%s\n\n' "$got" "$out"
fi

r=$(new_case long-line)
sed -i '' 's|        return new Order(id);|        return new Order(id + "'"$(printf '%0110d' 0)"'");|' \
  "$r/src/main/java/com/example/orders/service/OrderService.java"
compile "$r"; commit "$r" "feat: name orders"
expect 1 long-line "JAVA-1"

r=$(new_case thread-sleep-in-test)
sed -i '' 's|        new OrderService().find("1");|        Thread.sleep(10);|' \
  "$r/src/test/java/com/example/orders/service/OrderServiceTest.java"
commit "$r" "test: wait for the order"
expect 1 thread-sleep-in-test "TEST-10"

r=$(new_case layer-breach)
put "$r/src/main/java/com/example/orders/domain/OrderNames.java" <<'EOF'
package com.example.orders.domain;

import com.example.orders.service.OrderService;

public class OrderNames {

    public String nameOf(OrderService service, String id) {
        return service.find(id).name();
    }
}
EOF
compile "$r"; commit "$r" "feat: look up order names"
expect 1 layer-breach "STRUCT-2"

r=$(new_case repository-placement)
put "$r/src/main/java/com/example/orders/service/OrderRepository.java" <<'EOF'
package com.example.orders.service;

import com.example.orders.domain.Order;
import org.springframework.data.jpa.repository.JpaRepository;

public interface OrderRepository extends JpaRepository<Order, String> {
}
EOF
compile "$r"; commit "$r" "feat: store orders"
expect 1 repository-placement "STRUCT-3"

r=$(new_case generic-exception)
sed -i '' 's|throw new OrderNotFoundException(id);|throw new RuntimeException(id);|' \
  "$r/src/main/java/com/example/orders/service/OrderService.java"
compile "$r"; commit "$r" "fix: throw on an empty id"
expect 1 generic-exception "ERR-1"

r=$(new_case system-clock)
sed -i '' 's|        return new Order(id);|        return new Order(id + java.time.Instant.now());|' \
  "$r/src/main/java/com/example/orders/service/OrderService.java"
compile "$r"; commit "$r" "feat: stamp the order name"
expect 1 system-clock "TIME-4"

# expect_findings <case> <RULE-ID>:<text>... — runs check.sh once on the case; it must exit 1,
# and for each pair a finding line must start with the rule ID and contain the text.
expect_findings() {
  local name="$1" pair rule text out got
  shift
  out="$("$check" --project "$name" 2>&1)"; got=$?
  for pair in "$@"; do
    rule="${pair%%:*}" text="${pair#*:}"
    if [ "$got" -eq 1 ] && printf '%s\n' "$out" | grep -E "^$rule  " | grep -qF -- "$text"; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
      printf 'FAIL %s: want exit 1 with a %s finding on "%s", got %s\n' "$name" "$rule" "$text" "$got"
    fi
  done
  [ "$fail" -eq 0 ] || printf '%s\n\n' "$out"
}

# One seeded violation per Checkstyle rule, each in its own file; one check.sh run.
r=$(new_case checkstyle-seeds)
seed="$r/src/main/java/com/example/orders/domain"
printf 'package com.example.orders.domain;\n\npublic class TabSeed {\n\tint count;\n}\n' > "$seed/TabSeed.java"
printf 'package com.example.orders.domain;\n\npublic class IndentSeed {\n  int count;\n}\n' > "$seed/IndentSeed.java"
printf 'package com.example.orders.domain;\n\npublic class TrailingSeed { \n}\n' > "$seed/TrailingSeed.java"
printf 'package com.example.orders.domain;\n\npublic class NoNewlineSeed {\n}' > "$seed/NoNewlineSeed.java"
put "$seed/BracesSeed.java" <<'EOF'
package com.example.orders.domain;

public class BracesSeed {

    public int sign(int value) {
        if (value < 0) return -1;
        return 1;
    }
}
EOF
put "$seed/LombokSeed.java" <<'EOF'
package com.example.orders.domain;

import lombok.Getter;

@Getter
public class LombokSeed {

    private int count;
}
EOF
put "$seed/ImportSeed.java" <<'EOF'
package com.example.orders.domain;

import java.util.*;

public class ImportSeed {
}
EOF
put "$seed/TwoTypesSeed.java" <<'EOF'
package com.example.orders.domain;

public class TwoTypesSeed {
}

class SecondType {
}
EOF
put "$seed/NameSeed.java" <<'EOF'
package com.example.orders.domain;

public class NameSeed {

    public void Do_it() {
        // A method name that is not lowerCamelCase.
    }
}
EOF
put "$seed/OrderHTTPSeed.java" <<'EOF'
package com.example.orders.domain;

public class OrderHTTPSeed {
}
EOF
{
  printf 'package com.example.orders.domain;\n\npublic class LongMethodSeed {\n\n    public int sum() {\n'
  printf '        int total = 0;\n'
  for i in $(seq 1 51); do printf '        total += %d;\n' "$i"; done
  printf '        return total;\n    }\n}\n'
} > "$seed/LongMethodSeed.java"
put "$seed/ParametersSeed.java" <<'EOF'
package com.example.orders.domain;

public class ParametersSeed {

    public int sum(int a, int b, int c, int d, int e, int f, int g) {
        return a + b + c + d + e + f + g;
    }
}
EOF
put "$seed/EqualsSeed.java" <<'EOF'
package com.example.orders.domain;

public class EqualsSeed {

    @Override
    public boolean equals(Object other) {
        return other instanceof EqualsSeed;
    }
}
EOF
put "$seed/LiteralSeed.java" <<'EOF'
package com.example.orders.domain;

public class LiteralSeed {

    public boolean isOpen(String status) {
        return status == "OPEN";
    }
}
EOF
put "$seed/CatchSeed.java" <<'EOF'
package com.example.orders.domain;

public class CatchSeed {

    public void run(Runnable task) {
        try {
            task.run();
        } catch (IllegalStateException e) {
        }
    }
}
EOF
tests="$r/src/test/java/com/example/orders/service"
put "$tests/JunitFourSeedTest.java" <<'EOF'
package com.example.orders.service;

import org.junit.Test;

public class JunitFourSeedTest {

    @Test
    public void runs() {
        new OrderService().find("1");
    }
}
EOF
put "$tests/AssertionsSeedTest.java" <<'EOF'
package com.example.orders.service;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class AssertionsSeedTest {

    @Test
    void findsTheOrder() {
        assertEquals("1", new OrderService().find("1").name());
    }
}
EOF
compile "$r"; commit "$r" "feat: seed the checkstyle rules"
expect_findings checkstyle-seeds JAVA-2:TabSeed.java JAVA-2:IndentSeed.java JAVA-3:TrailingSeed.java \
  JAVA-3:NoNewlineSeed.java JAVA-4:BracesSeed.java JAVA-5:ImportSeed.java JAVA-6:TwoTypesSeed.java \
  JAVA-7:NameSeed.java JAVA-8:OrderHTTPSeed.java JAVA-10:LongMethodSeed.java \
  JAVA-11:ParametersSeed.java JAVA-12:EqualsSeed.java JAVA-13:LiteralSeed.java \
  JAVA-20:LombokSeed.java ERR-3:CatchSeed.java \
  TEST-8:JunitFourSeedTest.java TEST-9:AssertionsSeedTest.java

# The logger field "log" (ERR-15) is exempt from the constant names of JAVA-7.
r=$(new_case logger-name)
put "$r/src/main/java/com/example/orders/domain/OrderLog.java" <<'EOF'
package com.example.orders.domain;

public final class OrderLog {

    private static final Object log = new Object();

    public Object logger() {
        return log;
    }
}
EOF
compile "$r"; commit "$r" "feat: add the order log"
expect 0 logger-name "All checks passed"

# One seeded violation per ArchUnit rule, each in its own class; one check.sh run.
r=$(new_case archunit-seeds)
src="$r/src/main/java/com/example/orders"
put "$src/util/Strings.java" <<'EOF'
package com.example.orders.util;

public final class Strings {
}
EOF
put "$src/invoice/service/InvoiceService.java" <<'EOF'
package com.example.orders.invoice.service;

import com.example.orders.billing.service.BillingService;

public class InvoiceService {

    public void bill(BillingService billing) {
        billing.invoice(this);
    }
}
EOF
put "$src/billing/service/BillingService.java" <<'EOF'
package com.example.orders.billing.service;

import com.example.orders.invoice.service.InvoiceService;

public class BillingService {

    public void invoice(InvoiceService invoices) {
        invoices.hashCode();
    }
}
EOF
put "$src/web/InjectedController.java" <<'EOF'
package com.example.orders.web;

import com.example.orders.service.OrderService;
import org.springframework.beans.factory.annotation.Autowired;

public class InjectedController {

    @Autowired
    private OrderService orderService;
}
EOF
put "$src/web/MappedController.java" <<'EOF'
package com.example.orders.web;

import com.example.orders.domain.OrderEntity;
import org.modelmapper.ModelMapper;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class MappedController {

    @RequestMapping("/mapped")
    public String mapped() {
        return new ModelMapper().map(this, String.class);
    }

    public OrderEntity entity() {
        return new OrderEntity();
    }
}
EOF
put "$src/domain/OrderEntity.java" <<'EOF'
package com.example.orders.domain;

import jakarta.persistence.Entity;
import java.time.ZoneId;
import java.util.Date;

@Entity
public class OrderEntity {

    private Date created;

    public ZoneId zone() {
        return ZoneId.systemDefault();
    }

    @org.springframework.transaction.annotation.Transactional
    public void save() {
        // Saves in a transaction.
    }
}
EOF
put "$src/service/WebAwareService.java" <<'EOF'
package com.example.orders.service;

import org.springframework.web.server.ResponseStatusException;

public class WebAwareService {

    public void reject() {
        System.out.println("rejected");
        throw new ResponseStatusException();
    }
}
EOF
put "$src/web/TransactionalController.java" <<'EOF'
package com.example.orders.web;

import org.springframework.transaction.annotation.Transactional;

@Transactional
public class TransactionalController {
}
EOF
compile "$r"; commit "$r" "feat: seed the archunit rules"
expect_findings archunit-seeds STRUCT-1:orders.util.Strings "STRUCT-4:Cycle detected: Slice billing" \
  JAVA-16:InjectedController.orderService JAVA-21:MappedController.mapped \
  REST-4:MappedController.mapped REST-10:MappedController.entity ERR-7:WebAwareService \
  ERR-14:WebAwareService.reject TIME-1:OrderEntity.created TIME-6:OrderEntity.zone \
  DB-21:TransactionalController DB-21:OrderEntity.save

r=$(new_case commit-header)
echo "x=1" > "$r/src/main/resources/application.properties"
commit "$r" "Added a property file"
expect 1 commit-header "CORE-11"

r=$(new_case commit-subject)
echo "x=1" > "$r/src/main/resources/application.properties"
commit "$r" "feat: Add a property file."
expect 1 commit-subject "CORE-12"

r=$(new_case commit-body)
echo "x=1" > "$r/src/main/resources/application.properties"
commit "$r" "feat: add a property file

This body line is much longer than the limit of seventy-two characters, so it fails."
expect 1 commit-body "CORE-13"

r=$(new_case fixup)
echo "x=1" > "$r/src/main/resources/application.properties"
commit "$r" "fixup! feat(orders): add the order lookup endpoint"
expect 0 fixup "All checks passed"

r=$(new_case conflict-marker)
printf 'x=1\n<<<<<<< HEAD\nx=2\n=======\nx=3\n>>>>>>> other\n' > "$r/src/main/resources/application.properties"
commit "$r" "feat: add a property file"
expect 1 conflict-marker "CORE-14"

r=$(new_case uncommitted-conflict-marker)
printf 'x=1\n<<<<<<< HEAD\n' > "$r/src/main/resources/application.properties"
expect 1 uncommitted-conflict-marker "CORE-14"

r=$(new_case setext-underline)
printf 'Orders\n=======\n\nThe orders service.\n' > "$r/README.md"
commit "$r" "docs: add a readme"
expect 0 setext-underline "All checks passed"

r=$(new_case 'path|with&sed-characters')
sed -i '' 's|        return new Order(id);|        return new Order(id + "'"$(printf '%0110d' 0)"'");|' \
  "$r/src/main/java/com/example/orders/service/OrderService.java"
compile "$r"; commit "$r" "feat: name orders"
expect 1 'path|with&sed-characters' "JAVA-1  src/main/java/com/example/orders/service/OrderService.java:"

r=$(new_case migration-name)
echo "SELECT 1;" > "$r/src/main/resources/db/migration/V2__AddIndex.sql"
commit "$r" "feat: add an index"
expect 1 migration-name "DB-11"

r=$(new_case migration-changed)
echo "-- changed" >> "$r/src/main/resources/db/migration/V202601010000__create_orders.sql"
commit "$r" "fix: change the orders table"
expect 1 migration-changed "DB-12"

printf '// Copyright header of the team.\n' > "$tmp/header.txt"
new_case header-missing "FILE_HEADER=$tmp/header.txt" > /dev/null
expect 1 header-missing "HEADER"

# A relative FILE_HEADER is relative to the project folder (lib/service-env.sh).
new_case header-relative " FILE_HEADER = header.txt " > /dev/null
cp "$tmp/header.txt" "$MS_KIT_PROJECTS_DIR/header-relative/header.txt"
expect 1 header-relative "HEADER  src/main/java"

r=$(new_case header-present "FILE_HEADER=$tmp/header.txt")
for f in $(find "$r/src" -name '*.java'); do
  { cat "$tmp/header.txt"; cat "$f"; } > "$f.new" && mv "$f.new" "$f"
done
compile "$r"; commit "$r" "chore: add the file header"
expect 0 header-present "All checks passed"

r=$(new_case not-compiled)
rm -rf "$r/target"
expect 3 not-compiled "compile"

r=$(new_case stale-classes)
sleep 1
touch "$r/src/main/java/com/example/orders/service/OrderService.java"
expect 3 stale-classes "compile"

r=$(new_case no-default-branch)
git -C "$r" update-ref -d refs/remotes/origin/main
expect 3 no-default-branch "origin/main"

printf '%d passed, %d failed (%ds)\n' "$pass" "$fail" "$(( $(date +%s) - started ))"
[ "$fail" -eq 0 ]
