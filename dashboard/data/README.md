# Dashboard Data Artifacts

> **Provenance:** PACTA files are snapshots from `scripts/pacta_vietnam_scenario.R`. TRISK files are snapshots from `scripts/trisk_prepare_inputs.R` and `scripts/trisk_sector_demo.R` (run per sector, e.g. `scripts/trisk_sector_demo.R power`). Regenerate with `scripts/refresh_dashboard_data.R`, or run the whole chain via `scripts/pipeline_refresh.R`.

## `artifact_catalog.json`

Written by `scripts/refresh_dashboard_data.R` from `R/artifact_catalog.R`, the single owner of Artifact locations. The dashboard resolves every table path from it (see `dashboard/lib/loaders.py`), so no page spells a Snapshot filename. It carries no timestamp, its rows follow catalog order, and the byte-identity gate compares it like any other Snapshot artifact.

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

Only rows with a Snapshot location appear; `snapshot_path` is relative to this directory. `sector` is `null` for engagement-scoped Artifacts.

## `pacta/` — PACTA Alignment Outputs (Vietnam MCB)

| File | Columns | Units | Provenance |
|---|---|---|---|
| `02_vn_matched_prioritized.csv` | `id_loan, id_2dii, name_direct_loantaker, sector, sector_abcd, score` | N/A (match quality) | `pacta_vietnam_scenario.R` §2 — `prioritize()` output |
| `04_vn_ms_company.csv` | `sector, technology, year, region, scenario_source, metric, production, technology_share, scope, percentage_of_initial_production_by_scope` | MW (power), vehicles (auto) | `pacta_vietnam_scenario.R` §4 — `target_market_share()` company level |
| `04_vn_ms_portfolio.csv` | Same columns as company-level | Same | `pacta_vietnam_scenario.R` §4 — `target_market_share()` portfolio level |
| `05_vn_sda_portfolio.csv` | `sector, year, region, scenario_source, emission_factor_metric, emission_factor_value` | tCO2/unit | `pacta_vietnam_scenario.R` §5 — `target_sda()` portfolio level |
| `06_vn_ms_alignment_2030.csv` | `sector, technology, scenario, projected_share, target_share, gap_pp` | Percentage points | `pacta_vietnam_scenario.R` §6 — alignment gap calc |
| `06_vn_sda_alignment_2030.csv` | `sector, projected, target_pdp8, intensity_gap, gap_pct, aligned` | % above/below target | `pacta_vietnam_scenario.R` §6 — SDA alignment gap |

PNG charts in `pacta/` are copied from `synthesis_output/vietnam/` and remain single-file snapshot visuals for the dashboard.

## `trisk/` — TRISK Multi-Sector Stress-Test Snapshot

### Layout

- `manifest.csv` — sector catalog used by the dashboard loader and sector selector
- `power/` — power-sector TRISK snapshot
- `cement/` — cement-sector TRISK snapshot
- `steel/` — steel-sector TRISK snapshot

### `manifest.csv`

| Column | Meaning |
|---|---|
| `sector` | Stable programmatic sector key used by the loader and page |
| `label` | Display label shown in the dashboard |
| `folder` | Snapshot folder name under `dashboard/data/trisk/` |
| `price_unit` | Display unit for scenario prices |
| `pathway_unit` | Display unit for scenario pathways |
| `alignment_mode` | Alignment context mode: borrower-level market share or sector-level SDA |
| `disclaimer` | Sector-specific caveat shown on the TRISK page |

### Files inside each sector folder

| File | Purpose |
|---|---|
| `assets.csv` | TRISK asset input snapshot for the sector |
| `financial_features.csv` | Synthetic borrower financial assumptions used by the run |
| `scenarios.csv` | Baseline and stress scenario inputs for the sector |
| `ngfs_carbon_price.csv` | Carbon-price curve used for the selected sector |
| `company_summary.csv` | Borrower-level NPV and PD summary |
| `company_trajectories_latest.csv` | Borrower and technology shock trajectories |
| `npv_results_latest.csv` | Detailed NPV output from the base run |
| `pd_results_latest.csv` | Detailed PD output from the base run |
| `pd_summary.csv` | Aggregated PD summary |
| `params_latest.csv` | Parameters from the base run |
| `run_catalog.csv` | Sensitivity run registry |
| `sensitivity_results.csv` | Borrower-level sensitivity outputs |
| `sensitivity_summary.csv` | Run-level sensitivity summary |
| `top_borrowers_alignment_trisk.csv` | Prioritized borrower stress view with alignment context |
| `01_npv_change_by_company.png` | NPV change figure |
| `02_pd_change_by_company.png` | PD change figure |
| `03_priority_score_top10.png` | Priority score figure |

### Alignment context note

- `power` uses borrower-level PACTA market-share context.
- `cement` and `steel` currently use sector-level SDA context copied onto borrower rows for demo prioritization. This is not borrower-specific SDA alignment.

## `reports/` — Static HTML Reports

Reports remain copied as standalone HTML files into `dashboard/data/reports/`.

## Notes

- All monetary values are synthetic **Vietnamese Dong (VND)** unless otherwise noted.
- TRISK NPV / PD values are scenario-horizon stress outputs, not 1-year regulatory PDs.
- The dashboard reads only frozen snapshot files under `dashboard/data/`; it does not run PACTA or TRISK calculations live.

Displayed report dates come from each artifact file’s modification date, not from the catalog `date` strings (which remain only as a fallback when the file is absent).
