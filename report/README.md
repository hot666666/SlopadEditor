# Reports

Point-in-time published reports. Each file records what was true at one commit and is never
updated afterwards — a later report supersedes an earlier one rather than editing it.

Naming: `<publish-date>-<short-sha>-<slug>.html`

The short SHA is the commit the report describes, so a stale page can always be placed
against the tree it came from. Nothing here is a source of truth: current source and tests
define what the code does, `docs/ARCHITECTURE.md` and `ADR/` define the boundaries, and
`docs/ROADMAP.md` defines intent.

Delete a report when its commit is far enough behind that nobody would place it correctly.
