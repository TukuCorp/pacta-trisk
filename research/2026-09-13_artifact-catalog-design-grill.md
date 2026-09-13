---
title: "Design grill: the Artifact catalog (architecture review candidate A)"
date: "2026-09-13"
status: "decisions taken in the user's absence — review before implementing"
source: "/codebase architecture review, report at %TEMP%\\architecture-review-20260913-121302.html"
---

# Design grill: the Artifact catalog

The 2026-09-13 architecture review ranked eight deepening candidates and put
"Give every Artifact one owner" first. The user was absent, so the grilling
loop below was run by the reviewer alone: every question is recorded with the
recommended answer and the decision taken. **Nothing has been implemented.**
Each "Decision" is a proposal the user can overturn; the global working
agreement requires a plan in `activeContext.md` and a check-in before code.

## The friction being deepened

"Which Step writes which Artifact, and where its Snapshot copy lands" is
knowledge with no module. It is retyped, by hand, in:

| Site | What it spells |
|---|---|
| `R/step_registry.R:41-46` | six `produces_fn`/`requires_fn` path closures |
| `scripts/refresh_dashboard_data.R:65-71, 105-119, 172, 196-200` | 6 PACTA + 14 TRISK + 3 grid + 4 analytics basenames |
| `scripts/record_run_history.R:22-27` | 4 headline artifacts |
| `scripts/generate_refresh_audit.R:60-80` | 3 artifacts, read from the Snapshot copy |
| `tools/verify_refactor.R:53-60, 398-405` | `GATED_HTML_PATHS`, `TIMESTAMP_BASENAMES`, INV-003 candidates |
| `tests/testthat/test_snapshot_contract.R:4-13` | the 14 + 3 TRISK list again |
| `engagements/mcb-demo/engagement_config.json` `row_count_files` | 6 Snapshot paths verbatim |
| `dashboard/lib/loaders.py:100-178` | the Python twin, with semantic keys |
| `dashboard/tests/test_loaders.py:39-65` | the Python twin's fixture |

Deletion test on the registry closures: deleting them moves nothing, because
every consumer already carries the same literal. Shallow.

Two precedents already in the tree shape the answer:

- `reports/report_catalog.json` is a real catalog for HTML deliverables
  (title, date, summary, `category`), and the Snapshot copier cross-checks
  `cfg$published_reports` against it and refuses `internal_build` entries.
- `dashboard/lib/loaders.py` already names artifacts semantically
  (`matches`, `ms_company`, `sda_alignment`, `combined`, …).

---

## Round 1 — scope, seam, representation, the Python side, the bar

❓ **Q1 — Scope**: Which Artifacts belong in the catalog? (a) every file any
Step writes; (b) only Artifacts that some module *other than their producer*
names: Step inputs, Snapshot copies, run-history headlines, audit reads, gate
lists, `row_count_files`, the Python loaders; (c) only the Snapshot set.

➡️ (b). A catalog entry earns its place by having a consumer. Producer-internal
intermediates (PACTA `01_*.csv`, per-run grid CSVs under `runs/`) stay out
unless they are snapshotted. Directories that are consumed by name
(`trisk_input_root`, the per-sector TRISK output directories, the `figures`
PNG groups) are entries with `kind = "dir"` / `"png_group"`.

**Decision:** (b).

---

❓ **Q2 — Seam location**: Grow `R/step_registry.R` to hold the paths, or add a
new module the registry consumes?

➡️ New module, `R/artifact_catalog.R`. The registry's job is ordering and
arguments; the catalog's job is location. Registry entries then name
artifacts by key, and `produces`/`requires` are *derived* (every catalog row
whose `producer` is this step), which deletes the six closures rather than
moving them.

**Decision:** new module; registry derives.

---

❓ **Q3 — Representation**: R data built from `cfg` (a function), or a static
JSON/YAML file in the repo?

➡️ R data built from `cfg`. Every path depends on `cfg$paths$*` and
`cfg$trisk_sectors`, so a static file would need a template language, and
law 8 already rejected YAML. `reports/report_catalog.json` stays as it is: it
holds *metadata* about HTML deliverables (title, summary, category), not
locations, and it is already cross-checked. The catalog treats "published
reports" as one group whose members come from `cfg$published_reports`.

**Decision:** `artifact_catalog(cfg)` in R; `report_catalog.json` untouched.

---

❓ **Q4 — The Python side**: Keep the Python lists and add a test that they
equal the R catalog, or have R export a resolved catalog into the Snapshot
that Python reads?

➡️ Export. The Snapshot step writes `<snapshot_dir>/artifact_catalog.json`
(semantic key, group, snapshot-relative path, sector where applicable), and
`loaders.py` builds its tables from it. Two adapters — the R writer and the
Python reader — make the seam real; a Python test comparing two hand-typed
lists would only be checking that someone remembered to update both. The only
writer of `dashboard/data/` remains `scripts/refresh_dashboard_data.R`, so the
do-not-touch rule holds. `pipeline_manifest.json` is the precedent for an R
sidecar the app reads.

**Decision:** export + read. Python's `load_pacta()`/`load_trisk()` keep their
current return shape (same dict keys) so pages do not change.

---

❓ **Q5 — Acceptance bar**: What proves the refactor changed nothing?

➡️ Law 5 as written: `Rscript tools/verify_refactor.R` byte-identical CSVs,
gated HTML fingerprints unchanged, `--invariants` PASS, full R and Python
suites green. Plus one *transition test*, kept only during migration: the
catalog's resolved path set for `mcb-demo` equals the union of today's literal
lists (pin the union verbatim in the test, delete the test after the last
consumer is migrated). The new `artifact_catalog.json` in the Snapshot is an
added file, not drift.

**Decision:** as recommended.

---

## Round 2 — keys, sector expansion, fields, gate lists, config, migration order

❓ **Q6 — Keys**: Basenames (`02_vn_matched_prioritized.csv`) or semantic keys?

➡️ Semantic snake_case keys, adopting `loaders.py`'s existing names where they
exist so the Python side changes least: `matches`, `ms_company`,
`ms_portfolio`, `sda_portfolio`, `ms_alignment`, `sda_alignment`; TRISK
per-sector `assets`, `company_summary`, `company_trajectories`,
`financial_features`, `carbon_price`, `npv_results`, `params`, `pd_results`,
`pd_summary`, `run_catalog`, `scenarios`, `sensitivity_results`,
`sensitivity_summary`, `top_borrowers` (Python's `combined`);
grid `grid_scenarios`, `grid_borrower_results`, `grid_meta`; analytics
`financed_emissions`, `data_quality_summary`, `target_registry`,
`sll_readiness`; engagement `normalized_loanbook`, `coverage_metrics`,
`sector_priority_ranking`, `sector_priority_detail`, `engagement_priority`.
The basename is a property of the row, never the identity.

**Decision:** semantic keys; rename Python's `combined` → `top_borrowers`
only inside the loader, keeping the returned dict key `combined` for pages.

---

❓ **Q7 — Per-sector Artifacts**: How do the 14 TRISK files × N sectors and the
3 grid files × N sectors appear?

➡️ One template row per key with `scope = "sector"`; `artifact_catalog(cfg)`
expands it over `cfg$trisk_sectors` into resolved rows carrying a `sector`
column. Engagement-level rows have `scope = "engagement"` and `sector = NA`.

**Decision:** as recommended.

---

❓ **Q8 — Fields**: What does a resolved row carry?

➡️ `key`, `group` (pacta / trisk / grid / analytics / engagement / intake /
reports), `scope`, `sector`, `producer` (step key), `kind`
(csv / parquet / json / html / png_group / dir), `path` (repo-relative,
resolved from `cfg$paths`), `snapshot_path` (repo-relative, or NA when not
published), and boolean flags **only where a consumer exists today**:
`history_headline` (record_run_history), `timestamp_class` (gate),
`gated_html` (gate), `disclaimer_required` (INV-010). No flag without a
consumer; a flag with no reader is a shallow field.

**Decision:** as recommended.

---

❓ **Q9 — Gate lists**: Should `tools/verify_refactor.R` derive
`GATED_HTML_PATHS`, `TIMESTAMP_BASENAMES` and the INV-003 candidate list from
the catalog now, or wait for candidate F (the gate-as-module move)?

➡️ Derive now, but for `mcb-demo` only, so behaviour is byte-identical:
`artifact_catalog(load_engagement_config("engagements/mcb-demo/engagement_config.json"))`
filtered on the flags. The tool already sources `R/report_fingerprint.R` via
relative-path candidates; it sources `R/engagement_config.R` and
`R/artifact_catalog.R` the same way. Making the gate per-engagement is F's
job and is not started here.

**Decision:** derive for mcb-demo; F unchanged.

---

❓ **Q10 — `row_count_files` in the engagement config**: Today it lists six
Snapshot paths verbatim. Replace with catalog keys, or keep and validate?

➡️ Keep the key (which files get row-counted is a per-engagement choice) but
validate each entry against the catalog's `snapshot_path` set in
`.validate_engagement_config()`, so a renamed artifact fails config load
instead of silently counting nothing. Switching the config to keys is a
follow-up once the catalog is trusted.

**Decision:** keep + validate.

---

❓ **Q11 — Migration order and which tests survive**:

➡️ Order, each step landing green under law 5:
1. Add `R/artifact_catalog.R` + `tests/testthat/test_artifact_catalog.R`
   (row shape, sector expansion, every key unique, every `producer` is a
   registry key) + the transition test from Q5.
2. `R/step_registry.R`: replace the six closures with derived
   `produces`/`requires`. `test_step_dependencies.R` and
   `test_step_registry.R` are unchanged: the registry's interface is the same.
3. `scripts/refresh_dashboard_data.R`: copy lists come from
   `snapshot_path`; write `artifact_catalog.json`. Rewrite
   `test_snapshot_contract.R` to "every catalog row with a `snapshot_path`
   exists under `dashboard/data`, and nothing under `dashboard/data/{pacta,
   trisk,analytics}` is uncatalogued" — the version that passes the deletion
   test, since it no longer copies the list.
4. `scripts/record_run_history.R` (`history_headline` rows) and
   `scripts/generate_refresh_audit.R` (`snapshot_path` of `matches`,
   `top_borrowers[power]`, `engagement_priority`).
5. `tools/verify_refactor.R` lists (Q9).
6. `dashboard/lib/loaders.py` reads `artifact_catalog.json`;
   `test_loaders.py` fixtures are generated from that JSON.
7. Delete the transition test.

**Decision:** as recommended.

---

## Round 3 — interface shape, the audit's source, terms, ADR, leftovers

❓ **Q12 — Interface shape**: How many functions does a caller learn?

➡️ Three. `artifact_catalog(cfg)` → one data.frame, one row per resolved
Artifact (callers filter on columns: `producer == "pacta"`,
`!is.na(snapshot_path)`, `history_headline`). `artifact_path(cfg, key,
sector = NULL)` → one path, erroring on an unknown key (the common case in
scripts). `write_artifact_catalog_json(cfg, path)` → the Snapshot export.
No per-group accessor functions: a frame the caller filters is a smaller
interface than six getters, and it is the whole test surface.

**Decision:** three functions.

---

❓ **Q13 — The refresh audit reads the Snapshot copy, not the producer's
output**: Keep that?

➡️ Keep. The audit attests to what was *published*, so the copy is the right
source; it just gets that path from `snapshot_path` instead of spelling
`snapshot_dir/pacta/…` itself.

**Decision:** keep, via the catalog.

---

❓ **Q14 — Domain terms**: The review used Engagement, Step, Artifact,
Snapshot, Deliverable, Manifest, Loanbook without a glossary. Record them?

➡️ Yes: no `CONTEXT.md` existed. Created at the repo root with those terms
plus **Artifact catalog** and **Published report** (the `report_catalog.json`
concept), and **Gate** / **Golden numbers** because the laws in `CLAUDE.md`
lean on them. Implementation detail stays out of it.

**Decision:** `CONTEXT.md` created.

---

❓ **Q15 — ADR**: Does "artifact locations are owned by an R catalog, exported
to the Snapshot, never retyped in Python" meet the bar (hard to reverse,
surprising without context, a real trade-off)?

➡️ Yes on all three: once Python reads the export, a hand-typed list in
`loaders.py` becomes a regression; a future reader will ask why the app reads
a JSON sidecar instead of globbing; and a static repo-level catalog file was a
genuine alternative rejected for a specific reason (paths depend on the
engagement config; law 8 rejects YAML). Recorded as `docs/adr/0001-artifact-catalog-owns-locations.md`.

**Decision:** ADR written.

---

❓ **Q16 — Anything still silently assumed?**

➡️ Three things, made explicit:
- Engagement letters and the disclosure pack are directories nobody consumes
  by name, so the *directories* are not catalogued (Q1 rule). Correction on
  re-reading the gate: `tools/verify_refactor.R`'s `DISCLAIMER_HTML_PATHS`
  names `output/disclosure/disclosure_pack.html` and
  `output/engagement_letters/index.html`, so those two files *are* consumed by
  name and get rows with `disclaimer_required = TRUE`.
- `sdb-rehearsal` has `run_grid` false and no analytics; `artifact_catalog(cfg)`
  still lists those rows (the catalog is the *possible* set); consumers that
  copy or count check existence as they do today. The catalog does not know
  what ran; the Manifest does.
- The `trisk/manifest.csv` written by the Snapshot step is a Snapshot-only
  Artifact with `producer = "snapshot"`, `timestamp_class = TRUE`; it appears
  in the catalog so the gate's `TIMESTAMP_BASENAMES` can be derived.

**Decision:** as stated.

---

## Frontier

Empty. Every branch above has a recorded decision. Nothing has been built.

## Next step

Plan written: `plans/2026-09-13-artifact-catalog-plan.md` (five phases,
self-contained). Confirm before implementation. Estimated size: one new R module (~150 lines), one new test
file, edits in six R files and two Python files, no golden number moves, no
CSV drift.
