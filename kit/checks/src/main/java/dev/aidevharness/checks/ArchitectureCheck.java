package dev.aidevharness.checks;

import com.tngtech.archunit.core.domain.JavaClass;
import com.tngtech.archunit.core.domain.JavaClasses;
import com.tngtech.archunit.core.importer.ClassFileImporter;
import com.tngtech.archunit.core.importer.ImportOption;
import com.tngtech.archunit.lang.EvaluationResult;

import java.io.IOException;
import java.io.InputStream;
import java.io.PrintStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Properties;
import java.util.Set;
import java.util.TreeSet;

/**
 * Runs the ArchUnit rules of the standards against compiled production classes.
 *
 * <p>Usage: {@code ArchitectureCheck <architecture.properties> <classes-dir>...}
 *
 * <p>Prints one line per violation, {@code <RULE-ID>  <detail>}, then a summary line. Exit
 * status: 0 no violation, 1 violations, 2 usage error, 3 the check cannot run (no classes, no
 * {@code @SpringBootApplication} class, or a bad configuration value).
 */
public final class ArchitectureCheck {

    private static final PrintStream OUT = System.out;
    private static final PrintStream ERR = System.err;

    private ArchitectureCheck() {
    }

    public static void main(String[] args) {
        System.exit(run(args));
    }

    static int run(String[] args) {
        if (args.length < 2) {
            ERR.println("usage: ArchitectureCheck <architecture.properties> <classes-dir>...");
            return 2;
        }
        try {
            Properties config = load(Path.of(args[0]));
            JavaClasses classes = importClasses(args);
            if (classes.isEmpty()) {
                ERR.println("error: no class files found in the classes directories");
                return 3;
            }
            Layers layers = new Layers(basePackage(classes), config);
            return evaluate(Rules.all(layers), classes);
        } catch (Layers.ConfigException | CannotRunException e) {
            ERR.println("error: " + e.getMessage());
            return 3;
        }
    }

    private static int evaluate(List<Rules.Rule> rules, JavaClasses classes) {
        int violations = 0;
        Set<String> failedRules = new TreeSet<>();
        for (Rules.Rule rule : rules) {
            EvaluationResult result = rule.archRule().evaluate(classes);
            if (result.hasViolation()) {
                failedRules.add(rule.id());
                for (String detail : result.getFailureReport().getDetails()) {
                    OUT.println(rule.id() + "  " + detail);
                    violations++;
                }
            }
        }
        if (violations > 0) {
            OUT.println("ArchUnit: " + violations + " violation(s) of " + String.join(", ", failedRules));
            return 1;
        }
        OUT.println("ArchUnit: " + classes.size() + " classes, no violation");
        return 0;
    }

    private static Properties load(Path file) {
        Properties config = new Properties();
        try (InputStream in = Files.newInputStream(file)) {
            config.load(in);
        } catch (IOException e) {
            throw new CannotRunException("cannot read " + file + ": " + e.getMessage());
        }
        return config;
    }

    private static JavaClasses importClasses(String[] args) {
        List<Path> dirs = new ArrayList<>();
        for (int i = 1; i < args.length; i++) {
            Path dir = Path.of(args[i]);
            if (!Files.isDirectory(dir)) {
                throw new CannotRunException("not a directory: " + dir);
            }
            dirs.add(dir);
        }
        ImportOption noInfoFiles = location -> !location.contains("package-info.class")
            && !location.contains("module-info.class");
        return new ClassFileImporter().withImportOption(noInfoFiles).importPaths(dirs);
    }

    /** The package of the one {@code @SpringBootApplication} class. */
    private static String basePackage(JavaClasses classes) {
        Set<String> packages = new TreeSet<>();
        for (JavaClass javaClass : classes) {
            if (javaClass.isAnnotatedWith(Rules.SPRING_BOOT_APPLICATION)) {
                packages.add(javaClass.getPackageName());
            }
        }
        if (packages.isEmpty()) {
            throw new CannotRunException("no class annotated @SpringBootApplication: the base package is unknown");
        }
        if (packages.size() > 1) {
            throw new CannotRunException("@SpringBootApplication classes in more than one package: " + packages);
        }
        return packages.iterator().next();
    }

    /** A prerequisite of the check is missing. */
    private static final class CannotRunException extends RuntimeException {
        CannotRunException(String message) {
            super(message);
        }
    }
}
