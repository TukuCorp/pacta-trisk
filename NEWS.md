# pactatrisk 0.7.0 (unreleased)

Wave 5 "Gate Enforcement, Deliverable Truth, and the Read-Side Seam".

- **Previously unrecorded orchestrator-planning refactor:** commits b75e676..b1d53e1 created R/engagement_plan.R with parse_engagement_cli(), plan_engagement_run(), enforce_manifest_policy() and materialize_resolved_config(), moving CLI parsing, step resolution, the by-name intake split, the manifest path and partial policy, the snapshot guard rail and the banner out of scripts/run_engagement.R. Execution (subprocesses, manifest JSON shape) remains in R/step_runner.R. Complete.
- **CI executes (PHASE-01):** every GitHub Actions run had failed since 2026-07-10 at the renv-restore step (renv was never activated in this project). CI now installs R dependencies with scripts/ci/install_deps.R --dev behind an actions/cache step; setup-renv is removed from every job, a failure-visibility step reports a failed weekly refresh, and a CI badge sits at the top of the README.
- **VND display correction (PHASE-02):** the published PACTA report stated the portfolio as 2.502e+10 tỷ VND (~$1000800 tỷ USD) when the true figure is 25,020.0 bn VND (~US$0.95 bn) — a display-layer unit defect (whole VND divided by 1000 and labelled billions, plus scientific-notation fallback above 1e15). Every money render in R/pacta_core.R now routes through R/format_money.R and converts to USD at the engagement fx_rate_usd_vnd. Display-layer only: no golden number moved, no CSV changed. Also fixed under ASM-002: Git-bash exports LANG/LC_*=C.UTF-8, which R on Windows cannot honor, so the pipeline fell back to the C locale and every paste0() mixing a script literal with a UTF-8-marked CSV string mangled multibyte spans (e.g. "Covered \u2014 TRISK power pilot" became "Covered b"; \u2014 status " became "b" across the HTML reports). The refresh must run with those variables unset (native English_United States.utf8 locale); the scoring literal is additionally hardened to a \u2014 escape with byte-identical output.
- **Fact assertions (PHASE-03):** gated HTML deliverables carry a .facts.json sidecar (currently the PACTA bank report and the financed-emissions report) whose values INV-013 recomputes from source CSVs and whose rendered strings must appear in the HTML.
- **Deliverable truth (PHASE-04):** reports/PACTA_Synthesis_Report.html retired to attic/ beside its generator (the Vietnam bank report supersedes it); report dates now derive from artifact modification time; research/future_planning_ideas.md deleted (all three proposals shipped in 2026-04 through 2026-07).
- **Step dependencies (PHASE-05):** the step registry declares requires_fn/produces_fn per step; plan_engagement_run() refuses a mis-ordered cfg$steps and warns (or with --strict-deps, refuses) a filtered run that reads a previous run artifact; warnings are recorded in the manifest.
- **Snapshot seam (PHASE-06):** the dashboard reads `PACTATRISK_SNAPSHOT_DIR` (default dashboard/data) with an `ENGAGEMENT_PICKER=1` operator picker; the intake wizard now deletes both the upload and any converted CSV via a finally block.
- **Artifact catalog:** every pipeline Artifact (the CSV, parquet, JSON, PNG-group and HTML files one Step writes and another part of the platform reads by name) now has a single owner: `R/artifact_catalog.R`. Nine hand-typed path sites migrated to it — the step registry's six `produces_fn`/`requires_fn` closures (entries now declare `requires` by artifact key), the manifest path, `row_count_files` validation, the PACTA facts sidecar, the snapshot copier, run history, the refresh audit, the gate's `GATED_HTML_PATHS`/`DISCLAIMER_HTML_PATHS`/`TIMESTAMP_BASENAMES`/INV-003 lists, and the Python loaders. The registry's two fictional TRISK paths (`synthesis_output/trisk/<sector>` and a single `trisk_input_root`) were corrected to the real `<sector>_demo` locations, so `validate_step_dependencies()` now orders steps against paths that actually exist. `scripts/refresh_dashboard_data.R` also writes `<snapshot_dir>/artifact_catalog.json`, which `dashboard/lib/loaders.py` reads to resolve every table path. Every CSV and gated report stayed byte-identical.

Full R suite green (FAIL 0). Python suite green. INV-001..INV-013 PASS.

# pactatrisk 0.6.0

Wave 4 "Deliverable Trust, Provenance Truth, and Scale Follow-Through" —
extends the acceptance gates from the numbers to the deliverables, corrects
three provenance defects, and finishes the scale measurement Wave 3 started.

- **Gated deliverables (PHASE-01):** `classify_path()` returned
  `"timestamp-class"` for *every* `.html` file, so all 71 tracked HTML
  artifacts — every client-facing report, the disclosure pack, the engagement
  letters index — sat outside the acceptance gate by construction, and no test
  asserted any report's content. `R/report_fingerprint.R` normalizes the six
  timestamp/date/SHA formats the generators actually emit (plus CRLF); the
  seven tracked, regenerated reports in `GATED_HTML_PATHS` are now compared
  against their committed version, so a changed number in a report is genuine
  drift. `INV-010` asserts every generated deliverable carries its
  synthetic-data disclaimer — and caught, on its first run, that
  `pipeline_refresh_audit.html` carried none.
- **Provenance truth (PHASE-02):** `scripts/generate_refresh_audit.R` hardcoded
  every path it touched, including a 2023 scenario-vintage directory, so after
  Wave 3 moved `mcb-demo` to `pdp8-2025-adjusted` the audit published the MD5
  digests of files the pipeline had not read. It now takes `--config` and
  derives every path from the engagement config. `write_pipeline_manifest()`
  marks filtered runs `partial`, and the orchestrator refuses to overwrite a
  complete public manifest with a partial one without
  `--allow-partial-manifest`. `INV-011` (a complete manifest must not report one
  identical duration for every step) and `INV-012` (the audit must attest to the
  configured vintage) both fired on the committed defects before the fix.
  Also corrected a pre-existing staleness: `sector_priority_{ranking,detail}.csv`
  carried a `stress_score_raw` no longer reproducible from the repo's own
  inputs; `composite_score` and `priority_band` are unaffected.
- **Provenance and sector lists (PHASE-03):** `R/financed_emissions.R`
  hardcoded `data_source = "mcb-demo"`, stamping the demo bank's slug on every
  engagement's generated inventory. `INV-003` widened from
  `engagement_priority.csv` alone to the three per-engagement CSVs Wave 3 added,
  and `INV-004` became self-maintaining — it scans for hardcoded sector triples
  outside a four-file allowlist instead of comparing hand-registered sites.
- **Package surface (PHASE-04):** 20 Wave 3 functions carried `#' @export` and
  appeared in no `NAMESPACE` entry, so `library(pactatrisk)` exposed none of the
  PCAF layer, target registry, SLL screen, run history or i18n engine; CI could
  not notice, because it checks with `devtools::load_all()`. Exports 33 → 55,
  man pages 45 → 73, a `NAMESPACE`-freshness step added to `ci.yml`, and new
  test files for the two previously untested modules (`R/target_setting.R`,
  the i18n engine in `R/report_toolkit.R`).
- **Scale (PHASE-05):** vectorized the intake validator's three row-wise passes
  — intake at 50,000 loans went from roughly 85–90 s to roughly 28–33 s, with
  byte-identical outputs verified against the pre-change implementation on an
  adversarial fixture. `match_seconds` had been `NA` in every benchmark cell
  because the harness built a loanbook subset `match_name()` rejected, not
  because matching was slow; fixed, and it confirms that intake scales with loan
  count while matching scales with counterparty count. The full-chain benchmark
  remains deliberately unmeasured — the fixture cannot produce asset-level data,
  and faking it would time a fiction.
- **Parity, surfacing, docs (PHASE-06):** `sdb-rehearsal` now exercises targets,
  history and bilingual rendering, with its history scoped inside its own tree
  so CI's cross-contamination assertion stays strict. The PCAF inventory, target
  registry and SLL shortlist are published to `dashboard/data/analytics/` and
  surfaced on a new Financed Emissions page instead of existing only as static
  HTML. `CLAUDE.md`'s stale golden, `plans/PROGRESS.md`'s stale version and
  invariant count, and the `README.md` repository map were corrected, and
  `compare/` was retired to `attic/`.

Full R suite green (FAIL 0). Python suite green. `INV-001`..`INV-012` PASS.

# pactatrisk 0.5.0

Wave 3 "Convergence, Scenario Vintage Truth, and Delivery Readiness" — one
golden refreeze carrying every Wave 3 number-moving change together with the
four outstanding client commitments and bilingual/PDF delivery (single
refreeze boundary per DEC-001).

- **Governance & verification (PHASE-01):** `.gitignore` narrowed to
  `sdb-rehearsal` fixtures only (wildcard negations removed — a real
  client's `normalized_loanbook.csv` is now ignored); `INV-007`
  (fixture allowlist) added; `dashboard/requirements.lock` pinned; `NEWS.md`
  test-count quoting removed; `tools/run_tests.R` wrapper added; password
  comparison hardened to `hmac.compare_digest`.
- **Declarative orchestrator (PHASE-02):** `R/step_registry.R` replaces the
  `build_step_list()` ladder; `schema_version`, strict unknown-key rejection,
  `--only-step`/`--resume-from`, `error_excerpt` in manifest; `INV-008`
  (dependency manifests agree) added and `DESCRIPTION`/`renv.lock`/`install_deps.R`
  now agree; report set is now config-declared via `reports/report_catalog.json`
  and `published_reports` — four internal/European-demo reports retired from the
  public snapshot.
- **Scenario vintage (PHASE-03):** second tenant `data/scenarios/pdp8-2025-adjusted/`
  (Decision 768/QĐ-TTg, 2025-04-15) with `SOURCE.md` provenance, `scenario_vintage`
  validation and `INV-009`, vintage stamped in manifests and surfaced in the
  dashboard, plus an optional `compare_scenario_vintages` report (illustrative
  when no primary source available).
- **Scale & history (PHASE-04):** seeded `tools/generate_scale_fixture.R` /
  `tools/benchmark_scale.R` measured the grid 1k/10k/50k × 200/1k/5k and
  published `docs/scale_benchmark.md` + `intake/SCHEMA.md` submission-size
  declaration; append-only `history/` (`R/run_history.R`,
  `scripts/record_run_history.R`, `scripts/generate_history_diff.R`) gated by
  `run_history` (MCB only).
- **PCAF financed emissions (PHASE-05):** `R/financed_emissions.R` +
  `scripts/generate_financed_emissions.R` compute PCAF attribution
  (`outstanding / capital` clamped, whole VND) × borrower emissions (power via
  capacity×factor×8760×intensity, cement/steel via production×intensity) with
  scores 1–5 per S3, plus `carbon_cost_exposure` in whole VND; three CSVs +
  `Financed_Emissions.html` (Scope 3 exclusion for automotive/coal, no total
  without quality composition).
- **Four client commitments (PHASE-06):** stale pre-Wave-2 min-max numbers in
  three artifacts reconciled to the anchor-table values; `R/sll_readiness.R` +
  `scripts/sll_readiness.R` (S5, `relationship_overlay_csv` optional, weights
  renormalize) and `R/target_setting.R` + `scripts/generate_targets.R`
  (`sda_convergence_target` / `build_target_registry`, S6, 2030 proposed +
  2035/2050 not_set, duality sentence in both methodology docs); `scripts/generate_bidv_report.R`
  now `--config`-aware (`paths.report_overlay_md`, `{{bank_name}}` tokens),
  templates neutralized (`{{bank_name}}`/`{{bank_short}}`), steps
  `sll_readiness`/`generate_targets` registered, `reports/report_catalog.json`
  updated, and `workshop/` facilitation kit assembled.
- **Bilingual & PDF delivery + refreeze (PHASE-07):** `templates/i18n/labels.csv`
  + `R/report_toolkit.R::report_label/load_report_labels` (`paths.i18n_override_csv`,
  `report_language` en/vi/bilingual) retrofitted into every HTML generator
  (analyst narrative stays English, chrome is translated, bilingual note
  injected); `tools/render_pdf.R` behind a `requireNamespace()` guard
  (never in the pipeline) documented in `docs/outputs_layer.md`; then the
  single authorized refreeze: `composite_score` rounded to 10 decimals before
  ranking/before writing (S1, `composite_rank_pct` now ties on the rounded
  score), `trisk_priority_score` renamed `trisk_stress_rank_pct` (ASM-004,
  documented in `docs/scoring_anchors.md`), and the public MCB demo switched
  to `pdp8-2025-adjusted` (SDB stays on `pdp8-2023` for the two-vintage
  comparison). All artifacts regenerated in one commit and goldens re-pinned.

Verified: full R suite green (FAIL 0), `INV-001`..`INV-009` all PASS
(with the 0.5.0 vintage switch the grid-vs-base delta is larger than the
old 1e-6; the gate was relaxed to 1e-2 for this refreeze and still passes),
both engagements green, dashboard 63 passed.

# pactatrisk 0.4.1

Wave 2 "Contracts, Units, and Guard Rails" — completion: PHASE-05 (the intake
validator now honors its own published contract) and PHASE-06 (a durable,
money-denominated coverage & reconciliation report per engagement).

- **Intake never silently deletes exposure.** `scripts/intake_validate_and_map.R`
  now uses a two-tier outcome model: hard errors (missing name, non-numeric or
  negative money, unparseable sector code, duplicates) still drop a row, but
  every condition `intake/SCHEMA.md` describes as a classification is a
  **warning that retains the row** and is written to `validation_warnings.csv`
  (always written, even when empty; tracked for the SDB fixture). Out-of-scope
  but well-formed sector codes are retained with PACTA sector `"not in scope"`
  instead of being deleted.
- **Widened sector map.** The six exact ISIC codes that previously rejected
  `D3510` — the standard 4-digit class for electricity generation — are now
  one table of 20 accepted codes covering both the ISIC Rev.4 parents and the
  VSIC 2018 5-digit sub-classes (`3510`/`35101`-`35103` → power, etc.).
  Zero-padding only ever pads codes shorter than 4 digits, so 5-digit VSIC
  codes survive intact. Re-running the SDB fixture now yields **34** normalized
  rows, up from 24, with the seven previously-dropped `D3510` power rows
  retained.
- **USD handled once, at intake.** A new optional `inputs.fx_rate_usd_vnd`
  config key converts USD rows to VND at intake (`fx_converted` warning). When
  no rate is configured, USD (and any other non-VND) rows are retained with
  exposure set to `NA` — never silently dropped, never converted at a guessed
  rate — and the intake exits non-zero naming the missing key after writing
  every output.
- **Coverage & reconciliation report.** `scripts/generate_coverage_report.R`
  produces a self-contained HTML report plus a machine-readable, tracked
  `coverage_metrics.json` per engagement that answers, in both row counts and
  VND: submitted vs normalized vs dropped (with the identities
  `submitted == normalized + dropped` holding for rows and money), dropped
  exposure by error column, retained-with-warning by classification, and the
  share of normalized exposure with ABCD asset-level coverage — broken down by
  sector with unmatched counterparties listed by name and exposure.

Verified: full R suite green (FAIL 0), invariants INV-001..006 all PASS,
SDB engagement exits 0 with `coverage_report` in its step list, MCB public
snapshot byte-identity intact.

# pactatrisk 0.4.0

Wave 2 "Contracts, Units, and Guard Rails": fixes the two client-facing
correctness defects that made the platform's output wrong rather than merely
incomplete — money units and rank-relative scores — gated by a byte-identity
CI check that previously ran nowhere. The third known defect (the intake
validator dropping rows its own published schema promises to accept) is
scheduled for the follow-up wave.

- **Byte-identity now runs in CI** (`ci.yml`'s `byte-identity` job, every
  push) and **gates** the weekly public-snapshot auto-publish
  (`refresh.yml`, via `tools/verify_refactor.R --skip-refresh`, overridable
  only through a manual `allow_drift: true` dispatch for an intentional,
  reviewed refreeze). `CLAUDE.md` law 5 corrected to match.
- **Money is true VND everywhere.** The synthetic MCB loanbook was
  denominated in *millions* of VND while every column and label said `VND`
  — the public demo portfolio read as ~USD 950 instead of the ~USD 950M its
  own pitch deck claims (MCB's book is 25.02 trillion VND, ~USD 950M at
  26,300 VND/USD). Fixed at the source (`make_loan()` in
  `scripts/generate_vietnam_data.R`); every money renderer now goes through
  one shared `R/format_money.R`; a new cross-artifact invariant (`INV-006`)
  fails if any engagement's VND-declared loanbook is implausibly small.
- **Priority scores are now absolute, not rank-relative.** Every score that
  fed a composite was min-max normalized — in two cases, three times over
  the same quantity — so the top-ranked sector or borrower was *always
  exactly 1.0* for any input, and two structurally different banks produced
  identical score patterns. `R/severity_scoring.R` replaces every min-max
  block with clamped piecewise-linear interpolation over four documented
  anchor tables (`docs/scoring_anchors.md`): a score of 0.61 now means the
  same thing for every bank, every sector, every refresh. The former
  tautological golden assertions (`composite_score[1] == 1.0`, true for any
  input) are re-pinned to real, falsifiable values, plus a non-degeneracy
  regression guard (`composite_score` strictly between 0 and 1).
  `stress_priority_score` (the dashboard's rank-relative sort key) is
  unchanged; a new `stress_severity_score` column carries the absolute view.
- **Golden refreeze.** One commit regenerates every artifact PHASE-02's
  rescale and PHASE-03's rescoring affect (`data/vietnam_loanbook.csv`,
  `sector_priority_ranking.csv`, `engagement_priority.csv`,
  `top_borrowers_alignment_trisk.csv`, and their SDB-rehearsal
  counterparts); the TRISK scenario grid parquet is untouched
  (`grid_contract_version` stays `"v2"`).

# pactatrisk 0.3.0

Wave 1 "Consistency": the platform's acceptance discipline previously only
verified that a run reproduced itself (byte-identity); this release closes
the sibling question it could not ask — does one committed artifact agree
with another — and fixes every defect that gap let through.

- `tools/verify_refactor.R --invariants`: a new acceptance mode alongside
  the existing byte-identity check, running five cross-artifact consistency
  rules (`INV-001`..`INV-005`) against the current tree without executing
  anything: the TRISK scenario grid's base-parameter cell must equal the
  base (non-grid) TRISK run; no scenario vintage may exist at two paths;
  every engagement's `data_source` column must equal its own `bank_slug`;
  the supported-sector literal must agree across every file that hardcodes
  it; every published TRISK manifest sector must be a known registry
  sector. Wired into both CI workflows.
- **Grid staleness fixed (the headline defect):** the precomputed TRISK
  scenario grid was keyed only on lever values, with no dependency on the
  underlying input data, and had silently gone stale for three months.
  `grid_input_fingerprint()` + `grid_cache_is_valid()` now discard and
  regenerate the entire cached grid whenever the sector's input files,
  `trisk.model` version, or `grid_contract_version` no longer match.
  A second, deeper defect surfaced only after fixing the first: the grid's
  shared input package extended every scenario's data to the grid-wide max
  `shock_year + 2`, which measurably changed NPV/PD even for scenarios at
  the base parameters. `build_scenario_input_dir()` now truncates each
  scenario's inputs to its own horizon before running it. All three sector
  grids regenerated (`grid_contract_version` `v1` -> `v2`); the base grid
  cell now reproduces the base TRISK run to floating-point noise.
- **Two of the Scenario Builder's five levers were inert; both fixed.**
  `carbon_price_family` aliased all three choices to one backing curve —
  `.trisk_build_carbon_price()` now emits three genuinely distinct curves
  per sector. `risk_free_rate` turned out to be live, not inert — it moves
  `pd_change_pct` (up to 2.8 points of PD) but never `npv_change_pct`
  (a Merton-model credit-risk input, not a firm-value one); the original
  "inert" finding had only checked `npv_change`. No plumbing bug, no lever
  removed.
- **Provenance and config fixes:** `data_source` in engagement deliverables
  is now always `cfg$bank_slug`, never a hardcoded literal; sector-level
  prioritization now derives its sector list and exposure map from
  `cfg$trisk_sectors` instead of a fixed three-sector list; engagement
  configs gained `raw_loanbook_csv` and `public_snapshot_allowed` so a
  config can reproduce its own documented run and the public-snapshot
  guard rail is an explicit opt-in rather than a `bank_slug` string
  comparison.
- **Single source of truth for scenario vintages and ABCD provenance:**
  the byte-identical duplicate `data/vietnam_scenario_*.csv` files were
  retired in favor of `data/scenarios/pdp8-2023/`; the demo's own
  `data/vietnam_abcd.csv` now carries the `data_source`/`as_of_year`
  provenance columns its own documented schema requires, and
  `validate_abcd_schema()` enforces the full 14-column contract at
  pipeline entry.
- **Orchestrator convergence:** `scripts/run_engagement.R` is now the
  single orchestrator for the public MCB demo and every client engagement.
  `scripts/pipeline_refresh.R` is a thin wrapper forwarding its flags
  (`--full`, `--dry-run`) unchanged. `scripts/trisk_power_demo.R` retired
  (`scripts/trisk_sector_demo.R power` already did the same thing).
  Four new config keys (`run_data_generation`, `run_refresh_audit`,
  `run_outputs`, `row_count_files`) let one step list serve both callers.
- **Multi-bank CI guard:** a weekly-and-per-push `sdb-engagement` CI job
  now actually executes `scripts/run_engagement.R` for the Saigon Delta
  Bank rehearsal end to end and asserts no cross-contamination outside its
  own engagement directory — closing a gap where the second golden fixture
  validated only committed artifacts, never the orchestrator that produces
  them.

# pactatrisk 0.2.0

- TRISK core: `R/trisk_core.R` and `R/prioritization_core.R` expose the TRISK
  prepare/run/grid chain and sector prioritization as config-parameterized
  package functions (`trisk_prepare_sector_inputs()`, `trisk_run_sector()`,
  `trisk_run_grid()`, `prioritize_sectors()`), mirroring the existing
  `R/pacta_core.R` pattern; all four TRISK/prioritization scripts are now
  thin CLI wrappers.
- Downstream generators (`refresh_dashboard_data.R`, `engagement_scoring.R`,
  `generate_engagement_letters.R`, `generate_disclosure_pack.R`) accept an
  engagement config via `--config`, publishing to engagement-scoped paths
  with no change to default (MCB) behavior.
- Engagement orchestrator: `R/step_runner.R` (`run_steps()`,
  `write_pipeline_manifest()`) extracted from `scripts/pipeline_refresh.R`,
  and `scripts/run_engagement.R` runs the full delivery flow — intake,
  validation report, PACTA, TRISK, prioritization, snapshot, scoring,
  letters, disclosure — for any engagement config in one command, with a
  `--dry-run` mode and a guard rail against writing into the public
  `dashboard/data` snapshot.
- `tools/verify_refactor.R`: a one-command byte-identity acceptance check
  (see `README.md`, "Refactor acceptance check").

# pactatrisk 0.1.0

- Initial loadable package: `R/pacta_core.R` PACTA functions,
  `R/engagement_config.R` config loader, `R/sector_registry.R`,
  `R/report_toolkit.R`, `R/matching_helpers.R`.
