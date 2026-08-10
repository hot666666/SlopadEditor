set shell := ["bash", "-cu"]

host-surface:
    bash scripts/verify-host-surface.sh

debug scenario="initial":
    swift build --product SlopadDebugApp
    .build/debug/SlopadDebugApp --scenario "{{scenario}}"
