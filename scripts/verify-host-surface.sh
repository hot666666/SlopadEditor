#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/clang-module-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

appkit_fixture="Fixtures/DownstreamAppKitHost"
swiftui_fixture="Fixtures/DownstreamSwiftUIHost"
appkit_source="$appkit_fixture/Sources/DownstreamAppKitHost/DownstreamAppKitHost.swift"
swiftui_source="$swiftui_fixture/Sources/DownstreamSwiftUIHost/DownstreamSwiftUIHost.swift"
appkit_resolved="$appkit_fixture/Package.resolved"
swiftui_resolved="$swiftui_fixture/Package.resolved"
appkit_resolved_existed=false
swiftui_resolved_existed=false
if [[ -e "$appkit_resolved" ]]; then appkit_resolved_existed=true; fi
if [[ -e "$swiftui_resolved" ]]; then swiftui_resolved_existed=true; fi

probe_root="$(mktemp -d "${TMPDIR:-/tmp}/slopad-host-surface.XXXXXX")"
cleanup() {
    rm -rf "$probe_root"
    if [[ "$appkit_resolved_existed" == false ]]; then rm -f "$appkit_resolved"; fi
    if [[ "$swiftui_resolved_existed" == false ]]; then rm -f "$swiftui_resolved"; fi
}
trap cleanup EXIT

# Fail with an actionable message rather than an opaque abort partway through a guard.
if ! command -v rg >/dev/null 2>&1; then
    echo "ripgrep is required by this gate but is not installed." >&2
    echo "  macOS: brew install ripgrep" >&2
    exit 1
fi

require_equal() {
    local label="$1"
    local actual="$2"
    local expected="$3"
    if [[ "$actual" != "$expected" ]]; then
        echo "$label" >&2
        echo "  expected: $expected" >&2
        echo "  actual:   $actual" >&2
        exit 1
    fi
}

# Count matches rather than matching lines. Both `rg -c` and `grep -c` report lines, so two
# declarations sharing a line would read as one and defeat the exactly-one-product guard.
count_matches() {
    local pattern="$1"
    shift
    rg --no-ignore --no-line-number --no-filename -o "$pattern" "$@" \
        | wc -l \
        | tr -d '[:space:]'
}

# Reduce every import to its module name before comparing. Attributes, attribute arguments,
# indentation, and declaration-kind imports must not be able to carry a raw package
# dependency past the allowlist. An attribute pattern that stops at the attribute name
# fails open rather than closed: `@_spi(Internal) import SlopadEditorEngine` stops looking like
# an import at all and drops out of the comparison entirely, which is the opposite of what
# this guard is for.
fixture_import_modules() {
    rg --no-line-number --no-filename -o -r '$1' \
        '^\s*(?:@\w+(?:\([^)]*\))?\s+)*import\s+(?:(?:typealias|struct|class|enum|protocol|func|var|let)\s+)?(\w+)' \
        "$1" \
        | sort -u
}

# Keep the ordinary-host gate honest at the source boundary. A fixture that silently gains
# a raw package dependency can keep compiling while the supported one-product surface is
# already broken. The import allowlist is exact, so a module the fixture never imports is
# also a module it cannot name.
require_equal "AppKit lifecycle fixture imports more than the supported facade" \
    "$(fixture_import_modules "$appkit_source")" \
    $'AppKit\nSlopadEditorAppKit'
require_equal "SwiftUI lifecycle fixture imports more than the supported facade" \
    "$(fixture_import_modules "$swiftui_source")" \
    $'AppKit\nSlopadEditorSwiftUI\nSwiftUI'

require_equal "AppKit lifecycle fixture must depend on the SlopadEditorAppKit product" \
    "$(count_matches '\.product\(name: "SlopadEditorAppKit", package: "SlopadEditor"\)' \
        "$appkit_fixture/Package.swift")" \
    "1"
require_equal "AppKit lifecycle fixture declares more than one product dependency" \
    "$(count_matches '\.product\(name:' "$appkit_fixture/Package.swift")" \
    "1"
if rg -n \
    'SlopadEditorCoreModel|SlopadEditorEngine|SlopadEditorMarkdownInputRules|SlopadEditorMarkdown|SlopadEditorArchive|SlopadEditorDataStructure|SlopadEditorDocumentModel|SlopadEditorBlockLayout|SlopadEditorAppKitUI|SlopadEditorAppKitTextKit|SlopadEditorSwiftUI|SlopadEditorDebugApp|SlopadEditorUIBenchmarkApp' \
    "$appkit_fixture/Package.swift"; then
    echo "AppKit lifecycle fixture manifest bypasses the SlopadEditorAppKit facade" >&2
    exit 1
fi

require_equal "SwiftUI lifecycle fixture must depend on the SlopadEditorSwiftUI product" \
    "$(count_matches '\.product\(name: "SlopadEditorSwiftUI", package: "SlopadEditor"\)' \
        "$swiftui_fixture/Package.swift")" \
    "1"
require_equal "SwiftUI lifecycle fixture declares more than one product dependency" \
    "$(count_matches '\.product\(name:' "$swiftui_fixture/Package.swift")" \
    "1"
if rg -n \
    'SlopadEditorCoreModel|SlopadEditorEngine|SlopadEditorMarkdownInputRules|SlopadEditorMarkdown|SlopadEditorArchive|SlopadEditorDataStructure|SlopadEditorDocumentModel|SlopadEditorBlockLayout|SlopadEditorAppKitUI|SlopadEditorAppKitTextKit|SlopadEditorAppKit|SlopadEditorDebugApp|SlopadEditorUIBenchmarkApp' \
    "$swiftui_fixture/Package.swift"; then
    echo "SwiftUI lifecycle fixture manifest bypasses the SlopadEditorSwiftUI facade" >&2
    exit 1
fi

if rg -n '^\s*(@testable\s+import|package(\s|$))' \
    "$appkit_source" "$swiftui_source"; then
    echo "Ordinary lifecycle fixture uses non-public package access" >&2
    exit 1
fi

swift run --package-path "$appkit_fixture" DownstreamAppKitHost
swift run --package-path "$swiftui_fixture" DownstreamSwiftUIHost

find_swift_command_key() {
    local description="$1"
    local target="$2"
    local keys
    local count
    # Match per occurrence, not per line. A line-shaped substitution would collapse a
    # compact `description.json` to a single key and silently degrade the uniqueness
    # check into "whichever key came last".
    keys="$(
        rg --no-ignore --no-line-number --no-filename \
            -o "\"C\\.${target}-[^\"]+\\.module\"" "$description" \
            | tr -d '"' \
            | sort -u
    )"
    count="$(printf '%s\n' "$keys" | awk 'NF { count += 1 } END { print count + 0 }')"
    if [[ "$count" != "1" ]]; then
        echo "Expected one Swift compile command for $target, found $count" >&2
        return 1
    fi
    printf '%s' "$keys"
}

swift_command_value() {
    local description="$1"
    local command_key="$2"
    local field="$3"
    local escaped_key="${command_key//./\\.}"
    plutil -extract "swiftCommands.${escaped_key}.${field}" raw -o - "$description"
}

# Read one Swift-level flag value out of the real downstream compile command.
#
# `-Xcc` scopes the argument that follows it to clang, and the real command already carries
# `-Xcc -F -Xcc <path>` alongside the Swift-level `-F <path>`. Scanning linearly for the
# first bare occurrence would let a SwiftPM reordering hand back a clang-scoped token — or
# the literal `-Xcc` — while every probe still reported success. That was the one place in
# this gate that could fail open, so consume `-Xcc` pairs atomically and require exactly
# one Swift-level occurrence instead.
swift_command_argument() {
    local description="$1"
    local command_key="$2"
    local requested_flag="$3"
    local escaped_key="${command_key//./\\.}"
    local index=0
    local value
    local match_count=0
    local match_value=""
    while value="$(
        plutil -extract "swiftCommands.${escaped_key}.otherArguments.${index}" raw -o - \
            "$description" 2>/dev/null
    )"; do
        if [[ "$value" == "-Xcc" ]]; then
            index=$((index + 2))
            continue
        fi
        if [[ "$value" != "$requested_flag" ]]; then
            index=$((index + 1))
            continue
        fi
        if ! match_value="$(
            plutil -extract "swiftCommands.${escaped_key}.otherArguments.$((index + 1))" \
                raw -o - "$description" 2>/dev/null
        )"; then
            echo "$requested_flag has no value in the downstream Swift compile command" >&2
            return 1
        fi
        if [[ "$match_value" == -* ]]; then
            echo "Value for $requested_flag is itself a flag: $match_value" >&2
            return 1
        fi
        match_count=$((match_count + 1))
        index=$((index + 2))
    done
    if [[ "$match_count" != "1" ]]; then
        echo "Expected one Swift-level $requested_flag, found $match_count" >&2
        return 1
    fi
    printf '%s' "$match_value"
}

typecheck_probe() {
    local swiftc="$1"
    local import_path="$2"
    local target="$3"
    local sdk="$4"
    local frameworks="$5"
    local system_imports="$6"
    local swift_version="$7"
    local source="$8"
    local diagnostics="$9"
    "$swiftc" -typecheck \
        -swift-version "$swift_version" \
        -target "$target" \
        -sdk "$sdk" \
        -F "$frameworks" \
        -I "$system_imports" \
        -I "$import_path" \
        -module-cache-path "$probe_root/module-cache" \
        "$source" >"$diagnostics" 2>&1
}

positive_probe() {
    local facade="$1"
    local symbol="$2"
    local swiftc="$3"
    local import_path="$4"
    local target="$5"
    local sdk="$6"
    local frameworks="$7"
    local system_imports="$8"
    local swift_version="$9"
    local source="$probe_root/positive-${facade}-${symbol}.swift"
    local diagnostics="$probe_root/positive-${facade}-${symbol}.log"
    printf 'import %s\nlet positiveProbe = %s.self\n' "$facade" "$symbol" >"$source"
    if ! typecheck_probe \
        "$swiftc" "$import_path" "$target" "$sdk" "$frameworks" "$system_imports" \
        "$swift_version" "$source" "$diagnostics"; then
        echo "Intended $facade symbol $symbol did not typecheck" >&2
        cat "$diagnostics" >&2
        return 1
    fi
    echo "host-surface positive facade=$facade symbol=$symbol"
}

forbidden_probe_serial=0

forbidden_probe() {
    local facade="$1"
    local symbol="$2"
    local swiftc="$3"
    local import_path="$4"
    local target="$5"
    local sdk="$6"
    local frameworks="$7"
    local system_imports="$8"
    local swift_version="$9"
    # Number the probe files instead of naming them after the symbol. swiftc prints the
    # source path on every diagnostic, so a path carrying the symbol would satisfy the
    # "does this failure actually mention the symbol" guard below no matter why the
    # compile failed.
    forbidden_probe_serial=$((forbidden_probe_serial + 1))
    local source="$probe_root/forbidden-${forbidden_probe_serial}.swift"
    local diagnostics="$probe_root/forbidden-${forbidden_probe_serial}.log"
    printf 'import %s\nlet forbiddenProbe = %s.self\n' "$facade" "$symbol" >"$source"
    if typecheck_probe \
        "$swiftc" "$import_path" "$target" "$sdk" "$frameworks" "$system_imports" \
        "$swift_version" "$source" "$diagnostics"; then
        echo "Forbidden $facade symbol $symbol became externally accessible" >&2
        return 1
    fi
    # Only a symbol-specific access diagnostic counts. A plain "does the log mention the
    # symbol" guard cannot add anything here: swiftc echoes the offending source line, and
    # that line names the symbol whatever the failure was — including a missing module.
    if ! rg -q \
        "cannot find '$symbol' in scope|'$symbol' is inaccessible due to 'package' protection level|'$symbol' is inaccessible due to 'internal' protection level" \
        "$diagnostics"; then
        echo "Forbidden probe for $facade.$symbol failed without an access diagnostic" >&2
        cat "$diagnostics" >&2
        return 1
    fi
    echo "host-surface forbidden import=$facade symbol=$symbol"
}

appkit_bin_path="$(
    swift build --package-path "$appkit_fixture" --show-bin-path
)"
swiftui_bin_path="$(
    swift build --package-path "$swiftui_fixture" --show-bin-path
)"
appkit_description="$appkit_bin_path/description.json"
swiftui_description="$swiftui_bin_path/description.json"
test -f "$appkit_description"
test -f "$swiftui_description"

appkit_command_key="$(
    find_swift_command_key "$appkit_description" DownstreamAppKitHost
)"
swiftui_command_key="$(
    find_swift_command_key "$swiftui_description" DownstreamSwiftUIHost
)"

appkit_swiftc="$(swift_command_value "$appkit_description" "$appkit_command_key" executable)"
appkit_import_path="$(
    swift_command_value "$appkit_description" "$appkit_command_key" importPath
)"
appkit_target="$(swift_command_argument "$appkit_description" "$appkit_command_key" -target)"
appkit_sdk="$(swift_command_argument "$appkit_description" "$appkit_command_key" -sdk)"
appkit_frameworks="$(swift_command_argument "$appkit_description" "$appkit_command_key" -F)"
appkit_system_imports="$(
    swift_command_argument "$appkit_description" "$appkit_command_key" -I
)"
appkit_swift_version="$(
    swift_command_argument "$appkit_description" "$appkit_command_key" -swift-version
)"

swiftui_swiftc="$(swift_command_value "$swiftui_description" "$swiftui_command_key" executable)"
swiftui_import_path="$(
    swift_command_value "$swiftui_description" "$swiftui_command_key" importPath
)"
swiftui_target="$(swift_command_argument "$swiftui_description" "$swiftui_command_key" -target)"
swiftui_sdk="$(swift_command_argument "$swiftui_description" "$swiftui_command_key" -sdk)"
swiftui_frameworks="$(swift_command_argument "$swiftui_description" "$swiftui_command_key" -F)"
swiftui_system_imports="$(
    swift_command_argument "$swiftui_description" "$swiftui_command_key" -I
)"
swiftui_swift_version="$(
    swift_command_argument "$swiftui_description" "$swiftui_command_key" -swift-version
)"

positive_probe SlopadEditorAppKit AppKitEditorAction \
    "$appkit_swiftc" "$appkit_import_path" "$appkit_target" "$appkit_sdk" \
    "$appkit_frameworks" "$appkit_system_imports" "$appkit_swift_version"
positive_probe SlopadEditorAppKit AppKitEditorViewController \
    "$appkit_swiftc" "$appkit_import_path" "$appkit_target" "$appkit_sdk" \
    "$appkit_frameworks" "$appkit_system_imports" "$appkit_swift_version"
positive_probe SlopadEditorSwiftUI SlopadEditorView \
    "$swiftui_swiftc" "$swiftui_import_path" "$swiftui_target" "$swiftui_sdk" \
    "$swiftui_frameworks" "$swiftui_system_imports" "$swiftui_swift_version"
positive_probe SlopadEditorSwiftUI SlopadEditorViewModel \
    "$swiftui_swiftc" "$swiftui_import_path" "$swiftui_target" "$swiftui_sdk" \
    "$swiftui_frameworks" "$swiftui_system_imports" "$swiftui_swift_version"

appkit_forbidden_symbols=(
    EditorCommandState
    EditorCommandAction
    EditorCommandSelectionMode
    EditorSelectionPresentation
    EditorVisibleTextSelection
    AppKitFloatingFormattingToolbar
    AppKitTodoCheckboxControl
    BlockLayout
    TextKitTextSystem
)
for symbol in "${appkit_forbidden_symbols[@]}"; do
    forbidden_probe SlopadEditorAppKit "$symbol" \
        "$appkit_swiftc" "$appkit_import_path" "$appkit_target" "$appkit_sdk" \
        "$appkit_frameworks" "$appkit_system_imports" "$appkit_swift_version"
done

swiftui_forbidden_symbols=(
    AppKitEditorViewController
    EditorCommandState
    EditorCommandAction
    EditorCommandSelectionMode
    EditorSelectionPresentation
    EditorVisibleTextSelection
    AppKitFloatingFormattingToolbar
    AppKitTodoCheckboxControl
    BlockLayout
    TextKitTextSystem
)
for symbol in "${swiftui_forbidden_symbols[@]}"; do
    forbidden_probe SlopadEditorSwiftUI "$symbol" \
        "$swiftui_swiftc" "$swiftui_import_path" "$swiftui_target" "$swiftui_sdk" \
        "$swiftui_frameworks" "$swiftui_system_imports" "$swiftui_swift_version"
done

# The probes above import the facade, so what they pin is "this symbol is not re-exported
# through the supported product". For a symbol that is public in another module that is the
# entire claim available: SwiftPM gives the downstream target one `-I` covering every built
# module, so `import SlopadEditorAppKitTextKit` compiles in a target that only declared the
# SlopadEditorAppKit product, and `--explicit-target-dependency-import-check error` does not stop
# it across packages. Reaching that symbol still costs the host an explicit import of a
# module it never declared, which is visible in review, but the compiler does not forbid it.
#
# Package and internal symbols support the stronger claim, so pin that instead: they stay
# unreachable even when an external consumer imports their own module directly. These are
# the symbols whose exposure would actually widen the host contract.
declared_module_forbidden_symbols=(
    "SlopadEditorEngine:EditorCommandState"
    "SlopadEditorEngine:EditorCommandAction"
    "SlopadEditorEngine:EditorCommandSelectionMode"
    "SlopadEditorEngine:EditorSelectionPresentation"
    "SlopadEditorEngine:EditorVisibleTextSelection"
    "SlopadEditorAppKitUI:AppKitFloatingFormattingToolbar"
    "SlopadEditorAppKitUI:AppKitTodoCheckboxControl"
    "SlopadEditorBlockLayout:BlockLayout"
)
for entry in "${declared_module_forbidden_symbols[@]}"; do
    forbidden_probe "${entry%%:*}" "${entry##*:}" \
        "$appkit_swiftc" "$appkit_import_path" "$appkit_target" "$appkit_sdk" \
        "$appkit_frameworks" "$appkit_system_imports" "$appkit_swift_version"
done
