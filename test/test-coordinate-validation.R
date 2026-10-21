test_that("check_coordinate_plausibility returns no warnings for valid coordinates", {
  df <- data.frame(lat = c(-23.1, -23.2), long = c(26.5, 26.6))
  expect_equal(check_coordinate_plausibility(df), character(0))
})

test_that("check_coordinate_plausibility flags an out-of-range latitude", {
  df <- data.frame(lat = c(-23.1, 95), long = c(26.5, 26.6))
  result <- check_coordinate_plausibility(df)
  expect_length(result, 1)
  expect_match(result, "lat.*range", ignore.case = TRUE)
})

test_that("check_coordinate_plausibility flags an out-of-range longitude", {
  df <- data.frame(lat = c(-23.1, -23.2), long = c(26.5, 200))
  result <- check_coordinate_plausibility(df)
  expect_length(result, 1)
  expect_match(result, "long.*range", ignore.case = TRUE)
})

test_that("check_coordinate_plausibility flags both lat and long being out of range at once", {
  df <- data.frame(lat = c(95, -23.2), long = c(26.5, 200))
  result <- check_coordinate_plausibility(df)
  expect_length(result, 2)
})

test_that("check_coordinate_plausibility flags a raw value that became NA after numeric coercion", {
  raw_lat <- c("-23.1", "stray text")
  df <- data.frame(lat = suppressWarnings(as.numeric(raw_lat)), long = c(26.5, 26.6))
  result <- check_coordinate_plausibility(df, raw_lat = raw_lat)
  expect_length(result, 1)
  expect_match(result, "stray text", fixed = TRUE)
})

test_that("check_coordinate_plausibility returns no warnings when lat/long columns are missing entirely", {
  df <- data.frame(x = 1:3)
  expect_equal(check_coordinate_plausibility(df), character(0))
})

test_that("check_date_plausibility returns no warnings for plausible years", {
  df <- data.frame(setup_date = as.Date(c("2025-05-01", "2025-06-01")))
  expect_equal(check_date_plausibility(df), character(0))
})

test_that("check_date_plausibility flags an implausible year, e.g. from a wrong date format guess", {
  # The real-world case this guards: "5/7/25" misread with the wrong
  # format can silently produce year 5 instead of 2025.
  df <- data.frame(setup_date = as.Date(c("0005-07-05", "2025-06-01")))
  result <- check_date_plausibility(df)
  expect_length(result, 1)
  expect_match(result, "setup_date", fixed = TRUE)
})

test_that("check_date_plausibility checks multiple recognized date columns independently", {
  df <- data.frame(
    setup_date = as.Date(c("2025-05-01", "2025-06-01")),
    retrieved_date = as.Date(c("0005-07-05", "2025-07-01"))
  )
  result <- check_date_plausibility(df)
  expect_length(result, 1)
  expect_match(result, "retrieved_date", fixed = TRUE)
})

test_that("check_date_plausibility ignores columns it doesn't recognize", {
  df <- data.frame(some_other_date = as.Date("0005-07-05"))
  expect_equal(check_date_plausibility(df), character(0))
})
