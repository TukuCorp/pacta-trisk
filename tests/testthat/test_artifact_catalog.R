library(testthat)

root <- project_root()
source(file.path(root, "R", "engagement_config.R"))
source(file.path(root, "R", "artifact_catalog.R"))

.mcb_cfg <- function(path = file.path(root, "engagements", "mcb-demo", "engagement_config.json")) {
  # The loader validates every input path against the working directory
  # (CLAUDE.md law 1); testthat runs with cwd = tests/testthat.
  withr_wd <- setwd(root)
  on.exit(setwd(withr_wd), add = TRUE)
  load_engagement_config(path)
}

.artifact_columns <- c(
  "key", "group", "scope", "sector", "producer", "kind", "path", "snapshot_path",
  "history_headline", "timestamp_class", "gated_html", "disclaimer_required",
  "data_source_check"
)

test_that("artifact_catalog returns one row per resolved artifact, in column order", {
  cat <- artifact_catalog(.mcb_cfg())

  expect_equal(nrow(cat), 83) # 29 engagement rows + 3 sectors x 18 rows
  expect_identical(names(cat), .artifact_columns)
  expect_equal(anyDuplicated(paste(cat$key, cat$sector)), 0L)
})

test_that("artifact_catalog fills the engagement-scoped rows from cfg$paths", {
  cat <- artifact_catalog(.mcb_cfg())

  row <- cat[cat$key == "matches", , drop = FALSE]
  expect_equal(nrow(row), 1L)
  expect_equal(row$path, "synthesis_output/vietnam/02_vn_matched_prioritized.csv")
  expect_equal(row$snapshot_path, "dashboard/data/pacta/02_vn_matched_prioritized.csv")
  expect_equal(row$producer, "pacta_vietnam_scenario")
  expect_equal(row$scope, "engagement")
  expect_true(is.na(row$sector))
})

test_that("artifact_catalog expands sector-scoped rows over cfg$trisk_sectors", {
  cat <- artifact_catalog(.mcb_cfg())

  tb <- cat[cat$key == "top_borrowers" & cat$sector == "cement", , drop = FALSE]
  expect_equal(tb$path, "synthesis_output/trisk/cement_demo/top_borrowers_alignment_trisk.csv")
  expect_equal(tb$snapshot_path, "dashboard/data/trisk/cement/top_borrowers_alignment_trisk.csv")

  assets <- cat[cat$key == "assets" & cat$sector == "power", , drop = FALSE]
  expect_equal(assets$path, "output/trisk_inputs/power_demo/assets.csv")
  expect_equal(assets$producer, "trisk_prepare_inputs")

  expect_equal(
    cat$sector[cat$scope == "sector"][c(1, 19, 37)],
    c("power", "cement", "steel")
  )
})

test_that("artifact_catalog places the pipeline manifest where the engagement publishes", {
  cat <- artifact_catalog(.mcb_cfg())
  row <- cat[cat$key == "pipeline_manifest", , drop = FALSE]
  expect_equal(row$path, "dashboard/data/pipeline_manifest.json")
  expect_equal(row$snapshot_path, "dashboard/data/pipeline_manifest.json")

  sdb <- artifact_catalog(.mcb_cfg(
    file.path(root, "engagements", "sdb-rehearsal", "engagement_config.json")
  ))
  sdb_row <- sdb[sdb$key == "pipeline_manifest", , drop = FALSE]
  expect_equal(sdb_row$path, "engagements/sdb-rehearsal/pipeline_manifest.json")
  expect_true(is.na(sdb_row$snapshot_path))
})

test_that("artifact_catalog carries only the consumer flags DEC-004 allows", {
  cat <- artifact_catalog(.mcb_cfg())

  expect_equal(sum(cat$history_headline), 4L)
  expect_setequal(
    cat$key[cat$history_headline],
    c("ms_alignment", "sda_alignment", "sector_priority_ranking", "engagement_priority")
  )
  expect_equal(sum(cat$gated_html), 6L)
  expect_equal(sum(cat$disclaimer_required), 8L)
  expect_equal(sum(cat$data_source_check), 4L)
  expect_equal(sum(cat$timestamp_class), 3L)
  expect_setequal(
    basename(cat$path[cat$timestamp_class]),
    c("pipeline_manifest.json", "refresh_audit_metrics.json", "manifest.csv")
  )
})

test_that("every producer key the catalog names is in the registry's static list", {
  cat <- artifact_catalog(.mcb_cfg())
  expect_setequal(unique(stats::na.omit(cat$producer)), .artifact_catalog_producers())
})

test_that("artifact_path resolves one key, one sector, or every sector", {
  cfg <- .mcb_cfg()

  expect_equal(artifact_path(cfg, "engagement_priority"), "output/engagement/engagement_priority.csv")
  expect_equal(
    artifact_path(cfg, "top_borrowers"),
    c(
      "synthesis_output/trisk/power_demo/top_borrowers_alignment_trisk.csv",
      "synthesis_output/trisk/cement_demo/top_borrowers_alignment_trisk.csv",
      "synthesis_output/trisk/steel_demo/top_borrowers_alignment_trisk.csv"
    )
  )
  expect_equal(
    artifact_path(cfg, "top_borrowers", sector = "steel", where = "snapshot"),
    "dashboard/data/trisk/steel/top_borrowers_alignment_trisk.csv"
  )
})

test_that("artifact_path refuses an uncatalogued key, a wrong sector and a missing snapshot", {
  cfg <- .mcb_cfg()

  expect_error(artifact_path(cfg, "nope"), "unknown artifact key 'nope'")
  expect_error(artifact_path(cfg, "matches", sector = "power"), "not sector-scoped")
  expect_error(
    artifact_path(cfg, "engagement_priority", where = "snapshot"),
    "no snapshot location"
  )
})

test_that("every declared mcb-demo path exists in the committed tree", {
  cat <- artifact_catalog(.mcb_cfg())
  # Rows whose files this checkout does not carry: the intake output (only
  # written by a --raw-loanbook run), the gated reports not rendered in the
  # public tree, and the gitignored letters/disclosure deliverables.
  excluded <- c(
    "normalized_loanbook", "intake_validation_report", "coverage_report",
    "vintage_comparison_report", "disclosure_pack", "letters_index"
  )
  rows <- cat[!(cat$key %in% excluded), , drop = FALSE]

  withr_wd <- setwd(root)
  on.exit(setwd(withr_wd), add = TRUE)

  for (i in seq_len(nrow(rows))) {
    exists <- if (identical(rows$kind[[i]], "png_group")) {
      dir.exists(rows$path[[i]])
    } else {
      file.exists(rows$path[[i]])
    }
    if (!exists && !nzchar(Sys.getenv("CI"))) {
      testthat::skip(sprintf("run the pipeline first: %s is absent", rows$path[[i]]))
    }
    expect_true(exists, info = rows$path[[i]])
  }
})

test_that("a config with one sector gets only that sector's rows", {
  cfg <- .mcb_cfg()
  cfg$trisk_sectors <- "steel"
  cat <- artifact_catalog(cfg)

  expect_equal(nrow(cat), 47) # 29 engagement rows + 18 sector rows
  expect_setequal(unique(stats::na.omit(cat$sector)), "steel")
})

test_that("a config missing a path key the catalog needs is refused by name", {
  cfg <- .mcb_cfg()
  cfg$paths$letters_output_dir <- NULL

  expect_error(
    artifact_catalog(cfg),
    "cfg\\$paths\\$letters_output_dir is missing"
  )
})

test_that("write_artifact_catalog_json emits the deterministic snapshot export", {
  cfg <- .mcb_cfg()
  cat <- artifact_catalog(cfg)
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path), add = TRUE)

  expect_equal(write_artifact_catalog_json(cfg, path), path)
  parsed <- jsonlite::fromJSON(path, simplifyVector = FALSE)

  expect_equal(parsed$schema_version, 1L)
  expect_equal(parsed$bank_slug, "mcb-demo")
  expect_equal(unlist(parsed$sectors), c("power", "cement", "steel"))
  expect_equal(length(parsed$artifacts), sum(!is.na(cat$snapshot_path)))
  expect_equal(length(parsed$artifacts), 67L)
  expect_equal(parsed$artifacts[[1]]$snapshot_path, "pacta/02_vn_matched_prioritized.csv")
  expect_true(is.null(parsed$artifacts[[1]]$sector))
  expect_false(any(grepl("[0-9]{4}-[0-9]{2}-[0-9]{2}", readLines(path, warn = FALSE))))

  write_artifact_catalog_json(cfg, path)
  first <- readLines(path, warn = FALSE)
  write_artifact_catalog_json(cfg, path)
  expect_identical(readLines(path, warn = FALSE), first)
})
