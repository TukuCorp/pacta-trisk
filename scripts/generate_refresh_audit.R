#!/usr/bin/env Rscript
# generate_refresh_audit.R
# Generates a per-refresh audit report with checksums, coverage metrics,
# and a diff against the previous run's metrics.
#
# Usage: Rscript scripts/generate_refresh_audit.R [--config <path>]
#
# Reads: <snapshot_dir>/pipeline_manifest.json, key pipeline outputs
# Writes: <reports_dir>/pipeline_refresh_audit.html,
#         <reports_dir>/refresh_audit_metrics.json
#
# Wave 4 PHASE-02: this script used to hardcode every path it touched,
# including a hardcoded 2023 scenario-vintage directory. Once mcb-demo moved to
# the adjusted-2025 vintage in Wave 3 PHASE-03, the audit went on publishing
# the checksums of scenario files the pipeline had not read -- an audit
# artifact attesting to the wrong inputs. Every path now derives from the
# engagement config (CLAUDE.md law 6). Invoked with no --config flag it falls
# back to load_engagement_config(NULL)'s built-in MCB defaults, so a bare
# `Rscript scripts/generate_refresh_audit.R` behaves as it always did.

suppressPackageStartupMessages({
  library(jsonlite)
  library(dplyr)
  library(readr)
})

source("R/engagement_config.R")
source("R/artifact_catalog.R")

cfg <- load_engagement_config(get_config_arg())

# Every Artifact this audit reads or writes is located by the catalog
# (ADR-0001); the metrics sidecar's vintage field below is what makes the
# attestation checkable.
manifest_path <- artifact_path(cfg, "pipeline_manifest")
out_html <- artifact_path(cfg, "refresh_audit_report")
metrics_path <- artifact_path(cfg, "refresh_audit_metrics")

if (!file.exists(manifest_path)) {
  stop(sprintf("%s not found. Run the pipeline first.", manifest_path))
}

manifest <- fromJSON(readLines(manifest_path, warn = FALSE), simplifyVector = FALSE)

generated_at <- manifest$generated_at
git_sha <- manifest$git_sha %||% "unknown"
step_timings <- manifest$steps

# The engagement's own declared inputs -- never a hardcoded vintage.
scenario_ms_csv <- cfg$inputs$scenario_ms_csv
scenario_co2_csv <- cfg$inputs$scenario_co2_csv
input_files <- c(
  cfg$inputs$loanbook_csv,
  cfg$inputs$abcd_csv,
  scenario_ms_csv,
  scenario_co2_csv
)

input_checksums <- list()
for (f in input_files) {
  if (file.exists(f)) {
    input_checksums[[f]] <- unname(tools::md5sum(f))
  }
}

pacta_matched_path <- artifact_path(cfg, "matches", where = "snapshot")
pacta_coverage <- list()
if (file.exists(pacta_matched_path)) {
  matched <- read_csv(pacta_matched_path, show_col_types = FALSE)
  if ("sector_abcd" %in% names(matched)) {
    pacta_coverage <- as.list(table(matched$sector_abcd))
  }
}

trisk_top_path <- artifact_path(cfg, "top_borrowers", sector = "power", where = "snapshot")
trisk_top5 <- data.frame()
if (file.exists(trisk_top_path)) {
  tb <- read_csv(trisk_top_path, show_col_types = FALSE)
  if (nrow(tb) > 0 && "stress_priority_score" %in% names(tb)) {
    trisk_top5 <- head(tb[order(-tb$stress_priority_score), c("company_name", "stress_priority_score")], 5)
  }
}

engagement_path <- artifact_path(cfg, "engagement_priority")
engagement_top5 <- data.frame()
if (file.exists(engagement_path)) {
  ep <- read_csv(engagement_path, show_col_types = FALSE)
  if (nrow(ep) > 0 && "composite_score" %in% names(ep)) {
    engagement_top5 <- head(ep[order(-ep$composite_score), c("name_abcd", "composite_score")], 5)
  }
}

prev_metrics <- NULL
if (file.exists(metrics_path)) {
  prev_metrics <- fromJSON(readLines(metrics_path, warn = FALSE), simplifyVector = FALSE)
}

current_metrics <- list(
  generated_at = generated_at,
  git_sha = git_sha,
  n_pacta_matched = if (file.exists(pacta_matched_path)) nrow(read_csv(pacta_matched_path, show_col_types = FALSE)) else 0,
  n_engagement = if (file.exists(engagement_path)) nrow(read_csv(engagement_path, show_col_types = FALSE)) else 0,
  top_trisk_borrower = if (nrow(trisk_top5) > 0) trisk_top5$company_name[1] else NA_character_,
  top_engagement = if (nrow(engagement_top5) > 0) engagement_top5$name_abcd[1] else NA_character_,
  scenario_ms_checksum = input_checksums[[scenario_ms_csv]] %||% NA_character_,
  scenario_co2_checksum = input_checksums[[scenario_co2_csv]] %||% NA_character_,
  # Wave 4 PHASE-02: record WHICH vintage the checksums above belong to, so a
  # reader (and INV-012) can tell at a glance whether the audit attests to the
  # engagement's configured inputs.
  scenario_vintage = cfg$inputs$scenario_vintage %||% NA_character_
)

write(toJSON(current_metrics, auto_unbox = TRUE, pretty = TRUE), metrics_path)

cat("Building audit HTML...\n")

step_rows <- ""
for (s in step_timings) {
  step_rows <- paste0(step_rows, sprintf(
    "<tr><td>%s</td><td>%s</td><td>%.1fs</td></tr>\n",
    s$name, s$status, s$seconds
  ))
}

checksum_rows <- ""
for (nm in names(input_checksums)) {
  checksum_rows <- paste0(checksum_rows, sprintf(
    "<tr><td><code>%s</code></td><td><code>%s</code></td></tr>\n",
    nm, input_checksums[[nm]]
  ))
}

coverage_rows <- ""
for (nm in names(pacta_coverage)) {
  coverage_rows <- paste0(coverage_rows, sprintf(
    "<tr><td>%s</td><td>%d</td></tr>\n",
    nm, pacta_coverage[[nm]]
  ))
}

trisk_rows <- ""
if (nrow(trisk_top5) > 0) {
  for (i in seq_len(nrow(trisk_top5))) {
    trisk_rows <- paste0(trisk_rows, sprintf(
      "<tr><td>%s</td><td>%.2f</td></tr>\n",
      trisk_top5$company_name[i], trisk_top5$stress_priority_score[i]
    ))
  }
}

engagement_rows <- ""
if (nrow(engagement_top5) > 0) {
  for (i in seq_len(nrow(engagement_top5))) {
    engagement_rows <- paste0(engagement_rows, sprintf(
      "<tr><td>%s</td><td>%.4f</td></tr>\n",
      engagement_top5$name_abcd[i], engagement_top5$composite_score[i]
    ))
  }
}

diff_rows <- ""
if (!is.null(prev_metrics)) {
  fields <- c("n_pacta_matched", "n_engagement", "top_trisk_borrower", "top_engagement",
              "scenario_ms_checksum", "scenario_co2_checksum", "scenario_vintage")
  for (f in fields) {
    prev_val <- prev_metrics[[f]] %||% "N/A"
    curr_val <- current_metrics[[f]] %||% "N/A"
    marker <- if (identical(prev_val, curr_val)) "" else "<strong>CHANGED</strong>"
    diff_rows <- paste0(diff_rows, sprintf(
      "<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n",
      f, as.character(prev_val), as.character(curr_val), marker
    ))
  }
} else {
  diff_rows <- "<tr><td colspan='4'><em>No previous metrics found — this is the first run.</em></td></tr>\n"
}

html <- paste0('<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Pipeline Refresh Audit</title>
<style>
  body { font-family: system-ui, sans-serif; max-width: 900px; margin: 2rem auto; padding: 0 1rem; color: #2d3748; }
  h1 { color: #1a365d; border-bottom: 2px solid #e2e8f0; padding-bottom: 0.5rem; }
  h2 { color: #2b6cb0; margin-top: 2rem; }
  table { width: 100%; border-collapse: collapse; margin: 1rem 0; font-size: 0.9rem; }
  th { background: #1a365d; color: white; padding: 0.5rem; text-align: left; }
  td { padding: 0.5rem; border-bottom: 1px solid #e2e8f0; }
  tr:nth-child(even) { background: #f7fafc; }
  code { background: #edf2f7; padding: 0.1rem 0.3rem; border-radius: 3px; font-size: 0.85rem; }
  .meta { color: #718096; font-size: 0.85rem; }
</style>
</head>
<body>

<h1>Pipeline Refresh Audit</h1>
<p class="meta">Generated: ', generated_at, ' &middot; Commit: <code>', substr(git_sha, 1, 7), '</code></p>

<h2>Step Timings</h2>
<table>
<tr><th>Step</th><th>Status</th><th>Duration</th></tr>
', step_rows, '
</table>

<h2>Input Checksums (MD5)</h2>
<table>
<tr><th>File</th><th>Checksum</th></tr>
', checksum_rows, '
</table>

<h2>PACTA Match Coverage by Sector</h2>
<table>
<tr><th>Sector</th><th>Matched Rows</th></tr>
', coverage_rows, '
</table>

<h2>Top 5 TRISK Borrowers (Power — Stress Priority)</h2>
<table>
<tr><th>Company</th><th>Score</th></tr>
', trisk_rows, '
</table>

<h2>Top 5 Engagement Priority</h2>
<table>
<tr><th>Company</th><th>Composite Score</th></tr>
', engagement_rows, '
</table>

<h2>Changes Since Last Run</h2>
<table>
<tr><th>Metric</th><th>Previous</th><th>Current</th><th>Status</th></tr>
', diff_rows, '
</table>

<footer style="margin-top:2rem;padding-top:1rem;border-top:1px solid #e2e8f0;color:#718096;font-size:0.85rem;">
Synthetic data &mdash; illustrative only. Requires human &amp; legal review before any
external use. / D&#7919; li&#7879;u m&#244; ph&#7887;ng &mdash; ch&#7881; mang t&#237;nh minh h&#7885;a.
C&#7847;n r&#224; so&#225;t c&#7911;a con ng&#432;&#7901;i &amp; ph&#225;p l&#253; tr&#432;&#7899;c khi s&#7917; d&#7909;ng ra ngo&#224;i.
</footer>

</body>
</html>')

dir.create(dirname(out_html), showWarnings = FALSE, recursive = TRUE)
writeLines(html, out_html)
cat(sprintf("Audit report saved to: %s\n", out_html))
cat(sprintf("Metrics saved to: %s\n", metrics_path))
