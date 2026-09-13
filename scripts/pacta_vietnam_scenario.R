# ==============================================================================
# pacta_vietnam_scenario.R
# Vietnam-specific PACTA pipeline. Defaults to the synthetic Mekong
# Commercial Bank (MCB) demo; pass --config <path> to run against any
# engagement config (see R/engagement_config.R).
#
# Demonstrates climate alignment of a synthetic Vietnamese commercial bank
# loanbook against Vietnam's Power Development Plan 8 (PDP8), NDC targets,
# and global IEA NZE benchmarks.
#
# Prerequisites: run scripts/generate_vietnam_data.R first to produce input CSVs.
#
# Run from project root:
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" scripts/pacta_vietnam_scenario.R
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" scripts/pacta_vietnam_scenario.R --config engagements/<slug>/engagement_config.json
#
# This is a thin orchestration wrapper: all analysis logic lives in
# R/pacta_core.R as individually testable functions (see
# tests/testthat/test_pacta_core.R), called here in the same order as the
# original 9-section monolith.
# ==============================================================================

library(pacta.loanbook)
library(r2dii.data)
library(r2dii.match)
library(r2dii.analysis)
library(r2dii.plot)
library(dplyr)
library(tidyr)
library(ggplot2)
library(scales)
library(ggrepel)
library(base64enc)
library(readr)
library(stringi)

source("R/engagement_config.R")
source("R/artifact_catalog.R")
source("R/sector_registry.R")
source("R/report_toolkit.R")
source("R/matching_helpers.R")
source("R/format_money.R")
source("R/report_facts.R")
source("R/pacta_core.R")

cfg <- load_engagement_config(get_config_arg())
bank_name  <- cfg$bank_name
bank_short <- if (identical(bank_name, "Mekong Commercial Bank")) "MCB" else bank_name

cat("========================================\n")
cat(sprintf("PACTA VIETNAM: %s\n", bank_name))
cat("========================================\n\n")

# --- Output directories ---
vn_output  <- file.path(getwd(), cfg$paths$pacta_output_dir)
report_dir <- file.path(getwd(), cfg$paths$reports_dir)
dir.create(vn_output,  showWarnings = FALSE, recursive = TRUE)
dir.create(report_dir, showWarnings = FALSE, recursive = TRUE)

inputs <- pacta_load_inputs(cfg)

loanbook_classified <- pacta_prejoin_sectors(inputs$loanbook)

matches <- pacta_match_and_prioritize(loanbook_classified, inputs$abcd, vn_output)

coverage <- pacta_coverage(loanbook_classified, matches$prioritized, vn_output, bank_name, bank_short)

# Wave 3 PHASE-03: the scenario CSV's scenario_source value for the
# configured vintage -- e.g. inputs.scenario_vintage "pdp8-2023" (hyphen,
# directory name) -> scenario_source "pdp8_2023" (underscore, CSV column
# value). Every vintage this repo ships follows that same
# hyphen-to-underscore convention (see data/scenarios/*/SOURCE.md).
pdp8_scenario_source <- gsub("-", "_", cfg$inputs$scenario_vintage)

ms <- pacta_market_share(matches$prioritized, matches$abcd_norm, inputs$scenario, inputs$region,
                          vn_output, bank_short, pdp8_scenario_source = pdp8_scenario_source)

sda <- pacta_sda(matches$prioritized, matches$abcd_norm, inputs$co2, vn_output, bank_short)

gaps <- pacta_alignment_gaps(ms$ms_portfolio, ms$target_pdp8, sda$sda_portfolio, sda$sda_target_pdp8,
                              inputs$loanbook, vn_output, bank_short)

imgs <- pacta_encode_charts(vn_output)

report_path <- pacta_build_report(bank_name, bank_short, inputs$loanbook, matches$prioritized,
                                   gaps$ms_alignment_2030, gaps$sda_alignment_2030, imgs, report_dir,
                                   fx_rate_usd_vnd = cfg$inputs$fx_rate_usd_vnd)

# Wave 5 PHASE-03: facts sidecar -- headline figures recomputed from source
# CSVs and asserted by INV-013, so a wrong number fails a gate instead of
# being frozen by one.
pacta_report_rel <- artifact_path(cfg, "pacta_bank_report")
pacta_loanbook_total <- sum(inputs$loanbook$loan_size_outstanding)
pacta_matched_rel <- artifact_path(cfg, "matches")
pacta_matched_check <- utils::read.csv(pacta_matched_rel, stringsAsFactors = FALSE)
pacta_facts <- list(
  report_fact("portfolio_total_vnd", pacta_loanbook_total, cfg$inputs$loanbook_csv,
              "sum", column = "loan_size_outstanding", unit = "VND",
              rendered = format_vnd_bn(pacta_loanbook_total)),
  report_fact("n_loans", nrow(inputs$loanbook), cfg$inputs$loanbook_csv,
              "nrow", unit = "loans", rendered = as.character(nrow(inputs$loanbook))),
  report_fact("n_matched", nrow(pacta_matched_check),
              pacta_matched_rel,
              "nrow", unit = "loans", rendered = as.character(nrow(pacta_matched_check)))
)
write_report_facts(pacta_facts, pacta_report_rel, "scripts/pacta_vietnam_scenario.R")

# ==============================================================================
# FINAL SUMMARY
# ==============================================================================

n_loans   <- nrow(inputs$loanbook)
n_matched <- nrow(matches$prioritized)
total_portfolio_vnd <- sum(inputs$loanbook$loan_size_outstanding)

cat("========================================\n")
cat("PACTA Vietnam pipeline complete\n")
cat("========================================\n\n")
cat(sprintf("  Loanbook analysed : %d loans / %s\n",
            n_loans, format_vnd_bn(total_portfolio_vnd)))
cat(sprintf("  Matched to ABCD   : %d loans (%.1f%%)\n",
            n_matched, n_matched / n_loans * 100))
cat(sprintf("  Sectors analysed  : %s\n",
            paste(unique(matches$prioritized$sector), collapse = ", ")))
cat(sprintf("  Output directory  : %s\n", vn_output))
cat(sprintf("  HTML report       : %s\n\n", report_path))

cat("Key alignment findings (vs PDP8/NDC at 2030):\n")
if (nrow(gaps$ms_alignment_2030) > 0) {
  gaps$ms_alignment_2030 %>%
    mutate(
      proj_pct = round(projected * 100, 1),
      tgt_pct  = round(target_pdp8 * 100, 1)
    ) %>%
    select(sector, technology, proj_pct, tgt_pct, share_gap_pp, aligned) %>%
    arrange(sector, technology) %>%
    as.data.frame() %>%
    print()
}
cat("\nSDA alignment (vs PDP8/NDC at 2030):\n")
if (nrow(gaps$sda_alignment_2030) > 0) {
  print(as.data.frame(gaps$sda_alignment_2030 %>%
    select(sector, projected, target_pdp8, intensity_gap, aligned)))
}
cat("\nDone.\n")
