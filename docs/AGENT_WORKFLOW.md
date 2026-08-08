# Agent Workflow

This document defines the changeable operating policy for Codex work in Slopad. The
executable source of truth for current model and reasoning settings is
[`../.codex/config.toml`](../.codex/config.toml) and the role files in
[`../.codex/agents/`](../.codex/agents/). Do not copy their values into issue plans or
commit messages as a second source of truth.

`AGENTS.md` holds stable project invariants and routing. This document owns operational
roles, review flow, and task-packet expectations.

## Roles

| Role | Use it for | Boundary |
| --- | --- | --- |
| `worker` | Narrow changes with settled ownership and acceptance criteria | One writer; stop and re-route concurrency, IME, canonical-state, TextKit, performance, memory-pressure, or cross-layer work. |
| `high_risk_worker` | Those high-risk owner or contract changes | One writer; trace the production path and supply stable-head verification. |
| `reviewer` | First fresh review of a stable diff | Read-only; probe real correctness and architecture risks without replaying credible full verification. |
| `critical_reviewer` | A previously reported P1 after its fix | Read-only; recheck that P1 and directly affected contracts only. |

Read exact model, reasoning, sandbox, and concurrency values from the executable config.
Do not introduce a role merely to repeat worker verification.

## Flow

```text
ready → working → stable review packet → reviewing → fixing | ready-to-merge
```

1. The orchestrator gives the writer a short packet: exact base, owner, acceptance
   criteria, relevant architecture documents, and required verification.
2. Only one writer changes a worktree at a time. Independent read-only inspection may
   run in parallel only when it cannot observe a moving diff.
3. The writer stops editing before first review and returns a stable packet: base/head,
   ownership boundaries, acceptance mapping, diff summary, verification actually run,
   and known limitations.
4. The first review is a fresh stable-diff review. A P1 returns to the same writer for a
   focused correction, then goes only to `critical_reviewer` for that repaired path.
5. The orchestrator runs the final integration checks that remain necessary after merge.

After a correction, rerun focused checks and only the verification gates invalidated by
that correction. Batch status visualizations after several merges or a material ownership
boundary change rather than making one for every issue.

## Non-negotiable operating rules

- Never review a moving diff.
- Do not use a broad re-review to rediscover unrelated work after a focused P1 repair.
- Keep task packets self-contained; do not forward an entire conversation as a work order.
- The worker proves stable-head behavior; a separate verifier role is not a substitute for
  that responsibility.
- Model selection is operational policy. Change it in `.codex` and this document, not in
  `AGENTS.md`.
