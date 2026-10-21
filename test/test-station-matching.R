test_that("normalize_station_name strips underscores", {
  expect_equal(normalize_station_name("SiteA01st_A"), "SiteA01stA")
})

test_that("normalize_station_name strips multiple underscores", {
  expect_equal(normalize_station_name("Site_A01_st_A"), "SiteA01stA")
})

test_that("normalize_station_name leaves a string with no underscore unchanged", {
  expect_equal(normalize_station_name("SiteA01stA"), "SiteA01stA")
})

test_that("normalize_station_name works vectorized", {
  input <- c("SiteA01st_A", "SiteA01st_B", "SiteA02st_A")
  expect_equal(normalize_station_name(input), c("SiteA01stA", "SiteA01stB", "SiteA02stA"))
})

test_that("normalize_station_name makes TrapTagger's and the deployment sheet's own station naming agree", {
  # This is the actual real-world case normalize_station_name() exists
  # for: TrapTagger drops the underscore the deployment sheet itself
  # keeps, so the two sides only match once both are normalized the
  # same way.
  traptagger_side <- "SiteA01stA"
  deployment_sheet_side <- "SiteA01st_A"
  expect_equal(normalize_station_name(traptagger_side), normalize_station_name(deployment_sheet_side))
})
