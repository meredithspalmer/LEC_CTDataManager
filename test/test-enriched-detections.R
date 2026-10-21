make_test_traptagger_df <- function() {
  data.frame(
    station_folder = c("SiteA01stA", "SiteA02stA"),  # TrapTagger's own naming: no underscore
    species = c("Leopard", "Hyena"),
    timestamp = as.POSIXct(c("2025-05-01 08:00:00", "2025-05-02 09:00:00"), tz = "UTC"),
    stringsAsFactors = FALSE
  )
}

make_test_deployment_df_for_enrichment <- function() {
  # A01A/A01B are paired at one station (SiteA01st_A); A02A is alone at
  # its own station (SiteA02st_A).
  data.frame(
    station_folder = c("SiteA01st_A", "SiteA01st_A", "SiteA02st_A"),
    site_id = c("A01A", "A01B", "A02A"),
    ct_id   = c("100", "101", "200"),
    block = c("NW", "NW", "NW"),
    season = c("Dry", "Dry", "Dry"),
    block_season = c("NW_Dry", "NW_Dry", "NW_Dry"),
    cell_id = c("C1", "C1", "C2"),
    stringsAsFactors = FALSE
  )
}

test_that("build_enriched_detections leaves ct_id NA for a record at a multi-camera (paired) station", {
  result <- build_enriched_detections(make_test_traptagger_df(), NULL, NULL,
                                       make_test_deployment_df_for_enrichment())
  leopard_row <- result[result$species == "Leopard", ]
  expect_true(is.na(leopard_row$ct_id))
})

test_that("build_enriched_detections populates ct_id for a record at an unambiguous single-camera station", {
  result <- build_enriched_detections(make_test_traptagger_df(), NULL, NULL,
                                       make_test_deployment_df_for_enrichment())
  hyena_row <- result[result$species == "Hyena", ]
  expect_equal(hyena_row$ct_id, "200")
})

test_that("build_enriched_detections preserves TrapTagger's OWN station_folder, not the deployment sheet's", {
  # This is the behavior the station-level occupancy/SECR exports rely on
  # (joining enriched$station_folder against the deployment sheet via
  # normalize_station_name(), not expecting it to already be overwritten).
  result <- build_enriched_detections(make_test_traptagger_df(), NULL, NULL,
                                       make_test_deployment_df_for_enrichment())
  expect_true(all(result$station_folder %in% c("SiteA01stA", "SiteA02stA")))
  expect_false(any(grepl("_", result$station_folder)))
})

test_that("build_enriched_detections works with no deployment sheet at all", {
  result <- build_enriched_detections(make_test_traptagger_df(), NULL, NULL, NULL)
  expect_equal(nrow(result), 2)
  expect_true(all(is.na(result$ct_id)))
  expect_true(all(is.na(result$block)))
})

test_that("build_enriched_detections works with no ArgusWild data at all", {
  result <- build_enriched_detections(make_test_traptagger_df(), NULL, NULL,
                                       make_test_deployment_df_for_enrichment())
  expect_true(all(is.na(result$individual_id)))
  expect_true(all(is.na(result$sex)))
  expect_true(all(is.na(result$life_stage)))
})

test_that("build_enriched_detections joins ArgusWild individual IDs by matched local filename", {
  traptagger_df <- make_test_traptagger_df()
  exif_df <- data.frame(
    station_folder = c("SiteA01st_A", "SiteA02st_A"),
    datetime = traptagger_df$timestamp,
    path = c("/photos/leopard_001.jpg", "/photos/hyena_001.jpg"),
    stringsAsFactors = FALSE
  )
  argus_df <- data.frame(
    media_asset = "leopard_001.jpg",
    individual_id = "Leo_M3",
    sex = "Male",
    life_stage = "Adult",
    stringsAsFactors = FALSE
  )
  result <- build_enriched_detections(traptagger_df, exif_df, argus_df,
                                       make_test_deployment_df_for_enrichment())
  leopard_row <- result[result$species == "Leopard", ]
  expect_equal(leopard_row$individual_id, "Leo_M3")
})

test_that("build_enriched_detections returns NULL for NULL/empty traptagger_df", {
  expect_null(build_enriched_detections(NULL, NULL, NULL, NULL))
  expect_null(build_enriched_detections(data.frame(), NULL, NULL, NULL))
})
