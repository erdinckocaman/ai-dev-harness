# pom.sh — sourced by set-version.sh and new-project.sh: read the root version of a
# Maven reactor, so both read it the same way.

# pom_root_version <pom.xml> <root artifactId>: prints the root pom's own version: the first
# <version> after the line that holds <artifactId><root artifactId></artifactId> (the Spring
# Boot parent's <version> sits above it). Prints nothing when there is none.
pom_root_version() {
  awk -v tag="<artifactId>$2</artifactId>" '
    index($0, tag) { seen = 1 }
    seen && match($0, /<version>[^<]+<\/version>/) {
      v = substr($0, RSTART, RLENGTH)
      gsub(/<\/?version>/, "", v)
      print v
      exit
    }
  ' "$1"
}
