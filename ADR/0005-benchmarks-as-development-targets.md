# 0005 - Keep Benchmark APIs out of the Public Library Surface

Date: 2026-07-08

## Status

Accepted, amended 2026-07-16

## Context

Slopad needs benchmark executables for layout/index/storage work. These executables use
release builds, instrumentation flags, local CSV output, and sometimes package-internal
SPI. They are part of the development and regression workflow, not the library surface
that downstream users should depend on.

At the same time, keeping benchmarks inside the package is useful because benchmark code
can exercise package access without widening regular public API.

## Decision

Keep `SlopadHeightBenchmark` and `SlopadSessionBenchmark` as executable targets under
`Benchmarks/`, but do not list them as SwiftPM products.

Keep `SlopadUIBenchmarkApp` as a named executable product because the standard AppKit UI
verification workflow builds and runs it directly. It is still a development harness and
does not define a reusable library contract.

The reusable library products are `SlopadEngine`, `SlopadAppKitTextKit`, and
`SlopadAppKitUI`. `SlopadDebugApp` and `SlopadUIBenchmarkApp` are executable products that
consume those libraries from the outer edge.

## Consequences

- Build benchmark executables by target:

  ```sh
  swift build --target SlopadHeightBenchmark --quiet
  swift build --target SlopadSessionBenchmark --quiet
  ```

- Run benchmark executables by name when needed:

  ```sh
  swift run -c release -Xswiftc -DSLOPAD_BENCHMARK_INSTRUMENTATION SlopadSessionBenchmark
  ```

- Do not add benchmark-only types to public API to make benchmark code easier to write.
- A benchmark executable product is a runnable development entry point, not evidence that
  its helpers or policies belong in a public library surface.
- Treat benchmark baselines and docs as development evidence, not consumer-facing product
  surface.
