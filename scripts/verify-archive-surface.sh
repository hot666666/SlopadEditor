#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/clang-module-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

fixture="Fixtures/DownstreamArchiveHost"
codec_source="$fixture/Sources/ArchiveCodecSurfaceProbe/ArchiveCodecSurfaceProbe.swift"
lifecycle_source="$fixture/Sources/AppKitArchiveLifecycleProbe/AppKitArchiveLifecycleProbe.swift"
archive_source="Sources/SlopadEditorArchive"

test "$(rg '^public typealias ' "$archive_source" | wc -l | tr -d ' ')" = "5"
test "$(rg '^public import SlopadCoreModel$' "$archive_source" | wc -l | tr -d ' ')" = "1"
if rg -n '@_exported import|import SlopadEngine|import SlopadAppKit|import SlopadEditorSwiftUI' \
    "$archive_source"; then
    echo "Archive target widened beyond its CoreModel-only boundary" >&2
    exit 1
fi

codec_imports="$(rg '^import ' "$codec_source" | sort)"
test "$codec_imports" = $'import Foundation\nimport SlopadEditorArchive'

lifecycle_imports="$(rg '^import ' "$lifecycle_source" | sort)"
test "$lifecycle_imports" = $'import AppKit\nimport SlopadAppKit\nimport SlopadEditorArchive'

codec_manifest_block="$(sed -n '/name: "ArchiveCodecSurfaceProbe"/,/name: "AppKitArchiveLifecycleProbe"/p' "$fixture/Package.swift")"
test "$(printf '%s' "$codec_manifest_block" | rg -c 'product\(name: "SlopadEditorArchive"')" = "1"
if printf '%s' "$codec_manifest_block" | rg 'product\(name: "SlopadAppKit"'; then
    echo "Codec probe gained an AppKit dependency" >&2
    exit 1
fi

lifecycle_manifest_block="$(sed -n '/name: "AppKitArchiveLifecycleProbe"/,$p' "$fixture/Package.swift")"
test "$(printf '%s' "$lifecycle_manifest_block" | rg -c 'product\(name: "SlopadEditorArchive"')" = "1"
test "$(printf '%s' "$lifecycle_manifest_block" | rg -c 'product\(name: "SlopadAppKit"')" = "1"
if printf '%s' "$lifecycle_manifest_block" | rg 'SlopadCoreModel|SlopadEngine|SlopadEditorSwiftUI|SlopadEditorAppKitUI'; then
    echo "Lifecycle probe gained a raw product dependency" >&2
    exit 1
fi

if rg -n 'SlopadCoreModel|SlopadEngine|SlopadAppKit|SlopadEditorSwiftUI|SlopadEditorAppKitUI' \
    "$codec_source"; then
    echo "Codec probe bypasses the Archive facade" >&2
    exit 1
fi

if rg -n 'SlopadCoreModel|SlopadEngine|SlopadEditorSwiftUI|SlopadEditorAppKitUI|@testable|\bpackage\b' \
    "$lifecycle_source"; then
    echo "Lifecycle probe bypasses its public facades" >&2
    exit 1
fi

if rg -n 'SlopadEditorArchive' \
    Fixtures/DownstreamAppKitHost \
    Fixtures/DownstreamSwiftUIHost \
    Fixtures/DownstreamMarkdownHost \
    --glob '!**/.build/**'; then
    echo "An existing fixture gained an Archive dependency" >&2
    exit 1
fi

swift run --disable-sandbox --package-path "$fixture" ArchiveCodecSurfaceProbe
swift run --disable-sandbox --package-path "$fixture" AppKitArchiveLifecycleProbe
