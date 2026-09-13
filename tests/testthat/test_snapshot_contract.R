library(testthat)

test_that("the snapshot contains exactly the catalogued artifacts", {
  root <- project_root()
  source(file.path(root, "R", "engagement_config.R"))
  source(file.path(root, "R", "artifact_catalog.R"))
  old_wd <- setwd(root)
  on.exit(setwd(old_wd), add = TRUE)

  cfg <- load_engagement_config(file.path("engagements", "mcb-demo", "engagement_config.json"))
  catalog <- artifact_catalog(cfg)
  snapshot_rows <- catalog[!is.na(catalog$snapshot_path), , drop = FALSE]
  expect_true(nrow(snapshot_rows) > 0)

  # 1. Every catalogued Snapshot location exists (png_group rows are
  #    directories: each holds that producer's charts).
  for (i in seq_len(nrow(snapshot_rows))) {
    path <- snapshot_rows$snapshot_path[[i]]
    exists <- if (identical(snapshot_rows$kind[[i]], "png_group")) dir.exists(path) else file.exists(path)
    expect_true(exists, info = sprintf("missing catalogued snapshot artifact %s", path))
  }

  # 2. The manifest describes the configured sectors and their grids.
  manifest_path <- artifact_path(cfg, "trisk_manifest", where = "snapshot")
  manifest <- read.csv(manifest_path, stringsAsFactors = FALSE)
  expect_setequal(manifest$sector, cfg$trisk_sectors)
  expect_true(all(manifest$grid_available), info = "grid_available should be TRUE for all sectors")

  # 3. Nothing else hides in the data directories: every csv/parquet/json under
  #    pacta/, trisk/ and analytics/ is some row's snapshot_path (manifest.csv
  #    is written in place and is the one exception). An uncatalogued file means
  #    a consumer somewhere is still guessing at a location.
  data_dirs <- file.path("dashboard", "data", c("pacta", "trisk", "analytics"))
  data_files <- unlist(lapply(data_dirs, function(dir) {
    files <- list.files(dir, pattern = "\\.(csv|parquet|json)$", recursive = TRUE, full.names = FALSE)
    files <- files[!grepl("(^|/)runs/", files)]
    file.path(dir, files)
  }), use.names = FALSE)

  allowed <- c(snapshot_rows$snapshot_path, manifest_path)
  stray <- setdiff(data_files, allowed)
  expect_equal(
    stray, character(0),
    info = paste("uncatalogued snapshot file(s):", paste(stray, collapse = ", "))
  )
})

test_that("scenario vintages have exactly one authoritative path", {
  # Wave 1 PHASE-03 (C5): the flat data/vietnam_scenario_*.csv copies were
  # retired -- data/scenarios/<vintage>/ is now the only source of truth.
  # This intentionally replaces the prior test, which asserted the
  # now-removed duplication existed.
  root <- project_root()
  expect_false(file.exists(file.path(root, "data", "vietnam_scenario_ms.csv")))
  expect_false(file.exists(file.path(root, "data", "vietnam_scenario_co2.csv")))
  expect_true(file.exists(file.path(root, "data", "scenarios", "pdp8-2023", "vietnam_scenario_ms.csv")))
  expect_true(file.exists(file.path(root, "data", "scenarios", "pdp8-2023", "vietnam_scenario_co2.csv")))
})
