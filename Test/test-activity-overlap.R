test_that("compute_activity_overlap_table returns one row per pair of groups", {
  skip_if_not_installed("overlap")
  set.seed(42)
  groups <- list(
    SpeciesA = runif(60, 0, 24),
    SpeciesB = runif(60, 0, 24),
    SpeciesC = runif(60, 0, 24)
  )
  result <- compute_activity_overlap_table(groups, n_boot = 20)
  # 3 groups -> 3 possible pairs (A-B, A-C, B-C)
  expect_equal(nrow(result), 3)
  expect_setequal(names(result), c("Group_1", "Group_2", "n_1", "n_2", "Dhat", "Method", "CI_low", "CI_high"))
})

test_that("compute_activity_overlap_table's Dhat is between 0 and 1", {
  skip_if_not_installed("overlap")
  set.seed(42)
  groups <- list(SpeciesA = runif(60, 0, 24), SpeciesB = runif(60, 0, 24))
  result <- compute_activity_overlap_table(groups, n_boot = 20)
  expect_true(result$Dhat[1] >= 0 && result$Dhat[1] <= 1)
})

test_that("compute_activity_overlap_table gives near-complete overlap for two identical activity patterns", {
  skip_if_not_installed("overlap")
  set.seed(42)
  shared_hours <- runif(60, 0, 24)
  groups <- list(SpeciesA = shared_hours, SpeciesB = shared_hours)
  result <- compute_activity_overlap_table(groups, n_boot = 20)
  expect_true(result$Dhat[1] > 0.9)
})

test_that("compute_activity_overlap_table uses Dhat1 below 50 events and Dhat4 at or above", {
  skip_if_not_installed("overlap")
  set.seed(42)
  small_groups <- list(SpeciesA = runif(30, 0, 24), SpeciesB = runif(30, 0, 24))
  result_small <- compute_activity_overlap_table(small_groups, n_boot = 20)
  expect_equal(result_small$Method[1], "Dhat1")

  large_groups <- list(SpeciesA = runif(60, 0, 24), SpeciesB = runif(60, 0, 24))
  result_large <- compute_activity_overlap_table(large_groups, n_boot = 20)
  expect_equal(result_large$Method[1], "Dhat4")
})

test_that("compute_activity_overlap_table returns a CI that brackets the point estimate", {
  skip_if_not_installed("overlap")
  set.seed(42)
  groups <- list(SpeciesA = runif(60, 0, 24), SpeciesB = runif(60, 0, 24) + 6)  # some offset, partial overlap
  result <- compute_activity_overlap_table(groups, n_boot = 50)
  expect_false(is.na(result$CI_low[1]))
  expect_false(is.na(result$CI_high[1]))
  expect_true(result$CI_low[1] <= result$Dhat[1])
  expect_true(result$CI_high[1] >= result$Dhat[1])
})

test_that("compute_activity_overlap_table handles a group with too few events without erroring", {
  skip_if_not_installed("overlap")
  groups <- list(SpeciesA = c(8, 9), SpeciesB = runif(60, 0, 24))
  result <- expect_no_error(compute_activity_overlap_table(groups, n_boot = 20))
  expect_equal(nrow(result), 1)
})

test_that("compute_activity_overlap_table returns an empty result for fewer than 2 groups", {
  skip_if_not_installed("overlap")
  expect_equal(nrow(compute_activity_overlap_table(list(SpeciesA = runif(10, 0, 24)))), 0)
  expect_equal(nrow(compute_activity_overlap_table(list())), 0)
})
