# =============================================================================
# generate_traptagger_test_data.R
#
# Generates a synthetic TrapTagger classification export for the SAME
# survey generate_full_test_data.R already created on disk.
#
# IMPORTANT — why this version reads real EXIF data:
# An earlier version of this script generated its own independently-
# randomized timestamps for "match" stations, assuming they'd line up
# with the local test images' timestamps. They never could — the two
# scripts generate their random bursts completely independently, so
# "Match to local images" always reported everything as "not found," no
# matter how correctly the rest of the setup was done. This version reads
# the REAL EXIF timestamp of each actual local test image
# (generate_full_test_data.R already wrote these — this script never
# invents its own) and builds "match" stations' TrapTagger records
# directly from them, guaranteeing every one of those records has a
# genuinely matching local file, by construction.
#
# This deliberately creates a MIX of outcomes, but only across the
# stations confirmed to actually support each outcome cleanly (see the
# detailed trace above the `roles <-` assignment for why A01, A04st_A and
# A05st_A are deliberately left out):
#   - 3 stations (A06, A07, A09): clean match — one TrapTagger record per
#     REAL local image, using that image's own real EXIF timestamp.
#     "Match to local images" should find every one of these.
#   - 1 station (A08): clean match (as above) PLUS a subset of those same
#     real records relabeled "Knocked Down" instead of their real
#     species, simulating a knockdown gap.
#   - 2 stations (A02, A04st_B): genuine timestamp discrepancy (one
#     starts several days late, one ends more than a week early) —
#     synthetic, independently randomized, since the point here is
#     testing the cross-check's date-mismatch detection, not local-image
#     matching. These are EXPECTED to show "not found" when matching —
#     that's not a bug, matching isn't the point for these two.
#   - 1 station (A03): completely missing from the TrapTagger export
#     (zero records) — should be flagged "Not found" by the cross-check.
#   - 3 stations (A01, A04st_A, A05st_A): left out of this script's test
#     plan entirely — they still have real folders/images on disk (this
#     script's folder resolution handles reconyx/cuddeback/single-
#     subfolder/multi-visit layouts correctly if you want to explore
#     them manually), just not a clean, single guaranteed outcome worth
#     promising here.
#
# HOW TO USE:
# 1. Run generate_full_test_data.R FIRST — this script reads the actual
#    image folders and files it creates on disk, not just the deployment
#    sheet.
# 2. Edit the four variables below to match EXACTLY what you set in
#    generate_full_test_data.R (same BASE_DIR, SURVEY_NAME,
#    DEPLOYMENT_PHASE, DEPLOYMENT_FILE) — this script needs to find the
#    same folders on disk that script created.
# 3. Run this script. It writes traptagger_test_export.csv INSIDE your
#    survey folder itself (BASE_DIR/SURVEY_NAME/traptagger_test_export.csv)
#    — always this exact, predictable location, not wherever R's working
#    directory happens to be. The script prints the full path when done;
#    always upload THAT exact file, not any other copy — if you've run
#    this before, an older copy from that run may still exist elsewhere
#    on disk (e.g. Downloads) with the identical filename.
# 4. Upload that CSV on the Processing page:
#    - Cross-check should show: 4 stations OK (A06, A07, A08, A09), 2
#      flagged "Timestamp mismatch" (A02, A04st_B), 1 flagged "Not found"
#      (A03). A01, A04st_A, A05st_A won't appear at all (not part of this
#      script's test plan — see the note above).
#    - "Detect gaps from TrapTagger" should find the one knockdown period
#      (A08).
#    - Focal species export -> "Match to local images" should find a
#      local file for every A06/A07/A08/A09 record, and correctly report
#      "not found" for A02/A04st_B (expected, not a bug — see above).
# =============================================================================

suppressWarnings(suppressMessages({
  library(openxlsx)
  library(exiftoolr)
  library(fs)
}))

# ---- EDIT THESE FOUR LINES to match generate_full_test_data.R exactly -----
BASE_DIR         <- "~/Desktop/Work/Consultancies/Leopard Ecology & Conservation/App/Sample Folders"                       # matches "Choose output location"
SURVEY_NAME      <- "LEC_2023_S1_Dry"                     # matches what you typed as survey name
DEPLOYMENT_PHASE <- "First_deployment"                    # matches what you typed as deployment phase
DEPLOYMENT_FILE  <- "~/Desktop/Work/Consultancies/Leopard Ecology & Conservation/App/Sample Data/Deployment_Data_Sample.xlsx"  # path to your deployment sheet
# -----------------------------------------------------------------------------

survey_path <- fs::path_expand(file.path(BASE_DIR, SURVEY_NAME))
deployment_file <- fs::path_expand(DEPLOYMENT_FILE)

OUTPUT_FILE <- file.path("~/Desktop/Work/Consultancies/Leopard Ecology & Conservation/App/Sample Data", "traptagger_test_export.csv")
# Written INSIDE the survey folder itself (NOT a relative path depending
# on whatever R's working directory happens to be at runtime, which can
# silently differ between sessions/launch methods and is a common way to
# end up re-uploading an old copy by mistake without realizing it). Tied
# to this specific survey, not just BASE_DIR generally, in case BASE_DIR
# ever gets reused across more than one survey over time.

if (!dir.exists(survey_path)) {
  stop("Can't find '", survey_path, "'. Did you run generate_full_test_data.R first, ",
       "and set BASE_DIR/SURVEY_NAME above to match exactly what you used there?")
}
if (!file.exists(deployment_file)) {
  stop("Can't find deployment file at '", deployment_file, "'. Edit DEPLOYMENT_FILE above.")
}

set.seed(42)

cat("Reading deployment sheet...\n")

# --- Deployment reader — copied VERBATIM from generate_full_test_data.R ----
# (not re-derived) so site_id/camera_folder/station_folder compute
# IDENTICALLY to whatever that script actually used when it built the real
# folders on disk, regardless of this particular deployment sheet's exact
# column set (e.g. whether it has a real "CT Loc" column or falls back to
# cell_id + ct_station).
ext <- tolower(tools::file_ext(deployment_file))
if (ext %in% c("xlsx", "xls")) {
  if (!requireNamespace("readxl", quietly = TRUE)) stop("Please install the 'readxl' package first.")
  raw <- readxl::read_excel(deployment_file, sheet = 1, guess_max = 5000)
} else {
  raw <- utils::read.csv(deployment_file, stringsAsFactors = FALSE)
}
raw <- as.data.frame(raw, stringsAsFactors = FALSE)

normalize_header <- function(x) {
  x <- tolower(trimws(x))
  x <- gsub("[_[:space:]]+", " ", x)
  trimws(x)
}

col_map <- c(
  "season" = "season", "block" = "block", "cell id" = "cell_id", "ct station" = "ct_station",
  "ct station id" = "ct_station_id", "ct loc" = "ct_loc",
  "n cam per station" = "n_cam_per_station", "n cam centr" = "n_cam_per_station",
  "ct id" = "ct_id", "date setup" = "date_setup", "time setup" = "time_setup",
  "date retrieved" = "date_retrieved", "time retrieved" = "time_retrieved"
)
raw_names <- trimws(names(raw))
names(raw) <- raw_names
normalized <- normalize_header(raw_names)
matched <- normalized %in% names(col_map)
names(raw)[matched] <- col_map[normalized[matched]]

required <- c("season", "block", "cell_id", "ct_station", "ct_id")
missing_req <- setdiff(required, names(raw))
if (length(missing_req) > 0) {
  stop("Deployment sheet is missing required column(s): ", paste(missing_req, collapse = ", "))
}

is_blank <- apply(raw[required], 1, function(r) all(is.na(r) | trimws(as.character(r)) == ""))
df <- raw[!is_blank, , drop = FALSE]

df$block_season <- paste0(df$block, "_", df$season)
df$site_id <- if ("ct_loc" %in% names(df) && any(!is.na(df$ct_loc) & trimws(as.character(df$ct_loc)) != "")) {
  as.character(df$ct_loc)
} else {
  paste0(df$cell_id, "_", df$ct_station)
}
df$block_deploy <- paste0(df$block, "_", DEPLOYMENT_PHASE)
df$station_folder <- if ("ct_station_id" %in% names(df)) {
  paste0("Site", df$ct_station_id)
} else {
  paste0("Site", df$cell_id, "st", df$ct_station)
}
df$camera_folder <- paste0(df$site_id, "_", df$ct_id)
df$expected_camera_path <- file.path(survey_path, df$block_deploy, df$cell_id,
                                      df$station_folder, df$camera_folder)

excel_serial_to_date <- function(x) {
  if (inherits(x, "POSIXt")) return(as.Date(x))
  if (inherits(x, "Date"))   return(x)
  if (is.numeric(x))         return(as.Date(x, origin = "1899-12-30"))
  suppressWarnings(as.Date(as.character(x)))
}
excel_serial_to_time <- function(x) {
  if (inherits(x, "POSIXt")) return(format(x, "%H:%M:%S"))
  if (is.numeric(x)) {
    secs <- round((x %% 1) * 86400)
    return(sprintf("%02d:%02d:%02d", secs %/% 3600, (secs %% 3600) %/% 60, secs %% 60))
  }
  as.character(x)
}

if ("date_setup" %in% names(df))     df$setup_date     <- excel_serial_to_date(df$date_setup)
if ("time_setup" %in% names(df))     df$setup_time     <- excel_serial_to_time(df$time_setup)
if ("date_retrieved" %in% names(df)) df$retrieved_date <- excel_serial_to_date(df$date_retrieved)
if ("time_retrieved" %in% names(df)) df$retrieved_time <- excel_serial_to_time(df$time_retrieved)

df$setup_datetime <- suppressWarnings(as.POSIXct(
  paste(df$setup_date, df$setup_time), format = "%Y-%m-%d %H:%M:%S", tz = "UTC"))
df$retrieved_datetime <- suppressWarnings(as.POSIXct(
  paste(df$retrieved_date, df$retrieved_time), format = "%Y-%m-%d %H:%M:%S", tz = "UTC"))

cat("Cameras in deployment sheet:", nrow(df), "\n\n")

# ---- Folder resolution + real-image listing (mirrors app.R's logic) -------
# Read-only equivalents of app.R's resolve_camera_folder_path() and
# list_camera_images_ordered() — this script never creates or renames
# folders, only reads whatever generate_full_test_data.R already put there.
IMAGE_EXTENSION_PATTERN <- "\\.(jpg|jpeg|png)$"

list_real_subfolders <- function(path) {
  if (!dir.exists(path)) return(character(0))
  all_entries <- list.dirs(path, recursive = FALSE, full.names = TRUE)
  path_norm <- normalizePath(path, mustWork = FALSE)
  is_self <- vapply(all_entries, function(p) {
    identical(normalizePath(p, mustWork = FALSE), path_norm)
  }, logical(1))
  sort(all_entries[!is_self])
}

find_suffixed_sibling_folders <- function(parent_dir, expected_name) {
  if (!dir.exists(parent_dir)) return(character(0))
  siblings <- list_real_subfolders(parent_dir)
  sibling_names <- basename(siblings)
  is_suffixed <- nchar(sibling_names) == nchar(expected_name) + 1 &
    tolower(substr(sibling_names, 1, nchar(expected_name))) == tolower(expected_name) &
    grepl("^[a-z]$", substr(sibling_names, nchar(expected_name) + 1, nchar(expected_name) + 1),
          ignore.case = TRUE)
  sort(siblings[is_suffixed])
}

resolve_camera_dirs <- function(expected_path) {
  if (dir.exists(expected_path)) return(expected_path)
  empty_variant <- paste0(expected_path, "empty")
  if (dir.exists(empty_variant)) return(empty_variant)
  multi <- find_suffixed_sibling_folders(dirname(expected_path), basename(expected_path))
  if (length(multi) > 0) return(multi)
  character(0)
}

list_images_in_dirs <- function(dirs) {
  all_files <- character(0)
  for (d in dirs) {
    direct <- list.files(d, full.names = TRUE, no.. = TRUE)
    direct <- direct[!dir.exists(direct)]
    direct <- sort(direct[grepl(IMAGE_EXTENSION_PATTERN, direct, ignore.case = TRUE)])
    nested <- character(0)
    for (sf in list_real_subfolders(d)) {
      files <- list.files(sf, full.names = TRUE, no.. = TRUE)
      files <- files[!dir.exists(files)]
      files <- sort(files[grepl(IMAGE_EXTENSION_PATTERN, files, ignore.case = TRUE)])
      nested <- c(nested, files)
    }
    all_files <- c(all_files, direct, nested)
  }
  all_files
}

read_real_timestamps <- function(image_paths) {
  if (length(image_paths) == 0) return(as.POSIXct(character(0)))
  exif <- tryCatch(exiftoolr::exif_read(image_paths, tags = c("DateTimeOriginal", "CreateDate")),
                    error = function(e) NULL)
  if (is.null(exif) || nrow(exif) == 0) return(as.POSIXct(rep(NA, length(image_paths))))
  dt_str <- if ("DateTimeOriginal" %in% names(exif)) exif$DateTimeOriginal else rep(NA_character_, nrow(exif))
  if ("CreateDate" %in% names(exif)) {
    missing <- is.na(dt_str) | dt_str == ""
    dt_str[missing] <- exif$CreateDate[missing]
  }
  suppressWarnings(as.POSIXct(dt_str, format = "%Y:%m:%d %H:%M:%S", tz = "UTC"))
}

# ---- Station-level setup/retrieved window (min/max across its cameras) ---
stations <- unique(df$ct_station_id)
station_info <- do.call(rbind, lapply(stations, function(st) {
  rows <- df[df$ct_station_id == st, ]
  data.frame(station_id = st, station_folder = rows$station_folder[1], stringsAsFactors = FALSE)
}))

cat("Stations found:", nrow(station_info), "\n")

# ---- Role assignment ----
# generate_full_test_data.R assigns its OWN special test roles (mismatch,
# empty variants, reconyx, cuddeback, single_subfolder, multi_visit) to
# the FIRST 9 rows of the deployment sheet, in that fixed order,
# regardless of which station they belong to (role[1:9] <- special_needed,
# deterministic, not randomized). Traced through the real deployment
# sheet's actual row order, this lands as:
#   Row 1  A01/237  mismatch            Row 6  A04A/228 reconyx
#   Row 2  A01/133  empty_review        Row 7  A04B/108 cuddeback
#   Row 3  A02/204  empty_documented    Row 8  A05/286  single_subfolder
#   Row 4  A03/261  empty_no_reason     Row 9  A05/182  multi_visit
#   Row 5  A03/120  missing             Rows 10-14 (A06,A07,A08,A09 x2): normal
# So A01, A02, A03, A04st_A, A05st_A each have at least one camera in a
# special, non-standard state — A01 and A02 in particular would produce
# either shifted or zero real timestamps, not a clean match, if used
# here. Rather than force a misleading "clean match" label onto stations
# that can't actually deliver one, only A06/A07/A08/A09 (confirmed
# entirely "normal" by this same trace) are used for the deterministic
# match/knockdown outcomes below. A02 and A03 are naturally empty anyway
# (fits "missing"/discrepancy, which don't need real images). A01, A04st_A,
# and A05st_A are deliberately left OUT of this script's role list — real
# data exists there (reconyx/cuddeback/single_subfolder/multi_visit
# folders all still have genuine images, and this script's folder
# resolution handles all of them), but their outcome isn't a guaranteed,
# clean scenario worth promising a specific result for.
roles <- c(
  "A02st_A" = "discrepancy_early_end",  # naturally empty (empty_documented) — synthetic doesn't need real images
  "A03st_A" = "missing",                # naturally empty (empty_no_reason + missing) — fits perfectly as-is
  "A04st_B" = "discrepancy_late_start", # cuddeback sub-folder — synthetic doesn't need real images
  "A06st_A" = "match",                  # confirmed normal
  "A07st_A" = "match",                  # confirmed normal
  "A08st_A" = "match_with_knockdown",   # confirmed normal
  "A09st_A" = "match"                   # both cameras confirmed normal
)
station_info$role <- roles[station_info$station_id]

# ---- Species pool, weighted to roughly match real-world frequency ----
# (drawn from a real Kalahari camera-trap export, for realism)
species_pool <- c(
  rep("None", 60), rep("Human", 12), rep("Steenbok", 10), rep("Oryx - Gemsbok", 7),
  rep("Elephant", 6), rep("Duiker", 5), rep("Bird", 5), rep("Porcupine", 2),
  rep("Giraffe", 2), rep("Red Hartebeest", 2), rep("Black-backed jackal", 2),
  rep("Brown hyena", 1), rep("Warthog", 1), rep("Kudu", 1), rep("Leopard", 1),
  rep("Springbok", 1)
)

make_record_row <- function(station_folder, timestamp, species, sighting_count = NULL) {
  data.frame(
    `Site Name` = station_folder, Latitude = NA_real_, Longitude = NA_real_,
    Timestamp = format(timestamp, "%Y-%m-%d %H:%M:%S"),
    Species = species,
    `Sighting Count` = if (!is.null(sighting_count)) sighting_count else
      if (species == "None") 0 else sample(1:2, 1),
    `Image URL` = paste0("https://traptagger.co.uk/imageViewer?type=image&id=",
                          sample(100000000:999999999, 1)),
    check.names = FALSE, stringsAsFactors = FALSE
  )
}

# Synthetic fallback for discrepancy stations only — these are
# deliberately NOT based on real local images, since the point is testing
# the cross-check's date-mismatch detection, not local-image matching.
make_synthetic_records <- function(station_folder, start_date, end_date, n_bursts) {
  if (n_bursts <= 0 || is.na(start_date) || is.na(end_date) || end_date <= start_date) return(NULL)
  burst_days <- sort(sample(seq.int(0, as.integer(end_date - start_date)), n_bursts, replace = TRUE))
  rows <- lapply(burst_days, function(d) {
    burst_start <- as.POSIXct(start_date, tz = "UTC") + d * 86400 + sample(0:82800, 1)
    n_images <- sample(1:4, 1)
    times <- burst_start + (seq_len(n_images) - 1) * sample(4:20, 1)
    lapply(times, function(t) make_record_row(station_folder, t, sample(species_pool, 1)))
  })
  do.call(rbind, do.call(c, rows))
}

all_rows <- list()

for (i in seq_len(nrow(station_info))) {
  s <- station_info[i, ]

  if (is.na(s$role)) {
    cat(sprintf("Skipping %s (no test role assigned - see comment above roles<-).\n", s$station_id))
    next
  }
  cat(sprintf("Generating for %s (%s)...\n", s$station_id, s$role))

  if (s$role == "missing") next  # zero records — deliberately absent

  if (s$role %in% c("match", "match_with_knockdown")) {
    # One record per REAL local image, using its REAL EXIF timestamp —
    # guarantees "Match to local images" finds every one of these.
    cams <- df[df$ct_station_id == s$station_id, ]
    all_images <- character(0)
    for (j in seq_len(nrow(cams))) {
      dirs <- resolve_camera_dirs(cams$expected_camera_path[j])
      if (length(dirs) == 0) {
        cat("  [warning] no folder found for camera", cams$camera_folder[j],
            "- skipping (did generate_full_test_data.R actually create this camera?)\n")
        next
      }
      all_images <- c(all_images, list_images_in_dirs(dirs))
    }

    if (length(all_images) == 0) {
      cat("  [warning] no real images found for this station at all - producing zero records.\n")
      next
    }

    real_times <- read_real_timestamps(all_images)
    valid <- !is.na(real_times)
    real_times <- real_times[valid]
    cat("  Found", length(all_images), "real image(s),", sum(valid), "with a readable timestamp.\n")

    recs <- do.call(rbind, lapply(seq_along(real_times), function(k) {
      make_record_row(s$station_folder, real_times[k], sample(species_pool, 1))
    }))

    if (s$role == "match_with_knockdown" && nrow(recs) > 0) {
      # Relabel roughly the middle third of this station's OWN real
      # records as "Knocked Down" — a real subset of real images, not
      # newly-fabricated ones, matching the same "relabel real data"
      # approach used for sample_traptagger_export.csv.
      ord <- order(recs$Timestamp)
      recs <- recs[ord, ]
      n <- nrow(recs)
      kd_start_idx <- max(1, round(n * 0.4))
      kd_end_idx <- min(n, kd_start_idx + max(1, round(n * 0.15)))
      recs$Species[kd_start_idx:kd_end_idx] <- "Knocked Down"
      recs$`Sighting Count`[kd_start_idx:kd_end_idx] <- 1
      cat("  Relabeled", kd_end_idx - kd_start_idx + 1, "real record(s) as \"Knocked Down\".\n")
    }

  } else if (s$role == "discrepancy_late_start") {
    cams <- df[df$ct_station_id == s$station_id, ]
    window_start <- min(cams$setup_datetime, na.rm = TRUE)
    window_end   <- max(cams$retrieved_datetime, na.rm = TRUE)
    late_start <- as.Date(window_start) + 9
    window_days <- as.integer(as.Date(window_end) - late_start)
    recs <- make_synthetic_records(s$station_folder, late_start, as.Date(window_end),
                                    max(20, round(window_days * 1.5)))

  } else if (s$role == "discrepancy_early_end") {
    cams <- df[df$ct_station_id == s$station_id, ]
    window_start <- min(cams$setup_datetime, na.rm = TRUE)
    window_end   <- max(cams$retrieved_datetime, na.rm = TRUE)
    early_end <- as.Date(window_end) - 11
    window_days <- as.integer(early_end - as.Date(window_start))
    recs <- make_synthetic_records(s$station_folder, as.Date(window_start), early_end,
                                    max(20, round(window_days * 1.5)))
  }

  if (!is.null(recs) && nrow(recs) > 0) all_rows[[length(all_rows) + 1]] <- recs
}

final_df <- do.call(rbind, all_rows)
final_df <- final_df[order(final_df$`Site Name`, final_df$Timestamp), ]

write.csv(final_df, OUTPUT_FILE, row.names = FALSE)

cat("\nDone. Wrote", nrow(final_df), "records to", OUTPUT_FILE, "\n\n")
cat("Expected results when you upload this on the Processing page:\n")
for (i in seq_len(nrow(station_info))) {
  s <- station_info[i, ]
  if (is.na(s$role)) {
    cat(sprintf("  %-10s (no test role assigned \u2014 real data exists but outcome not guaranteed)\n",
                s$station_id))
    next
  }
  expectation <- switch(s$role,
    "match" = "OK, and every record should match a local file",
    "match_with_knockdown" = "OK, records match local files, plus a detectable knockdown gap",
    "discrepancy_late_start" = "FLAGGED \u2014 timestamp mismatch (starts ~9 days late); records are synthetic, expected \"not found\" when matching",
    "discrepancy_early_end" = "FLAGGED \u2014 timestamp mismatch (ends ~11 days early); records are synthetic, expected \"not found\" when matching",
    "missing" = "FLAGGED \u2014 not found in TrapTagger export"
  )
  cat(sprintf("  %-10s %s\n", s$station_id, expectation))
}
