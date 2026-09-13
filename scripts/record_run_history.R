#!/usr/bin/env Rscript
# ==============================================================================
# record_run_history.R
# Wave 3 PHASE-04: thin pipeline-step wrapper around R/run_history.R's
# record_run_history(). Registered as the last step for engagements with
# run_history: true (only mcb-demo, initially -- see R/engagement_config.R).
#
# Usage: Rscript scripts/record_run_history.R --config <path>
# ==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

source("R/engagement_config.R")
source("R/artifact_catalog.R")
source("R/run_history.R")

cfg <- load_engagement_config(get_config_arg())

# The headline artifacts worth keeping across time -- deliberately not the
# full output tree (history/ would grow without bound otherwise). Which
# artifacts count as headlines is the catalog's `history_headline` flag
# (ADR-0001), so promoting a new artifact into history is a catalog-row
# change, not a change here.
headlines <- artifact_catalog(cfg)
artifacts <- headlines$path[headlines$history_headline]

history_root <- cfg$paths$history_dir %||% "history"

# Wave 4 PHASE-06: record_run_history() refuses to overwrite an existing run
# directory, which is the right append-only contract for a direct caller. As a
# PIPELINE STEP, though, re-running the same engagement on the same day at the
# same commit and vintage is a no-op, not a failure -- that run is already
# recorded. Treating it as an error made the orchestrator exit non-zero and
# stamped an otherwise-clean manifest "failed", which is precisely the kind of
# untrue provenance Wave 4 exists to remove.
git_sha <- tryCatch(trimws(system("git rev-parse HEAD", intern = TRUE)), error = function(e) NA_character_)
if (length(git_sha) == 0 || identical(git_sha, "")) git_sha <- NA_character_
existing <- file.path(history_root, cfg$bank_slug,
                      make_run_id(git_sha, cfg$inputs$scenario_vintage))

if (dir.exists(existing)) {
  cat(sprintf("[SKIP] Run history already recorded for this date/commit/vintage: %s\n", existing))
} else {
  run_dir <- record_run_history(cfg, artifacts, history_root = history_root)
  cat(sprintf("[OK] Run history recorded: %s\n", run_dir))
}
