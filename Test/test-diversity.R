make_test_traptagger_for_diversity <- function() {
  # Station A: 2 Leopard events (far apart in time), 1 Hyena event.
  # Station B: 1 Leopard event, 1 Human event (to be excluded).
  data.frame(
    station_folder = c("SiteA01stA", "SiteA01stA", "SiteA01stA", "SiteA02stA", "SiteA02stA"),
    species = c("Leopard", "Leopard", "Hyena", "Leopard", "Human"),
    timestamp = as.POSIXct(c("2025-05-01 08:00:00", "2025-05-02 08:00:00", "2025-05-01 09:00:00",
                              "2025-05-03 08:00:00", "2025-05-03 09:00:00"), tz = "UTC"),
    stringsAsFactors = FALSE
  )
}

test_that("build_community_matrix produces one row per station and one column per species", {
  mat <- build_community_matrix(make_test_traptagger_for_diversity(), threshold_mins = 30)
  expect_equal(nrow(mat), 2)
  expect_setequal(colnames(mat), c("Leopard", "Hyena", "Human"))
})

test_that("build_community_matrix counts independent EVENTS, not raw photos", {
  mat <- build_community_matrix(make_test_traptagger_for_diversity(), threshold_mins = 30)
  # Station A's two Leopard timestamps are a day apart -- well beyond a
  # 30-minute threshold, so they're two separate events, not one.
  expect_equal(mat["SiteA01stA", "Leopard"], 2)
})

test_that("build_community_matrix excludes specified species", {
  mat <- build_community_matrix(make_test_traptagger_for_diversity(), threshold_mins = 30,
                                 exclude_species = "Human")
  expect_false("Human" %in% colnames(mat))
})

test_that("build_community_matrix returns NULL for NULL/empty input", {
  expect_null(build_community_matrix(NULL, threshold_mins = 30))
  expect_null(build_community_matrix(data.frame(), threshold_mins = 30))
})

test_that("build_community_matrix returns NULL if excluding leaves nothing", {
  single_species_df <- data.frame(
    station_folder = "SiteA01stA", species = "Human",
    timestamp = as.POSIXct("2025-05-01 08:00:00", tz = "UTC"), stringsAsFactors = FALSE
  )
  expect_null(build_community_matrix(single_species_df, threshold_mins = 30, exclude_species = "Human"))
})

test_that("compute_diversity_summary reports the correct observed richness", {
  skip_if_not_installed("vegan")
  mat <- build_community_matrix(make_test_traptagger_for_diversity(), threshold_mins = 30)
  summ <- compute_diversity_summary(mat)
  expect_equal(summ$observed_richness, 3)  # Leopard, Hyena, Human
  expect_equal(summ$n_stations, 2)
})

test_that("compute_diversity_summary's Shannon index is 0 for a single-species community", {
  skip_if_not_installed("vegan")
  single_species_df <- data.frame(
    station_folder = c("SiteA01stA", "SiteA02stA"), species = c("Leopard", "Leopard"),
    timestamp = as.POSIXct(c("2025-05-01 08:00:00", "2025-05-02 08:00:00"), tz = "UTC"),
    stringsAsFactors = FALSE
  )
  mat <- build_community_matrix(single_species_df, threshold_mins = 30)
  summ <- compute_diversity_summary(mat)
  # Shannon diversity is exactly 0 when only one species is present --
  # there's no uncertainty about which species a random detection is.
  expect_equal(summ$shannon, 0)
})

test_that("compute_diversity_summary includes Chao/Jackknife estimates from specpool", {
  skip_if_not_installed("vegan")
  mat <- build_community_matrix(make_test_traptagger_for_diversity(), threshold_mins = 30)
  summ <- compute_diversity_summary(mat)
  expect_true(!is.null(summ$pool))
  expect_true("chao" %in% names(summ$pool))
  expect_true("jack1" %in% names(summ$pool))
})

test_that("compute_diversity_summary returns NULL for an empty community matrix", {
  expect_null(compute_diversity_summary(NULL))
  expect_null(compute_diversity_summary(data.frame()))
})
