test_that("collapse_to_independent_events merges photos within the threshold into one event", {
  df <- data.frame(
    station_folder = c("SiteA01stA", "SiteA01stA"),
    species = c("Leopard", "Leopard"),
    timestamp = as.POSIXct(c("2025-05-01 08:00:00", "2025-05-01 08:05:00"), tz = "UTC"),
    stringsAsFactors = FALSE
  )
  result <- collapse_to_independent_events(df, threshold_mins = 30)
  expect_equal(nrow(result), 1)
  expect_equal(result$n_photos, 2)
})

test_that("collapse_to_independent_events splits photos beyond the threshold into separate events", {
  df <- data.frame(
    station_folder = c("SiteA01stA", "SiteA01stA"),
    species = c("Leopard", "Leopard"),
    timestamp = as.POSIXct(c("2025-05-01 08:00:00", "2025-05-01 09:00:00"), tz = "UTC"),
    stringsAsFactors = FALSE
  )
  result <- collapse_to_independent_events(df, threshold_mins = 30)
  expect_equal(nrow(result), 2)
  expect_equal(result$n_photos, c(1, 1))
})

test_that("collapse_to_independent_events treats different species at the same station/time as separate events", {
  df <- data.frame(
    station_folder = c("SiteA01stA", "SiteA01stA"),
    species = c("Leopard", "Hyena"),
    timestamp = as.POSIXct(c("2025-05-01 08:00:00", "2025-05-01 08:00:30"), tz = "UTC"),
    stringsAsFactors = FALSE
  )
  result <- collapse_to_independent_events(df, threshold_mins = 30)
  expect_equal(nrow(result), 2)
})

test_that("collapse_to_independent_events treats the same species at different stations as separate events", {
  df <- data.frame(
    station_folder = c("SiteA01stA", "SiteA02stA"),
    species = c("Leopard", "Leopard"),
    timestamp = as.POSIXct(c("2025-05-01 08:00:00", "2025-05-01 08:00:30"), tz = "UTC"),
    stringsAsFactors = FALSE
  )
  result <- collapse_to_independent_events(df, threshold_mins = 30)
  expect_equal(nrow(result), 2)
})

test_that("collapse_to_independent_events does not crash on an NA species value", {
  # The actual regression this guards: a raw `!=` on two values that could
  # each be NA evaluates to NA, and `if (NA)` throws a hard R error, not
  # just a wrong result. A record with a missing species must not crash
  # the whole function.
  df <- data.frame(
    station_folder = c("SiteA01stA", "SiteA01stA"),
    species = c(NA_character_, "Leopard"),
    timestamp = as.POSIXct(c("2025-05-01 08:00:00", "2025-05-01 08:05:00"), tz = "UTC"),
    stringsAsFactors = FALSE
  )
  expect_no_error(collapse_to_independent_events(df, threshold_mins = 30))
})

test_that("collapse_to_independent_events does not crash on an NA station_folder value", {
  df <- data.frame(
    station_folder = c(NA_character_, "SiteA01stA"),
    species = c("Leopard", "Leopard"),
    timestamp = as.POSIXct(c("2025-05-01 08:00:00", "2025-05-01 08:05:00"), tz = "UTC"),
    stringsAsFactors = FALSE
  )
  expect_no_error(collapse_to_independent_events(df, threshold_mins = 30))
})

test_that("collapse_to_independent_events does not crash on an NA timestamp value", {
  df <- data.frame(
    station_folder = c("SiteA01stA", "SiteA01stA"),
    species = c("Leopard", "Leopard"),
    timestamp = as.POSIXct(c(NA, "2025-05-01 08:05:00"), tz = "UTC"),
    stringsAsFactors = FALSE
  )
  expect_no_error(collapse_to_independent_events(df, threshold_mins = 30))
})

test_that("collapse_to_independent_events returns an empty result with the right columns for NULL/empty input", {
  result <- collapse_to_independent_events(NULL, threshold_mins = 30)
  expect_equal(nrow(result), 0)
  expect_setequal(names(result), c("station_folder", "species", "event_start", "event_end", "n_photos"))

  result2 <- collapse_to_independent_events(data.frame(), threshold_mins = 30)
  expect_equal(nrow(result2), 0)
})
