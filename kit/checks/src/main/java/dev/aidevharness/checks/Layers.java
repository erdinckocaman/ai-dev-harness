package dev.aidevharness.checks;

import com.tngtech.archunit.base.DescribedPredicate;
import com.tngtech.archunit.core.domain.JavaClass;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Properties;
import java.util.Set;
import java.util.TreeSet;

/**
 * The layer model of standards/checks/architecture.properties, relative to one base package.
 * A class belongs to the layer of the first package segment below the base package that names
 * a layer.
 */
final class Layers {

    private final String basePackage;
    private final List<String> names;
    private final Map<String, Set<String>> mayUse = new LinkedHashMap<>();
    private final Map<String, List<String>> placements = new LinkedHashMap<>();
    private final String springDataLayer;
    private final List<String> noWebLayers;
    private final String transactionalLayer;

    Layers(String basePackage, Properties config) {
        this.basePackage = basePackage;
        this.names = list(config.getProperty("layers"));
        if (names.isEmpty()) {
            throw new ConfigException("no value for 'layers'");
        }
        for (String layer : names) {
            String key = "may-use." + layer;
            String value = config.getProperty(key);
            if (value == null) {
                throw new ConfigException("no line for '" + key + "'");
            }
            Set<String> allowed = new TreeSet<>(value.trim().equals("*") ? names : list(value));
            for (String other : allowed) {
                if (!names.contains(other)) {
                    throw new ConfigException("'" + key + "' names an unknown layer: " + other);
                }
            }
            allowed.add(layer);
            mayUse.put(layer, allowed);
            placements.put(layer, list(config.getProperty("placement." + layer)));
        }
        this.springDataLayer = single(config, "layer.spring-data");
        this.noWebLayers = known(config, "layer.no-web");
        this.transactionalLayer = single(config, "layer.transactional");
    }

    String basePackage() {
        return basePackage;
    }

    List<String> names() {
        return names;
    }

    Map<String, List<String>> placements() {
        return placements;
    }

    /** STRUCT-3: the layer of the Spring Data repositories. */
    String springDataLayer() {
        return springDataLayer;
    }

    /** ERR-7: the layers that do not use org.springframework.web. */
    List<String> noWebLayers() {
        return noWebLayers;
    }

    /** DB-21: the layer of the @Transactional classes and methods. */
    String transactionalLayer() {
        return transactionalLayer;
    }

    Optional<String> layerOf(JavaClass javaClass) {
        String pkg = javaClass.getPackageName();
        if (!pkg.startsWith(basePackage + ".")) {
            return Optional.empty();
        }
        for (String segment : pkg.substring(basePackage.length() + 1).split("\\.")) {
            if (names.contains(segment)) {
                return Optional.of(segment);
            }
        }
        return Optional.empty();
    }

    boolean mayUse(String fromLayer, String toLayer) {
        return mayUse.get(fromLayer).contains(toLayer);
    }

    Set<String> allowedFrom(String layer) {
        return mayUse.get(layer);
    }

    DescribedPredicate<JavaClass> in(String... layers) {
        return in(Arrays.asList(layers));
    }

    DescribedPredicate<JavaClass> in(List<String> wanted) {
        return DescribedPredicate.describe("are in the layer " + String.join(" or ", wanted),
            javaClass -> layerOf(javaClass).map(wanted::contains).orElse(false));
    }

    /** The layers of a key: at least one, each a layer of "layers". */
    private List<String> known(Properties config, String key) {
        List<String> values = list(config.getProperty(key));
        if (values.isEmpty()) {
            throw new ConfigException("no value for '" + key + "'");
        }
        for (String value : values) {
            if (!names.contains(value)) {
                throw new ConfigException("'" + key + "' names an unknown layer: " + value);
            }
        }
        return values;
    }

    /** The one layer of a key. */
    private String single(Properties config, String key) {
        List<String> values = known(config, key);
        if (values.size() > 1) {
            throw new ConfigException("'" + key + "' names more than one layer: " + values);
        }
        return values.get(0);
    }

    private static List<String> list(String value) {
        List<String> result = new ArrayList<>();
        if (value == null) {
            return result;
        }
        for (String part : value.split(",")) {
            if (!part.isBlank()) {
                result.add(part.trim());
            }
        }
        return result;
    }

    /** A value in the configuration file that the runner cannot use. */
    static final class ConfigException extends RuntimeException {
        ConfigException(String message) {
            super(message);
        }
    }
}
