---
title: "Artifact Catalog: One Owner for Every Artifact Location"
date: "2026-09-13"
status: "complete"
request: "Artifact catalog: give every Artifact one owner (architecture review candidate A). Design decisions already taken in research/2026-09-13_artifact-catalog-design-grill.md and docs/adr/0001-artifact-catalog-owns-locations.md; glossary in CONTEXT.md."
plan_type: "multi-phase"
research_inputs:
  - "research/2026-09-13_artifact-catalog-design-grill.md"
  - "docs/adr/0001-artifact-catalog-owns-locations.md"
---

# Plan: Artifact Catalog: One Owner for Every Artifact Location

## Objective

Give every pipeline Artifact (the CSV, parquet, JSON, PNG-group and HTML files
one pipeline Step writes and another part of the platform reads by name) a
single owner: a new R module `R/artifact_catalog.R` that knows each Artifact's
key, producing Step, repo-relative output path and Snapshot path. Nine places
currently spell those paths by hand and two of them are already wrong (the
step registry declares a TRISK output directory that does not exist). After
this work every R consumer derives its list from the catalog, the Snapshot
carries a machine-readable export of it, and the Streamlit dashboard reads
that export instead of retyping the paths. All committed CSV and HTML
artifacts must remain byte-identical: this is a refactor under the repo's
existing acceptance gate, not a behaviour change.

## Context Snapshot

- **Current state:** `main` at `bd09f48` (Wave 5 landed; `NEWS.md` says
  0.7.0 unreleased). Artifact paths are hand-typed in:
  `R/step_registry.R:41-46` (six `produces_fn`/`requires_fn` closures);
  `scripts/refresh_dashboard_data.R:65-71, 105-119, 152-153, 172, 196-200`
  (6 PACTA + 14 TRISK + 3 grid + 4 analytics basenames and the `_demo`
  directory suffix); `scripts/record_run_history.R:22-27` (4 headline
  artifacts); `scripts/generate_refresh_audit.R:69, 78, 87` (3 artifacts);
  `scripts/pacta_vietnam_scenario.R:83-96` (facts sidecar re-reads
  `02_vn_matched_prioritized.csv`); `tools/verify_refactor.R:48-52, 77-84,
  89-93, 368-378` (`TIMESTAMP_BASENAMES`, `GATED_HTML_PATHS`,
  `DISCLAIMER_HTML_PATHS`, INV-003 candidates); `R/engagement_plan.R:191-195`
  (manifest path rule); `tests/testthat/test_snapshot_contract.R:4-13` (the
  TRISK list again); `dashboard/lib/loaders.py:100-178` and
  `dashboard/tests/test_loaders.py` (the Python twin). Two declared paths in
  the registry are fictional: `file.path(cfg$paths$trisk_output_root,
  cfg$trisk_sectors)` yields `synthesis_output/trisk/power` but the real
  directory is `synthesis_output/trisk/power_demo` (see
  `R/trisk_core.R:641`), and `cfg$paths$trisk_input_root` is declared as a
  single produced path while the real inputs sit under
  `<trisk_input_root>/<sector>_demo/`. `validate_step_dependencies()`
  compares strings, so ordering still validated against paths nothing writes.
- **Desired state:** `R/artifact_catalog.R` exists with three exported
  functions; `step_registry()` derives every `produces_fn` from the catalog
  and declares `requires` by artifact key; `scripts/refresh_dashboard_data.R`
  copies what the catalog says and writes `<snapshot_dir>/artifact_catalog.json`;
  run history, the refresh audit, the PACTA facts sidecar and the gate's path
  lists come from the catalog; `dashboard/lib/loaders.py` reads
  `artifact_catalog.json`; `dashboard/data/artifact_catalog.json` is committed
  for the public MCB Snapshot; `tests/testthat/test_artifact_catalog.R` and
  a rewritten `test_snapshot_contract.R` prove the catalog against the frozen
  Snapshot. `Rscript tools/verify_refactor.R` reports no drift and
  `--invariants` passes.
- **Key repo surfaces:** `R/artifact_catalog.R` (new), `R/step_registry.R`,
  `R/engagement_plan.R`, `R/engagement_config.R`,
  `scripts/run_engagement.R`, `scripts/refresh_dashboard_data.R`,
  `scripts/record_run_history.R`, `scripts/generate_refresh_audit.R`,
  `scripts/pacta_vietnam_scenario.R`, `tools/verify_refactor.R`,
  `dashboard/lib/loaders.py`, `dashboard/data/artifact_catalog.json` (new,
  generated), `dashboard/data/README.md`, `tests/testthat/test_artifact_catalog.R`
  (new), `tests/testthat/test_snapshot_contract.R`,
  `dashboard/tests/test_loaders.py`, `NAMESPACE`, `man/`, `NEWS.md`.
- **Out of scope:** Changing any Step's order or what any producer writes
  (the producers in `R/pacta_core.R`, `R/trisk_core.R`,
  `R/prioritization_core.R` and the generator scripts keep their own write
  paths; the catalog *declares* them, and a test checks the declaration
  matches the tree). Fixing the ordering defect this plan exposes (see
  Gotchas: `sector_prioritization` and the analytics copy read the *previous*
  run's Snapshot). Making the gate's HTML lists per-engagement (they are
  derived for `mcb-demo` only, exactly as today). Moving
  `tools/verify_refactor.R`'s `.engagement_manifests()` onto the catalog (its
  test fixtures write minimal configs the catalog cannot resolve). Replacing
  the engagement config's `row_count_files` paths with keys (they are
  validated against the catalog instead). Any change to `reports/report_catalog.json`,
  which stays the owner of Deliverable *metadata* (title, summary, category).

## Environment & Conventions

- **Stack:** R 4.5.2 via `Rscript` (base R `%||%` is available; `R/engagement_config.R`
  also defines a fallback), packages pinned in `renv.lock` but installed
  without renv activation by `scripts/ci/install_deps.R`; the R sources double
  as the `pactatrisk` package (`DESCRIPTION`, roxygen2-generated `NAMESPACE`
  and `man/`). Python 3.11+ with Streamlit for `dashboard/`, pinned in
  `dashboard/requirements.lock`. JSON via `jsonlite` only: YAML is a rejected
  dependency.
- **Setup:** `Rscript scripts/ci/install_deps.R --dev` (adds testthat,
  roxygen2, devtools) and `python -m pip install -r dashboard/requirements.lock`.
  On Windows, `Rscript` is `"C:\Program Files\R\R-4.5.2\bin\Rscript.exe"`;
  PowerShell 5.1 has no `&&`, so run commands one at a time.
- **Build / Run:** always from the repo root (every script resolves paths via
  `getwd()`). Full public refresh: `Rscript scripts/pipeline_refresh.R`
  (delegates to `Rscript scripts/run_engagement.R --config engagements/mcb-demo/engagement_config.json`).
  Snapshot step alone: `Rscript scripts/refresh_dashboard_data.R --config engagements/mcb-demo/engagement_config.json`.
  Regenerate `NAMESPACE`/`man/` after adding or changing `#' @export`
  functions: `Rscript -e "roxygen2::roxygenise()"` (CI diffs `NAMESPACE`
  before/after and fails on any difference). Package load check:
  `Rscript -e "devtools::load_all('.')"`.
- **Test:** full R suite `Rscript -e "testthat::test_dir('tests/testthat')"`
  (expect `FAIL 0`); single file
  `Rscript -e "testthat::test_file('tests/testthat/test_artifact_catalog.R')"`.
  Python suite `python -m pytest dashboard/tests` (runs against the frozen
  `dashboard/data` unless a test sets `PACTATRISK_SNAPSHOT_DIR`); single file
  `python -m pytest dashboard/tests/test_loaders.py`. Byte-identity gate:
  `Rscript tools/verify_refactor.R` (runs the full refresh, then classifies
  `git diff --name-only`; expect `BYTE-IDENTITY PASS`); consistency gate:
  `Rscript tools/verify_refactor.R --invariants` (expect `INVARIANTS PASS`).
  SDB end-to-end (minutes):
  `Rscript scripts/run_engagement.R --config engagements/sdb-rehearsal/engagement_config.json`
  then `RUN_SDB_ENGAGEMENT=1 Rscript -e "testthat::test_file('tests/testthat/test_sdb_engagement.R')"`.
- **Conventions & traps:** Loanbook money is whole VND and is never rescaled.
  Vietnamese names are matched after ASCII normalization
  (`normalize_vn_name()`). `tests/testthat/test_golden_numbers.R` pins exact
  values; a green suite is the proof a refactor changed nothing. Every change
  under `scripts/` or `R/` must leave `synthesis_output/vietnam/*.csv` and
  the gated HTML reports byte-identical; PNGs are ignored by the gate. Only
  `scripts/refresh_dashboard_data.R` may write under `dashboard/data/`.
  `NEWS.md` entries are prose and must not quote test counts. Test files
  `source()` R files relative to `project_root()` (a helper that walks up to
  the directory containing `dashboard/`); R files under `R/` must have no
  top-level side effects beyond `suppressPackageStartupMessages(library(...))`
  because `devtools::load_all()` also loads them. Roxygen comments use
  `#'` and `@export` for every public function.
- **Repo map:**
  - `R/` shared modules sourced by scripts and loaded as the package
    (`engagement_config.R` loader+validator, `step_registry.R` step table,
    `engagement_plan.R` planning, `step_runner.R` execution + manifest JSON,
    `sector_registry.R` sector metadata, `report_fingerprint.R` HTML
    normalization for the gate).
  - `scripts/` one R script per pipeline Step, plus `run_engagement.R`
    (orchestrator) and `pipeline_refresh.R` (MCB wrapper).
  - `engagements/<slug>/engagement_config.json` per-Engagement config; only
    `mcb-demo` has `public_snapshot_allowed: true` and
    `paths.snapshot_dir: dashboard/data`. `sdb-rehearsal` writes everything
    under `engagements/sdb-rehearsal/` (mostly gitignored).
  - `synthesis_output/vietnam/` PACTA outputs; `synthesis_output/trisk/<sector>_demo/`
    TRISK outputs (+ `figures/`); `synthesis_output/trisk/grid/<sector>/` grid;
    `output/trisk_inputs/<sector>_demo/` TRISK inputs; `output/engagement/`,
    `output/financed_emissions/`, `synthesis_output/prioritization/`.
  - `dashboard/data/` the frozen public Snapshot (`pacta/`, `trisk/<sector>/`,
    `trisk/grid/<sector>/`, `trisk/manifest.csv`, `analytics/`, `reports/`,
    `pipeline_manifest.json`).
  - `tools/verify_refactor.R` the gate (byte-identity + INV-001..013).
  - `dashboard/lib/loaders.py` the app's only path knowledge;
    `dashboard/tests/` pytest.
  - `CONTEXT.md` glossary (Engagement, Step, Artifact, Artifact catalog,
    Snapshot, Deliverable, Published report, Gate, Invariant);
    `docs/adr/0001-artifact-catalog-owns-locations.md`.

## Research Inputs

- From `research/2026-09-13_artifact-catalog-design-grill.md`:
  - Scope rule: an Artifact gets a catalog row only when something other
    than its producer names it (a Step's `requires`, the Snapshot copier, run
    history, the refresh audit, the gate's lists, `row_count_files`, the
    Python loaders). Producer-internal intermediates (`01_vn_matched_raw.csv`,
    per-run TRISK folders, `carbon_cost_exposure.csv`, `sector_priority_chart.png`,
    `interpretation_notes.md`, `coverage_metrics.json`) stay out.
  - Seam: a new module `R/artifact_catalog.R`; the step registry names
    artifacts by key and derives its path closures from the catalog, so the
    six hand-written closures are deleted rather than moved.
  - Representation: R data built from the loaded engagement config (paths
    depend on `cfg$paths$*` and `cfg$trisk_sectors`), never a static
    JSON/YAML file in the repo. `reports/report_catalog.json` is untouched.
  - Python side: the Snapshot step exports the resolved catalog as
    `<snapshot_dir>/artifact_catalog.json`; `loaders.py` reads it. Two
    adapters (R writer, Python reader) make the seam real.
  - Keys are semantic snake_case, adopting `loaders.py`'s existing names
    where they exist; the basename is a property of a row, never its identity.
  - Interface is three functions: `artifact_catalog(cfg)` (one data.frame),
    `artifact_path(cfg, key, sector, where)`, `write_artifact_catalog_json(cfg, path)`.
  - Acceptance: byte-identical CSVs and gated HTML, plus a transition test
    pinning today's literal path set that is deleted after the last consumer
    migrates.
- From `docs/adr/0001-artifact-catalog-owns-locations.md`:
  - A hand-typed Artifact path anywhere outside `R/artifact_catalog.R` is a
    defect. The catalog lists what an Engagement *can* produce; the Manifest
    records what a run *did* produce, so consumers keep their existence checks.

## Assumptions and Constraints

- **ASM-001:** `dashboard/tests` run against the committed `dashboard/data`
  Snapshot, so `dashboard/data/artifact_catalog.json` must be generated and
  committed in PHASE-03 before the Python loaders switch in PHASE-05.
- **ASM-002:** `tools/verify_refactor.R` gathers changed paths with
  `git diff --name-only` (`tools/verify_refactor.R:994-997`), which never lists
  untracked files, so a brand-new `dashboard/data/artifact_catalog.json` is an
  addition, not drift. Once committed it is compared like any other tracked
  file, so its writer must be deterministic (fixed row order, no timestamps).
- **ASM-003:** The `.facts.json` sidecars are located by convention (`.html`
  replaced with `.facts.json`, `tools/verify_refactor.R:888`) and get no
  catalog rows. — **BINDING DEFAULT:** keep the convention; do not add rows.
- **ASM-004:** `BIDV_Framework_Recommendation_Report.html` is produced by
  `scripts/generate_bidv_report.R`, which is not a registry Step. —
  **BINDING DEFAULT:** its catalog row has `producer = NA_character_`; the
  registry derivation ignores rows with `NA` producers.
- **ASM-005:** The registry's dependency *edges* must not change in this
  plan (they feed `dependency_warnings` into `pipeline_manifest.json` and are
  pinned by `tests/testthat/test_step_dependencies.R`). — **BINDING DEFAULT:**
  `sector_prioritization` keeps requiring TRISK output files (now at their
  real `<sector>_demo` paths) even though the script reads the Snapshot copy;
  the truthful Snapshot dependency is recorded in Gotchas for a follow-up.
- **ASM-006:** `tools/verify_refactor.R` must stay sourceable from both the
  repo root and `tests/testthat` (its existing relative-candidate pattern at
  lines 39-47). — **BINDING DEFAULT:** extend that same pattern to source
  `R/engagement_config.R` and `R/artifact_catalog.R`.
- **ASM-007:** The refresh audit's hardcoded `"power"` sector
  (`scripts/generate_refresh_audit.R:71`) is a display choice, not a path
  rule. — **BINDING DEFAULT:** keep `sector = "power"` and take the path from
  the catalog.
- **ASM-008:** Both engagements have `trisk_sectors = c("power","cement","steel")`.
  The catalog expands sector-scoped rows over `cfg$trisk_sectors` in the
  order given in the config, not power-first (`.order_sectors_power_first()`
  is a step-ordering concern, not a location concern).
- **CON-001:** All `synthesis_output/vietnam/*.csv`, every tracked CSV, and
  every path in `GATED_HTML_PATHS` must be byte-identical after every phase
  (`Rscript tools/verify_refactor.R` must print `BYTE-IDENTITY PASS`).
- **CON-002:** Only `scripts/refresh_dashboard_data.R` writes under
  `dashboard/data/`; the new JSON export lives in that script.
- **CON-003:** No new R package dependency; `jsonlite` and base R only.
- **CON-004:** CI's `sdb-engagement` job asserts
  `git status --porcelain synthesis_output output dashboard/data reports` is
  empty after an SDB run; the SDB catalog export goes to
  `engagements/sdb-rehearsal/snapshot/artifact_catalog.json` (gitignored via
  `engagements/*/snapshot/`), so this holds.
- **DEC-001:** Catalog keys (final; used identically in R and in the JSON):
  PACTA `matches`, `ms_company`, `ms_portfolio`, `sda_portfolio`,
  `ms_alignment`, `sda_alignment`, `pacta_figures`; TRISK inputs `assets`,
  `financial_features`, `carbon_price`, `scenarios`; TRISK outputs
  `company_summary`, `company_trajectories`, `npv_results`, `params`,
  `pd_results`, `pd_summary`, `run_catalog`, `sensitivity_results`,
  `sensitivity_summary`, `top_borrowers`, `trisk_figures`; grid
  `grid_scenarios`, `grid_borrower_results`, `grid_meta`; Snapshot-only
  `trisk_manifest`, `pipeline_manifest`; prioritization
  `sector_priority_ranking`, `sector_priority_detail`; engagement
  `engagement_priority`; analytics `financed_emissions`,
  `data_quality_summary`, `target_registry`, `sll_readiness`; intake
  `normalized_loanbook`; reports `pacta_bank_report`,
  `financed_emissions_report`, `sll_readiness_report`,
  `target_registry_report`, `bidv_framework_report`, `refresh_audit_report`,
  `refresh_audit_metrics`, `intake_validation_report`, `coverage_report`,
  `vintage_comparison_report`, `disclosure_pack`, `letters_index`.
- **DEC-002:** Python page-facing dict keys do not change. `loaders.py`
  keeps two aliases: page key `combined` → catalog key `top_borrowers`, page
  key `company_trajectories_latest` → catalog key `company_trajectories`.
- **DEC-003:** Producers keep writing where they write today. The catalog
  declares those locations, and `test_artifact_catalog.R` asserts every
  declared engagement-level and sector-level path for `mcb-demo` exists in
  the committed tree (except rows whose files are gitignored or optional,
  listed in the test).
- **DEC-004:** Flags carried by a row are only those with a consumer today:
  `history_headline` (run history), `timestamp_class` (gate),
  `gated_html` (gate byte-identity), `disclaimer_required` (INV-010),
  `data_source_check` (INV-003). No other flags.
- **DEC-005:** `artifact_catalog.json` contains only rows with a non-NA
  `snapshot_path`, plus the header fields `schema_version`, `bank_slug`,
  `sectors`. The app never learns producer-side paths.

## Specification

### S1 — Catalog row definition

`artifact_catalog(cfg)` returns one `data.frame` with these columns, in this
order: `key` (character), `group` (character: one of `intake`, `pacta`,
`trisk_input`, `trisk`, `grid`, `snapshot`, `prioritization`, `engagement`,
`analytics`, `reports`), `scope` (`"engagement"` or `"sector"`), `sector`
(character; `NA` for engagement scope), `producer` (registry step key, or
`"run_engagement"` for `pipeline_manifest`, or `NA`), `kind` (`csv`,
`parquet`, `json`, `html`, `png_group`), `path` (repo-relative, forward
slashes, built with `file.path()`), `snapshot_path` (repo-relative under
`cfg$paths$snapshot_dir`, or `NA`), `history_headline`, `timestamp_class`,
`gated_html`, `disclaimer_required`, `data_source_check` (all logical,
default `FALSE`).

Row order is fixed: engagement-scoped rows in the order of the table below,
then sector-scoped rows grouped by sector in `cfg$trisk_sectors` order and,
within a sector, in the order of the table below. This order is what
`write_artifact_catalog_json()` emits, so it must be deterministic.

Let `S` = `cfg$paths$snapshot_dir`, `P` = `cfg$paths$pacta_output_dir`,
`T` = `cfg$paths$trisk_output_root`, `I` = `cfg$paths$trisk_input_root`,
`R` = `cfg$paths$reports_dir`, `E` = `cfg$paths$engagement_output_dir`,
`F` = `cfg$paths$financed_emissions_output_dir`,
`Q` = `cfg$paths$prioritization_output_dir`, `L` = `cfg$paths$letters_output_dir`,
`D` = `cfg$paths$disclosure_output_dir`, `slug` = `cfg$bank_slug`,
`sec` = one configured sector.

Engagement-scoped rows (`scope = "engagement"`, `sector = NA`):

| key | group | producer | kind | path | snapshot_path | flags |
|---|---|---|---|---|---|---|
| normalized_loanbook | intake | intake | csv | `engagements/<slug>/intake/normalized_loanbook.csv` | NA | — |
| matches | pacta | pacta_vietnam_scenario | csv | `P/02_vn_matched_prioritized.csv` | `S/pacta/02_vn_matched_prioritized.csv` | — |
| ms_company | pacta | pacta_vietnam_scenario | csv | `P/04_vn_ms_company.csv` | `S/pacta/04_vn_ms_company.csv` | — |
| ms_portfolio | pacta | pacta_vietnam_scenario | csv | `P/04_vn_ms_portfolio.csv` | `S/pacta/04_vn_ms_portfolio.csv` | — |
| sda_portfolio | pacta | pacta_vietnam_scenario | csv | `P/05_vn_sda_portfolio.csv` | `S/pacta/05_vn_sda_portfolio.csv` | — |
| ms_alignment | pacta | pacta_vietnam_scenario | csv | `P/06_vn_ms_alignment_2030.csv` | `S/pacta/06_vn_ms_alignment_2030.csv` | history_headline |
| sda_alignment | pacta | pacta_vietnam_scenario | csv | `P/06_vn_sda_alignment_2030.csv` | `S/pacta/06_vn_sda_alignment_2030.csv` | history_headline |
| pacta_figures | pacta | pacta_vietnam_scenario | png_group | `P` | `S/pacta` | — |
| trisk_manifest | snapshot | refresh_dashboard_data | csv | `S/trisk/manifest.csv` | `S/trisk/manifest.csv` | timestamp_class |
| pipeline_manifest | snapshot | run_engagement | json | if `isTRUE(cfg$public_snapshot_allowed)` then `S/pipeline_manifest.json` else `engagements/<slug>/pipeline_manifest.json` | `S/pipeline_manifest.json` when public, else NA | timestamp_class |
| sector_priority_ranking | prioritization | sector_prioritization | csv | `Q/sector_priority_ranking.csv` | NA | history_headline |
| sector_priority_detail | prioritization | sector_prioritization | csv | `Q/sector_priority_detail.csv` | NA | — |
| engagement_priority | engagement | engagement_scoring | csv | `E/engagement_priority.csv` | NA | history_headline, data_source_check |
| financed_emissions | analytics | financed_emissions | csv | `F/financed_emissions.csv` | `S/analytics/financed_emissions.csv` | data_source_check |
| data_quality_summary | analytics | financed_emissions | csv | `F/data_quality_summary.csv` | `S/analytics/data_quality_summary.csv` | — |
| target_registry | analytics | generate_targets | csv | `E/target_registry.csv` | `S/analytics/target_registry.csv` | data_source_check |
| sll_readiness | analytics | sll_readiness | csv | `E/sll_readiness.csv` | `S/analytics/sll_readiness.csv` | data_source_check |
| pacta_bank_report | reports | pacta_vietnam_scenario | html | `R/PACTA_Vietnam_Bank_Report.html` | NA | gated_html, disclaimer_required |
| financed_emissions_report | reports | financed_emissions | html | `R/Financed_Emissions.html` | NA | gated_html, disclaimer_required |
| sll_readiness_report | reports | sll_readiness | html | `R/SLL_Readiness_Shortlist.html` | NA | gated_html, disclaimer_required |
| target_registry_report | reports | generate_targets | html | `R/Sector_Target_Registry.html` | NA | gated_html, disclaimer_required |
| bidv_framework_report | reports | NA | html | `R/BIDV_Framework_Recommendation_Report.html` | NA | gated_html, disclaimer_required |
| refresh_audit_report | reports | refresh_audit | html | `R/pipeline_refresh_audit.html` | NA | gated_html, disclaimer_required |
| refresh_audit_metrics | reports | refresh_audit | json | `R/refresh_audit_metrics.json` | NA | timestamp_class |
| intake_validation_report | reports | validation_report | html | `R/Intake_Validation_Report.html` | NA | — |
| coverage_report | reports | coverage_report | html | `R/Coverage_Reconciliation_Report.html` | NA | — |
| vintage_comparison_report | reports | compare_scenario_vintages | html | `R/Scenario_Vintage_Comparison.html` | NA | — |
| disclosure_pack | reports | generate_disclosure_pack | html | `D/disclosure_pack.html` | NA | disclaimer_required |
| letters_index | reports | generate_engagement_letters | html | `L/index.html` | NA | disclaimer_required |

Sector-scoped rows (`scope = "sector"`, one copy per `sec` in `cfg$trisk_sectors`):

| key | group | producer | kind | path | snapshot_path |
|---|---|---|---|---|---|
| assets | trisk_input | trisk_prepare_inputs | csv | `I/<sec>_demo/assets.csv` | `S/trisk/<sec>/assets.csv` |
| financial_features | trisk_input | trisk_prepare_inputs | csv | `I/<sec>_demo/financial_features.csv` | `S/trisk/<sec>/financial_features.csv` |
| carbon_price | trisk_input | trisk_prepare_inputs | csv | `I/<sec>_demo/ngfs_carbon_price.csv` | `S/trisk/<sec>/ngfs_carbon_price.csv` |
| scenarios | trisk_input | trisk_prepare_inputs | csv | `I/<sec>_demo/scenarios.csv` | `S/trisk/<sec>/scenarios.csv` |
| company_summary | trisk | trisk_sector_demo | csv | `T/<sec>_demo/company_summary.csv` | `S/trisk/<sec>/company_summary.csv` |
| company_trajectories | trisk | trisk_sector_demo | csv | `T/<sec>_demo/company_trajectories_latest.csv` | `S/trisk/<sec>/company_trajectories_latest.csv` |
| npv_results | trisk | trisk_sector_demo | csv | `T/<sec>_demo/npv_results_latest.csv` | `S/trisk/<sec>/npv_results_latest.csv` |
| params | trisk | trisk_sector_demo | csv | `T/<sec>_demo/params_latest.csv` | `S/trisk/<sec>/params_latest.csv` |
| pd_results | trisk | trisk_sector_demo | csv | `T/<sec>_demo/pd_results_latest.csv` | `S/trisk/<sec>/pd_results_latest.csv` |
| pd_summary | trisk | trisk_sector_demo | csv | `T/<sec>_demo/pd_summary.csv` | `S/trisk/<sec>/pd_summary.csv` |
| run_catalog | trisk | trisk_sector_demo | csv | `T/<sec>_demo/run_catalog.csv` | `S/trisk/<sec>/run_catalog.csv` |
| sensitivity_results | trisk | trisk_sector_demo | csv | `T/<sec>_demo/sensitivity_results.csv` | `S/trisk/<sec>/sensitivity_results.csv` |
| sensitivity_summary | trisk | trisk_sector_demo | csv | `T/<sec>_demo/sensitivity_summary.csv` | `S/trisk/<sec>/sensitivity_summary.csv` |
| top_borrowers | trisk | trisk_sector_demo | csv | `T/<sec>_demo/top_borrowers_alignment_trisk.csv` | `S/trisk/<sec>/top_borrowers_alignment_trisk.csv` |
| trisk_figures | trisk | trisk_sector_demo | png_group | `T/<sec>_demo/figures` | `S/trisk/<sec>` |
| grid_scenarios | grid | trisk_scenario_grid | csv | `T/grid/<sec>/scenarios.csv` | `S/trisk/grid/<sec>/scenarios.csv` |
| grid_borrower_results | grid | trisk_scenario_grid | parquet | `T/grid/<sec>/borrower_results.parquet` | `S/trisk/grid/<sec>/borrower_results.parquet` |
| grid_meta | grid | trisk_scenario_grid | json | `T/grid/<sec>/grid_meta.json` | `S/trisk/grid/<sec>/grid_meta.json` |

No sector-scoped row carries a flag.

### S2 — Registry dependency derivation

1. Each `step_registry()` entry may declare `requires = character()` of
   catalog **keys** (never paths). Entries no longer declare `produces`.
2. After the entry list is built, `step_registry()` wraps every entry:
   `produces_fn = function(cfg) { cat <- artifact_catalog(cfg); cat$path[!is.na(cat$producer) & cat$producer == <entry key>] }`
   and, when `requires` is non-empty,
   `requires_fn = function(cfg) { cat <- artifact_catalog(cfg); cat$path[cat$key %in% <entry$requires>] }`.
   A step whose derived `produces_fn` returns `character(0)` gets no
   `produces_fn` field (so `validate_step_dependencies()` and
   `test_step_dependencies.R`'s "neither field" case behave as today).
3. Sector-scoped rows expand to one path per configured sector, so
   `requires = "top_borrowers"` resolves to three paths for three sectors.
4. The declared `requires` per step (edges unchanged from today, paths now
   real): `validation_report`, `coverage_report` → `normalized_loanbook`;
   `trisk_prepare_inputs` → `matches`; `trisk_sector_demo` → `assets`,
   `financial_features`, `carbon_price`, `scenarios`; `sector_prioritization`
   → `ms_alignment`, `top_borrowers`; `engagement_scoring` →
   `sector_priority_ranking`; `financed_emissions`, `sll_readiness`,
   `generate_targets`, `generate_engagement_letters`,
   `generate_disclosure_pack` → `engagement_priority`. All other steps
   declare none.

### S3 — `artifact_catalog.json` shape (written by `write_artifact_catalog_json()`)

```json
{
  "schema_version": 1,
  "bank_slug": "mcb-demo",
  "sectors": ["power", "cement", "steel"],
  "artifacts": [
    {"key": "matches", "group": "pacta", "scope": "engagement", "sector": null,
     "producer": "pacta_vietnam_scenario", "kind": "csv",
     "snapshot_path": "pacta/02_vn_matched_prioritized.csv"},
    {"key": "assets", "group": "trisk_input", "scope": "sector", "sector": "power",
     "producer": "trisk_prepare_inputs", "kind": "csv",
     "snapshot_path": "trisk/power/assets.csv"}
  ]
}
```

Rules: only rows with a non-NA `snapshot_path`; `snapshot_path` is relative
to `cfg$paths$snapshot_dir` with forward slashes (strip the `S/` prefix);
`sector` is JSON `null` for engagement scope; rows in catalog order;
`jsonlite::toJSON(x, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")`
followed by `writeLines()`; no timestamp anywhere in the file.

## Phase Summary

| Phase | Goal | Dependencies | Primary outputs |
|---|---|---|---|
| PHASE-01 | Create the catalog module and prove it against the tree and today's literal lists | None | `R/artifact_catalog.R`, `tests/testthat/test_artifact_catalog.R`, `NAMESPACE`/`man/` regenerated |
| PHASE-02 | Registry, planner and PACTA driver derive paths from the catalog | PHASE-01 | `R/step_registry.R`, `R/engagement_plan.R`, `scripts/run_engagement.R`, `scripts/pacta_vietnam_scenario.R` |
| PHASE-03 | Snapshot copier, run history and refresh audit use the catalog; Snapshot gains `artifact_catalog.json` | PHASE-01 | `scripts/refresh_dashboard_data.R`, `scripts/record_run_history.R`, `scripts/generate_refresh_audit.R`, `dashboard/data/artifact_catalog.json`, rewritten `test_snapshot_contract.R` |
| PHASE-04 | The gate derives its path lists from the catalog | PHASE-01 | `tools/verify_refactor.R` |
| PHASE-05 | The dashboard reads the export; docs, changelog, transition test removed | PHASE-03 | `dashboard/lib/loaders.py`, `dashboard/tests/test_loaders.py`, `dashboard/data/README.md`, `NEWS.md` |

## Detailed Phases

### PHASE-01 - Catalog Module

**Goal**
Add `R/artifact_catalog.R` implementing S1 and S3, with tests that (a) pin
the row shape, (b) prove every declared `mcb-demo` path exists in the
committed tree, and (c) pin the union of every hand-typed path list in the
repo today (the transition test) so later phases can prove they moved
knowledge without changing it.

**Tasks**
- [x] TASK-01-01: Create `R/artifact_catalog.R` with the header comment
  explaining the module's role (one owner for Artifact locations; consumers
  never spell a path), a private `.artifact_rows_engagement(cfg)` returning
  the engagement-scoped rows of S1 and a private `.artifact_rows_sector(cfg, sector)`
  returning the sector-scoped rows for one sector, and the three exported
  functions below. Use only base R and `jsonlite`. No top-level side effects.
- [x] TASK-01-02: Implement `artifact_catalog(cfg)`: bind engagement rows,
  then for each `sector in cfg$trisk_sectors` the sector rows; enforce
  column order of S1; stop with `"artifact_catalog: duplicate key(s): ..."`
  if any `(key, sector)` pair repeats; stop with
  `"artifact_catalog: cfg$paths$<name> is missing"` naming the first missing
  path key among `pacta_output_dir`, `trisk_output_root`, `trisk_input_root`,
  `snapshot_dir`, `reports_dir`, `engagement_output_dir`,
  `financed_emissions_output_dir`, `prioritization_output_dir`,
  `letters_output_dir`, `disclosure_output_dir`.
- [x] TASK-01-03: Implement `artifact_path(cfg, key, sector = NULL, where = c("output", "snapshot"))`.
  `where = "output"` returns `path`; `where = "snapshot"` returns
  `snapshot_path` and stops with `"artifact_path: '<key>' has no snapshot location"`
  when it is NA. For a sector-scoped key with `sector = NULL`, return the
  paths for every configured sector in `cfg$trisk_sectors` order (a
  character vector); with `sector` given, return exactly one path. For an
  engagement-scoped key with a non-NULL `sector`, stop with
  `"artifact_path: '<key>' is not sector-scoped"`. Unknown key: stop with
  `"artifact_path: unknown artifact key '<key>' (known: ...)"`.
- [x] TASK-01-04: Implement `write_artifact_catalog_json(cfg, path)` per S3,
  creating the parent directory, returning `invisible(path)`.
- [x] TASK-01-05: Create `tests/testthat/test_artifact_catalog.R` with the
  Test Specs below. The transition test lists, verbatim, every path literal
  from: `R/step_registry.R:41-46`, `scripts/refresh_dashboard_data.R`
  (PACTA six, TRISK fourteen with the `input_root` split for `assets.csv`,
  `financial_features.csv`, `ngfs_carbon_price.csv`, `scenarios.csv`, grid
  three, analytics four), `scripts/record_run_history.R:22-27`,
  `scripts/generate_refresh_audit.R:69,78,87`, `tools/verify_refactor.R`
  (`GATED_HTML_PATHS`, the two extra `DISCLAIMER_HTML_PATHS`,
  `TIMESTAMP_BASENAMES`, the four INV-003 basenames), and
  `tests/testthat/test_snapshot_contract.R:4-13`, resolved for `mcb-demo`.
  Mark the test with a comment `# TRANSITION TEST -- delete in PHASE-05 once
  every consumer reads the catalog.`
- [x] TASK-01-06: Run `Rscript -e "roxygen2::roxygenise()"`; confirm
  `NAMESPACE` gains `export(artifact_catalog)`, `export(artifact_path)`,
  `export(write_artifact_catalog_json)` and `man/` gains three `.Rd` files.
- [x] TASK-01-07: Run the full R suite and the invariants gate; both green.

**File Changes**
- `R/artifact_catalog.R` (create): the module described in TASK-01-01..04.
  Build every path with `file.path()` on the config's own strings (which are
  forward-slash, repo-relative); never call `normalizePath()` or `getwd()`.
- `tests/testthat/test_artifact_catalog.R` (create): tests per Test Specs;
  `source()` `R/engagement_config.R` and `R/artifact_catalog.R` via
  `project_root()` like `tests/testthat/test_step_registry.R:3-5` does.
- `NAMESPACE` (modify, generated): three new `export()` lines.
- `man/artifact_catalog.Rd`, `man/artifact_path.Rd`, `man/write_artifact_catalog_json.Rd`
  (create, generated).

**Function Signatures**
- `artifact_catalog(cfg: list) -> data.frame` — one row per resolved
  Artifact with the S1 columns, engagement rows first then sector rows in
  `cfg$trisk_sectors` order.
- `artifact_path(cfg: list, key: character(1), sector: character(1) | NULL = NULL, where: character(1) = "output") -> character` — the repo-relative `path` (or `snapshot_path`) for one key; a vector of one path per configured sector when the key is sector-scoped and `sector` is NULL.
- `write_artifact_catalog_json(cfg: list, path: character(1)) -> invisible(character(1))` — writes the S3 JSON to `path` and returns `path`.
- `.artifact_rows_engagement(cfg: list) -> data.frame` — private; the engagement-scoped rows of S1.
- `.artifact_rows_sector(cfg: list, sector: character(1)) -> data.frame` — private; the sector-scoped rows of S1 for one sector.

**Test Specs**
- `artifact_catalog(load_engagement_config("engagements/mcb-demo/engagement_config.json"))` → 29 engagement rows + 3 × 18 = 54 sector rows = 83 rows; `names()` equals exactly the 13 S1 columns in order; no duplicated `paste(key, sector)`.
- Same call, row `key == "matches"` → `path == "synthesis_output/vietnam/02_vn_matched_prioritized.csv"`, `snapshot_path == "dashboard/data/pacta/02_vn_matched_prioritized.csv"`, `producer == "pacta_vietnam_scenario"`, `scope == "engagement"`, `is.na(sector)`.
- Row `key == "top_borrowers" & sector == "cement"` → `path == "synthesis_output/trisk/cement_demo/top_borrowers_alignment_trisk.csv"`, `snapshot_path == "dashboard/data/trisk/cement/top_borrowers_alignment_trisk.csv"`.
- Row `key == "assets" & sector == "power"` → `path == "output/trisk_inputs/power_demo/assets.csv"`, `producer == "trisk_prepare_inputs"`.
- Row `key == "pipeline_manifest"` for `mcb-demo` → `path == "dashboard/data/pipeline_manifest.json"`, `snapshot_path == "dashboard/data/pipeline_manifest.json"`; for `sdb-rehearsal` → `path == "engagements/sdb-rehearsal/pipeline_manifest.json"`, `is.na(snapshot_path)`.
- `sum(cat$history_headline)` → 4 with keys `ms_alignment`, `sda_alignment`, `sector_priority_ranking`, `engagement_priority`; `sum(cat$gated_html)` → 6; `sum(cat$disclaimer_required)` → 8; `sum(cat$timestamp_class)` → 3 with basenames `manifest.csv`, `pipeline_manifest.json`, `refresh_audit_metrics.json`; `sum(cat$data_source_check)` → 4.
- `artifact_path(cfg, "engagement_priority")` → `"output/engagement/engagement_priority.csv"`; `artifact_path(cfg, "top_borrowers")` → length-3 vector for power, cement, steel in that order; `artifact_path(cfg, "top_borrowers", sector = "steel", where = "snapshot")` → `"dashboard/data/trisk/steel/top_borrowers_alignment_trisk.csv"`; `artifact_path(cfg, "engagement_priority", where = "snapshot")` → error matching `"no snapshot location"`; `artifact_path(cfg, "nope")` → error matching `"unknown artifact key 'nope'"`; `artifact_path(cfg, "matches", sector = "power")` → error matching `"not sector-scoped"`.
- Every `mcb-demo` row's `path` exists on disk under `project_root()` (use `file.exists()` for files and `dir.exists()` for `png_group`), excluding keys `normalized_loanbook`, `intake_validation_report`, `coverage_report`, `vintage_comparison_report`, `disclosure_pack`, `letters_index` (not produced or gitignored for MCB). This is the "declaration matches the tree" check that today's registry closures fail.
- `write_artifact_catalog_json(cfg, tmp)` → file parses with `jsonlite::fromJSON(tmp, simplifyVector = FALSE)`; `schema_version == 1`; `bank_slug == "mcb-demo"`; `length(artifacts) == sum(!is.na(cat$snapshot_path))`, which for `mcb-demo` is 67 (13 engagement rows: six PACTA CSVs, `pacta_figures`, `trisk_manifest`, `pipeline_manifest`, four analytics; plus 54 sector rows); first artifact `snapshot_path == "pacta/02_vn_matched_prioritized.csv"` (no `dashboard/data/` prefix); writing twice yields identical bytes.
- Transition test: `sort(unique(c(cat$path[...], cat$snapshot_path[...])))` restricted to the keys that today's lists mention equals `sort(unique(<the literal union>))`; the literal union must include `synthesis_output/trisk/power_demo/...` paths (real) and must NOT include `synthesis_output/trisk/power` (the fictional one from the old registry) — record that difference in a comment.
- A config with `trisk_sectors = c("steel")` only → sector rows for steel only, 29 + 18 = 47 rows.
- A config missing `paths$letters_output_dir` (set to NULL) → error matching `"cfg\\$paths\\$letters_output_dir is missing"`.

**Dependencies**
- None (new module; nothing consumes it yet).

**Exit Criteria**
- [x] `Rscript -e "testthat::test_file('tests/testthat/test_artifact_catalog.R')"` reports `FAIL 0`.
- [x] `Rscript -e "testthat::test_dir('tests/testthat')"` reports `FAIL 0`.
- [x] `Rscript -e "roxygen2::roxygenise()"` leaves `git diff --stat NAMESPACE` showing exactly three added lines.
- [x] `Rscript -e "devtools::load_all('.')"` succeeds.
- [x] `git status --porcelain synthesis_output dashboard/data reports` is empty (no artifact touched).

**Phase Risks**
- **RISK-01-01:** The "declaration matches the tree" test fails on a
  developer machine that has not run the pipeline. Mitigation: the test
  checks only paths that are tracked by git for `mcb-demo` (every path in S1
  except the excluded keys is tracked; confirm with `git ls-files <path>` when
  writing the test) and skips with `testthat::skip()` when
  `Sys.getenv("CI") == ""` and the file is absent, naming the file.

### PHASE-02 - Registry, Planner and PACTA Driver Read the Catalog

**Goal**
Delete the six path closures in `R/step_registry.R`, derive every
`produces_fn` from the catalog, declare `requires` by key (S2), move the
manifest path rule in `R/engagement_plan.R` onto the catalog, validate
`row_count_files` against the catalog, and make the PACTA driver's facts
sidecar ask the catalog. Step order, arguments, dependency edges and every
output stay byte-identical.

**Tasks**
- [x] TASK-02-01: In `R/step_registry.R`, delete lines 41-46 (the six
  closures). Add `requires = c(...)` (keys per S2 item 4) to the entries that
  declare `requires_fn` today and delete every `produces_fn`/`requires_fn`
  field from the literal entries. Replace the three
  `file.path(cfg$paths$reports_dir, "<name>.html")` literals in the
  `validation_report`, `coverage_report` and `compare_scenario_vintages`
  `args_fn` with `artifact_path(cfg, "intake_validation_report")`,
  `artifact_path(cfg, "coverage_report")` and
  `artifact_path(cfg, "vintage_comparison_report")`.
- [x] TASK-02-02: In `step_registry()`, after the `list(...)` is built,
  apply S2 items 2-3: a private `.attach_dependency_fns(registry)` that adds
  `produces_fn` (when the catalog has rows for that producer) and
  `requires_fn` (when `requires` is non-empty) closures to each entry and
  returns the registry. Update the file header (lines 22-29) to say
  dependencies are declared by artifact key and resolved through
  `R/artifact_catalog.R`.
- [x] TASK-02-03: In `R/engagement_plan.R:191-195`, replace the manifest
  path branch with `manifest_path <- artifact_path(cfg, "pipeline_manifest")`.
  Keep the explanatory comment, pointing at the catalog row.
- [x] TASK-02-04: In `plan_engagement_run()`, after `steps` are resolved and
  before the dependency validation, add: if `length(cfg$row_count_files) > 0`,
  compute `known <- na.omit(artifact_catalog(cfg)$snapshot_path)` and stop
  with `"plan_engagement_run: row_count_files entry '<x>' is not a catalogued Snapshot artifact"`
  for the first entry not in `known`.
- [x] TASK-02-05: In `scripts/run_engagement.R`, add
  `source("R/artifact_catalog.R")` immediately after
  `source("R/engagement_config.R")` (line 56). Do the same in every script
  that sources `R/step_registry.R` or `R/engagement_plan.R` (check with
  `grep -rn "step_registry.R\|engagement_plan.R" scripts tools tests`).
- [x] TASK-02-06: In `scripts/pacta_vietnam_scenario.R:83-96`, add
  `source("R/artifact_catalog.R")` next to the existing `source()` calls and
  replace both `file.path(cfg$paths$pacta_output_dir, "02_vn_matched_prioritized.csv")`
  occurrences with `artifact_path(cfg, "matches")` and
  `file.path(cfg$paths$reports_dir, "PACTA_Vietnam_Bank_Report.html")` with
  `artifact_path(cfg, "pacta_bank_report")`.
- [x] TASK-02-07: In `tests/testthat/test_step_dependencies.R`,
  `test_step_registry.R` and `test_engagement_plan.R`, add
  `source(file.path(root, "R", "artifact_catalog.R"))` after the
  `engagement_config.R` source line. Add one new test to
  `test_step_dependencies.R`: every path returned by any `produces_fn` for
  the MCB step list is a row `path` in `artifact_catalog(cfg)`, and
  `produces_fn` for `trisk_sector_demo` contains
  `"synthesis_output/trisk/power_demo/top_borrowers_alignment_trisk.csv"`.
  Add one test to `test_engagement_plan.R`: a config with
  `row_count_files = "dashboard/data/nope.csv"` is refused by
  `plan_engagement_run()` with the message above; the real `mcb-demo`
  config plans clean.
- [x] TASK-02-08: Run `Rscript scripts/run_engagement.R --config engagements/mcb-demo/engagement_config.json --dry-run`
  and diff its output against the same command run at `bd09f48` (use
  `git stash` around the second run, or a second checkout): identical.
- [x] TASK-02-09: Run the full R suite, then `Rscript tools/verify_refactor.R`
  (full refresh) and `--invariants`.

**File Changes**
- `R/step_registry.R` (modify): delete closures; entries declare `requires`
  keys; `.attach_dependency_fns()` derives closures; three report literals
  become `artifact_path()` calls; header updated. Leave `resolve_step_list()`,
  `.resolve_step_list_from_flags()`, `filter_step_list()` untouched.
- `R/engagement_plan.R` (modify): manifest path via the catalog;
  `row_count_files` validation. Leave `enforce_manifest_policy()`,
  `materialize_resolved_config()`, `parse_engagement_cli()` untouched.
- `scripts/run_engagement.R` (modify): one added `source()` line.
- `scripts/pacta_vietnam_scenario.R` (modify): one `source()` line; three
  literals replaced.
- `tests/testthat/test_step_dependencies.R`, `tests/testthat/test_step_registry.R`,
  `tests/testthat/test_engagement_plan.R` (modify): source line; new tests.
- `man/step_registry.Rd` (modify, generated) if the roxygen block changes.

**Function Signatures**
- `.attach_dependency_fns(registry: list) -> list` — private in `R/step_registry.R`; returns the same registry with `produces_fn`/`requires_fn` closures added per S2.
- `step_registry() -> list` — unchanged signature; entries additionally carry `requires: character` (keys) and derived closures.
- `plan_engagement_run(cfg: list, cli: list) -> list` — unchanged signature; additionally refuses uncatalogued `row_count_files`.

**Test Specs**
- `step_registry()[["trisk_sector_demo"]]$produces_fn(mcb_cfg)` → 33 paths (11 keys × 3 sectors) including `"synthesis_output/trisk/power_demo/figures"`; `[["trisk_prepare_inputs"]]$produces_fn(mcb_cfg)` → 12 paths under `output/trisk_inputs/<sec>_demo/`; `[["sector_prioritization"]]$requires_fn(mcb_cfg)` → `c("synthesis_output/vietnam/06_vn_ms_alignment_2030.csv", <3 top_borrowers paths>)`; `[["generate_vietnam_data"]]` has neither field; `[["refresh_dashboard_data"]]$produces_fn(mcb_cfg)` → `"dashboard/data/trisk/manifest.csv"`.
- Existing `test_step_dependencies.R` cases pass unchanged: mis-ordered `c("financed_emissions","engagement_scoring")` still errors naming `engagement_priority.csv`; the six-step chain validates clean; filtered `financed_emissions` warns once mentioning `engagement_priority.csv` and `previous run`; "every requires edge in the full MCB list is wired" passes.
- `plan_engagement_run(mcb_cfg, cli)$manifest_path` → `"dashboard/data/pipeline_manifest.json"` (existing assertion at `test_engagement_plan.R:307`); the synthetic `some/snapshot` and `test-bank` cases at lines 251/254 still hold.
- `--dry-run` output for `mcb-demo` and for `sdb-rehearsal` is character-identical to the pre-change output (16 and 15 lines respectively, per `test_step_registry.R`'s pinned orders).

**Dependencies**
- PHASE-01.

**Exit Criteria**
- [x] `grep -c "file.path(cfg\$paths\$pacta_output_dir" R/step_registry.R scripts/pacta_vietnam_scenario.R` prints `0` for both files.
- [x] `Rscript -e "testthat::test_dir('tests/testthat')"` reports `FAIL 0`.
- [x] `Rscript tools/verify_refactor.R` prints `BYTE-IDENTITY PASS`.
- [x] `Rscript tools/verify_refactor.R --invariants` prints `INVARIANTS PASS`.
- [x] `git diff --name-only -- '*.csv'` is empty after the refresh.

**Phase Risks**
- **RISK-02-01:** `validate_step_dependencies()`'s warning text for filtered
  runs now names real `_demo` paths where it used to name fictional ones;
  only `pipeline_manifest.json` (timestamp-class, ignored by the gate) and no
  test pins those strings. Mitigation: the Test Specs above assert the only
  pinned substring (`engagement_priority.csv`) still appears.
- **RISK-02-02:** A script that sources `R/step_registry.R` without
  `R/artifact_catalog.R` fails at plan time with "could not find function
  artifact_catalog". Mitigation: TASK-02-05's grep, plus the SDB end-to-end
  run in PHASE-05's verification.

### PHASE-03 - Snapshot Copier, Run History and Refresh Audit

**Goal**
`scripts/refresh_dashboard_data.R` copies exactly the rows the catalog says
have a Snapshot location and writes `artifact_catalog.json` into the
Snapshot; `scripts/record_run_history.R` and `scripts/generate_refresh_audit.R`
ask the catalog; `tests/testthat/test_snapshot_contract.R` becomes a
catalog-versus-Snapshot check; `dashboard/data/artifact_catalog.json` is
generated and committed.

**Tasks**
- [x] TASK-03-01: In `scripts/refresh_dashboard_data.R`, add
  `source("R/artifact_catalog.R")` after line 13, then
  `cat <- artifact_catalog(cfg)` after `cfg` is loaded. Delete `pacta_files`
  (lines 65-72), `trisk_sector_files` (105-120), the `input_root` branch
  (152-161) and `grid_file_names` (172); keep `report_catalog` handling
  (73-101), `trisk_manifest` construction, `clear_dir(trisk_dest)`, the
  `misses_required` mechanism and the final exit status exactly as they are.
- [x] TASK-03-02: Rewrite the copy loops to iterate the catalog:
  for every row with `!is.na(snapshot_path)`: `kind == "png_group"` →
  `copy_png_group(row$path, row$snapshot_path)`; `key %in% c("trisk_manifest", "pipeline_manifest")`
  → skip (produced in place, not copied); `group == "grid"` →
  `copy_file(row$path, dirname(row$snapshot_path), required = isTRUE(cfg$run_grid))`;
  `group == "analytics"` → copy only if `file.exists(row$path)`, else the
  existing `[SKIP]` message; every other row →
  `copy_file(row$path, dirname(row$snapshot_path))`. Keep the ordering
  PACTA → PNGs → reports → TRISK per sector (files, then figures, then grid)
  → `manifest.csv` → analytics so the console log reads as before.
  `trisk_manifest$grid_available[[i]]` must still be computed from the three
  grid rows' `snapshot_path` for that sector.
- [x] TASK-03-03: After the analytics loop and before the `misses_required`
  check, add `write_artifact_catalog_json(cfg, file.path(snapshot_dir, "artifact_catalog.json"))`
  with a `message()` line `[OK] <path> written`.
- [x] TASK-03-04: In `scripts/record_run_history.R:22-27`, replace the
  `artifacts` vector with `artifacts <- artifact_catalog(cfg)`, filtered to
  `history_headline`, taking `$path` (add the `source()` line). Keep the
  comment about extending the list, redirected to "set `history_headline`
  on the catalog row".
- [x] TASK-03-05: In `scripts/generate_refresh_audit.R`, add the `source()`
  line and replace line 69 with `artifact_path(cfg, "matches", where = "snapshot")`,
  line 78 with `artifact_path(cfg, "top_borrowers", sector = "power", where = "snapshot")`,
  line 87 with `artifact_path(cfg, "engagement_priority")`.
- [x] TASK-03-06: Rewrite the first test in `tests/testthat/test_snapshot_contract.R`
  (lines 3-38) as: for `mcb-demo`, every catalog row with a non-NA
  `snapshot_path` exists under `project_root()` (`dir.exists` for
  `png_group`, `file.exists` otherwise); `dashboard/data/trisk/manifest.csv`
  has one row per configured sector with `grid_available` all `TRUE`; and
  every `*.csv`, `*.parquet`, `*.json` file under `dashboard/data/pacta`,
  `dashboard/data/trisk` and `dashboard/data/analytics` (recursive,
  excluding `runs/`) is some row's `snapshot_path` or is
  `dashboard/data/trisk/manifest.csv` — an uncatalogued file fails with its
  name. Leave the second test (scenario vintages) untouched.
- [x] TASK-03-07: Run `Rscript scripts/pipeline_refresh.R` from the repo root
  (native locale, not `LANG=C.UTF-8`; see Gotchas). Confirm
  `dashboard/data/artifact_catalog.json` now exists and
  `git status --porcelain` shows it as the only untracked file plus the usual
  timestamp-class changes.
- [x] TASK-03-08: Run `Rscript tools/verify_refactor.R --skip-refresh`
  (expect `BYTE-IDENTITY PASS`) and `--invariants`. Commit
  `dashboard/data/artifact_catalog.json` together with this phase's code.

**File Changes**
- `scripts/refresh_dashboard_data.R` (modify): as TASK-03-01..03. Do not
  change `copy_file()`, `copy_png_group()`, `clear_dir()`, the
  `report_catalog` cross-check, or the exit-status logic.
- `scripts/record_run_history.R` (modify): headline list from the catalog.
- `scripts/generate_refresh_audit.R` (modify): three paths from the catalog.
- `tests/testthat/test_snapshot_contract.R` (modify): first test rewritten.
- `dashboard/data/artifact_catalog.json` (create, generated by the copier;
  committed).

**Function Signatures**
- None — no code interfaces change in this phase (script-level changes only).

**Test Specs**
- After `Rscript scripts/refresh_dashboard_data.R --config engagements/mcb-demo/engagement_config.json`: `git diff --name-only -- dashboard/data` lists only `dashboard/data/trisk/manifest.csv` (timestamp-class) and PNGs, and `dashboard/data/artifact_catalog.json` exists with `bank_slug == "mcb-demo"` and 67 artifacts (equal to `sum(!is.na(artifact_catalog(cfg)$snapshot_path))`).
- Rewritten `test_snapshot_contract.R` passes against the committed tree; temporarily creating `dashboard/data/pacta/stray.csv` makes it fail naming `stray.csv` (do this by hand once, then delete the file).
- `record_run_history()` receives the same four paths as before: `output/engagement/engagement_priority.csv`, `synthesis_output/prioritization/sector_priority_ranking.csv`, `synthesis_output/vietnam/06_vn_ms_alignment_2030.csv`, `synthesis_output/vietnam/06_vn_sda_alignment_2030.csv` (assert by `Rscript -e` printing the filtered catalog paths for `mcb-demo`, in that order).
- `reports/refresh_audit_metrics.json` after a refresh differs from HEAD only in `generated_at`/`git_sha` (it is timestamp-class; confirm with `git diff reports/refresh_audit_metrics.json`).

**Dependencies**
- PHASE-01 (and PHASE-02 for the full refresh to run; if executed before PHASE-02, run only `refresh_dashboard_data.R` directly).

**Exit Criteria**
- [x] `grep -c "\.csv\"" scripts/refresh_dashboard_data.R` prints `0` (no CSV basename literal remains; `report_catalog.json` and `manifest.csv` are the only literals, and `manifest.csv` is written via the `trisk_manifest` catalog row's path).
- [x] `test -f dashboard/data/artifact_catalog.json` succeeds and the file is tracked (`git ls-files dashboard/data/artifact_catalog.json` prints it).
- [x] `Rscript -e "testthat::test_dir('tests/testthat')"` reports `FAIL 0`.
- [x] `Rscript tools/verify_refactor.R --skip-refresh` prints `BYTE-IDENTITY PASS`; `--invariants` prints `INVARIANTS PASS`.

**Phase Risks**
- **RISK-03-01:** The `analytics/` copy and `sector_prioritization` read
  the previous run's Snapshot (see Gotchas). This phase preserves that
  behaviour; do not "fix" it here or `test_step_registry.R`'s pinned order
  and the manifest break.
- **RISK-03-02:** `refresh.yml` auto-commits with `git add dashboard/data`,
  so the new JSON will be committed by the weekly refresh even if a developer
  forgets; the byte-identity gate then compares it. Deterministic output
  (ASM-002) is what keeps that green.

### PHASE-04 - The Gate Derives Its Lists

**Goal**
`tools/verify_refactor.R` computes `TIMESTAMP_BASENAMES`,
`GATED_HTML_PATHS`, `DISCLAIMER_HTML_PATHS` and INV-003's candidate list
from `artifact_catalog()` for `mcb-demo`, producing the same values as the
literals it replaces.

**Tasks**
- [x] TASK-04-01: Extend the sourcing block at lines 39-47 to also source
  `R/engagement_config.R` and `R/artifact_catalog.R` (same two-candidate
  pattern, `R/...` and `../../R/...`). Immediately after, define
  `.mcb_catalog <- function() artifact_catalog(load_engagement_config(if (file.exists("engagements/mcb-demo/engagement_config.json")) "engagements/mcb-demo/engagement_config.json" else "../../engagements/mcb-demo/engagement_config.json"))`.
- [x] TASK-04-02: Replace the `TIMESTAMP_BASENAMES` literal (48-52) with
  `unique(basename(.mcb_catalog()$path[.mcb_catalog()$timestamp_class]))`
  (compute the catalog once into a local variable). Replace
  `GATED_HTML_PATHS` (77-84) with `cat$path[cat$gated_html]` and
  `DISCLAIMER_HTML_PATHS` (89-93) with `cat$path[cat$disclaimer_required]`.
  Keep every explanatory comment; add one line saying the lists are derived
  from the catalog and that a new gated report is added by setting the flag
  on its catalog row.
- [x] TASK-04-03: In `inv_engagement_data_source()` (lines 360-395), replace
  the two hand-built `candidates` blocks with: parse the config as today;
  if it lacks `paths` keys the catalog needs, keep the current fallback
  logic unchanged (fixtures write minimal configs); otherwise
  `candidates <- file.path(root, cat$path[cat$data_source_check])` where
  `cat <- artifact_catalog(cfg_merged)` and `cfg_merged` is the raw config
  merged over `.default_engagement_config()` via the loader's
  `.merge_config_lists()`. Simplest safe form: `tryCatch(artifact_catalog(...), error = function(e) NULL)` and fall back to the literal four basenames when NULL.
- [x] TASK-04-04: Run `Rscript -e "source('tools/verify_refactor.R'); print(GATED_HTML_PATHS); print(DISCLAIMER_HTML_PATHS); print(TIMESTAMP_BASENAMES)"`
  and confirm the three vectors equal the pre-change literals as sets
  (order within `DISCLAIMER_HTML_PATHS` may differ; `classify_path()` and
  INV-010 use `%in%`).
- [x] TASK-04-05: Run `tests/testthat/test_verify_invariants.R` and
  `test_report_fingerprint.R` (both `source()` the tool from
  `tests/testthat`), then the full suite and both gate modes.

**File Changes**
- `tools/verify_refactor.R` (modify): sourcing block; three list
  definitions; INV-003 candidate derivation. Leave `classify_path()`,
  `.html_is_timestamp_only()`, every other `inv_*()`, `changed_paths()`,
  `main()` and `.engagement_manifests()` untouched.

**Function Signatures**
- `.mcb_catalog() -> data.frame` — private in `tools/verify_refactor.R`; the `mcb-demo` catalog resolved from whichever of the two candidate config paths exists.
- `inv_engagement_data_source(root: character(1)) -> list(id, ok, detail)` — unchanged signature; candidates from the catalog when the config resolves, literal fallback otherwise.

**Test Specs**
- `setequal(GATED_HTML_PATHS, c("reports/PACTA_Vietnam_Bank_Report.html","reports/Financed_Emissions.html","reports/SLL_Readiness_Shortlist.html","reports/Sector_Target_Registry.html","reports/BIDV_Framework_Recommendation_Report.html","reports/pipeline_refresh_audit.html"))` → `TRUE`.
- `setequal(DISCLAIMER_HTML_PATHS, c(GATED_HTML_PATHS, "output/disclosure/disclosure_pack.html", "output/engagement_letters/index.html"))` → `TRUE`.
- `setequal(TIMESTAMP_BASENAMES, c("pipeline_manifest.json","refresh_audit_metrics.json","manifest.csv"))` → `TRUE`.
- Existing INV-003 fixture tests in `test_verify_invariants.R` (minimal configs with only `engagement_output_dir`) still pass via the fallback branch; the live-repo `inv_engagement_data_source(root)` returns `ok = TRUE`.
- `Rscript tools/verify_refactor.R --invariants` → `INVARIANTS PASS`.

**Dependencies**
- PHASE-01.

**Exit Criteria**
- [x] `grep -n "PACTA_Vietnam_Bank_Report.html" tools/verify_refactor.R` prints nothing.
- [x] `Rscript -e "testthat::test_file('tests/testthat/test_verify_invariants.R')"` reports `FAIL 0`.
- [x] `Rscript tools/verify_refactor.R --skip-refresh` prints `BYTE-IDENTITY PASS`; `--invariants` prints `INVARIANTS PASS`.

**Phase Risks**
- **RISK-04-01:** Sourcing `R/engagement_config.R` inside the tool attaches
  `jsonlite` and defines `%||%`; the tool already uses both. If the config
  file cannot be found from a test cwd, `.mcb_catalog()` errors at source
  time and breaks every test that sources the tool. Mitigation: the
  two-candidate path lookup mirrors the existing `report_fingerprint.R`
  lookup, and TASK-04-05 runs both test files from `tests/testthat`.

### PHASE-05 - The Dashboard Reads the Export; Docs; Cleanup

**Goal**
`dashboard/lib/loaders.py` builds every table path from
`artifact_catalog.json`; Python tests cover the mapping and the absent-file
error; `dashboard/data/README.md` and `NEWS.md` describe the catalog; the
transition test from PHASE-01 is deleted.

**Tasks**
- [x] TASK-05-01: In `dashboard/lib/loaders.py`, add
  `artifact_catalog_path()` returning `snapshot_root() / "artifact_catalog.json"`,
  and `load_artifact_catalog()` (cached with `st.cache_data`, keyed on the
  path string like `load_csv`) returning the parsed dict. When the file is
  missing raise `FileNotFoundError(f"{path} not found: regenerate the snapshot with Rscript scripts/refresh_dashboard_data.R --config <engagement config>")`.
- [x] TASK-05-02: Add `artifact_snapshot_path(key: str, sector: str | None = None) -> Path`
  that looks up the row by `key` (and `sector` when given) and returns
  `snapshot_root() / row["snapshot_path"]`; raise `KeyError` naming the key
  and sector when absent.
- [x] TASK-05-03: Rewrite `load_pacta_alignment_tables()` to build its dict
  from the six PACTA keys via `artifact_snapshot_path()`;
  `load_trisk_sector_tables(sector)` from the fourteen sector keys with the
  two aliases of DEC-002 (`"combined"` ← `top_borrowers`,
  `"company_trajectories_latest"` ← `company_trajectories`);
  `load_trisk_grid(sector)` from `grid_scenarios` and `grid_borrower_results`;
  `load_analytics_tables()` from the four analytics keys (keep the
  skip-when-absent behaviour). Delete `ANALYTICS_TABLES` and the
  `pacta_path`/`trisk_sector_path` helpers only if no other module imports
  them (`grep -rn "pacta_path\|trisk_sector_path\|ANALYTICS_TABLES" dashboard`);
  otherwise leave them and stop using them here. Keep
  `load_trisk_tables()`'s `manifest`/`default_sector` shape.
- [x] TASK-05-04: In `dashboard/tests/test_loaders.py`, add: (a)
  `test_artifact_catalog_lists_every_frozen_file` — for the committed
  Snapshot, every `artifacts[].snapshot_path` exists on disk (skip
  `png_group` rows as directories); (b) `test_loaders_use_catalog_paths` —
  with `PACTATRISK_SNAPSHOT_DIR` pointed at a `tmp_path` holding a minimal
  `artifact_catalog.json` (one PACTA row `matches` → `pacta/m.csv`, one
  sector row `top_borrowers`/`power` → `trisk/power/t.csv`) and those two
  CSVs (`a,b\n1,2\n`), `load_pacta_alignment_tables()` raises `KeyError`
  for the missing `ms_company` key, and `artifact_snapshot_path("top_borrowers", "power")`
  resolves to the tmp file; (c) `test_missing_catalog_raises` — an empty
  `tmp_path` makes `load_artifact_catalog()` raise `FileNotFoundError`
  mentioning `refresh_dashboard_data.R`. Keep every existing test.
- [x] TASK-05-05: Run `python -m pytest dashboard/tests` (expect all pass,
  including `test_smoke.py`'s `AppTest` page renders).
- [x] TASK-05-06: In `dashboard/data/README.md`, add a section
  `## artifact_catalog.json` (after the Provenance blockquote) stating: it is
  written by `scripts/refresh_dashboard_data.R` from `R/artifact_catalog.R`;
  the app resolves every table path from it; it carries no timestamp and
  is compared byte-for-byte by the gate; the JSON shape (copy S3's example).
- [x] TASK-05-07: In `NEWS.md` under `# pactatrisk 0.7.0 (unreleased)`, add
  one bullet `**Artifact catalog:** ...` describing: one owner for Artifact
  locations (`R/artifact_catalog.R`), the nine hand-typed sites it replaced,
  the two fictional registry paths it corrected (`synthesis_output/trisk/<sector>`
  → `<sector>_demo`), the new `artifact_catalog.json` in the Snapshot read by
  the dashboard, and that every CSV and gated report stayed byte-identical.
  Do not quote a test count.
- [x] TASK-05-08: Delete the transition test from
  `tests/testthat/test_artifact_catalog.R` (the block marked
  `# TRANSITION TEST`).
- [x] TASK-05-09: Set `status:` in this plan file's front matter to
  `"complete"` and tick every box once TASK-05-10 passes.
- [x] TASK-05-10: Final verification: full R suite, full Python suite,
  `Rscript tools/verify_refactor.R` (full refresh), `--invariants`, and the
  SDB end-to-end command pair from Environment & Conventions; confirm
  `git status --porcelain synthesis_output output dashboard/data reports`
  is empty after the SDB run.

**File Changes**
- `dashboard/lib/loaders.py` (modify): catalog reader and path resolver;
  four loader functions rebuilt on it; nothing else (`report_catalog()`,
  `load_pipeline_manifest()`, `snapshot_root()`, caching helpers untouched).
- `dashboard/tests/test_loaders.py` (modify): three new tests.
- `dashboard/data/README.md` (modify): new section.
- `NEWS.md` (modify): one bullet under 0.7.0.
- `tests/testthat/test_artifact_catalog.R` (modify): transition test removed.
- `plans/2026-09-13-artifact-catalog-plan.md` (modify): status and boxes.

**Function Signatures**
- `artifact_catalog_path() -> Path` — `snapshot_root() / "artifact_catalog.json"`.
- `load_artifact_catalog(path: str | Path | None = None) -> dict` — parsed JSON; `FileNotFoundError` when absent.
- `artifact_snapshot_path(key: str, sector: str | None = None) -> Path` — absolute path of one catalogued Snapshot file; `KeyError` when the key/sector pair is not in the catalog.
- `load_pacta_alignment_tables() -> dict[str, pd.DataFrame]`, `load_trisk_sector_tables(sector: str) -> dict[str, pd.DataFrame]`, `load_trisk_grid(sector: str) -> dict[str, pd.DataFrame]`, `load_analytics_tables() -> dict[str, pd.DataFrame]` — unchanged signatures and returned keys.

**Test Specs**
- `load_pacta_alignment_tables().keys()` against the committed Snapshot → exactly `{"matches","ms_company","ms_portfolio","sda_portfolio","ms_alignment","sda_alignment"}`.
- `load_trisk_sector_tables("cement").keys()` → the same thirteen keys as today, including `"combined"` and `"company_trajectories_latest"`; `tables["combined"]` is non-empty.
- `load_trisk_grid("power")` → keys `{"scenarios","borrower_results"}`; existing schema and `3 ** 5` scenario-count tests unchanged.
- `artifact_snapshot_path("matches")` → `snapshot_root()/"pacta"/"02_vn_matched_prioritized.csv"`; `artifact_snapshot_path("assets", "steel")` → `.../trisk/steel/assets.csv`; `artifact_snapshot_path("assets")` → `KeyError`.
- Empty snapshot dir → `load_artifact_catalog()` raises `FileNotFoundError` whose message contains `refresh_dashboard_data.R`.
- `python -m pytest dashboard/tests` → all passed.

**Dependencies**
- PHASE-03 (the committed `dashboard/data/artifact_catalog.json`).

**Exit Criteria**
- [x] `grep -c "02_vn_matched_prioritized.csv" dashboard/lib/loaders.py` prints `0`.
- [x] `python -m pytest dashboard/tests` exits 0.
- [x] `Rscript -e "testthat::test_dir('tests/testthat')"` reports `FAIL 0` with the transition test gone.
- [x] `Rscript tools/verify_refactor.R` prints `BYTE-IDENTITY PASS`; `--invariants` prints `INVARIANTS PASS`.
- [x] SDB end-to-end run exits 0 and leaves `git status --porcelain synthesis_output output dashboard/data reports` empty.

**Phase Risks**
- **RISK-05-01:** Streamlit Community Cloud serves the committed
  `dashboard/data`; if PHASE-03's JSON is not committed before this phase
  deploys, every page fails with `FileNotFoundError`. Mitigation: the
  PHASE-03 exit criterion requires the file to be tracked; land PHASE-03 and
  PHASE-05 in the same push.
- **RISK-05-02:** An operator snapshot generated before this change (via
  `PACTATRISK_SNAPSHOT_DIR`) has no `artifact_catalog.json`. Mitigation: the
  error message names the exact regeneration command.

## Gotchas

- **Two registry paths are fictional today.** `synthesis_output/trisk/<sector>`
  does not exist; TRISK writes `synthesis_output/trisk/<sector>_demo/` and
  reads inputs from `output/trisk_inputs/<sector>_demo/` (`R/trisk_core.R:639-641`).
  The catalog must use the `_demo` suffix; the transition test in PHASE-01
  documents the correction.
- **Ordering defect this plan exposes but must not fix.** `sector_prioritization`
  reads `<snapshot_dir>/trisk/<sector>/top_borrowers_alignment_trisk.csv`
  (`R/prioritization_core.R:18-21, 174`) but runs *before*
  `refresh_dashboard_data` in the resolved order (`R/step_registry.R:241-243`),
  so it consumes the previous run's Snapshot; likewise `analytics/` is copied
  before `financed_emissions`, `sll_readiness` and `generate_targets` run, so
  the Snapshot's analytics CSVs lag one run. Both are invisible while runs are
  byte-identical. Reordering changes the pinned step order and the manifest;
  do it in a separate plan. The catalog's `snapshot_path` column makes that
  follow-up a one-line `requires` change.
- **Byte-identity classifies `git diff --name-only`.** A new untracked file is
  never drift, but once `dashboard/data/artifact_catalog.json` is committed any
  nondeterminism in `write_artifact_catalog_json()` (row order, key order,
  number formatting) shows up as `DRIFT`. Emit rows in catalog order and
  never include a date.
- **Locale.** Run the pipeline refresh with the native Windows locale or a
  UTF-8 Linux locale; Git Bash's `LANG=C.UTF-8` makes R fall back to the C
  locale and mangles the em dash in scoring status strings (documented in
  `NEWS.md` 0.7.0). Use PowerShell or `env -u LANG -u LC_ALL` before `Rscript`.
- **`png_group` rows are directories.** `path` is the directory holding the
  PNGs (`synthesis_output/vietnam` for PACTA, `.../<sector>_demo/figures` for
  TRISK); `snapshot_path` is the destination directory. `copy_png_group()`
  already takes a source dir and a dest dir. The gate ignores PNGs.
- **`trisk_manifest` and `pipeline_manifest` are produced *in* the Snapshot.**
  Their `path` equals their `snapshot_path`; the copier must skip them (they
  are not copied from anywhere) but they must still be rows so
  `TIMESTAMP_BASENAMES` and the Python export can derive them.
- **`pipeline_manifest` for a private engagement** lives at
  `engagements/<slug>/pipeline_manifest.json` with `snapshot_path = NA`; do
  not export it into that engagement's Snapshot JSON.
- **`report_catalog.json` is a different catalog.** It maps a published HTML
  basename to title/summary/category and is cross-checked by the copier. Do
  not merge, rename or move it; the artifact catalog's `reports` rows are
  about *location*, not metadata.
- **The Python alias keys are page contracts.** `dashboard/pages/2_TRISK_Risk.py:75-76`
  reads `tables["combined"]` and `tables["company_trajectories_latest"]`;
  changing those dict keys is out of scope.
- **Roxygen regeneration is a CI gate.** After adding `#' @export` functions,
  run `Rscript -e "roxygen2::roxygenise()"` and commit `NAMESPACE` and the new
  `man/*.Rd`; CI diffs `NAMESPACE` and fails on any change.
- **`%||%`** is available in R ≥ 4.4 and also defined in
  `R/engagement_config.R`; `R/artifact_catalog.R` should not rely on it (use
  explicit `is.null()` checks) so the module can be sourced alone.
- **Windows paths.** `file.path()` on the config's forward-slash strings
  yields forward slashes; never introduce `\\`. `classify_path()` normalizes
  backslashes defensively but the catalog must not produce them.

## Verification Strategy

- **TEST-001:** `Rscript -e "testthat::test_file('tests/testthat/test_artifact_catalog.R')"` → `[ FAIL 0 | WARN 0 | SKIP 0 | PASS N ]` with N > 0 (PHASE-01, PHASE-05).
- **TEST-002:** `Rscript -e "testthat::test_dir('tests/testthat')"` → last line reports `FAIL 0` (every phase).
- **TEST-003:** `Rscript -e "testthat::test_file('tests/testthat/test_step_dependencies.R')"` → `FAIL 0` (PHASE-02).
- **TEST-004:** `Rscript -e "testthat::test_file('tests/testthat/test_snapshot_contract.R')"` → `FAIL 0` (PHASE-03).
- **TEST-005:** `Rscript -e "testthat::test_file('tests/testthat/test_verify_invariants.R')"` → `FAIL 0` (PHASE-04).
- **TEST-006:** `python -m pytest dashboard/tests` → exit code 0, output ends with `passed` and no `failed` (PHASE-05).
- **TEST-007:** `Rscript tools/verify_refactor.R` → prints `BYTE-IDENTITY PASS` (PHASE-02, PHASE-05); `Rscript tools/verify_refactor.R --skip-refresh` → `BYTE-IDENTITY PASS` (PHASE-03, PHASE-04).
- **TEST-008:** `Rscript tools/verify_refactor.R --invariants` → prints `INVARIANTS PASS` (every phase).
- **TEST-009:** `Rscript scripts/run_engagement.R --config engagements/mcb-demo/engagement_config.json --dry-run` → 16 step lines identical to the output of the same command at commit `bd09f48` (PHASE-02).
- **TEST-010:** `Rscript scripts/run_engagement.R --config engagements/sdb-rehearsal/engagement_config.json` → exit 0; then `RUN_SDB_ENGAGEMENT=1 Rscript -e "testthat::test_file('tests/testthat/test_sdb_engagement.R')"` → `FAIL 0`; then `git status --porcelain synthesis_output output dashboard/data reports` → empty (PHASE-05).
- **TEST-011:** `Rscript -e "roxygen2::roxygenise()"` followed by `git diff --quiet NAMESPACE` → exit 0 (NAMESPACE already up to date) (PHASE-01, PHASE-02).
- **DATA-001:** `git diff --name-only -- '*.csv'` → empty after every pipeline refresh in this plan.
- **DATA-002:** `Rscript -e "source('R/engagement_config.R'); source('R/artifact_catalog.R'); cfg <- load_engagement_config('engagements/mcb-demo/engagement_config.json'); cat(artifact_path(cfg, 'top_borrowers', sector = 'power'), '\n')"` → `synthesis_output/trisk/power_demo/top_borrowers_alignment_trisk.csv` (PHASE-01).
- **DATA-003:** `python -c "import json;c=json.load(open('dashboard/data/artifact_catalog.json'));print(c['bank_slug'], len(c['artifacts']), c['artifacts'][0]['snapshot_path'])"` → `mcb-demo 67 pacta/02_vn_matched_prioritized.csv` (PHASE-03; if the count differs, reconcile it with `sum(!is.na(artifact_catalog(cfg)$snapshot_path))` and fix whichever side is wrong).
- **MANUAL-001:** `python -m streamlit run dashboard/app.py`, open the PACTA, TRISK, Scenario Builder and Financed Emissions pages; each renders its tables (PHASE-05).
- **OBS-001:** After pushing, every GitHub Actions job in `ci.yml` (`python-tests`, `r-tests`, `sdb-engagement`, `byte-identity`) is green; the next `refresh.yml` run commits no unexpected files.

## Risks and Alternatives

- **RISK-001:** A future engagement config with a sector outside
  `c("power","cement","steel")` is refused by config validation before the
  catalog sees it; the catalog does not re-validate sectors. No action.
- **RISK-002:** Deriving `produces_fn` for every producer makes
  `validate_step_dependencies()` call `artifact_catalog(cfg)` once per
  registry key per required path (`registry_produces()` loops over all
  keys). For 20 keys × ~30 requires that is a few hundred data.frame builds
  per plan; measured cost is milliseconds, but if `--dry-run` becomes
  noticeably slower, memoize the catalog per `cfg` inside
  `.attach_dependency_fns()` with a local environment keyed on
  `cfg$bank_slug`.
- **RISK-003:** Someone adds a new Artifact to a producer script without a
  catalog row. The rewritten `test_snapshot_contract.R` catches it only if
  the file reaches the Snapshot; a producer-side-only file is not caught.
  Accepted: the scope rule says such a file needs no row until something
  consumes it.
- **ALT-001:** A static `artifact_catalog.json` (or YAML) checked into the
  repo as the source of truth, read by both R and Python. Rejected: every
  path depends on the engagement config, so the file would need a template
  language; YAML is a rejected dependency (ADR-0001).
- **ALT-002:** Keep Python's hand-typed lists and add a test asserting they
  equal the R export. Rejected: it tests that two copies were updated
  together instead of removing the second copy (ADR-0001).
- **ALT-003:** Put the path knowledge into `R/step_registry.R` itself.
  Rejected: the registry owns ordering and arguments; the gate, the copier and
  the dashboard need locations without needing the registry, and the manifest
  path is not a step's product.

## Suggested Next Step

Execute PHASE-01. Its exit criteria (new tests green, full suite green,
`NAMESPACE` regenerated, no artifact touched) are verifiable before PHASE-02
begins; PHASE-02, PHASE-03 and PHASE-04 each depend only on PHASE-01 and can
be reviewed as separate commits, but land PHASE-03 and PHASE-05 in the same
push so the deployed dashboard never sees a Snapshot without
`artifact_catalog.json`.

## Execution Notes

All five phases landed in one implementation commit, with the plan file and
verification report in a second. Nothing was deferred.

**Verified results:** full R suite `FAIL 0 | PASS 946 | SKIP 1` (the gated SDB
test, run separately: `FAIL 0 | PASS 15`); Python suite `79 passed`;
`Rscript tools/verify_refactor.R` on a clean tree `BYTE-IDENTITY PASS` (10
PNG-noise, 5 timestamp-class, 0 drift — including the newly committed
`dashboard/data/artifact_catalog.json`, proven deterministic across two full
refreshes); `--invariants` `INVARIANTS PASS`; dry-run output for both
engagements character-identical to a `bd09f48` worktree; SDB end-to-end exit 0
with `git status --porcelain synthesis_output output dashboard/data reports`
empty.

**Deviations (deliberate, all documented in the report):**
`test_engagement_plan.R`'s `.test_cfg()` gained the full `paths` key set (the
catalog refuses an unresolvable config); the copier's intra-sector file order
follows catalog order (bytes unchanged); `load_trisk_tables()` resolves
`manifest.csv` from the catalog and the now-dead `trisk_manifest()`/
`trisk_path()`/`trisk_sector_path()`/`reports_path()` helpers were deleted;
`tools/verify_refactor.R`'s `.mcb_catalog()` merges the engagement config
without the loader's file-existence validation so the tool stays sourceable from
`tests/testthat`; INV-003 keeps its literal fallback for minimal fixture
configs. The previous-run ordering defect in `sector_prioritization` and the
analytics copy was preserved, as the plan requires.
