#!/bin/bash
# Report every remaining pre-ADR-0016 name.
#
# ADR 0016 reserves the bare name `Slopad` for the consuming application and gives this
# package and all of its modules the `SlopadEditor` prefix. The migration runs in stages, so
# this script is an inventory first and a gate second: it prints what is left, grouped by
# the kind of work each occurrence needs, and fails only when a category that is supposed to
# be finished is not.
#
# It exists because judging a rename "done" by eye already failed once. `f059bc5` renamed
# the package but left the old name inside the gate script's own assertion, so
# verify-host-surface.sh failed closed against correctly renamed fixtures. A checker can
# hold a stale name exactly as easily as the files it checks.
#
# Usage:
#   bash scripts/verify-naming.sh            # summary; exit 0 unless a sealed stage regressed
#   bash scripts/verify-naming.sh --all      # additionally list every remaining file
#   bash scripts/verify-naming.sh --strict   # additionally fail while any occurrence remains

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

strict=0
show_all=0
for arg in "$@"; do
    case "$arg" in
        --strict) strict=1 ;;
        --all) show_all=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

# Which migration stage owns a path. The stage order is defined in
# docs/RENAME_MIGRATION_PLAN.md; this mapping is what makes progress measurable per stage
# instead of as one undifferentiated pile.
category_of() {
    case "$1" in
        Sources/*)            echo "module source" ;;
        Tests/*)              echo "test" ;;
        Fixtures/*)           echo "downstream fixture" ;;
        Debug/*|Benchmarks/*) echo "development target" ;;
        scripts/*|justfile)   echo "script + gate" ;;
        .github/*|.codex/*)   echo "repo tooling" ;;
        ADR/*)                echo "ADR" ;;
        *.html)               echo "HTML page" ;;
        *)                    echo "doc + prose" ;;
    esac
}

# Occurrences that are content rather than identity, and must survive the migration.
# Each entry needs a reason; an unexplained exclusion is how a real stale name hides.
is_allowed() {
    local file="$1"
    case "$file" in
        # Archive wire fixture: "Slopad" is the block text of a stored v1 document. Changing
        # it would rewrite the fixture the round-trip test asserts against.
        Tests/SlopadArchiveTests/Fixtures/*.json) return 0 ;;
        # Quotes that fixture verbatim.
        ADR/0015-*.md) return 0 ;;
        # Defines the distinction; necessarily names both sides.
        ADR/0016-*.md) return 0 ;;
        docs/RENAME_MIGRATION_PLAN.md) return 0 ;;
        scripts/verify-naming.sh) return 0 ;;
        # Point-in-time record of the state before the migration.
        docs/ARCHITECTURE_AUDIT_*.md) return 0 ;;
        # Historical background record, explicitly not a work order (AGENTS.md).
        Slopad_Semantic_Editor_Architecture_Handoff.md) return 0 ;;
        *) return 1 ;;
    esac
}

# `Slopad` not already followed by `Editor`. Matches both the bare project name and any
# module or type still carrying the old prefix.
pattern='\bSlopad(?!Editor)'

declare -a offenders=()
total=0

while IFS= read -r file; do
    is_allowed "$file" && continue
    count=$(rg -c --pcre2 "$pattern" "$file" 2>/dev/null || true)
    [[ -z "$count" || "$count" == "0" ]] && continue
    offenders+=("$count|$file")
    total=$((total + count))
done < <(rg -l --pcre2 --hidden --glob '!.git' --glob '!.build' "$pattern" . 2>/dev/null | sed 's|^\./||' | sort)

if ((total == 0)); then
    echo "naming: clean — no pre-ADR-0016 names outside the documented allowlist"
    exit 0
fi

echo "naming: $total occurrence(s) of the pre-ADR-0016 name remain, in ${#offenders[@]} file(s)"
echo
echo "  by stage category:"
printf '%s\n' "${offenders[@]}" \
    | while IFS='|' read -r count file; do
        printf '%s\t%s\n' "$(category_of "$file")" "$count"
    done \
    | awk -F'\t' '{ n[$1] += $2; f[$1] += 1 }
        END { for (k in n) printf "  %6d in %3d file(s)  %s\n", n[k], f[k], k }' \
    | sort -rn
echo
if ((show_all == 1)); then
    echo "  all files:"
else
    echo "  largest 12 (use --all for the full list):"
fi
printf '%s\n' "${offenders[@]}" \
    | sort -t'|' -k1,1rn \
    | { ((show_all == 1)) && cat || head -12; } \
    | awk -F'|' '{ printf "  %6s  %s\n", $1, $2 }'
echo
echo "See ADR/0016 for the target scheme and docs/RENAME_MIGRATION_PLAN.md for the stage order."

# A stage that has been sealed must not regress. Each sealed stage adds its own check here
# as it completes, so finished work is protected while unfinished work stays reportable.

# STAGE 0 (sealed): the gate scripts must never disagree with the package identity again.
for script in scripts/verify-host-surface.sh scripts/verify-archive-surface.sh; do
    if rg -q --pcre2 'package: "Slopad(?!Editor)"' "$script"; then
        echo "REGRESSION: $script asserts a package name that is not the package identity" >&2
        exit 1
    fi
done

if ((strict == 1)); then
    echo "strict: failing while any occurrence remains" >&2
    exit 1
fi
exit 0
