package dev.aidevharness.checks;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.classes;
import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.methods;
import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noClasses;
import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noFields;
import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noMethods;
import static com.tngtech.archunit.library.dependencies.SlicesRuleDefinition.slices;

import com.tngtech.archunit.base.DescribedPredicate;
import com.tngtech.archunit.core.domain.Dependency;
import com.tngtech.archunit.core.domain.JavaCall;
import com.tngtech.archunit.core.domain.JavaClass;
import com.tngtech.archunit.core.domain.JavaMethod;
import com.tngtech.archunit.core.domain.properties.CanBeAnnotated;
import com.tngtech.archunit.lang.ArchCondition;
import com.tngtech.archunit.lang.ArchRule;
import com.tngtech.archunit.lang.ConditionEvents;
import com.tngtech.archunit.lang.SimpleConditionEvent;
import com.tngtech.archunit.lang.syntax.elements.FieldsShouldConjunction;
import com.tngtech.archunit.library.GeneralCodingRules;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.Set;

/**
 * The ArchUnit rules of the standards, one entry per rule ID. The rule text lives in
 * standards/guidelines/*.md; the layer values live in standards/checks/architecture.properties.
 */
final class Rules {

    static final String SPRING_BOOT_APPLICATION = "org.springframework.boot.autoconfigure.SpringBootApplication";
    private static final String REST_CONTROLLER = "org.springframework.web.bind.annotation.RestController";
    private static final String REQUEST_MAPPING = "org.springframework.web.bind.annotation.RequestMapping";
    private static final String[] ENTITY = {"jakarta.persistence.Entity", "javax.persistence.Entity"};
    private static final String[] FIELD_INJECTION = {
        "org.springframework.beans.factory.annotation.Autowired",
        "org.springframework.beans.factory.annotation.Value",
        "jakarta.inject.Inject",
        "javax.inject.Inject",
    };
    private static final String[] TRANSACTIONAL = {
        "org.springframework.transaction.annotation.Transactional",
        "jakarta.transaction.Transactional",
        "javax.transaction.Transactional",
    };
    private static final Set<String> GENERIC_THROWABLES = Set.of(
        "java.lang.Throwable", "java.lang.Exception", "java.lang.RuntimeException", "java.lang.Error");
    private static final Set<String> LEGACY_TIME_TYPES = Set.of(
        "java.util.Date", "java.util.Calendar", "java.util.TimeZone", "java.sql.Date", "java.sql.Time",
        "java.sql.Timestamp", "java.text.SimpleDateFormat");
    private static final Set<String> CLOCK_TYPES = Set.of(
        "java.time.Instant", "java.time.LocalDate", "java.time.LocalDateTime", "java.time.LocalTime",
        "java.time.OffsetDateTime", "java.time.ZonedDateTime", "java.time.Year", "java.time.YearMonth");

    /** One rule of the standards: its ID and the ArchUnit rule that checks it. */
    record Rule(String id, ArchRule archRule) {
    }

    private Rules() {
    }

    static List<Rule> all(Layers layers) {
        List<Rule> rules = new ArrayList<>();
        rules.add(rule("STRUCT-1", classes()
            .that(DescribedPredicate.not(CanBeAnnotated.Predicates.annotatedWith(SPRING_BOOT_APPLICATION)))
            .should(resideInLayerPackage(layers))));
        rules.add(rule("STRUCT-2", classes().should(useOnlyAllowedLayers(layers))));
        layers.placements().forEach((layer, annotations) -> annotations.forEach(annotation ->
            rules.add(rule("STRUCT-3", classes().that().areAnnotatedWith(annotation)
                .should(beIn(layers, layer))))));
        rules.add(rule("STRUCT-3", classes().that(springDataRepository())
            .should(beIn(layers, layers.springDataLayer()))));
        rules.add(rule("STRUCT-4", slices().matching(layers.basePackage() + ".(*)..").should().beFreeOfCycles()));
        FieldsShouldConjunction fieldInjection = noFields().should().beAnnotatedWith(FIELD_INJECTION[0]);
        for (int i = 1; i < FIELD_INJECTION.length; i++) {
            fieldInjection = fieldInjection.orShould().beAnnotatedWith(FIELD_INJECTION[i]);
        }
        rules.add(rule("JAVA-16", fieldInjection));
        rules.add(rule("JAVA-21", noClasses().should().dependOnClassesThat()
            .resideInAnyPackage("org.modelmapper..", "org.dozer..", "com.github.dozermapper..")
            .orShould().callMethodWhere(call("org.springframework.beans.BeanUtils", "copyProperties", -1))));
        rules.add(rule("REST-4", noMethods().should().beAnnotatedWith(REQUEST_MAPPING)));
        rules.add(rule("REST-10", methods().that().arePublic()
            .and().areDeclaredInClassesThat().areAnnotatedWith(REST_CONTROLLER)
            .should(notTakeOrReturnAnEntity())));
        rules.add(rule("ERR-1", noClasses().should().callConstructorWhere(throwableConstructor())));
        rules.add(rule("ERR-7", noClasses().that(layers.in(layers.noWebLayers()))
            .should().dependOnClassesThat().resideInAPackage("org.springframework.web..")));
        rules.add(rule("ERR-14", GeneralCodingRules.NO_CLASSES_SHOULD_USE_JAVA_UTIL_LOGGING));
        rules.add(rule("ERR-14", GeneralCodingRules.NO_CLASSES_SHOULD_ACCESS_STANDARD_STREAMS));
        rules.add(rule("TIME-1", noClasses().should().dependOnClassesThat(legacyTimeType())));
        rules.add(rule("TIME-4", noClasses().should().callMethodWhere(systemClockCall())));
        rules.add(rule("TIME-6", noClasses().should()
            .callMethodWhere(call("java.time.ZoneId", "systemDefault", 0))
            .orShould().callMethodWhere(call("java.util.TimeZone", "getDefault", 0))));
        rules.add(rule("DB-21", classes().that(anyAnnotation(TRANSACTIONAL))
            .should(beIn(layers, layers.transactionalLayer()))));
        rules.add(rule("DB-21", methods().that(anyAnnotation(TRANSACTIONAL))
            .should().beDeclaredInClassesThat(layers.in(layers.transactionalLayer()))));
        return rules;
    }

    private static Rule rule(String id, ArchRule archRule) {
        return new Rule(id, archRule.allowEmptyShould(true));
    }

    private static ArchCondition<JavaClass> resideInLayerPackage(Layers layers) {
        String description = "reside in a layer package (" + String.join(", ", layers.names())
            + ") below " + layers.basePackage();
        return new ArchCondition<>(description) {
            @Override
            public void check(JavaClass javaClass, ConditionEvents events) {
                if (layers.layerOf(javaClass).isEmpty()) {
                    events.add(SimpleConditionEvent.violated(javaClass, javaClass.getName()
                        + " is not in a layer package (" + String.join(", ", layers.names())
                        + ") below " + layers.basePackage()));
                }
            }
        };
    }

    private static ArchCondition<JavaClass> useOnlyAllowedLayers(Layers layers) {
        return new ArchCondition<>("use only the layers that architecture.properties allows") {
            @Override
            public void check(JavaClass javaClass, ConditionEvents events) {
                Optional<String> from = layers.layerOf(javaClass);
                if (from.isEmpty()) {
                    return;
                }
                for (Dependency dependency : javaClass.getDirectDependenciesFromSelf()) {
                    Optional<String> to = layers.layerOf(dependency.getTargetClass().getBaseComponentType());
                    if (to.isPresent() && !layers.mayUse(from.get(), to.get())) {
                        events.add(SimpleConditionEvent.violated(dependency, "layer " + from.get()
                            + " may not use layer " + to.get() + " (may use: "
                            + String.join(", ", layers.allowedFrom(from.get())) + "): "
                            + dependency.getDescription()));
                    }
                }
            }
        };
    }

    private static ArchCondition<JavaClass> beIn(Layers layers, String layer) {
        return new ArchCondition<>("be in the layer " + layer) {
            @Override
            public void check(JavaClass javaClass, ConditionEvents events) {
                if (!layers.layerOf(javaClass).map(layer::equals).orElse(false)) {
                    events.add(SimpleConditionEvent.violated(javaClass, javaClass.getName()
                        + " belongs in the layer " + layer + " (a package segment '" + layer + "')"));
                }
            }
        };
    }

    private static DescribedPredicate<JavaClass> springDataRepository() {
        return DescribedPredicate.describe("are Spring Data repositories", javaClass ->
            javaClass.getAllRawInterfaces().stream().anyMatch(type ->
                type.getName().startsWith("org.springframework.data.") && type.getSimpleName().endsWith("Repository")));
    }

    private static DescribedPredicate<CanBeAnnotated> anyAnnotation(String... names) {
        return DescribedPredicate.describe("annotated with any of " + String.join(", ", names), annotated -> {
            for (String name : names) {
                if (annotated.isAnnotatedWith(name)) {
                    return true;
                }
            }
            return false;
        });
    }

    /** A call to owner.method; parameterCount -1 matches every overload. */
    private static DescribedPredicate<JavaCall<?>> call(String owner, String method, int parameterCount) {
        return DescribedPredicate.describe(owner + "." + method + "()", javaCall ->
            javaCall.getTargetOwner().getName().equals(owner)
                && javaCall.getName().equals(method)
                && (parameterCount < 0 || javaCall.getTarget().getRawParameterTypes().size() == parameterCount));
    }

    private static DescribedPredicate<JavaCall<?>> throwableConstructor() {
        return DescribedPredicate.describe("a constructor of " + String.join(", ", GENERIC_THROWABLES),
            javaCall -> GENERIC_THROWABLES.contains(javaCall.getTargetOwner().getName())
                && !javaCall.getOriginOwner().isAssignableTo(javaCall.getTargetOwner().getName())
        );
    }

    private static DescribedPredicate<JavaClass> legacyTimeType() {
        return DescribedPredicate.describe("are legacy date and time types or Joda-Time", javaClass ->
            LEGACY_TIME_TYPES.contains(javaClass.getName()) || javaClass.getPackageName().startsWith("org.joda.time"));
    }

    private static DescribedPredicate<JavaCall<?>> systemClockCall() {
        return DescribedPredicate.describe("now() without a Clock, or System.currentTimeMillis()", javaCall -> {
            String owner = javaCall.getTargetOwner().getName();
            boolean noArguments = javaCall.getTarget().getRawParameterTypes().isEmpty();
            return noArguments && (CLOCK_TYPES.contains(owner) && javaCall.getName().equals("now")
                || owner.equals("java.lang.System") && javaCall.getName().equals("currentTimeMillis"));
        });
    }

    private static ArchCondition<JavaMethod> notTakeOrReturnAnEntity() {
        return new ArchCondition<>("not take or return a JPA entity") {
            @Override
            public void check(JavaMethod method, ConditionEvents events) {
                List<JavaClass> types = new ArrayList<>(method.getRawParameterTypes());
                types.add(method.getRawReturnType());
                for (JavaClass type : types) {
                    if (anyAnnotation(ENTITY).test(type)) {
                        events.add(SimpleConditionEvent.violated(method, method.getFullName()
                            + " takes or returns the entity " + type.getName()));
                    }
                }
            }
        };
    }
}
