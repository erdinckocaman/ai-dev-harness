#!/usr/bin/env bash
# Checks the skill catalog of the workspace (docs/adr/0004-skill-catalog-mirrored-by-symlink.md).
#
# Usage: scripts/check-skills.sh [workspace root]   (default: the repository of this script)
#
# For the root catalog and every projects/<name>/ catalog it fails (exit 1) when:
#   - .agents/skills/<name> is not a real directory with a SKILL.md whose `name:` is <name>;
#   - .claude/skills/<name> is missing, is not a symlink, does not resolve, or does not point
#     at exactly ../../.agents/skills/<name>;
#   - a skill file names a file, folder or skill of the personal knowledge base the skills came
#     from, or names a skill that is not in the catalog.
# The root catalog must hold at least one skill. Exit 0 prints "check-skills: OK".
set -u

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
[ -d "$root" ] || { echo "usage: $0 [workspace root]" >&2; exit 2; }
cd "$root" || exit 2

# Names that come from the personal knowledge base and have no meaning here.
foreign_re='WIKI\.md|PROJECTS\.md|USER\.md|IDENTITY\.md|WORKPLACES\.md'
foreign_re+='|(^|[^A-Za-z0-9_.-])(wiki|raw|daily|research|workplaces)/'
foreign_re+='|\baos\b|\bingest\b|wiki-sync|wayfind|improve-codebase-architecture'
foreign_re+='|jira-tasks|jira-fetch|test-handoff|setup-matt-pocock|mattpocock'

status=0
bad() { printf 'FAIL: %s\n' "$*"; status=1; }

catalogs="."
for p in projects/*/; do
  p="${p%/}"
  [ -e "$p/.agents/skills" ] || [ -e "$p/.claude/skills" ] && catalogs+=" $p"
done

# Every skill name of every catalog.
known=" "
for c in $catalogs; do
  for d in "$c"/.agents/skills/*/; do
    [ -d "$d" ] && known+="$(basename "$d") "
  done
done

for c in $catalogs; do
  count=0
  for d in "$c"/.agents/skills/*; do
    [ -e "$d" ] || [ -L "$d" ] || continue
    name="$(basename "$d")"
    count=$((count + 1))
    if [ -L "$d" ] || [ ! -d "$d" ]; then
      bad "$d is not a real directory"
      continue
    fi
    if [ ! -f "$d/SKILL.md" ]; then
      bad "$d has no SKILL.md"
    elif ! sed -n '2,/^---$/p' "$d/SKILL.md" | grep -qx "name: $name"; then
      bad "$d/SKILL.md frontmatter name is not '$name'"
    fi
    link="$c/.claude/skills/$name"
    [ -L "$link" ] || bad "$link is missing or not a symlink"
  done
  [ "$c" = "." ] && [ "$count" -eq 0 ] && bad "the catalog .agents/skills/ holds no skill"

  for link in "$c"/.claude/skills/*; do
    [ -e "$link" ] || [ -L "$link" ] || continue
    name="$(basename "$link")"
    if [ ! -L "$link" ]; then
      bad "$link is not a symlink"
      continue
    fi
    target="$(readlink "$link")"
    [ "$target" = "../../.agents/skills/$name" ] ||
      bad "$link points at '$target', not '../../.agents/skills/$name'"
    [ -d "$link" ] || bad "$link does not resolve"
  done

  [ -d "$c/.agents/skills" ] || continue
  hits="$(grep -rInE "$foreign_re" "$c/.agents/skills")"
  [ -z "$hits" ] || bad "foreign references:
$hits"

  # Skill references: `x` skill, Skill tool with "x", /x as a command, .claude/skills/x paths.
  # A /x token is a path, not a command, when a path character comes before it, when a / or a
  # file extension follows it, or when x is a standard root folder (/tmp, /etc, ...).
  while IFS=: read -r file line ref; do
    case "$known" in *" $ref "*) ;; *) bad "$file:$line names unknown skill '$ref'" ;; esac
  done < <(grep -rIl . "$c/.agents/skills" | while IFS= read -r f; do
    perl -ne '
      my @refs;
      push @refs, /`([a-z][a-z0-9-]*)` skill\b/g;
      push @refs, /Skill tool with ["`]([a-z][a-z0-9-]*)["`]/g;
      push @refs, grep { !/^(?:bin|dev|etc|home|lib|mnt|opt|private|proc|root|run|sbin|srv|sys|tmp|usr|var|volumes)$/ }
        /(?:^|[\s(`"])\/([a-z][a-z0-9-]*)(?![\w\/-]|\.\w)/g;
      push @refs, /\.(?:agents|claude)\/skills\/([a-z][a-z0-9-]*)/g;
      print "$ARGV:$.:$_\n" for @refs;
      close ARGV if eof;' "$f"
  done)
done

[ "$status" -eq 0 ] && echo "check-skills: OK"
exit "$status"
