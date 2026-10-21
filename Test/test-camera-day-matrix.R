make_test_operation_df <- function(camera_id = "100") {
  data.frame(
    cameraID = camera_id,
    deploymentStart = c("2025-05-01T00:00:00Z", "2025-05-10T00:00:00Z"),
    deploymentEnd   = c("2025-05-04T00:00:00Z", "2025-05-15T00:00:00Z"),
    stringsAsFactors = FALSE
  )
}

test_that("build_camera_day_matrix marks a continuous period as 1 throughout, with no detections supplied", {
  # A single, unbroken period (no gap) -- the whole window should be 1,
  # matching camtrapR's cameraOperation() convention.
  op_df <- data.frame(cameraID = "100", deploymentStart = "2025-05-01T00:00:00Z",
                       deploymentEnd = "2025-05-05T00:00:00Z", stringsAsFactors = FALSE)
  mat <- build_camera_day_matrix(op_df, NULL)
  row <- mat[mat$cameraID == "100", ]
  expect_equal(row[["2025-05-01"]], 1L)
  expect_equal(row[["2025-05-03"]], 1L)
  expect_equal(row[["2025-05-05"]], 1L)
})

test_that("build_camera_day_matrix marks a gap within a camera's window as 0, not NA", {
  # Two periods for the same camera (5-01 to 5-04, then 5-10 to 5-15) --
  # the days in between (a recorded gap) should be 0 (camera physically
  # there, just not operating), not NA (which would mean never set up).
  op_df <- make_test_operation_df()
  mat <- build_camera_day_matrix(op_df, NULL)
  row <- mat[mat$cameraID == "100", ]
  expect_equal(row[["2025-05-02"]], 1L)  # within first period
  expect_equal(row[["2025-05-07"]], 0L)  # within the gap
  expect_equal(row[["2025-05-12"]], 1L)  # within second period
})

test_that("build_camera_day_matrix marks a day outside any camera's own window as NA", {
  # Two DIFFERENT cameras with non-overlapping windows -- a day only
  # within camera B's window should be NA (not set up at all) for camera A.
  op_df <- rbind(
    data.frame(cameraID = "100", deploymentStart = "2025-05-01T00:00:00Z",
               deploymentEnd = "2025-05-10T00:00:00Z", stringsAsFactors = FALSE),
    data.frame(cameraID = "200", deploymentStart = "2025-05-20T00:00:00Z",
               deploymentEnd = "2025-05-25T00:00:00Z", stringsAsFactors = FALSE)
  )
  mat <- build_camera_day_matrix(op_df, NULL)
  row100 <- mat[mat$cameraID == "100", ]
  expect_true(is.na(row100[["2025-05-22"]]))  # only camera 200 was set up then
})

test_that("build_camera_day_matrix handles a numeric-looking cameraID without misreading it as a row index", {
  # The actual regression this guards: R indexes a named matrix
  # POSITIONALLY when given a numeric subscript rather than by name, so
  # an un-coerced numeric camera ID like 237 could silently become "row
  # number 237" instead of "the row named 237" -- there are nowhere near
  # 237 rows in a matrix with one row per camera.
  op_df <- data.frame(cameraID = 237, deploymentStart = "2025-05-01T00:00:00Z",
                       deploymentEnd = "2025-05-05T00:00:00Z", stringsAsFactors = FALSE)
  mat <- build_camera_day_matrix(op_df, NULL)
  expect_equal(nrow(mat), 1)
  expect_equal(mat$cameraID, "237")
  expect_equal(mat[["2025-05-02"]], 1L)
})

test_that("build_camera_day_matrix with detections marks 1=detected, 0=operating-not-detected", {
  op_df <- data.frame(cameraID = "100", deploymentStart = "2025-05-01T00:00:00Z",
                       deploymentEnd = "2025-05-05T00:00:00Z", stringsAsFactors = FALSE)
  det <- data.frame(cameraID = "100", Date = as.Date("2025-05-03"), stringsAsFactors = FALSE)
  mat <- build_camera_day_matrix(op_df, det)
  row <- mat[mat$cameraID == "100", ]
  expect_equal(row[["2025-05-01"]], 0L)  # operating, not detected
  expect_equal(row[["2025-05-03"]], 1L)  # operating AND detected
})

test_that("build_camera_day_matrix ignores a detection recorded outside any operating window", {
  # A detection on a day the camera wasn't operating at all shouldn't be
  # able to create a 1 where the base matrix has NA.
  op_df <- data.frame(cameraID = "100", deploymentStart = "2025-05-01T00:00:00Z",
                       deploymentEnd = "2025-05-05T00:00:00Z", stringsAsFactors = FALSE)
  det <- data.frame(cameraID = "100", Date = as.Date("2025-06-15"), stringsAsFactors = FALSE)
  mat <- build_camera_day_matrix(op_df, det)
  expect_false("2025-06-15" %in% names(mat))  # that day isn't even in the matrix's date range... 
  # ...since all_days is derived only from the operation_df's own start/end range.
})

test_that("build_camera_day_matrix returns an empty data.frame for NULL/empty operation_df", {
  expect_equal(nrow(build_camera_day_matrix(NULL, NULL)), 0)
  expect_equal(nrow(build_camera_day_matrix(data.frame(), NULL)), 0)
})
