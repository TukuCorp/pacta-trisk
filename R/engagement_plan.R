# ==============================================================================
# R/engagement_plan.R
# Deep planning module for the engagement orchestrator.
#
# scripts/run_engagement.R used to own CLI parsing, step_ctx construction,
# the resolve/filter call pair, the by-name intake split, the manifest path
# branch, and the partial-manifest refusal inline. Ordering policy therefore
# had no locality: the pure helpers in R/step_registry.R were unit-tested,
# but the wiring between them was only reachable through a subprocess.
# This module is the single seam for that policy: scripts/run_engagement.R
# parses, plans, then executes. Execution (subprocesses, manifest JSON
# shape) stays in R/step_runner.R.
# ==============================================================================

#' Extract the value following a single-occurrence flag.
#'
#' @param args character — CLI tokens.
#' @param name character(1) — the flag to look up.
#' @return character(1)|NULL — the following token, or NULL when absent.
.cli_flag_value <- function(args, name) {
  idx <- which(args == name)
  if (length(idx) == 0 || idx[[1]] >= length(args)) return(NULL)
  args[[idx[[1]] + 1]]
}

#' Collect every value following a repeatable flag.
#'
#' @param args character — CLI tokens.
#' @param name character — the flag to collect values for.
#' @return character — every value found, in argument order; empty if none.
.cli_flag_values <- function(args, name) {
  idx <- which(args == name)
  idx <- idx[idx < length(args)]
  if (length(idx) == 0) return(character(0))
  args[idx + 1]
}

#' Map a resolved step name to its registry entry key.
#'
#' Per-sector steps resolve as `trisk_sector_demo_<sector>` but are declared
#' once as `trisk_sector_demo`; any other display name that extends a
#' registry key with a suffix maps back to that key.
#' @param name character(1) -- resolved step name.
#' @param registry list -- step_registry() output.
#' @return character(1) -- the registry key.
.registry_key_for_step <- function(name, registry) {
  if (!is.null(registry[[name]])) return(name)
  for (key in names(registry)) {
    if (startsWith(name, paste0(key, "_"))) return(key)
  }
  name
}

#' Validate inter-step file dependencies for a resolved step list (Wave 5
#' PHASE-05, S3).
#'
#' For each step's `requires_fn` paths: when some registry step produces the
#' path but appears in this run *after* the requiring step, that is a hard
#' ordering violation and this stops. When no step in this run produces the
#' path, the step reads a previous run's artifact -- a warning naming the
#' file, escalated to an error under `strict = TRUE` (--strict-deps).
#'
#' @param steps list -- resolve_step_list() output (possibly filtered).
#' @param cfg list -- the loaded engagement config.
#' @param registry list -- step_registry() output; overridable for tests.
#' @param strict logical(1) -- escalate previous-run reads to errors.
#' @return character -- warning messages (empty when none); stops on a hard
#'   ordering violation (and, when strict, on a previous-run read).
#' @export
validate_step_dependencies <- function(steps, cfg, registry = step_registry(), strict = FALSE) {
  produces_of <- function(key) {
    entry <- registry[[key]]
    if (is.null(entry) || is.null(entry$produces_fn)) return(character(0))
    entry$produces_fn(cfg)
  }
  registry_produces <- function(path) {
    any(vapply(names(registry), function(k) path %in% produces_of(k), logical(1)))
  }
  keys <- vapply(steps, function(s) .registry_key_for_step(s$name, registry), character(1))
  warnings <- character(0)
  for (i in seq_along(steps)) {
    entry <- registry[[keys[[i]]]]
    if (is.null(entry) || is.null(entry$requires_fn)) next
    for (r in entry$requires_fn(cfg)) {
      produced_at <- which(vapply(seq_along(steps), function(j) r %in% produces_of(keys[[j]]), logical(1)))
      if (any(produced_at > i)) {
        producer <- steps[[produced_at[produced_at > i][[1]]]]$name
        stop(sprintf(
          "validate_step_dependencies: step '%s' requires '%s', which is produced by later step '%s' -- fix cfg$steps order",
          steps[[i]]$name, r, producer
        ), call. = FALSE)
      }
      if (length(produced_at) == 0) {
        msg <- if (registry_produces(r)) {
          sprintf("step '%s' requires '%s', which no step in this run produces -- it will be read from a previous run",
                  steps[[i]]$name, r)
        } else {
          sprintf("step '%s' requires '%s', which no known step produces -- it will be read from a previous run",
                  steps[[i]]$name, r)
        }
        if (isTRUE(strict)) {
          stop(sprintf("validate_step_dependencies (strict): %s", msg), call. = FALSE)
        }
        warnings <- c(warnings, msg)
      }
    }
  }
  warnings
}

#' Plan one engagement run: resolve the ordered step list and derive run paths.
#'
#' Owns the --full application, raw-loanbook resolution, run_intake
#' derivation, intake directories, step_ctx construction, the
#' resolve_step_list() + filter_step_list() call pair, the by-name intake
#' split, and the manifest path + partial-run derivation. The guard rail,
#' manifest refusal effect, resolved-config write, and banner move in the
#' final step.
#'
#' @param cfg list — validated engagement config (load_engagement_config() output).
#' @param cli list — parse_engagement_cli() output.
#' @return named list with fields cfg (with cli$full applied), cli,
#'   raw_loanbook character(1)|NULL, run_intake logical(1),
#'   intake_dir character(1), effective_config_path character(1),
#'   step_ctx list, steps list of list(name, script, args),
#'   intake_present logical(1), steps_before_intake list,
#'   intake_step list|NULL, steps_after_intake list,
#'   manifest_path character(1),
#'   dependency_warnings character,
#'   manifest_policy list(run_is_partial logical(1),
#'     only_step character, resume_from character(1)),
#'   banner character(1).
#' @export
plan_engagement_run <- function(cfg, cli) {
  if (isTRUE(cli$full)) {
    cfg$run_data_generation <- TRUE
  }

  # A CLI --raw-loanbook flag wins; otherwise fall back to the config's own
  # inputs$raw_loanbook_csv (verbatim from scripts/run_engagement.R).
  # %||% is base R (>= 4.4.0).
  raw_loanbook <- cli$raw_loanbook %||% cfg$inputs$raw_loanbook_csv

  # Guard rail: never let an engagement publish into the public snapshot
  # directory unless its config explicitly allows it (verbatim from
  # scripts/run_engagement.R).
  if (identical(cfg$paths$snapshot_dir, "dashboard/data") && !isTRUE(cfg$public_snapshot_allowed)) {
    stop("Engagement snapshot_dir must not be the public dashboard/data unless public_snapshot_allowed is true", call. = FALSE)
  }

  run_intake <- !is.null(raw_loanbook) && !isTRUE(cli$skip_intake)
  intake_dir <- file.path("engagements", cfg$bank_slug, "intake")
  effective_config_path <- if (run_intake) {
    file.path("engagements", cfg$bank_slug, "engagement_config.resolved.json")
  } else {
    cli$config_path
  }

  step_ctx <- list(
    effective_config_path = effective_config_path,
    run_intake = run_intake,
    raw_loanbook = raw_loanbook,
    intake_dir = intake_dir,
    top_n = cli$top_n
  )
  steps <- resolve_step_list(cfg, step_ctx)
  steps <- filter_step_list(steps, only = cli$only_steps, resume_from = cli$resume_from)

  # The manifest records a row count per entry in cfg$row_count_files (Wave 1
  # PHASE-05). Those entries are Snapshot Artifact paths spelled in the
  # engagement config; the catalog is what decides whether a given path is a
  # real catalogued Snapshot location, so a typo or a retired file is refused
  # here rather than recorded as a count of nothing.
  if (length(cfg$row_count_files) > 0) {
    known <- stats::na.omit(artifact_catalog(cfg)$snapshot_path)
    unknown <- setdiff(as.character(cfg$row_count_files), known)
    if (length(unknown) > 0) {
      stop(sprintf(
        "plan_engagement_run: row_count_files entry '%s' is not a catalogued Snapshot artifact",
        unknown[[1]]
      ), call. = FALSE)
    }
  }

  dependency_warnings <- validate_step_dependencies(steps, cfg, strict = isTRUE(cli$strict_deps))
  if (length(dependency_warnings) > 0) {
    for (w in dependency_warnings) warning(w, call. = FALSE)
  }

  # Locate "intake" by name, not by position: run_data_generation may have
  # prepended a generate_vietnam_data step ahead of it (verbatim from
  # scripts/run_engagement.R).
  intake_present <- any(vapply(steps, function(s) identical(s$name, "intake"), logical(1)))
  if (intake_present) {
    intake_idx <- which(vapply(steps, function(s) identical(s$name, "intake"), logical(1)))[[1]]
    steps_before_intake <- if (intake_idx > 1) steps[seq_len(intake_idx - 1)] else list()
    intake_step <- steps[[intake_idx]]
    steps_after_intake <- steps[-seq_len(intake_idx)]
  } else {
    steps_before_intake <- list()
    intake_step <- NULL
    steps_after_intake <- list()
  }

  # Public engagements (mcb-demo) write the manifest alongside the public
  # snapshot; every other engagement keeps its manifest under its own
  # engagements/<slug>/ tree. The rule lives on the catalog's
  # `pipeline_manifest` row, which encodes both branches.
  manifest_path <- artifact_path(cfg, "pipeline_manifest")
  # A --only-step / --resume-from run produces a manifest that describes
  # only the steps it ran (verbatim from scripts/run_engagement.R).
  run_is_partial <- length(cli$only_steps) > 0 || (!is.na(cli$resume_from) && nzchar(cli$resume_from))

  banner <- sprintf(
    "Engagement: %s (%s)\nEffective config: %s\nLoanbook: %s\n\n",
    cfg$bank_name, cfg$bank_slug, effective_config_path,
    if (!is.null(raw_loanbook)) raw_loanbook else cfg$inputs$loanbook_csv
  )

  list(
    cfg = cfg,
    cli = cli,
    raw_loanbook = raw_loanbook,
    run_intake = run_intake,
    intake_dir = intake_dir,
    effective_config_path = effective_config_path,
    step_ctx = step_ctx,
    steps = steps,
    intake_present = intake_present,
    steps_before_intake = steps_before_intake,
    intake_step = intake_step,
    steps_after_intake = steps_after_intake,
    manifest_path = manifest_path,
    dependency_warnings = dependency_warnings,
    manifest_policy = list(
      run_is_partial = run_is_partial,
      only_step = cli$only_steps,
      resume_from = cli$resume_from
    ),
    banner = banner
  )
}

#' Enforce the manifest policy decided by plan_engagement_run().
#'
#' A filtered run's manifest describes only the steps it ran. Writing that
#' over a complete PUBLIC manifest silently destroys the provenance record,
#' so the orchestrator refuses without an explicit opt-in (verbatim from
#' scripts/run_engagement.R). Filesystem reads and the refusal stop() live
#' here, at the edge; the decision inputs live in the plan.
#'
#' @param plan list — plan_engagement_run() output.
#' @param allow_partial_manifest logical(1) — cli$allow_partial_manifest.
#' @return invisible TRUE; calls stop() only when a filtered run would
#'   clobber a complete public manifest without the opt-in flag.
#' @export
enforce_manifest_policy <- function(plan, allow_partial_manifest) {
  policy <- plan$manifest_policy
  if (!isTRUE(policy$run_is_partial)) return(invisible(TRUE))
  if (!isTRUE(plan$cfg$public_snapshot_allowed)) return(invisible(TRUE))
  if (isTRUE(allow_partial_manifest)) return(invisible(TRUE))

  manifest_path <- plan$manifest_path
  if (!file.exists(manifest_path)) return(invisible(TRUE))
  existing <- tryCatch(
    jsonlite::fromJSON(manifest_path, simplifyVector = TRUE),
    error = function(e) NULL
  )
  existing_is_complete <- !is.null(existing) && !isTRUE(existing$partial)
  if (existing_is_complete) {
    stop(sprintf(paste0(
      "Refusing to overwrite the complete public manifest at %s with a partial run.\n",
      "  This run was filtered by %s.\n",
      "  Re-run without --only-step/--resume-from, or pass --allow-partial-manifest ",
      "to accept a partial provenance record."
    ), manifest_path, paste(c(
      if (length(policy$only_step) > 0) sprintf("--only-step %s", paste(policy$only_step, collapse = ", ")),
      if (!is.na(policy$resume_from) && nzchar(policy$resume_from)) sprintf("--resume-from %s", policy$resume_from)
    ), collapse = " and ")), call. = FALSE)
  }
  invisible(TRUE)
}

#' Materialize the post-intake resolved config.
#'
#' After the intake step normalizes the raw loanbook, all later steps run
#' against a resolved config whose inputs$loanbook_csv points at the
#' normalized output (verbatim from scripts/run_engagement.R). I/O lives
#' here, at the edge; the paths come from the plan.
#'
#' @param cfg list — the pre-intake config.
#' @param intake_dir character(1) — plan$intake_dir.
#' @param effective_config_path character(1) — plan$effective_config_path.
#' @return character(1) — the path written (effective_config_path).
#' @export
materialize_resolved_config <- function(cfg, intake_dir, effective_config_path) {
  dir.create(dirname(effective_config_path), recursive = TRUE, showWarnings = FALSE)
  resolved_cfg <- cfg
  resolved_cfg$inputs$loanbook_csv <- file.path(intake_dir, "normalized_loanbook.csv")
  write(jsonlite::toJSON(resolved_cfg, auto_unbox = TRUE, pretty = TRUE), effective_config_path)
  invisible(effective_config_path)
}
#' Parse the orchestrator CLI into a plain data list.
#'
#' Moved verbatim from scripts/run_engagement.R's inline flag handling so
#' the flag shapes (repeatable --only-step, valued --resume-from) are
#' learned once, behind the planning seam, instead of at every call site.
#'
#' @param args character — CLI tokens, defaults to commandArgs(trailingOnly = TRUE).
#' @return named list with fields config_path character(1), full logical(1),
#'   raw_loanbook character(1)|NULL, skip_intake logical(1),
#'   top_n character(1)|NULL, only_steps character,
#'   resume_from character(1) (NA_character_ when unset),
#'   allow_partial_manifest logical(1), strict_deps logical(1),
#'   dry_run logical(1).
#' @export
parse_engagement_cli <- function(args = commandArgs(trailingOnly = TRUE)) {
  config_path <- .cli_flag_value(args, "--config")
  if (is.null(config_path)) {
    stop(paste(
      "Usage: Rscript scripts/run_engagement.R --config <path>",
      "[--full] [--raw-loanbook <path>] [--skip-intake] [--top-n <int>]",
      "[--only-step <name> [--only-step <name> ...]] [--resume-from <name>]",
      "[--allow-partial-manifest] [--strict-deps] [--dry-run]"
    ), call. = FALSE)
  }

  # %||% is base R (>= 4.4.0); R/engagement_config.R also defines a fallback.
  resume_from <- .cli_flag_value(args, "--resume-from")
  if (is.null(resume_from)) resume_from <- NA_character_

  list(
    config_path = config_path,
    full = "--full" %in% args,
    raw_loanbook = .cli_flag_value(args, "--raw-loanbook"),
    skip_intake = "--skip-intake" %in% args,
    top_n = .cli_flag_value(args, "--top-n"),
    only_steps = .cli_flag_values(args, "--only-step"),
    resume_from = resume_from,
    # Opt-in to overwriting a complete public manifest with a partial
    # (filtered) run's manifest.
    allow_partial_manifest = "--allow-partial-manifest" %in% args,
    strict_deps = "--strict-deps" %in% args,
    dry_run = "--dry-run" %in% args
  )
}
