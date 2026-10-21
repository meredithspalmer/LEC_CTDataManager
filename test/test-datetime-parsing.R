test_that("parse_deployment_datetime passes through an already-POSIXct value unchanged", {
  x <- as.POSIXct("2025-07-01 08:00:00", tz = "UTC")
  expect_identical(parse_deployment_datetime(x), x)
})

test_that("parse_deployment_datetime correctly parses Camtrap DP's ISO 8601 text format", {
  result <- parse_deployment_datetime("2025-07-01T08:00:00Z")
  expect_true(inherits(result, "POSIXct"))
  expect_false(is.na(result))
  expect_equal(format(result, "%Y-%m-%d %H:%M:%S", tz = "UTC"), "2025-07-01 08:00:00")
})

test_that("parse_deployment_datetime handles a vector of ISO text values", {
  x <- c("2025-07-01T08:00:00Z", "2025-07-15T14:30:00Z", NA)
  result <- parse_deployment_datetime(x)
  expect_equal(length(result), 3)
  expect_false(is.na(result[1]))
  expect_false(is.na(result[2]))
  expect_true(is.na(result[3]))
})

test_that("parse_deployment_datetime does NOT silently turn a re-printed POSIXct into all-NA", {
  # This is the exact regression this function exists to fix: R's default
  # print format for POSIXct ("YYYY-MM-DD HH:MM:SS", no T/Z) doesn't match
  # the ISO format string, so a bare as.character() on an already-POSIXct
  # value used to silently fail to re-parse. Passing the POSIXct directly
  # (not pre-stringified) must still work correctly.
  original <- as.POSIXct(c("2025-07-01 08:00:00", "2025-07-02 09:15:00"), tz = "UTC")
  result <- parse_deployment_datetime(original)
  expect_false(any(is.na(result)))
  expect_identical(result, original)
})

test_that("excel_serial_to_date converts a numeric Excel serial correctly", {
  # Excel's epoch is 1899-12-30 (not 1900-01-01, due to Excel's own
  # leap-year bug) -- serial 45658 should land in mid-2025.
  result <- excel_serial_to_date(45658)
  expect_true(inherits(result, "Date"))
  expect_equal(format(result, "%Y"), "2025")
})

test_that("excel_serial_to_date passes through a Date input unchanged", {
  d <- as.Date("2025-07-01")
  expect_identical(excel_serial_to_date(d), d)
})

test_that("excel_serial_to_date converts a POSIXt input to Date", {
  result <- excel_serial_to_date(as.POSIXct("2025-07-01 08:00:00", tz = "UTC"))
  expect_true(inherits(result, "Date"))
  expect_equal(as.character(result), "2025-07-01")
})

test_that("excel_serial_to_date with an explicit format parses text dates correctly", {
  result <- excel_serial_to_date("07/15/2025", format = "%m/%d/%Y")
  expect_equal(as.character(result), "2025-07-15")
})

test_that("excel_serial_to_date retries with the alternate year width for mixed 2-digit/4-digit years", {
  # Manually-entered field data commonly mixes "5/12/26" and "5/12/2026"
  # within the same column -- the function should recover both even
  # though only one matches the %Y format literally.
  result <- excel_serial_to_date(c("5/12/26", "5/12/2026"), format = "%m/%d/%Y")
  expect_false(any(is.na(result)))
  expect_equal(format(result, "%Y"), c("2026", "2026"))
})

test_that("excel_serial_to_date auto-detects an unambiguous day>12 format without an explicit format", {
  # Day = 15 can only be the day-of-month, not the month, so this should
  # resolve to July 15 regardless of which M/D ordering is tried first.
  result <- excel_serial_to_date("07/15/2025")
  expect_equal(as.character(result), "2025-07-15")
})

test_that("excel_serial_to_date returns NA (not an error) for unparseable input", {
  result <- excel_serial_to_date("not a date at all")
  expect_true(is.na(result))
})

test_that("excel_serial_to_time converts a numeric day-fraction correctly", {
  expect_equal(excel_serial_to_time(0.5), "12:00:00")
  expect_equal(excel_serial_to_time(0), "00:00:00")
})

test_that("excel_serial_to_time formats a POSIXt input as HH:MM:SS", {
  result <- excel_serial_to_time(as.POSIXct("2025-07-01 13:45:30", tz = "UTC"))
  expect_equal(result, "13:45:30")
})

test_that("excel_serial_to_time does not error on unparseable input", {
  # R's format() on an NA POSIXlt value can return the literal string
  # "NA" rather than the NA sentinel depending on version/locale, so this
  # accepts either -- what actually matters (and is the function's own
  # documented contract) is that it never throws.
  result <- expect_no_error(excel_serial_to_time("garbage", format = "%H:%M:%S"))
  expect_true(is.na(result) || identical(result, "NA"))
})
