#!/usr/bin/env Rscript
# refresh_dashboard_data.R
# Republish the dashboard data snapshot from current pipeline outputs.
# Usage: Rscript scripts/refresh_dashboard_data.R [--config <path>]
#
# PHASE-03 of plans/2026-09-13-artifact-catalog-plan.md: every path this script
# copies, and every path it skips, comes from R/artifact_catalog.R -- the single
# owner of Artifact locations (ADR-0001). The script keeps its own copy
# mechanics (copy_file/copy_png_group), its published-report cross-check, and
# its exit status; it no longer spells a single CSV basename.
#
# It also writes <snapshot_dir>/artifact_catalog.json: the machine-readable
# export the Streamlit app resolves every table path from.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
  library(jsonlite)
})

source("R/engagement_config.R")
source("R/artifact_catalog.R")
source("R/sector_registry.R")

cfg <- load_engagement_config(get_config_arg())
catalog <- artifact_catalog(cfg)

clear_dir <- function(path) {
  if (dir.exists(path)) {
    unlink(list.files(path, full.names = TRUE, all.files = TRUE, no.. = TRUE), recursive = TRUE, force = TRUE)
  }
}

# Required artifacts that fail to copy are collected here; the script exits
# non-zero at the end if any are missing, so a partial upstream run can never
# silently publish a half-populated snapshot.
misses_required <- character(0)

record_miss <- function(src, required) {
  message(sprintf("  [MISS] %s not found", src))
  if (required) {
    misses_required <<- c(misses_required, src)
  }
}

copy_file <- function(src, dest_dir, required = TRUE) {
  if (!dir.exists(dest_dir)) dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  if (file.exists(src)) {
    file.copy(src, dest_dir, overwrite = TRUE)
    message(sprintf("  [OK] %s -> %s", src, dest_dir))
    invisible(TRUE)
  } else {
    record_miss(src, required)
    invisible(FALSE)
  }
}

copy_png_group <- function(src_dir, dest_dir, required = TRUE) {
  if (!dir.exists(src_dir)) {
    record_miss(paste0(src_dir, " (directory)"), required)
    return(invisible(NULL))
  }
  if (!dir.exists(dest_dir)) dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  pngs <- list.files(src_dir, pattern = "\\.png$", full.names = TRUE)
  if (length(pngs) == 0) {
    record_miss(paste0(src_dir, " (no PNGs)"), required)
    return(invisible(NULL))
  }
  for (f in pngs) {
    file.copy(f, dest_dir, overwrite = TRUE)
    message(sprintf("  [OK] %s -> %s", f, dest_dir))
  }
}

# Copy one catalog row: a single file into the directory its Snapshot path
# names, or a PNG group from directory to directory.
copy_row <- function(row, required = TRUE) {
  if (identical(row$kind[[1]], "png_group")) {
    copy_png_group(row$path[[1]], row$snapshot_path[[1]], required = required)
  } else {
    copy_file(row$path[[1]], dirname(row$snapshot_path[[1]]), required = required)
  }
}

# Wave 3 PHASE-02 (DEC-006): the published report set is config-declared
# (cfg$published_reports) and cross-checked against reports/report_catalog.json
# rather than hardcoded here. A file named in published_reports that is absent
# from the catalog, or present with category "internal_build", is a hard
# error -- this is what keeps an internal engineering phase report or a
# European-demo-data report from silently reaching the public snapshot again.
# (report_catalog.json is Deliverable *metadata*, not an Artifact location;
# the artifact catalog's `reports` rows are about where the generator writes.)
report_catalog_path <- "reports/report_catalog.json"
report_catalog <- if (file.exists(report_catalog_path)) {
  jsonlite::fromJSON(report_catalog_path, simplifyVector = TRUE)
} else {
  list()
}

for (fname in cfg$published_reports) {
  entry <- report_catalog[[fname]]
  if (is.null(entry)) {
    stop(sprintf(
      "refresh_dashboard_data.R: '%s' is named in published_reports but has no entry in %s",
      fname, report_catalog_path
    ), call. = FALSE)
  }
  if (identical(entry$category, "internal_build")) {
    stop(sprintf(
      "refresh_dashboard_data.R: '%s' is category \"internal_build\" in %s and may not be published",
      fname, report_catalog_path
    ), call. = FALSE)
  }
}

report_files <- file.path("reports", cfg$published_reports)

snapshot_dir <- cfg$paths$snapshot_dir

# Only rows with a Snapshot location are the copier's business. The
# `trisk_manifest` and `pipeline_manifest` rows are produced *in* the Snapshot
# by this script and by the orchestrator, so they are never copied.
snapshot_rows <- catalog[!is.na(catalog$snapshot_path), , drop = FALSE]

trisk_manifest <- sector_registry() %>%
  filter(sector %in% cfg$trisk_sectors) %>%
  select(sector, label, folder, price_unit, pathway_unit, alignment_mode, grid_available, disclaimer)

# --- PACTA tables, then the PACTA figure group --------------------------------
pacta_rows <- snapshot_rows[snapshot_rows$group == "pacta", , drop = FALSE]
for (i in seq_len(nrow(pacta_rows))) {
  copy_row(pacta_rows[i, , drop = FALSE])
}

# Reports are optional (warn only): a missing rendered report should not block
# the data snapshot from publishing.
for (f in report_files) {
  copy_file(f, file.path(snapshot_dir, "reports"), required = FALSE)
}
if (file.exists(report_catalog_path)) {
  copy_file(report_catalog_path, file.path(snapshot_dir, "reports"), required = FALSE)
}

# --- TRISK per sector: files, then figures, then the scenario grid -------------
trisk_dest <- file.path(snapshot_dir, "trisk")
if (!dir.exists(trisk_dest)) dir.create(trisk_dest, recursive = TRUE)
clear_dir(trisk_dest)

grid_root <- file.path(trisk_dest, "grid")
dir.create(grid_root, recursive = TRUE, showWarnings = FALSE)

sector_rows <- snapshot_rows[snapshot_rows$scope == "sector", , drop = FALSE]

for (i in seq_len(nrow(trisk_manifest))) {
  sector <- trisk_manifest$sector[[i]]
  dest_root <- file.path(trisk_dest, sector)
  if (!dir.exists(dest_root)) dir.create(dest_root, recursive = TRUE, showWarnings = FALSE)

  rows <- sector_rows[sector_rows$sector == sector & sector_rows$group != "grid", , drop = FALSE]
  for (j in seq_len(nrow(rows))) {
    if (identical(rows$kind[[j]], "png_group")) next
    copy_row(rows[j, , drop = FALSE])
  }
  for (j in seq_len(nrow(rows))) {
    if (!identical(rows$kind[[j]], "png_group")) next
    copy_row(rows[j, , drop = FALSE])
  }

  # The app reads only the consolidated grid artifacts; raw per-run CSVs under
  # runs/ stay in synthesis_output and are never published to the snapshot.
  grid_rows <- sector_rows[sector_rows$sector == sector & sector_rows$group == "grid", , drop = FALSE]
  for (j in seq_len(nrow(grid_rows))) {
    copy_row(grid_rows[j, , drop = FALSE], required = cfg$run_grid)
  }
  trisk_manifest$grid_available[[i]] <- all(file.exists(grid_rows$snapshot_path))
}

manifest_path <- artifact_path(cfg, "trisk_manifest")
write_csv(trisk_manifest, manifest_path)
message(sprintf("  [OK] %s written", manifest_path))

# --- Wave 3 analytics as DATA, not just as rendered HTML (Wave 4 PHASE-06) ---
# The PCAF inventory, the sector target registry and the SLL shortlist reached
# the dashboard only as static <snapshot>/reports/*.html, so a bank evaluator
# could filter and drill into PACTA and TRISK but could only scroll a picture of
# the financed-emissions layer the BIDV MoU names first. Copy the underlying
# CSVs into <snapshot>/analytics/ so the app can read them like any other table.
#
# Each file is copied only when it exists: an engagement that did not run
# financed emissions, targets or the SLL screen still refreshes cleanly.
analytics_rows <- snapshot_rows[snapshot_rows$group == "analytics", , drop = FALSE]
for (i in seq_len(nrow(analytics_rows))) {
  src <- analytics_rows$path[[i]]
  if (file.exists(src)) {
    copy_file(src, dirname(analytics_rows$snapshot_path[[i]]))
  } else {
    message(sprintf("  [SKIP] %s not present for this engagement", src))
  }
}

# --- The catalog the dashboard reads (PHASE-03) -------------------------------
catalog_path <- file.path(snapshot_dir, "artifact_catalog.json")
write_artifact_catalog_json(cfg, catalog_path)
message(sprintf("  [OK] %s written", catalog_path))

if (length(misses_required) > 0) {
  message("\nMISSING REQUIRED artifacts — snapshot refresh FAILED:")
  for (m in unique(misses_required)) message(sprintf("  - %s", m))
  quit(status = 1)
}

message("Dashboard data snapshot refreshed.")
