# ==============================================================================
# R/artifact_catalog.R
# One owner for every Artifact location (ADR-0001).
#
# An "Artifact" is a file or directory one pipeline Step writes and something
# other than its producer names: a step's `requires`, the Snapshot copier, the
# run-history recorder, the refresh audit, the gate's path lists, the
# engagement config's `row_count_files`, or the Python dashboard loaders.
# Before this module nine places spelled those paths by hand and two of them
# were already wrong (the step registry declared `synthesis_output/trisk/power`
# where TRISK actually writes `synthesis_output/trisk/power_demo`).
#
# The catalog is built from the loaded engagement config, never from a static
# file in the repo: every location depends on cfg$paths$* and cfg$trisk_sectors.
# Producer-internal intermediates (per-run TRISK folders, PACTA's `01_*.csv`,
# classification notes) earn no row -- nothing outside their producer names
# them.
#
# Contract:
#   artifact_catalog(cfg)            one data.frame, one row per resolved Artifact
#   artifact_path(cfg, key, ...)     the repo-relative path (or snapshot path) of one key
#   write_artifact_catalog_json(...)  the machine-readable export the dashboard reads
#
# Producers keep writing where they write today; the catalog only *declares*
# those locations (tests/testthat/test_artifact_catalog.R checks the
# declaration against the committed tree). A hand-typed Artifact path anywhere
# outside this file is a defect.
#
# Base R + jsonlite only; no top-level side effects (`devtools::load_all()`
# loads this file alongside the rest of the package). No `%||%`: the module
# must be sourceable on its own, in any order.
# ==============================================================================

# Column names of the catalog data.frame, in order.
# @return character — the 13 catalog columns.
.artifact_catalog_columns <- function() {
  c(
    "key", "group", "scope", "sector", "producer", "kind", "path", "snapshot_path",
    "history_headline", "timestamp_class", "gated_html", "disclaimer_required",
    "data_source_check"
  )
}

# Build one catalog row (a one-row data.frame with the S1 column order).
# @param key character(1) — semantic artifact key.
# @param group character(1) — intake | pacta | trisk_input | trisk | grid |
#   snapshot | prioritization | engagement | analytics | reports.
# @param scope character(1) — "engagement" or "sector".
# @param sector character(1)|NA — the sector for sector-scoped rows.
# @param producer character(1)|NA — registry step key, "run_engagement", or NA.
# @param kind character(1) — csv | parquet | json | html | png_group.
# @param path character(1) — repo-relative output location.
# @param snapshot_path character(1)|NA — repo-relative Snapshot location.
# @param history_headline,timestamp_class,gated_html,disclaimer_required,data_source_check
#   logical(1) — consumer flags (DEC-004).
# @return data.frame with one row and the catalog column order.
.artifact_row <- function(key, group, scope, sector, producer, kind, path,
                          snapshot_path = NA_character_,
                          history_headline = FALSE, timestamp_class = FALSE,
                          gated_html = FALSE, disclaimer_required = FALSE,
                          data_source_check = FALSE) {
  data.frame(
    key = key,
    group = group,
    scope = scope,
    sector = sector,
    producer = producer,
    kind = kind,
    path = path,
    snapshot_path = snapshot_path,
    history_headline = history_headline,
    timestamp_class = timestamp_class,
    gated_html = gated_html,
    disclaimer_required = disclaimer_required,
    data_source_check = data_source_check,
    stringsAsFactors = FALSE
  )
}

# Row-bind a list of one-row catalog frames.
# @param rows list — .artifact_row() results.
# @return data.frame, or NULL when `rows` is empty.
.artifact_bind <- function(rows) {
  if (length(rows) == 0) {
    return(NULL)
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

# Engagement-scoped catalog rows, in the S1 table order.
# @param cfg list — the loaded engagement config.
# @return data.frame of the engagement-scoped rows.
.artifact_rows_engagement <- function(cfg) {
  P <- cfg$paths$pacta_output_dir
  T <- cfg$paths$trisk_output_root
  S <- cfg$paths$snapshot_dir
  R <- cfg$paths$reports_dir
  E <- cfg$paths$engagement_output_dir
  F <- cfg$paths$financed_emissions_output_dir
  Q <- cfg$paths$prioritization_output_dir
  L <- cfg$paths$letters_output_dir
  D <- cfg$paths$disclosure_output_dir
  slug <- cfg$bank_slug
  public <- isTRUE(cfg$public_snapshot_allowed)

  # The public Snapshot's manifest IS the pipeline manifest (written in place
  # by run_engagement.R); a private engagement keeps its manifest under its own
  # tree and never exports it into a Snapshot (Gotchas).
  manifest_path <- if (public) {
    file.path(S, "pipeline_manifest.json")
  } else {
    file.path("engagements", slug, "pipeline_manifest.json")
  }
  manifest_snapshot <- if (public) file.path(S, "pipeline_manifest.json") else NA_character_

  .artifact_bind(list(
    .artifact_row("normalized_loanbook", "intake", "engagement", NA_character_, "intake", "csv",
                  file.path("engagements", slug, "intake", "normalized_loanbook.csv")),
    .artifact_row("matches", "pacta", "engagement", NA_character_, "pacta_vietnam_scenario", "csv",
                  file.path(P, "02_vn_matched_prioritized.csv"),
                  file.path(S, "pacta", "02_vn_matched_prioritized.csv")),
    .artifact_row("ms_company", "pacta", "engagement", NA_character_, "pacta_vietnam_scenario", "csv",
                  file.path(P, "04_vn_ms_company.csv"),
                  file.path(S, "pacta", "04_vn_ms_company.csv")),
    .artifact_row("ms_portfolio", "pacta", "engagement", NA_character_, "pacta_vietnam_scenario", "csv",
                  file.path(P, "04_vn_ms_portfolio.csv"),
                  file.path(S, "pacta", "04_vn_ms_portfolio.csv")),
    .artifact_row("sda_portfolio", "pacta", "engagement", NA_character_, "pacta_vietnam_scenario", "csv",
                  file.path(P, "05_vn_sda_portfolio.csv"),
                  file.path(S, "pacta", "05_vn_sda_portfolio.csv")),
    .artifact_row("ms_alignment", "pacta", "engagement", NA_character_, "pacta_vietnam_scenario", "csv",
                  file.path(P, "06_vn_ms_alignment_2030.csv"),
                  file.path(S, "pacta", "06_vn_ms_alignment_2030.csv"),
                  history_headline = TRUE),
    .artifact_row("sda_alignment", "pacta", "engagement", NA_character_, "pacta_vietnam_scenario", "csv",
                  file.path(P, "06_vn_sda_alignment_2030.csv"),
                  file.path(S, "pacta", "06_vn_sda_alignment_2030.csv"),
                  history_headline = TRUE),
    .artifact_row("pacta_figures", "pacta", "engagement", NA_character_, "pacta_vietnam_scenario", "png_group",
                  P, file.path(S, "pacta")),
    .artifact_row("trisk_manifest", "snapshot", "engagement", NA_character_, "refresh_dashboard_data", "csv",
                  file.path(S, "trisk", "manifest.csv"),
                  file.path(S, "trisk", "manifest.csv"),
                  timestamp_class = TRUE),
    .artifact_row("pipeline_manifest", "snapshot", "engagement", NA_character_, "run_engagement", "json",
                  manifest_path, manifest_snapshot, timestamp_class = TRUE),
    .artifact_row("sector_priority_ranking", "prioritization", "engagement", NA_character_, "sector_prioritization", "csv",
                  file.path(Q, "sector_priority_ranking.csv"), NA_character_,
                  history_headline = TRUE),
    .artifact_row("sector_priority_detail", "prioritization", "engagement", NA_character_, "sector_prioritization", "csv",
                  file.path(Q, "sector_priority_detail.csv")),
    .artifact_row("engagement_priority", "engagement", "engagement", NA_character_, "engagement_scoring", "csv",
                  file.path(E, "engagement_priority.csv"), NA_character_,
                  history_headline = TRUE, data_source_check = TRUE),
    .artifact_row("financed_emissions", "analytics", "engagement", NA_character_, "financed_emissions", "csv",
                  file.path(F, "financed_emissions.csv"),
                  file.path(S, "analytics", "financed_emissions.csv"),
                  data_source_check = TRUE),
    .artifact_row("data_quality_summary", "analytics", "engagement", NA_character_, "financed_emissions", "csv",
                  file.path(F, "data_quality_summary.csv"),
                  file.path(S, "analytics", "data_quality_summary.csv")),
    .artifact_row("target_registry", "analytics", "engagement", NA_character_, "generate_targets", "csv",
                  file.path(E, "target_registry.csv"),
                  file.path(S, "analytics", "target_registry.csv"),
                  data_source_check = TRUE),
    .artifact_row("sll_readiness", "analytics", "engagement", NA_character_, "sll_readiness", "csv",
                  file.path(E, "sll_readiness.csv"),
                  file.path(S, "analytics", "sll_readiness.csv"),
                  data_source_check = TRUE),
    .artifact_row("pacta_bank_report", "reports", "engagement", NA_character_, "pacta_vietnam_scenario", "html",
                  file.path(R, "PACTA_Vietnam_Bank_Report.html"), NA_character_,
                  gated_html = TRUE, disclaimer_required = TRUE),
    .artifact_row("financed_emissions_report", "reports", "engagement", NA_character_, "financed_emissions", "html",
                  file.path(R, "Financed_Emissions.html"), NA_character_,
                  gated_html = TRUE, disclaimer_required = TRUE),
    .artifact_row("sll_readiness_report", "reports", "engagement", NA_character_, "sll_readiness", "html",
                  file.path(R, "SLL_Readiness_Shortlist.html"), NA_character_,
                  gated_html = TRUE, disclaimer_required = TRUE),
    .artifact_row("target_registry_report", "reports", "engagement", NA_character_, "generate_targets", "html",
                  file.path(R, "Sector_Target_Registry.html"), NA_character_,
                  gated_html = TRUE, disclaimer_required = TRUE),
    # ASM-004: generated by scripts/generate_bidv_report.R, which is not a
    # registry Step, so it has no producer to derive a dependency edge from.
    .artifact_row("bidv_framework_report", "reports", "engagement", NA_character_, NA_character_, "html",
                  file.path(R, "BIDV_Framework_Recommendation_Report.html"), NA_character_,
                  gated_html = TRUE, disclaimer_required = TRUE),
    .artifact_row("refresh_audit_report", "reports", "engagement", NA_character_, "refresh_audit", "html",
                  file.path(R, "pipeline_refresh_audit.html"), NA_character_,
                  gated_html = TRUE, disclaimer_required = TRUE),
    .artifact_row("refresh_audit_metrics", "reports", "engagement", NA_character_, "refresh_audit", "json",
                  file.path(R, "refresh_audit_metrics.json"), NA_character_,
                  timestamp_class = TRUE),
    .artifact_row("intake_validation_report", "reports", "engagement", NA_character_, "validation_report", "html",
                  file.path(R, "Intake_Validation_Report.html")),
    .artifact_row("coverage_report", "reports", "engagement", NA_character_, "coverage_report", "html",
                  file.path(R, "Coverage_Reconciliation_Report.html")),
    .artifact_row("vintage_comparison_report", "reports", "engagement", NA_character_, "compare_scenario_vintages", "html",
                  file.path(R, "Scenario_Vintage_Comparison.html")),
    .artifact_row("disclosure_pack", "reports", "engagement", NA_character_, "generate_disclosure_pack", "html",
                  file.path(D, "disclosure_pack.html"), NA_character_,
                  disclaimer_required = TRUE),
    .artifact_row("letters_index", "reports", "engagement", NA_character_, "generate_engagement_letters", "html",
                  file.path(L, "index.html"), NA_character_,
                  disclaimer_required = TRUE)
  ))
}

# Sector-scoped catalog rows for one sector, in the S1 table order.
# @param cfg list — the loaded engagement config.
# @param sector character(1) — one configured TRISK sector.
# @return data.frame of that sector's rows.
.artifact_rows_sector <- function(cfg, sector) {
  T <- cfg$paths$trisk_output_root
  I <- cfg$paths$trisk_input_root
  S <- cfg$paths$snapshot_dir
  demo <- paste0(sector, "_demo")
  input_dir <- file.path(I, demo)
  output_dir <- file.path(T, demo)
  snap_dir <- file.path(S, "trisk", sector)
  grid_out <- file.path(T, "grid", sector)
  grid_snap <- file.path(S, "trisk", "grid", sector)

  .artifact_bind(list(
    .artifact_row("assets", "trisk_input", "sector", sector, "trisk_prepare_inputs", "csv",
                  file.path(input_dir, "assets.csv"), file.path(snap_dir, "assets.csv")),
    .artifact_row("financial_features", "trisk_input", "sector", sector, "trisk_prepare_inputs", "csv",
                  file.path(input_dir, "financial_features.csv"), file.path(snap_dir, "financial_features.csv")),
    .artifact_row("carbon_price", "trisk_input", "sector", sector, "trisk_prepare_inputs", "csv",
                  file.path(input_dir, "ngfs_carbon_price.csv"), file.path(snap_dir, "ngfs_carbon_price.csv")),
    .artifact_row("scenarios", "trisk_input", "sector", sector, "trisk_prepare_inputs", "csv",
                  file.path(input_dir, "scenarios.csv"), file.path(snap_dir, "scenarios.csv")),
    .artifact_row("company_summary", "trisk", "sector", sector, "trisk_sector_demo", "csv",
                  file.path(output_dir, "company_summary.csv"), file.path(snap_dir, "company_summary.csv")),
    .artifact_row("company_trajectories", "trisk", "sector", sector, "trisk_sector_demo", "csv",
                  file.path(output_dir, "company_trajectories_latest.csv"),
                  file.path(snap_dir, "company_trajectories_latest.csv")),
    .artifact_row("npv_results", "trisk", "sector", sector, "trisk_sector_demo", "csv",
                  file.path(output_dir, "npv_results_latest.csv"), file.path(snap_dir, "npv_results_latest.csv")),
    .artifact_row("params", "trisk", "sector", sector, "trisk_sector_demo", "csv",
                  file.path(output_dir, "params_latest.csv"), file.path(snap_dir, "params_latest.csv")),
    .artifact_row("pd_results", "trisk", "sector", sector, "trisk_sector_demo", "csv",
                  file.path(output_dir, "pd_results_latest.csv"), file.path(snap_dir, "pd_results_latest.csv")),
    .artifact_row("pd_summary", "trisk", "sector", sector, "trisk_sector_demo", "csv",
                  file.path(output_dir, "pd_summary.csv"), file.path(snap_dir, "pd_summary.csv")),
    .artifact_row("run_catalog", "trisk", "sector", sector, "trisk_sector_demo", "csv",
                  file.path(output_dir, "run_catalog.csv"), file.path(snap_dir, "run_catalog.csv")),
    .artifact_row("sensitivity_results", "trisk", "sector", sector, "trisk_sector_demo", "csv",
                  file.path(output_dir, "sensitivity_results.csv"),
                  file.path(snap_dir, "sensitivity_results.csv")),
    .artifact_row("sensitivity_summary", "trisk", "sector", sector, "trisk_sector_demo", "csv",
                  file.path(output_dir, "sensitivity_summary.csv"),
                  file.path(snap_dir, "sensitivity_summary.csv")),
    .artifact_row("top_borrowers", "trisk", "sector", sector, "trisk_sector_demo", "csv",
                  file.path(output_dir, "top_borrowers_alignment_trisk.csv"),
                  file.path(snap_dir, "top_borrowers_alignment_trisk.csv")),
    .artifact_row("trisk_figures", "trisk", "sector", sector, "trisk_sector_demo", "png_group",
                  file.path(output_dir, "figures"), snap_dir),
    .artifact_row("grid_scenarios", "grid", "sector", sector, "trisk_scenario_grid", "csv",
                  file.path(grid_out, "scenarios.csv"), file.path(grid_snap, "scenarios.csv")),
    .artifact_row("grid_borrower_results", "grid", "sector", sector, "trisk_scenario_grid", "parquet",
                  file.path(grid_out, "borrower_results.parquet"),
                  file.path(grid_snap, "borrower_results.parquet")),
    .artifact_row("grid_meta", "grid", "sector", sector, "trisk_scenario_grid", "json",
                  file.path(grid_out, "grid_meta.json"), file.path(grid_snap, "grid_meta.json"))
  ))
}

# Every registry step key that produces at least one catalog Artifact.
#
# The producer column is part of the catalog definition, not of a resolved
# config, so the step registry can decide *whether* a step carries a derived
# `produces_fn` without a config in hand (TASK-02-02). The catalog test asserts
# this set equals `unique(artifact_catalog(cfg)$producer)` minus NA.
#
# @return character — producer keys named by the catalog row definitions.
.artifact_catalog_producers <- function() {
  c(
    "intake",
    "pacta_vietnam_scenario",
    "refresh_dashboard_data",
    "run_engagement",
    "sector_prioritization",
    "engagement_scoring",
    "financed_emissions",
    "generate_targets",
    "sll_readiness",
    "validation_report",
    "coverage_report",
    "compare_scenario_vintages",
    "refresh_audit",
    "generate_disclosure_pack",
    "generate_engagement_letters",
    "trisk_prepare_inputs",
    "trisk_sector_demo",
    "trisk_scenario_grid"
  )
}

# Stop, naming the first config path key the catalog needs but cannot find.
# @param cfg list — the loaded engagement config.
# @return invisible TRUE; stops when a required path key is missing.
.artifact_require_paths <- function(cfg) {
  required <- c(
    "pacta_output_dir", "trisk_output_root", "trisk_input_root", "snapshot_dir",
    "reports_dir", "engagement_output_dir", "financed_emissions_output_dir",
    "prioritization_output_dir", "letters_output_dir", "disclosure_output_dir"
  )
  for (name in required) {
    value <- cfg$paths[[name]]
    if (is.null(value) || length(value) == 0 || all(is.na(value)) || !nzchar(as.character(value[[1]]))) {
      stop(sprintf("artifact_catalog: cfg$paths$%s is missing", name), call. = FALSE)
    }
  }
  invisible(TRUE)
}

#' The resolved Artifact catalog for one engagement.
#'
#' Builds the engagement-scoped rows, then one sector-scoped block per sector
#' in `cfg$trisk_sectors` order, so the row order is deterministic (the JSON
#' export and the byte-identity gate both depend on that).
#'
#' @param cfg list — the loaded engagement config.
#' @return data.frame with the columns of `.artifact_catalog_columns()`, in
#'   that order: engagement rows first, then sector rows grouped by sector.
#' @export
artifact_catalog <- function(cfg) {
  .artifact_require_paths(cfg)
  rows <- list(.artifact_rows_engagement(cfg))
  for (sector in cfg$trisk_sectors) {
    rows[[length(rows) + 1]] <- .artifact_rows_sector(cfg, sector)
  }
  out <- .artifact_bind(rows)
  duplicated_key <- duplicated(paste(out$key, out$sector))
  if (any(duplicated_key)) {
    dupes <- unique(paste(out$key[duplicated_key], out$sector[duplicated_key], sep = "/"))
    stop(sprintf("artifact_catalog: duplicate key(s): %s", paste(dupes, collapse = ", ")), call. = FALSE)
  }
  out[, .artifact_catalog_columns(), drop = FALSE]
}

#' Resolve one Artifact location by key.
#'
#' @param cfg list — the loaded engagement config.
#' @param key character(1) — a catalog key.
#' @param sector character(1)|NULL — the sector for a sector-scoped key; NULL
#'   returns every configured sector, in `cfg$trisk_sectors` order.
#' @param where character(1) — "output" (the producer's own location) or
#'   "snapshot" (the location the dashboard reads).
#' @return character — the repo-relative path(s). Length 1 for an
#'   engagement-scoped key; length `length(cfg$trisk_sectors)` for a
#'   sector-scoped key resolved without a sector.
#' @export
artifact_path <- function(cfg, key, sector = NULL, where = "output") {
  where <- match.arg(where, c("output", "snapshot"))
  catalog <- artifact_catalog(cfg)
  hit <- catalog[catalog$key == key, , drop = FALSE]
  if (nrow(hit) == 0) {
    stop(sprintf(
      "artifact_path: unknown artifact key '%s' (known: %s)",
      key, paste(unique(catalog$key), collapse = ", ")
    ), call. = FALSE)
  }
  if (!is.null(sector)) {
    if (all(is.na(hit$sector))) {
      stop(sprintf("artifact_path: '%s' is not sector-scoped", key), call. = FALSE)
    }
    hit <- hit[!is.na(hit$sector) & hit$sector == sector, , drop = FALSE]
    if (nrow(hit) == 0) {
      scoped <- catalog[!is.na(catalog$sector), , drop = FALSE]
      stop(sprintf(
        "artifact_path: unknown sector '%s' for artifact key '%s' (known: %s)",
        sector, key, paste(unique(scoped$sector), collapse = ", ")
      ), call. = FALSE)
    }
  }
  values <- hit[[if (identical(where, "snapshot")) "snapshot_path" else "path"]]
  if (identical(where, "snapshot") && any(is.na(values))) {
    stop(sprintf("artifact_path: '%s' has no snapshot location", key), call. = FALSE)
  }
  values
}

#' Write the machine-readable catalog export the dashboard reads.
#'
#' Only rows with a Snapshot location are exported, and `snapshot_path` is
#' relative to the Snapshot root (the `dashboard/data/` prefix is stripped).
#' The file carries no timestamp and its rows follow catalog order, so two
#' runs produce byte-identical bytes -- the gate compares it like any other
#' Snapshot artifact.
#'
#' @param cfg list — the loaded engagement config.
#' @param path character(1) — where to write the JSON.
#' @return invisible(path).
#' @export
write_artifact_catalog_json <- function(cfg, path) {
  catalog <- artifact_catalog(cfg)
  catalog <- catalog[!is.na(catalog$snapshot_path), , drop = FALSE]
  prefix_len <- nchar(cfg$paths$snapshot_dir) + 2L # + "/"
  artifacts <- lapply(seq_len(nrow(catalog)), function(i) {
    list(
      key = catalog$key[[i]],
      group = catalog$group[[i]],
      scope = catalog$scope[[i]],
      sector = catalog$sector[[i]],
      producer = catalog$producer[[i]],
      kind = catalog$kind[[i]],
      snapshot_path = substring(catalog$snapshot_path[[i]], prefix_len)
    )
  })
  payload <- list(
    schema_version = 1L,
    bank_slug = cfg$bank_slug,
    sectors = cfg$trisk_sectors,
    artifacts = artifacts
  )
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(
    jsonlite::toJSON(payload, auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null"),
    path
  )
  invisible(path)
}
