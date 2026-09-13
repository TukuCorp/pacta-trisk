---
status: proposed
date: 2026-09-13
---

# Artifact locations are owned by one R catalog and exported to the Snapshot

Nine places (the step registry, the Snapshot copier, run history, the refresh
audit, the gate, the snapshot-contract test, the engagement config's
`row_count_files`, and the Python loaders and their test) each spelled the same
Artifact paths by hand, so a rename broke consumers with no test to say so. We
decided that a single R module, `artifact_catalog(cfg)`, owns every Artifact's
key, producing Step, path and Snapshot path; every R consumer derives its list
from it, and the Snapshot step exports the resolved catalog as
`artifact_catalog.json` so the dashboard reads locations rather than retyping
them.

## Considered options

- **A static catalog file in the repo (JSON or YAML)** — rejected: every path
  depends on the engagement config (`cfg$paths$*`, `cfg$trisk_sectors`), so a
  file would need a template language, and YAML was already rejected as a
  dependency (CLAUDE.md law 8). `reports/report_catalog.json` remains: it holds
  Deliverable *metadata*, not locations.
- **Keep the Python lists and test that they equal the R catalog** — rejected:
  a test between two hand-typed lists only checks that someone updated both.
  With the export, the R writer and the Python reader are two adapters at one
  seam.

## Consequences

- A hand-typed Artifact path anywhere outside `R/artifact_catalog.R` is a
  defect, not a convenience.
- The Snapshot gains one file; the only writer of `dashboard/data/` is still
  `scripts/refresh_dashboard_data.R`.
- The catalog lists what an Engagement *can* produce; the Manifest records what
  a run *did* produce. Consumers keep their existence checks.
