# ---- compute_operational_periods() ----------------------------------------

test_that("compute_operational_periods with no gaps returns one continuous period", {
  start <- as.POSIXct("2025-05-01 08:00:00", tz = "UTC")
  end   <- as.POSIXct("2025-07-01 08:00:00", tz = "UTC")
  result <- compute_operational_periods(start, end, as.POSIXct(character(0)), as.POSIXct(character(0)))
  expect_equal(nrow(result), 1)
  expect_equal(result$period_start[1], start)
  expect_equal(result$period_end[1], end)
})

test_that("compute_operational_periods splits around a single gap in the middle", {
  start <- as.POSIXct("2025-05-01 00:00:00", tz = "UTC")
  end   <- as.POSIXct("2025-05-31 00:00:00", tz = "UTC")
  gap_start <- as.POSIXct("2025-05-10 00:00:00", tz = "UTC")
  gap_end   <- as.POSIXct("2025-05-15 00:00:00", tz = "UTC")
  result <- compute_operational_periods(start, end, gap_start, gap_end)
  expect_equal(nrow(result), 2)
  expect_equal(result$period_start[1], start)
  expect_equal(result$period_end[1], gap_start)
  expect_equal(result$period_start[2], gap_end)
  expect_equal(result$period_end[2], end)
})

test_that("compute_operational_periods merges two overlapping gaps into one split", {
  start <- as.POSIXct("2025-05-01 00:00:00", tz = "UTC")
  end   <- as.POSIXct("2025-05-31 00:00:00", tz = "UTC")
  gap_starts <- as.POSIXct(c("2025-05-10 00:00:00", "2025-05-12 00:00:00"), tz = "UTC")
  gap_ends   <- as.POSIXct(c("2025-05-14 00:00:00", "2025-05-16 00:00:00"), tz = "UTC")
  result <- compute_operational_periods(start, end, gap_starts, gap_ends)
  # Two overlapping gaps (10-14 and 12-16) should merge into one combined
  # gap (10-16), leaving exactly two operational periods either side of it.
  expect_equal(nrow(result), 2)
  expect_equal(result$period_end[1], as.POSIXct("2025-05-10 00:00:00", tz = "UTC"))
  expect_equal(result$period_start[2], as.POSIXct("2025-05-16 00:00:00", tz = "UTC"))
})

test_that("compute_operational_periods ignores a gap entirely outside the deployment window", {
  start <- as.POSIXct("2025-05-01 00:00:00", tz = "UTC")
  end   <- as.POSIXct("2025-05-31 00:00:00", tz = "UTC")
  gap_start <- as.POSIXct("2025-06-01 00:00:00", tz = "UTC")  # after the window ends
  gap_end   <- as.POSIXct("2025-06-05 00:00:00", tz = "UTC")
  result <- compute_operational_periods(start, end, gap_start, gap_end)
  expect_equal(nrow(result), 1)
  expect_equal(result$period_start[1], start)
  expect_equal(result$period_end[1], end)
})

test_that("compute_operational_periods clips a gap that starts before the window to the window boundary", {
  start <- as.POSIXct("2025-05-01 00:00:00", tz = "UTC")
  end   <- as.POSIXct("2025-05-31 00:00:00", tz = "UTC")
  gap_start <- as.POSIXct("2025-04-20 00:00:00", tz = "UTC")  # before the window starts
  gap_end   <- as.POSIXct("2025-05-05 00:00:00", tz = "UTC")
  result <- compute_operational_periods(start, end, gap_start, gap_end)
  expect_equal(nrow(result), 1)
  expect_equal(result$period_start[1], as.POSIXct("2025-05-05 00:00:00", tz = "UTC"))
  expect_equal(result$period_end[1], end)
})

test_that("compute_operational_periods returns an empty result when end <= start", {
  start <- as.POSIXct("2025-05-10 00:00:00", tz = "UTC")
  end   <- as.POSIXct("2025-05-01 00:00:00", tz = "UTC")  # before start
  result <- compute_operational_periods(start, end, as.POSIXct(character(0)), as.POSIXct(character(0)))
  expect_equal(nrow(result), 0)
})

test_that("compute_operational_periods returns an empty result for NA start/end", {
  result <- compute_operational_periods(as.POSIXct(NA), as.POSIXct("2025-05-01", tz = "UTC"),
                                         as.POSIXct(character(0)), as.POSIXct(character(0)))
  expect_equal(nrow(result), 0)
})

# ---- build_camera_operation_export() ---------------------------------------

make_test_deployment_df <- function() {
  data.frame(
    site_id = c("A01A", "A01B"),
    ct_id   = c("100", "101"),
    station_folder = c("SiteA01st_A", "SiteA01st_A"),
    setup_datetime     = as.POSIXct(c("2025-05-01 08:00:00", "2025-05-01 08:00:00"), tz = "UTC"),
    retrieved_datetime = as.POSIXct(c("2025-07-01 08:00:00", "2025-07-01 08:00:00"), tz = "UTC"),
    lat  = c(-23.10, -23.10),
    long = c(26.50, 26.50),
    stringsAsFactors = FALSE
  )
}

test_that("build_camera_operation_export returns one row per camera with no gaps or exclusions", {
  result <- build_camera_operation_export(make_test_deployment_df(), NULL, NULL)
  expect_equal(nrow(result), 2)
  expect_setequal(result$locationID, c("A01A", "A01B"))
  expect_true(all(result$locationName == "SiteA01st_A"))
})

test_that("build_camera_operation_export drops a camera marked 'Do not use' entirely", {
  decisions <- data.frame(site_id = "A01A", ct_id = "100", use_status = "Do not use",
                           note = "", stringsAsFactors = FALSE)
  result <- build_camera_operation_export(make_test_deployment_df(), NULL, decisions)
  expect_equal(nrow(result), 1)
  expect_equal(result$locationID, "A01B")
})

test_that("build_camera_operation_export splits one camera's periods around a recorded gap, leaving its pair untouched", {
  gaps <- data.frame(
    site_id = "A01A", ct_id = "100",
    gap_start = as.POSIXct("2025-06-01 00:00:00", tz = "UTC"),
    gap_end   = as.POSIXct("2025-06-05 00:00:00", tz = "UTC"),
    stringsAsFactors = FALSE
  )
  result <- build_camera_operation_export(make_test_deployment_df(), gaps, NULL)
  a01a_rows <- result[result$locationID == "A01A", ]
  a01b_rows <- result[result$locationID == "A01B", ]
  expect_equal(nrow(a01a_rows), 2)   # split around the gap
  expect_equal(nrow(a01b_rows), 1)   # no gap recorded for this camera
})

test_that("build_camera_operation_export returns an empty result with the right columns for NULL input", {
  result <- build_camera_operation_export(NULL, NULL, NULL)
  expect_equal(nrow(result), 0)
  expect_setequal(names(result), c("deploymentID", "locationID", "locationName", "latitude", "longitude",
                                     "deploymentStart", "deploymentEnd", "cameraID", "deploymentComments"))
})

# ---- build_station_operation_periods() -------------------------------------

test_that("build_station_operation_periods unions two paired cameras with the same window into one station period", {
  cam_periods <- build_camera_operation_export(make_test_deployment_df(), NULL, NULL)
  result <- build_station_operation_periods(cam_periods)
  expect_equal(nrow(result), 1)
  expect_equal(result$locationID, normalize_station_name("SiteA01st_A"))
})

test_that("build_station_operation_periods covers a gap in one camera if its pair was operating throughout", {
  # Camera A01A has a gap 2025-06-01 to 2025-06-05; A01A's pair, A01B, has
  # no gap at all. The STATION should show as continuously operating
  # across that window, since at least one camera there was always on.
  gaps <- data.frame(
    site_id = "A01A", ct_id = "100",
    gap_start = as.POSIXct("2025-06-01 00:00:00", tz = "UTC"),
    gap_end   = as.POSIXct("2025-06-05 00:00:00", tz = "UTC"),
    stringsAsFactors = FALSE
  )
  cam_periods <- build_camera_operation_export(make_test_deployment_df(), gaps, NULL)
  expect_equal(nrow(cam_periods), 3)  # A01A split into 2, A01B still 1 -- confirms the gap is really there

  result <- build_station_operation_periods(cam_periods)
  expect_equal(nrow(result), 1)       # station-level: no gap, since A01B covered it
  # ISO 8601 format ("...T...Z"), matching build_camera_operation_export()'s
  # own convention and parse_deployment_datetime()'s expected input -- NOT
  # the space-separated format this test originally expected, which was
  # itself the bug fixed earlier this session (see build_station_
  # operation_periods()'s own comments for the full story).
  expect_equal(result$deploymentStart, format(as.POSIXct("2025-05-01 08:00:00", tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ"))
  expect_equal(result$deploymentEnd,   format(as.POSIXct("2025-07-01 08:00:00", tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ"))
})

test_that("build_station_operation_periods on a single-camera station returns that camera's own window", {
  single_cam_df <- data.frame(
    site_id = "A02A", ct_id = "200", station_folder = "SiteA02st_A",
    setup_datetime     = as.POSIXct("2025-05-01 08:00:00", tz = "UTC"),
    retrieved_datetime = as.POSIXct("2025-07-01 08:00:00", tz = "UTC"),
    lat = -23.2, long = 26.6, stringsAsFactors = FALSE
  )
  cam_periods <- build_camera_operation_export(single_cam_df, NULL, NULL)
  result <- build_station_operation_periods(cam_periods)
  expect_equal(nrow(result), 1)
  expect_equal(result$locationID, normalize_station_name("SiteA02st_A"))
})

test_that("build_station_operation_periods returns an empty result for empty input", {
  empty_periods <- build_camera_operation_export(NULL, NULL, NULL)
  result <- build_station_operation_periods(empty_periods)
  expect_equal(nrow(result), 0)
})
