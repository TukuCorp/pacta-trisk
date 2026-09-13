# ==============================================================================
# R/step_registry.R
# Wave 3 PHASE-02: a named step registry, extracted from the hardcoded `if`
# ladder that used to live inline in scripts/run_engagement.R's
# build_step_list(). Every step this repo's pipeline can run is declared once
# here, by name, with a function that builds its CLI arguments from the
# engagement config and a small runtime context. Adding a new pipeline step
# (a later Wave 3 phase, or any future one) means adding one registry entry
# and one config key -- not a new branch in an orchestrator script.
#
# resolve_step_list() reproduces, byte-for-byte, the step list the old
# build_step_list() produced for both engagements/mcb-demo/engagement_config.json
# and engagements/sdb-rehearsal/engagement_config.json when cfg$steps is
# unset -- see tests/testthat/test_step_registry.R, which pins both.
#
# `ctx` (a plain named list) carries the values that are NOT part of the
# engagement config: effective_config_path, run_intake, raw_loanbook,
# intake_dir, top_n. Per-sector steps additionally receive `sector` when
# their args_fn is invoked.
#
# Wave 5 PHASE-05: entries with real inter-step dependencies declare
# `requires`/`produces` (repo-relative paths) so ordering is checked rather
# than assumed.
#
# PHASE-02 of plans/2026-09-13-artifact-catalog-plan.md: an entry no longer
# spells a path at all. It declares `requires = c(<artifact keys>)` and
# `step_registry()` derives every `requires_fn`/`produces_fn` from
# R/artifact_catalog.R, the single owner of Artifact locations (ADR-0001).
# A dependency recorded only in a prose comment is still not a dependency.
# ==============================================================================

#' The full catalog of pipeline steps this repo knows how to run.
#'
#' Each entry is `list(script = character(1), args_fn = function(cfg, ctx) character())`,
#' optionally plus `requires = character()` (Artifact keys this step reads that
#' another registry step produces). `step_registry()` derives
#' `produces_fn = function(cfg) character()` (files the step writes) from
#' `artifact_catalog(cfg)` for every producer named there, and a `requires_fn`
#' from the declared keys.
#' `trisk_sector_demo` is special-cased in resolve_step_list() because it
#' expands to one step per configured sector, not one step total.
#'
#' @return named list of step definitions, keyed by step name.
step_registry <- function() {
  .attach_dependency_fns(list(
    generate_vietnam_data = list(
      script = "scripts/generate_vietnam_data.R",
      args_fn = function(cfg, ctx) character()
    ),
    intake = list(
      script = "scripts/intake_validate_and_map.R",
      args_fn = function(cfg, ctx) {
        intake_args <- c("--input", ctx$raw_loanbook, "--output-dir", ctx$intake_dir)
        if (isTRUE(cfg$anonymize)) intake_args <- c(intake_args, "--anonymize")
        if (length(cfg$inputs$fx_rate_usd_vnd) > 0) {
          intake_args <- c(intake_args, "--fx-rate-usd-vnd", as.character(cfg$inputs$fx_rate_usd_vnd))
        }
        intake_args
      },
      requires = character()
    ),
    validation_report = list(
      script = "scripts/generate_validation_report.R",
      args_fn = function(cfg, ctx) c(
        "--intake-dir", ctx$intake_dir,
        "--output", artifact_path(cfg, "intake_validation_report"),
        "--bank-name", cfg$bank_name
      ),
      requires = "normalized_loanbook"
    ),
    coverage_report = list(
      script = "scripts/generate_coverage_report.R",
      args_fn = function(cfg, ctx) c(
        "--config", ctx$effective_config_path,
        "--intake-dir", ctx$intake_dir,
        "--output", artifact_path(cfg, "coverage_report")
      ),
      requires = "normalized_loanbook"
    ),
    pacta_vietnam_scenario = list(
      script = "scripts/pacta_vietnam_scenario.R",
      args_fn = function(cfg, ctx) c("--config", ctx$effective_config_path),
      requires = character()
    ),
    trisk_prepare_inputs = list(
      script = "scripts/trisk_prepare_inputs.R",
      args_fn = function(cfg, ctx) c("--config", ctx$effective_config_path),
      requires = "matches"
    ),
    # trisk_sector_demo_<sector>: expanded per-sector in resolve_step_list();
    # this entry documents the shared script and per-sector arg shape.
    trisk_sector_demo = list(
      script = "scripts/trisk_sector_demo.R",
      args_fn = function(cfg, ctx) c(ctx$sector, "--config", ctx$effective_config_path),
      requires = c("assets", "financial_features", "carbon_price", "scenarios")
    ),
    trisk_scenario_grid = list(
      script = "scripts/trisk_scenario_grid.R",
      args_fn = function(cfg, ctx) c("--config", ctx$effective_config_path),
      requires = character()
    ),
    sector_prioritization = list(
      script = "scripts/sector_prioritization.R",
      args_fn = function(cfg, ctx) c("--config", ctx$effective_config_path),
      requires = c("ms_alignment", "top_borrowers")
    ),
    refresh_dashboard_data = list(
      script = "scripts/refresh_dashboard_data.R",
      args_fn = function(cfg, ctx) c("--config", ctx$effective_config_path),
      requires = character()
    ),
    engagement_scoring = list(
      script = "scripts/engagement_scoring.R",
      args_fn = function(cfg, ctx) c(
        "--config", ctx$effective_config_path,
        "--w_align", cfg$scoring$weight_alignment, "--w_trisk", cfg$scoring$weight_trisk
      ),
      requires = "sector_priority_ranking"
    ),
    # Wave 3 PHASE-05: reads output/engagement/engagement_priority.csv, so
    # it must run after engagement_scoring.
    financed_emissions = list(
      script = "scripts/generate_financed_emissions.R",
      args_fn = function(cfg, ctx) c("--config", ctx$effective_config_path),
      requires = "engagement_priority"
    ),
    # Wave 3 PHASE-06: reads engagement_priority.csv, so it must run after
    # engagement_scoring (and, per ASM-004, after refresh_dashboard_data --
    # already true here since engagement_scoring itself is placed there).
    sll_readiness = list(
      script = "scripts/sll_readiness.R",
      args_fn = function(cfg, ctx) c("--config", ctx$effective_config_path),
      requires = "engagement_priority"
    ),
    # Wave 3 PHASE-06: sector target registry, reads SDA/MS portfolio and the
    # engagement's own scenario vintage; must run after engagement_scoring and
    # refresh_dashboard_data for the same reason as sll_readiness.
    generate_targets = list(
      script = "scripts/generate_targets.R",
      args_fn = function(cfg, ctx) c("--config", ctx$effective_config_path),
      requires = "engagement_priority"
    ),
    generate_engagement_letters = list(
      script = "scripts/generate_engagement_letters.R",
      args_fn = function(cfg, ctx) {
        letters_args <- c("--config", ctx$effective_config_path)
        if (!is.null(ctx$top_n)) letters_args <- c(letters_args, "--top_n", ctx$top_n)
        letters_args
      },
      requires = "engagement_priority"
    ),
    generate_disclosure_pack = list(
      script = "scripts/generate_disclosure_pack.R",
      args_fn = function(cfg, ctx) c("--config", ctx$effective_config_path),
      requires = "engagement_priority"
    ),
    # Wave 4 PHASE-02: previously the only step receiving no config at all,
    # which is why it hardcoded a scenario vintage and the public snapshot dir.
    refresh_audit = list(
      script = "scripts/generate_refresh_audit.R",
      args_fn = function(cfg, ctx) c("--config", ctx$effective_config_path),
      requires = character()
    ),
    # Wave 3 PHASE-03: optional, gated on run_vintage_comparison (default
    # FALSE). Compares the engagement's current inputs.scenario_vintage
    # against data/scenarios/pdp8-2023/ -- the first tenant of the vintage
    # mechanism, so the comparison's "other" side is always the original.
    compare_scenario_vintages = list(
      script = "scripts/compare_scenario_vintages.R",
      args_fn = function(cfg, ctx) c(
        "--config", ctx$effective_config_path,
        "--vintage-a", "pdp8-2023",
        "--vintage-b", cfg$inputs$scenario_vintage,
        "--output", artifact_path(cfg, "vintage_comparison_report")
      ),
      requires = character()
    ),
    # Wave 3 PHASE-04: gated on run_history, placed last (after
    # refresh_audit) so it captures the run's final published outputs.
    record_history = list(
      script = "scripts/record_run_history.R",
      args_fn = function(cfg, ctx) c("--config", ctx$effective_config_path),
      requires = character()
    )
  ))
}

# A closure factory per derivation: `force()` the captured value so a closure
# built inside a loop cannot read the loop variable's final value at call time.
# Local functions are looked up when called, so definition order here is free.

# All catalog paths a given producer Step writes (S2). Empty when the producer
# has no catalog rows, which is how a step with nothing to declare behaves
# exactly as it did before this plan.
.artifact_paths_for_producer <- function(producer) {
  force(producer)
  function(cfg) {
    catalog <- artifact_catalog(cfg)
    catalog$path[!is.na(catalog$producer) & catalog$producer == producer]
  }
}

# All catalog paths named by a set of Artifact keys (S2). Sector-scoped keys
# expand to one path per configured sector.
.artifact_paths_for_keys <- function(keys) {
  force(keys)
  function(cfg) {
    catalog <- artifact_catalog(cfg)
    catalog$path[catalog$key %in% keys]
  }
}

# Derive `produces_fn`/`requires_fn` for every registry entry from the catalog:
# entries declare Artifact keys, never paths (ADR-0001).
.attach_dependency_fns <- function(registry) {
  producers <- .artifact_catalog_producers()
  for (key in names(registry)) {
    entry <- registry[[key]]
    if (key %in% producers) {
      entry$produces_fn <- .artifact_paths_for_producer(key)
    }
    if (length(entry$requires) > 0) {
      entry$requires_fn <- .artifact_paths_for_keys(entry$requires)
    }
    registry[[key]] <- entry
  }
  registry
}

#' Order the configured TRISK sectors with "power" first, if present.
#' Extracted verbatim from the pre-registry build_step_list() so the
#' "power first, for continuity with the default pipeline's step naming"
#' behavior is unchanged.
#' @param sectors character — cfg$trisk_sectors.
#' @return character — reordered sector vector.
.order_sectors_power_first <- function(sectors) {
  if ("power" %in% sectors) {
    return(c("power", setdiff(sectors, "power")))
  }
  sectors
}

#' Resolve the ordered, boolean-flag-driven step list -- reproduces
#' build_step_list()'s original behavior exactly.
#' @param cfg list — the loaded engagement config.
#' @param ctx list — effective_config_path, run_intake, raw_loanbook,
#'   intake_dir, top_n.
#' @param registry list — step_registry() output; overridable for tests.
#' @return list of list(name, script, args).
.resolve_step_list_from_flags <- function(cfg, ctx, registry) {
  steps <- list()
  add_step <- function(name, extra_ctx = list()) {
    entry <- registry[[name]]
    if (is.null(entry)) stop(sprintf("step_registry: unknown step name '%s'", name), call. = FALSE)
    step_ctx <- utils::modifyList(ctx, extra_ctx)
    steps[[length(steps) + 1]] <<- list(name = name, script = entry$script, args = entry$args_fn(cfg, step_ctx))
  }
  add_named_step <- function(display_name, registry_name, extra_ctx = list()) {
    entry <- registry[[registry_name]]
    step_ctx <- utils::modifyList(ctx, extra_ctx)
    steps[[length(steps) + 1]] <<- list(name = display_name, script = entry$script, args = entry$args_fn(cfg, step_ctx))
  }

  if (isTRUE(cfg$run_data_generation)) add_step("generate_vietnam_data")

  if (isTRUE(ctx$run_intake)) {
    add_step("intake")
    add_step("validation_report")
    add_step("coverage_report")
  }

  add_step("pacta_vietnam_scenario")
  add_step("trisk_prepare_inputs")

  sectors <- .order_sectors_power_first(cfg$trisk_sectors)
  for (sector in sectors) {
    add_named_step(sprintf("trisk_sector_demo_%s", sector), "trisk_sector_demo", list(sector = sector))
  }

  if (isTRUE(cfg$run_grid)) add_step("trisk_scenario_grid")

  add_step("sector_prioritization")
  add_step("refresh_dashboard_data")
  add_step("engagement_scoring")

  if (isTRUE(cfg$run_financed_emissions)) add_step("financed_emissions")
  if (isTRUE(cfg$run_sll_readiness)) add_step("sll_readiness")
  if (isTRUE(cfg$run_targets)) add_step("generate_targets")

  if (isTRUE(cfg$run_outputs)) {
    add_step("generate_engagement_letters")
    add_step("generate_disclosure_pack")
  }

  if (isTRUE(cfg$run_refresh_audit)) add_step("refresh_audit")

  # Wave 3 PHASE-03: only meaningful when the engagement's own vintage
  # differs from the comparison baseline (pdp8-2023) -- comparing a vintage
  # against itself would always show zero delta.
  if (isTRUE(cfg$run_vintage_comparison) &&
      !identical(cfg$inputs$scenario_vintage, "pdp8-2023")) {
    add_step("compare_scenario_vintages")
  }

  if (isTRUE(cfg$run_history)) add_step("record_history")

  steps
}

#' Resolve the ordered step list for an engagement run.
#'
#' When `cfg$steps` is non-empty, it names the steps to run, in order,
#' overriding the boolean-flag translation entirely (per-sector
#' `trisk_sector_demo_<sector>` names are still expanded against
#' `cfg$trisk_sectors`). When empty (the default for every config written
#' before this phase), falls back to the exact flag-driven behavior of the
#' original build_step_list(), so every existing config keeps working
#' unchanged.
#'
#' @param cfg list — the loaded engagement config.
#' @param ctx list — effective_config_path, run_intake, raw_loanbook,
#'   intake_dir, top_n.
#' @return list of list(name, script, args).
#' @export
resolve_step_list <- function(cfg, ctx) {
  registry <- step_registry()
  if (length(cfg$steps) == 0) {
    return(.resolve_step_list_from_flags(cfg, ctx, registry))
  }

  sectors <- .order_sectors_power_first(cfg$trisk_sectors)
  steps <- list()
  for (name in cfg$steps) {
    if (identical(name, "trisk_sector_demo")) {
      for (sector in sectors) {
        entry <- registry[["trisk_sector_demo"]]
        step_ctx <- utils::modifyList(ctx, list(sector = sector))
        steps[[length(steps) + 1]] <- list(
          name = sprintf("trisk_sector_demo_%s", sector), script = entry$script,
          args = entry$args_fn(cfg, step_ctx)
        )
      }
      next
    }
    entry <- registry[[name]]
    if (is.null(entry)) stop(sprintf("step_registry: unknown step name '%s' in cfg$steps", name), call. = FALSE)
    steps[[length(steps) + 1]] <- list(name = name, script = entry$script, args = entry$args_fn(cfg, ctx))
  }
  steps
}

#' Filter a resolved step list by --only-step and/or --resume-from.
#'
#' @param steps list — output of resolve_step_list().
#' @param only character — step names to keep, preserving registry order;
#'   empty means "no filter".
#' @param resume_from character(1)|NA — drop every step before the first
#'   whose name matches; NA means "no filter".
#' @return list — the filtered step list.
#' @export
filter_step_list <- function(steps, only = character(0), resume_from = NA_character_) {
  all_names <- vapply(steps, function(s) s$name, character(1))

  if (length(only) > 0) {
    unknown <- setdiff(only, all_names)
    if (length(unknown) > 0) {
      stop(sprintf(
        "filter_step_list: unknown step name(s) requested via --only-step: %s\nValid step names for this run: %s",
        paste(unknown, collapse = ", "), paste(all_names, collapse = ", ")
      ), call. = FALSE)
    }
    steps <- steps[all_names %in% only]
    all_names <- vapply(steps, function(s) s$name, character(1))
  }

  if (!is.na(resume_from) && nzchar(resume_from)) {
    if (!(resume_from %in% all_names)) {
      stop(sprintf(
        "filter_step_list: unknown step name '%s' requested via --resume-from\nValid step names for this run: %s",
        resume_from, paste(all_names, collapse = ", ")
      ), call. = FALSE)
    }
    idx <- which(all_names == resume_from)[[1]]
    steps <- steps[idx:length(steps)]
  }

  steps
}
