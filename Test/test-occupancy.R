make_test_daily_matrix <- function() {
  # 2 stations, 14 consecutive days. Station A: operating all 14 days,
  # detected on day 3 and day 10. Station B: NOT operating days 1-7 (not
  # yet deployed), operating days 8-14, no detections at all.
  dates <- as.character(seq(as.Date("2025-05-01"), as.Date("2025-05-14"), by = "day"))
  row_a <- rep(0L, 14); row_a[c(3, 10)] <- 1L
  row_b <- c(rep(NA_integer_, 7), rep(0L, 7))
  mat <- matrix(c(row_a, row_b), nrow = 2, byrow = TRUE, dimnames = list(NULL, dates))
  data.frame(cameraID = c("StationA", "StationB"), mat, check.names = FALSE, stringsAsFactors = FALSE)
}

test_that("build_occupancy_occasion_matrix collapses days into the right number of occasions", {
  result <- build_occupancy_occasion_matrix(make_test_daily_matrix(), occasion_length = 7)
  expect_equal(result$n_occasions, 2)
  expect_equal(ncol(result$y), 2)
  expect_equal(nrow(result$y), 2)
})

test_that("build_occupancy_occasion_matrix marks an occasion as detected (1) if ANY day in it has a detection", {
  result <- build_occupancy_occasion_matrix(make_test_daily_matrix(), occasion_length = 7)
  # Station A's day 3 (in occasion 1) and day 10 (in occasion 2) both had detections.
  expect_equal(unname(result$y["StationA", ]), c(1L, 1L))
})

test_that("build_occupancy_occasion_matrix marks an occasion as NA if the station had NO operating days at all in it", {
  result <- build_occupancy_occasion_matrix(make_test_daily_matrix(), occasion_length = 7)
  # Station B's first 7 days (occasion 1) are all NA (not yet deployed there).
  expect_true(is.na(result$y["StationB", 1]))
  # Its second 7 days (occasion 2) were operating with no detection, so 0.
  expect_equal(unname(result$y["StationB", 2]), 0L)
})

test_that("build_occupancy_occasion_matrix's effort matrix counts actually-operating days per occasion", {
  result <- build_occupancy_occasion_matrix(make_test_daily_matrix(), occasion_length = 7)
  expect_equal(unname(result$effort["StationA", ]), c(7L, 7L))
  expect_equal(unname(result$effort["StationB", ]), c(0L, 7L))
})

test_that("build_occupancy_occasion_matrix handles a survey length that isn't an exact multiple of occasion_length", {
  result <- build_occupancy_occasion_matrix(make_test_daily_matrix(), occasion_length = 5)
  # 14 days / 5-day occasions = 3 occasions (5, 5, 4), not silently dropped.
  expect_equal(result$n_occasions, 3)
  expect_equal(ncol(result$y), 3)
})

test_that("build_occupancy_occasion_matrix returns NULL for NULL/empty input or an invalid occasion length", {
  expect_null(build_occupancy_occasion_matrix(NULL, occasion_length = 7))
  expect_null(build_occupancy_occasion_matrix(data.frame(), occasion_length = 7))
  expect_null(build_occupancy_occasion_matrix(make_test_daily_matrix(), occasion_length = 0))
})

make_test_station_ops_for_covariates <- function() {
  data.frame(
    locationID = c("StationA", "StationB", "StationB"),  # B has 2 gap-split rows
    locationName = c("Station_A", "Station_B", "Station_B"),
    latitude = c(-23.1, -23.3, -23.3),
    longitude = c(29.1, 29.3, 29.3),
    n_cameras = c(1, 2, 2),  # A: single camera; B: paired
    stringsAsFactors = FALSE
  )
}

make_test_deployment_for_covariates <- function() {
  data.frame(
    station_folder = c("Station_A", "Station_B"),
    block = c("North", "South"),
    season = c("Dry", "Dry"),
    stringsAsFactors = FALSE
  )
}

test_that("build_occupancy_site_covariates produces one row per DISTINCT station, not per gap-split row", {
  covs <- build_occupancy_site_covariates(make_test_station_ops_for_covariates(),
                                           make_test_deployment_for_covariates())
  expect_equal(nrow(covs), 2)
  expect_setequal(covs$locationID, c("StationA", "StationB"))
})

test_that("build_occupancy_site_covariates correctly identifies paired vs single-camera stations", {
  covs <- build_occupancy_site_covariates(make_test_station_ops_for_covariates(),
                                           make_test_deployment_for_covariates())
  expect_equal(covs$paired[covs$locationID == "StationA"], "Single")
  expect_equal(covs$paired[covs$locationID == "StationB"], "Paired")
})

test_that("build_occupancy_site_covariates pulls block/season from the deployment sheet by normalized station name", {
  covs <- build_occupancy_site_covariates(make_test_station_ops_for_covariates(),
                                           make_test_deployment_for_covariates())
  expect_equal(covs$block[covs$locationID == "StationA"], "North")
  expect_equal(covs$block[covs$locationID == "StationB"], "South")
})

test_that("build_occupancy_site_covariates handles no GIS layers gracefully (habitat column all NA, no error)", {
  covs <- build_occupancy_site_covariates(make_test_station_ops_for_covariates(),
                                           make_test_deployment_for_covariates(), gis_layers = NULL)
  expect_true(all(is.na(covs$habitat)))
})

test_that("build_occupancy_site_covariates returns NULL for NULL/empty station_ops", {
  expect_null(build_occupancy_site_covariates(NULL, make_test_deployment_for_covariates()))
  expect_null(build_occupancy_site_covariates(data.frame(), make_test_deployment_for_covariates()))
})

test_that("fit_occupancy_model runs a null model end-to-end without error on simple synthetic data", {
  skip_if_not_installed("unmarked")
  set.seed(42)
  # 20 stations, 5 occasions, no missing data, no real covariate effect --
  # just confirming the pipeline runs and returns the expected structure,
  # not validating statistical correctness of a specific result.
  y <- matrix(rbinom(100, 1, 0.4), nrow = 20, ncol = 5,
              dimnames = list(paste0("Station", seq_len(20)), paste0("o", seq_len(5))))
  site_covs <- data.frame(locationID = paste0("Station", seq_len(20)),
                           block = rep(c("North", "South"), 10), stringsAsFactors = FALSE)
  result <- fit_occupancy_model(y, site_covs, obs_covs = NULL,
                                 occ_covariates = character(0), det_covariates = character(0))
  expect_null(result$error)
  expect_true(is.numeric(result$aic))
  expect_true(!is.null(result$state_summary))
  expect_true(!is.null(result$det_summary))
  expect_equal(nrow(result$site_predictions), 20)
})

test_that("fit_occupancy_model fails gracefully (not with an uncaught error) on empty input", {
  result <- fit_occupancy_model(NULL, NULL, NULL)
  expect_false(is.null(result$error))
})
