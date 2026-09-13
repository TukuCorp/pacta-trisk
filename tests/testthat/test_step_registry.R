library(testthat)

root <- project_root()
source(file.path(root, "R", "engagement_config.R"))
source(file.path(root, "R", "artifact_catalog.R"))
source(file.path(root, "R", "step_registry.R"))

# --- resolve_step_list(): flag-driven behavior (cfg$steps unset) -------------
# These pin the exact same 13-step / 15-step orders that
# tests/testthat/test_step_runner.R's subprocess dry-run tests independently
# verify by running scripts/run_engagement.R itself -- this file exercises
# resolve_step_list() directly, without spawning a subprocess.

test_that("resolve_step_list for MCB (run_intake FALSE) matches the pre-registry step order", {
  withr_wd <- setwd(root)
  on.exit(setwd(withr_wd))

  cfg <- load_engagement_config(file.path(root, "engagements", "mcb-demo", "engagement_config.json"))
  ctx <- list(
    effective_config_path = "engagements/mcb-demo/engagement_config.json",
    run_intake = FALSE, raw_loanbook = NULL,
    intake_dir = "engagements/mcb-demo/intake", top_n = NULL
  )

  steps <- resolve_step_list(cfg, ctx)
  names <- vapply(steps, function(s) s$name, character(1))

  expect_equal(names, c(
    "pacta_vietnam_scenario", "trisk_prepare_inputs",
    "trisk_sector_demo_power", "trisk_sector_demo_cement", "trisk_sector_demo_steel",
    "trisk_scenario_grid", "sector_prioritization", "refresh_dashboard_data",
    "engagement_scoring", "financed_emissions", "sll_readiness", "generate_targets", "generate_engagement_letters", "generate_disclosure_pack",
    "refresh_audit", "record_history"
  ))
})

# Wave 4 PHASE-06 brought sdb-rehearsal to feature parity with mcb-demo
# (run_targets, run_history, report_language), so its step list grew by
# generate_targets and record_history. The point of the second engagement is
# that CI's end-to-end job exercises the same feature set the public demo does.
test_that("resolve_step_list for SDB (run_intake TRUE) includes intake steps and omits grid/refresh_audit", {
  withr_wd <- setwd(root)
  on.exit(setwd(withr_wd))

  cfg <- load_engagement_config(file.path(root, "engagements", "sdb-rehearsal", "engagement_config.json"))
  ctx <- list(
    effective_config_path = "engagements/sdb-rehearsal/engagement_config.resolved.json",
    run_intake = TRUE, raw_loanbook = "data/fixtures/unseen_bank_loanbook.csv",
    intake_dir = "engagements/sdb-rehearsal/intake", top_n = NULL
  )

  steps <- resolve_step_list(cfg, ctx)
  names <- vapply(steps, function(s) s$name, character(1))

  expect_equal(names, c(
    "intake", "validation_report", "coverage_report",
    "pacta_vietnam_scenario", "trisk_prepare_inputs",
    "trisk_sector_demo_power", "trisk_sector_demo_cement", "trisk_sector_demo_steel",
    "sector_prioritization", "refresh_dashboard_data", "engagement_scoring",
    "financed_emissions", "sll_readiness", "generate_targets",
    "generate_engagement_letters", "generate_disclosure_pack",
    "record_history"
  ))
  expect_false("trisk_scenario_grid" %in% names)
  expect_false("refresh_audit" %in% names)

  intake_step <- steps[[1]]
  expect_equal(intake_step$script, "scripts/intake_validate_and_map.R")
  expect_true("--fx-rate-usd-vnd" %in% intake_step$args)
  expect_true("26300" %in% intake_step$args)
})

test_that("resolve_step_list orders trisk_sector_demo steps power-first", {
  cfg <- list(trisk_sectors = c("steel", "power", "cement"), run_grid = FALSE, run_outputs = FALSE,
              run_data_generation = FALSE, run_refresh_audit = FALSE, steps = character(0))
  ctx <- list(effective_config_path = "x.json", run_intake = FALSE, raw_loanbook = NULL,
              intake_dir = "x", top_n = NULL)

  steps <- resolve_step_list(cfg, ctx)
  names <- vapply(steps, function(s) s$name, character(1))
  sector_steps <- names[grepl("^trisk_sector_demo_", names)]
  expect_equal(sector_steps, c("trisk_sector_demo_power", "trisk_sector_demo_steel", "trisk_sector_demo_cement"))
})

# --- resolve_step_list(): declarative cfg$steps override ----------------------

test_that("a non-empty cfg$steps overrides the boolean-flag translation entirely", {
  cfg <- list(trisk_sectors = c("power"), run_grid = TRUE, run_outputs = TRUE,
              run_data_generation = TRUE, run_refresh_audit = TRUE,
              steps = c("pacta_vietnam_scenario", "engagement_scoring"))
  ctx <- list(effective_config_path = "x.json", run_intake = FALSE, raw_loanbook = NULL,
              intake_dir = "x", top_n = NULL)

  steps <- resolve_step_list(cfg, ctx)
  names <- vapply(steps, function(s) s$name, character(1))
  expect_equal(names, c("pacta_vietnam_scenario", "engagement_scoring"))
})

test_that("cfg$steps expands trisk_sector_demo against cfg$trisk_sectors, power first", {
  cfg <- list(trisk_sectors = c("cement", "power"), steps = c("trisk_sector_demo"))
  ctx <- list(effective_config_path = "x.json", run_intake = FALSE, raw_loanbook = NULL,
              intake_dir = "x", top_n = NULL)

  steps <- resolve_step_list(cfg, ctx)
  names <- vapply(steps, function(s) s$name, character(1))
  expect_equal(names, c("trisk_sector_demo_power", "trisk_sector_demo_cement"))
})

test_that("cfg$steps naming an unknown step name errors", {
  cfg <- list(trisk_sectors = character(0), steps = c("not_a_real_step"))
  ctx <- list(effective_config_path = "x.json", run_intake = FALSE, raw_loanbook = NULL,
              intake_dir = "x", top_n = NULL)

  expect_error(resolve_step_list(cfg, ctx), "not_a_real_step")
})

# --- filter_step_list() -------------------------------------------------------

.fixture_steps <- function() {
  list(
    list(name = "a", script = "a.R", args = character()),
    list(name = "b", script = "b.R", args = character()),
    list(name = "c", script = "c.R", args = character())
  )
}

test_that("filter_step_list with no filters returns the input unchanged", {
  steps <- .fixture_steps()
  out <- filter_step_list(steps)
  expect_equal(out, steps)
})

test_that("filter_step_list(only=) keeps only the named steps, preserving order", {
  steps <- .fixture_steps()
  out <- filter_step_list(steps, only = c("c", "a"))
  names <- vapply(out, function(s) s$name, character(1))
  expect_equal(names, c("a", "c"))
})

test_that("filter_step_list(only=) with an unknown name errors, naming valid names", {
  steps <- .fixture_steps()
  err <- tryCatch(filter_step_list(steps, only = c("nope")), error = function(e) conditionMessage(e))
  expect_true(grepl("nope", err, fixed = TRUE))
  expect_true(grepl("a, b, c", err, fixed = TRUE))
})

test_that("filter_step_list(resume_from=) drops steps before the match, keeps the rest", {
  steps <- .fixture_steps()
  out <- filter_step_list(steps, resume_from = "b")
  names <- vapply(out, function(s) s$name, character(1))
  expect_equal(names, c("b", "c"))
})

test_that("filter_step_list(resume_from=) with an unknown name errors", {
  steps <- .fixture_steps()
  expect_error(filter_step_list(steps, resume_from = "nope"), "nope")
})

test_that("filter_step_list combines only= and resume_from=", {
  steps <- .fixture_steps()
  out <- filter_step_list(steps, only = c("a", "b", "c"), resume_from = "b")
  names <- vapply(out, function(s) s$name, character(1))
  expect_equal(names, c("b", "c"))
})
