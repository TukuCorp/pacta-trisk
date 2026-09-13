library(testthat)

root <- project_root()
source(file.path(root, "R", "engagement_config.R"))
source(file.path(root, "R", "artifact_catalog.R"))
source(file.path(root, "R", "step_registry.R"))
source(file.path(root, "R", "engagement_plan.R"))

.mcb_cfg <- function(steps = character(0)) {
  cfg <- load_engagement_config(file.path(root, "engagements", "mcb-demo", "engagement_config.json"))
  cfg$steps <- steps
  cfg
}

.mcb_ctx <- function() {
  list(
    effective_config_path = file.path(root, "engagements", "mcb-demo", "engagement_config.json"),
    run_intake = FALSE,
    raw_loanbook = NULL,
    intake_dir = file.path(root, "engagements", "mcb-demo", "intake"),
    top_n = NULL
  )
}

.mcb_cli <- function(...) {
  parse_engagement_cli(c("--config", file.path(root, "engagements", "mcb-demo", "engagement_config.json"), ...))
}

test_that("a mis-ordered cfg$steps is refused naming both steps and the file", {
  withr_wd <- setwd(root)
  on.exit(setwd(withr_wd))
  cfg <- .mcb_cfg(steps = c("financed_emissions", "engagement_scoring"))
  err <- tryCatch(
    { plan_engagement_run(cfg, .mcb_cli()); NULL },
    error = function(e) conditionMessage(e)
  )
  expect_false(is.null(err))
  expect_match(err, "financed_emissions", fixed = TRUE)
  expect_match(err, "engagement_scoring", fixed = TRUE)
  expect_match(err, "engagement_priority.csv", fixed = TRUE)
})

test_that("correct order validates clean", {
  withr_wd <- setwd(root)
  on.exit(setwd(withr_wd))
  chain <- c("pacta_vietnam_scenario", "trisk_prepare_inputs", "trisk_sector_demo",
             "sector_prioritization", "engagement_scoring", "financed_emissions")
  cfg <- .mcb_cfg(steps = chain)
  plan <- plan_engagement_run(cfg, .mcb_cli())
  expect_equal(
    validate_step_dependencies(plan$steps, cfg),
    character(0)
  )
})

test_that("a filtered run warns about the previous-run artifact", {
  withr_wd <- setwd(root)
  on.exit(setwd(withr_wd))
  cfg <- .mcb_cfg()
  steps <- resolve_step_list(cfg, .mcb_ctx())
  filtered <- filter_step_list(steps, only = "financed_emissions")
  warnings <- validate_step_dependencies(filtered, cfg, strict = FALSE)
  expect_equal(length(warnings), 1)
  expect_match(warnings[[1]], "engagement_priority.csv", fixed = TRUE)
  expect_match(warnings[[1]], "previous run", fixed = TRUE)
})

test_that("--strict-deps escalates the previous-run read to an error", {
  withr_wd <- setwd(root)
  on.exit(setwd(withr_wd))
  cfg <- .mcb_cfg()
  steps <- resolve_step_list(cfg, .mcb_ctx())
  filtered <- filter_step_list(steps, only = "financed_emissions")
  expect_error(
    validate_step_dependencies(filtered, cfg, strict = TRUE),
    "engagement_priority.csv"
  )
  cfg2 <- .mcb_cfg(steps = "financed_emissions")
  expect_error(
    plan_engagement_run(cfg2, .mcb_cli("--strict-deps")),
    "engagement_priority.csv"
  )
})

test_that("a step with neither field contributes no requirement", {
  withr_wd <- setwd(root)
  on.exit(setwd(withr_wd))
  cfg <- .mcb_cfg(steps = "generate_vietnam_data")
  plan <- plan_engagement_run(cfg, .mcb_cli())
  expect_equal(length(plan$steps), 1)
  expect_equal(validate_step_dependencies(plan$steps, cfg), character(0))
})

test_that("every requires edge in the full MCB list is wired to a producer", {
  withr_wd <- setwd(root)
  on.exit(setwd(withr_wd))
  cfg <- .mcb_cfg()
  steps <- resolve_step_list(cfg, .mcb_ctx())
  registry <- step_registry()
  produced <- unique(unlist(lapply(steps, function(s) {
    key <- .registry_key_for_step(s$name, registry)
    entry <- registry[[key]]
    if (is.null(entry) || is.null(entry$produces_fn)) return(character(0))
    entry$produces_fn(cfg)
  })))
  required <- unlist(lapply(steps, function(s) {
    key <- .registry_key_for_step(s$name, registry)
    entry <- registry[[key]]
    if (is.null(entry) || is.null(entry$requires_fn)) return(character(0))
    entry$requires_fn(cfg)
  }))
  expect_true(length(required) > 0)
  expect_true(all(required %in% produced))
  expect_equal(validate_step_dependencies(steps, cfg), character(0))
})

test_that("registry dependencies are derived from the catalog, at real locations", {
  withr_wd <- setwd(root)
  on.exit(setwd(withr_wd))
  cfg <- .mcb_cfg()
  registry <- step_registry()
  catalog <- artifact_catalog(cfg)

  produced <- unique(unlist(lapply(names(registry), function(key) {
    entry <- registry[[key]]
    if (is.null(entry$produces_fn)) return(character(0))
    entry$produces_fn(cfg)
  })))
  expect_true(length(produced) > 0)
  expect_true(all(produced %in% catalog$path))

  # 11 TRISK keys x 3 sectors, at the `_demo` locations TRISK actually writes.
  trisk_produced <- registry[["trisk_sector_demo"]]$produces_fn(cfg)
  expect_equal(length(trisk_produced), 33)
  expect_true("synthesis_output/trisk/power_demo/top_borrowers_alignment_trisk.csv" %in% trisk_produced)
  expect_equal(length(registry[["trisk_prepare_inputs"]]$produces_fn(cfg)), 12)

  # A step the catalog names no Artifact for carries no derived closure.
  expect_null(registry[["generate_vietnam_data"]]$produces_fn)
  expect_null(registry[["record_history"]]$produces_fn)

  expect_equal(
    registry[["refresh_dashboard_data"]]$produces_fn(cfg),
    "dashboard/data/trisk/manifest.csv"
  )
  expect_equal(
    registry[["sector_prioritization"]]$requires_fn(cfg),
    c(
      "synthesis_output/vietnam/06_vn_ms_alignment_2030.csv",
      "synthesis_output/trisk/power_demo/top_borrowers_alignment_trisk.csv",
      "synthesis_output/trisk/cement_demo/top_borrowers_alignment_trisk.csv",
      "synthesis_output/trisk/steel_demo/top_borrowers_alignment_trisk.csv"
    )
  )
})
