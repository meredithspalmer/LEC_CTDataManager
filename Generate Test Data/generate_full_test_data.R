# =============================================================================
# CamTrap Manager — Full Workflow Test Data Generator
# Creates ONE test dataset that exercises Image Audit, Rename, and QA/QC in
# sequence — replacing the three separate generate_test_data.R /
# generate_rename_test_data.R / generate_qaqc_test_data.R scripts, which each
# created data usable for only one page.
#
# Every image is a genuinely valid (if minimal) JPEG with a real embedded
# EXIF timestamp — including the ones deliberately placed in sub-folders —
# so the exact same dataset works as you move through the whole pipeline:
# the folders/statuses Image Audit should show, the sub-folder consolidation
# Rename should perform, and the timestamps QA/QC should check, all come
# from ONE run of this script.
#
# EVERY camera starts with generic, unrenamed filenames ("IMG_0001.jpg"-
# style, as a real SD card would produce), not the app's final naming
# convention — Rename images (Page 2, Step 4) is a genuinely necessary
# step for the whole dataset, not just the sub-folder cameras. Nothing is
# pre-renamed for you.
#
# HOW TO USE:
# 1. Run app.R and go through Page 2, Step 1 (Survey setup): upload your
#    deployment sheet, type a Survey name AND a Deployment phase (e.g.
#    First_deployment), then click "Create folder structure".
# 2. Edit the four variables below to match exactly what you entered in the
#    app and where your deployment file lives.
# 3. Run this whole script. It's slower than the old dummy-file generators
#    (real EXIF writing takes ~0.5-1s per image) — expect a few minutes for
#    a full survey.
# 4. Walk the workflow in the app, in order:
#      a. Page 2, Step 2 (Image audit): point it at your survey folder, run
#         the audit, and confirm the mix of statuses described below.
#      b. Page 2, Step 4 (Rename images): preview, then commit — confirm the
#         sub-folder cameras get consolidated and correctly chronologically
#         ordered (check the EXIF timestamp column in the preview).
#      c. Page 2, Step 5 (QA/QC): extract EXIF, check timestamps, check
#         paired stations, check camera health, check coordinates.
#
# WHAT IT DELIBERATELY CREATES:
#   Image Audit tests:
#     - Most cameras: normal, flat, real images                -> "OK"
#     - One camera left completely empty                       -> "Empty — needs review"
#     - One camera pre-marked "...empty" WITH a reason file     -> "Empty (documented)"
#     - One camera pre-marked "...empty" WITHOUT a reason file  -> "Empty (marked, no reason file)"
#     - One camera folder deleted entirely                      -> "Folder missing"
#     - One extra folder that matches no camera in the sheet    -> flagged "unexpected"
#   Rename tests (sub-folders, brand-agnostic consolidation):
#     - One camera: "100RECNX"/"101RECNX" sub-folders (Reconyx-style)
#     - One camera: "CUDD1"/"CUDD2" sub-folders (Cuddeback-style)
#     - One camera: single generic "DCIM" sub-folder
#     (all three use REAL, chronologically-ordered EXIF timestamps within
#     their actual deployment window, so after renaming they should show
#     "OK" in QA/QC too — proving the consolidation preserved order)
#   QA/QC tests:
#     - One camera: real dates shifted a whole number of years (calendar-
#       aware, true duration preserved) -> "Timestamp mismatch"
#     - One true co-located pair (same CT station ID, 2 CT Locs): one
#       station member shifted a different whole number of years ->
#       paired-station mismatch
#     - All untouched cameras: real timestamps within their actual
#       deployment window -> "OK", proving the baseline case works
#
# Everything else (deployment/retrieval notes, clock-drift columns, lat/
# long) comes straight from your real deployment sheet, so Camera health
# flags and Coordinate check reflect your actual data as-is.
# =============================================================================

library(fs)

# ---- EDIT THESE FOUR LINES --------------------------------------------------
BASE_DIR         <- "~/Desktop/Work/Consultancies/Leopard Ecology & Conservation/App/Sample Folders"                       # matches "Choose output location"
SURVEY_NAME      <- "LEC_2023_S1_Dry"                     # matches what you typed as survey name
DEPLOYMENT_PHASE <- "First_deployment"                    # matches what you typed as deployment phase
DEPLOYMENT_FILE  <- "~/Desktop/Work/Consultancies/Leopard Ecology & Conservation/App/Sample Data/Deployment_Data_Sample.xlsx"  # path to your deployment sheet
# -----------------------------------------------------------------------------

survey_path <- fs::path_expand(file.path(BASE_DIR, SURVEY_NAME))
deployment_file <- fs::path_expand(DEPLOYMENT_FILE)

if (!dir.exists(survey_path)) {
  stop("Can't find '", survey_path, "'. Did you run 'Create folder structure' in the app first, ",
       "and set BASE_DIR/SURVEY_NAME above to match exactly?")
}
if (!file.exists(deployment_file)) {
  stop("Can't find deployment file at '", deployment_file, "'. Edit DEPLOYMENT_FILE above.")
}

cat("Reading deployment sheet...\n")

# --- Minimal, self-contained deployment reader (mirrors app.R's logic) -----
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

# Drop fully-blank padding rows
is_blank <- apply(raw[required], 1, function(r) all(is.na(r) | trimws(as.character(r)) == ""))
df <- raw[!is_blank, , drop = FALSE]

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

df$block_season <- paste0(df$block, "_", df$season)
# site_id is the TRUE per-camera location (CT Loc), matching app.R.
df$site_id <- if ("ct_loc" %in% names(df) && any(!is.na(df$ct_loc) & trimws(as.character(df$ct_loc)) != "")) {
  as.character(df$ct_loc)
} else {
  paste0(df$cell_id, "_", df$ct_station)
}

# Folder-path pieces, matching app.R's TrapTagger-compatible hierarchy:
# SurveyName / {Block}_{DeploymentPhase} / Cell_ID / Site{StationID} / {Loc}_{ID}
df$block_deploy <- paste0(df$block, "_", DEPLOYMENT_PHASE)
df$station_folder <- if ("ct_station_id" %in% names(df)) {
  paste0("Site", df$ct_station_id)
} else {
  paste0("Site", df$cell_id, "st", df$ct_station)
}
df$camera_folder <- paste0(df$site_id, "_", df$ct_id)

if ("date_setup" %in% names(df))     df$setup_date     <- excel_serial_to_date(df$date_setup)
if ("time_setup" %in% names(df))     df$setup_time     <- excel_serial_to_time(df$time_setup)
if ("date_retrieved" %in% names(df)) df$retrieved_date <- excel_serial_to_date(df$date_retrieved)
if ("time_retrieved" %in% names(df)) df$retrieved_time <- excel_serial_to_time(df$time_retrieved)

df$setup_datetime <- suppressWarnings(as.POSIXct(
  paste(df$setup_date, df$setup_time), format = "%Y-%m-%d %H:%M:%S", tz = "UTC"))
df$retrieved_datetime <- suppressWarnings(as.POSIXct(
  paste(df$retrieved_date, df$retrieved_time), format = "%Y-%m-%d %H:%M:%S", tz = "UTC"))

n_valid_setup     <- sum(!is.na(df$setup_datetime))
n_valid_retrieved <- sum(!is.na(df$retrieved_datetime))
cat("Parsed setup dates successfully for", n_valid_setup, "/", nrow(df), "camera(s).\n")
cat("Parsed retrieval dates successfully for", n_valid_retrieved, "/", nrow(df), "camera(s).\n\n")

valid_starts <- df$setup_datetime[!is.na(df$setup_datetime)]
fallback_anchor <- if (length(valid_starts) > 0) {
  as.POSIXct(stats::median(as.numeric(valid_starts)), origin = "1970-01-01", tz = "UTC")
} else {
  as.POSIXct("2023-06-01", tz = "UTC")
}
fallback_start <- fallback_anchor
fallback_end   <- fallback_anchor + 30 * 86400

cat("Found", nrow(df), "camera(s) in the deployment sheet.\n\n")

# --- Helpers -----------------------------------------------------------------

IMAGE_PATTERN <- "\\.(jpg|jpeg|png)$"

create_minimal_jpeg <- function(path) {
  grDevices::jpeg(filename = path, width = 20, height = 20, quality = 30)
  graphics::par(mar = c(0, 0, 0, 0))
  graphics::plot.new()
  grDevices::dev.off()
}

set_exif_datetime <- function(path, datetime) {
  ts <- format(datetime, "%Y:%m:%d %H:%M:%S")
  tryCatch({
    exiftoolr::exif_call(args = c(
      paste0("-DateTimeOriginal=", ts),
      paste0("-CreateDate=", ts),
      "-overwrite_original", "-q", "-q",
      path
    ))
    TRUE
  }, error = function(e) FALSE)
}

shift_datetime_years <- function(dt, years) {
  if (is.na(dt)) return(dt)
  lt <- as.POSIXlt(dt)
  lt$year <- lt$year + years
  as.POSIXct(lt)
}

# Create N real, EXIF-stamped images directly in `dir` (flat, no
# sub-folder), evenly spaced across [start, end] (or an override window).
# Uses generic placeholder names ("IMG_XXXX.jpg"), matching real SD-card
# output — these are deliberately NOT pre-renamed, so running "Rename
# images" in the app is a real, necessary step for every camera, not just
# the sub-folder ones.
make_flat_images <- function(dir, n, start, end, override_start = NULL, override_end = NULL) {
  if (!is.null(override_start) && !is.null(override_end)) {
    start <- override_start; end <- override_end
  } else if (is.na(start) || is.na(end) || start >= end) {
    start <- fallback_start; end <- fallback_end
  }
  times <- seq(start, end, length.out = n)
  n_ok <- 0
  for (i in seq_len(n)) {
    fname <- sprintf("IMG_%04d.jpg", i)
    fpath <- file.path(dir, fname)
    create_minimal_jpeg(fpath)
    if (set_exif_datetime(fpath, times[i])) n_ok <- n_ok + 1
  }
  list(n_ok = n_ok, actual_start = start, actual_end = end)
}

# Create N real, EXIF-stamped images inside a NEW sub-folder of `dir` (SD-
# card-style), continuing a running image-number sequence for chronological
# ordering across sub-folders. Placeholder "IMG_XXXX.jpg"-style names, since
# these are meant to be consolidated+renamed by the app's Rename step.
make_subfolder_images <- function(camera_dir, subfolder_name, n, start, end, start_index = 1) {
  sub_dir <- file.path(camera_dir, subfolder_name)
  fs::dir_create(sub_dir)
  times <- seq(start, end, length.out = n)
  for (i in seq_len(n)) {
    fname <- sprintf("IMG_%04d.jpg", start_index + i - 1)
    fpath <- file.path(sub_dir, fname)
    create_minimal_jpeg(fpath)
    set_exif_datetime(fpath, times[i])
  }
}

clear_folder_completely <- function(dir) {
  existing_files <- list.files(dir, recursive = TRUE, full.names = TRUE)
  existing_files <- existing_files[!file.info(existing_files)$isdir]
  if (length(existing_files) > 0) file.remove(existing_files)
  old_subdirs <- list.dirs(dir, recursive = FALSE, full.names = TRUE)
  for (sd in old_subdirs) {
    if (length(list.files(sd, all.files = TRUE, no.. = TRUE)) == 0) fs::dir_delete(sd)
  }
}

# A camera folder may already exist under an "empty" suffix (from a
# previous run of this script, or real Image Audit use) rather than its
# plain name. Checks both, restoring the "empty" variant to plain if found,
# so re-running this script always starts from a clean, known state.
resolve_and_restore_camera_dir <- function(plain_path) {
  if (dir.exists(plain_path)) return(list(path = plain_path, found = TRUE))
  empty_path <- paste0(plain_path, "empty")
  if (dir.exists(empty_path)) {
    file.rename(empty_path, plain_path)
    return(list(path = plain_path, found = TRUE))
  }
  list(path = plain_path, found = FALSE)
}

# --- Assign special roles to specific cameras --------------------------------

n_cams <- nrow(df)
role <- rep("normal", n_cams)

special_needed <- c("mismatch", "empty_review", "empty_documented", "empty_no_reason",
                     "missing", "reconyx", "cuddeback", "single_subfolder", "multi_visit")
n_special <- min(length(special_needed), n_cams)
if (n_cams < length(special_needed)) {
  cat("WARNING: only", n_cams, "camera(s) in this deployment sheet — some test scenarios",
      "below will be skipped (need at least", length(special_needed), "for all of them).\n\n")
}
for (i in seq_len(n_special)) role[i] <- special_needed[i]

# Find a genuine co-located pair (same ct_station_id, 2 distinct CT Locs) for
# the paired-station mismatch test — the SECOND member of the pair gets its
# own role; the first stays "normal" so the mismatch is between them.
has_station_id <- "ct_station_id" %in% names(df)
group_key <- if (has_station_id) df$ct_station_id else paste(df$block_season, df$cell_id)
pair_key_groups <- split(seq_len(n_cams), group_key)
valid_pair_groups <- pair_key_groups[sapply(pair_key_groups, function(idx) {
  length(unique(df$site_id[idx])) == 2 && all(role[idx] == "normal")
})]
pair_second_idx <- NA_integer_
if (length(valid_pair_groups) > 0) {
  g <- valid_pair_groups[[1]]
  g <- g[!duplicated(df$site_id[g])]
  g <- g[order(df$site_id[g])]
  pair_second_idx <- g[2]
  role[pair_second_idx] <- "pair_mismatch"
}

MISMATCH_YEAR_SHIFT <- -6
PAIR_YEAR_SHIFT <- -1

cat("=== Test plan ===\n")
for (i in seq_len(n_cams)) {
  if (role[i] != "normal") {
    cat(sprintf("  [%s] %s / %s (camera %s)\n", role[i], df$site_id[i], df$station_folder[i], df$ct_id[i]))
  }
}
if (is.na(pair_second_idx)) {
  cat("  No genuine co-located pair found in this deployment sheet; skipping paired-station test.\n")
}
cat("  All other cameras: normal, real EXIF within their actual deployment window -> expect 'OK'\n\n")

# --- Process every camera ----------------------------------------------------

for (i in seq_len(n_cams)) {
  row <- df[i, ]
  cam_dir_plain <- file.path(survey_path, row$block_deploy, row$cell_id,
                              row$station_folder, row$camera_folder)
  resolved <- resolve_and_restore_camera_dir(cam_dir_plain)

  if (!resolved$found) {
    cat("Skipping", row$ct_id, "- folder not found (checked both plain and 'empty' names):",
        cam_dir_plain, "\n")
    next
  }
  cam_dir <- resolved$path
  clear_folder_completely(cam_dir)

  r <- role[i]

  if (r == "empty_review") {
    cat("[empty_review]", row$site_id, "/", row$ct_id, "- left empty (no rename, no reason)\n")

  } else if (r == "empty_documented") {
    new_dir <- paste0(cam_dir, "empty")
    fs::dir_create(new_dir)
    fs::dir_delete(cam_dir)
    writeLines("Camera stolen — reported to site manager 2024-06-02", file.path(new_dir, "EMPTY_REASON.txt"))
    cat("[empty_documented]", row$site_id, "/", row$ct_id, "- marked empty WITH reason file\n")

  } else if (r == "empty_no_reason") {
    new_dir <- paste0(cam_dir, "empty")
    fs::dir_create(new_dir)
    fs::dir_delete(cam_dir)
    cat("[empty_no_reason]", row$site_id, "/", row$ct_id, "- marked empty WITHOUT reason file\n")

  } else if (r == "missing") {
    fs::dir_delete(cam_dir)
    cat("[missing]", row$site_id, "/", row$ct_id, "- folder deleted entirely\n")

  } else if (r == "reconyx") {
    start <- if (is.na(row$setup_datetime)) fallback_start else row$setup_datetime
    end   <- if (is.na(row$retrieved_datetime)) fallback_end else row$retrieved_datetime
    mid   <- start + as.numeric(difftime(end, start, units = "secs")) / 2
    make_subfolder_images(cam_dir, "100RECNX", 6, start, mid, start_index = 1)
    make_subfolder_images(cam_dir, "101RECNX", 4, mid, end, start_index = 7)
    cat("[reconyx]", row$site_id, "/", row$ct_id, "- '100RECNX' (6) + '101RECNX' (4), real EXIF\n")

  } else if (r == "cuddeback") {
    start <- if (is.na(row$setup_datetime)) fallback_start else row$setup_datetime
    end   <- if (is.na(row$retrieved_datetime)) fallback_end else row$retrieved_datetime
    mid   <- start + as.numeric(difftime(end, start, units = "secs")) / 2
    make_subfolder_images(cam_dir, "CUDD1", 5, start, mid, start_index = 1)
    make_subfolder_images(cam_dir, "CUDD2", 5, mid, end, start_index = 6)
    cat("[cuddeback]", row$site_id, "/", row$ct_id, "- 'CUDD1' (5) + 'CUDD2' (5), real EXIF\n")

  } else if (r == "single_subfolder") {
    start <- if (is.na(row$setup_datetime)) fallback_start else row$setup_datetime
    end   <- if (is.na(row$retrieved_datetime)) fallback_end else row$retrieved_datetime
    make_subfolder_images(cam_dir, "DCIM", 7, start, end, start_index = 1)
    cat("[single_subfolder]", row$site_id, "/", row$ct_id, "- single 'DCIM' sub-folder (7), real EXIF\n")

  } else if (r == "multi_visit") {
    # Simulates a field technician swapping this camera's SD card
    # mid-deployment without fully retrieving it — per the SOP, this
    # produces two sibling folders with a trailing letter suffix instead
    # of one plain folder (e.g. "F01C_LEC134a", "F01C_LEC134b"). The
    # plain folder itself shouldn't exist afterward — the technician
    # renamed it, not left it alongside the suffixed ones.
    start <- if (is.na(row$setup_datetime)) fallback_start else row$setup_datetime
    end   <- if (is.na(row$retrieved_datetime)) fallback_end else row$retrieved_datetime
    mid   <- start + as.numeric(difftime(end, start, units = "secs")) / 2
    fs::dir_delete(cam_dir)
    fs::dir_create(paste0(cam_dir, "a"))
    fs::dir_create(paste0(cam_dir, "b"))
    make_flat_images(paste0(cam_dir, "a"), 5, start, mid)
    make_flat_images(paste0(cam_dir, "b"), 5, mid, end)
    cat("[multi_visit]", row$site_id, "/", row$ct_id, "- SD-card-swap: '",
        basename(cam_dir), "a' (5) + '", basename(cam_dir), "b' (5), no plain folder\n", sep = "")

  } else if (r == "mismatch") {
    ov_start <- shift_datetime_years(row$setup_datetime, MISMATCH_YEAR_SHIFT)
    ov_end   <- shift_datetime_years(row$retrieved_datetime, MISMATCH_YEAR_SHIFT)
    result <- make_flat_images(cam_dir, 6, row$setup_datetime, row$retrieved_datetime,
                                override_start = ov_start, override_end = ov_end)
    cat("[mismatch]", row$site_id, "/", row$ct_id, "- shifted", MISMATCH_YEAR_SHIFT,
        "year(s) (true duration preserved) -> resolve with Years =", -MISMATCH_YEAR_SHIFT, "\n")

  } else if (r == "pair_mismatch") {
    ov_start <- shift_datetime_years(row$setup_datetime, PAIR_YEAR_SHIFT)
    ov_end   <- shift_datetime_years(row$retrieved_datetime, PAIR_YEAR_SHIFT)
    result <- make_flat_images(cam_dir, 6, row$setup_datetime, row$retrieved_datetime,
                                override_start = ov_start, override_end = ov_end)
    cat("[pair_mismatch]", row$site_id, "/", row$ct_id, "- shifted", PAIR_YEAR_SHIFT,
        "year(s) -> resolve with Years =", -PAIR_YEAR_SHIFT, "\n")

  } else {
    result <- make_flat_images(cam_dir, sample(4:8, 1), row$setup_datetime, row$retrieved_datetime)
  }
}

# --- Unexpected extra folder (doesn't match any camera in the sheet) --------

normal_rows <- which(role == "normal")
if (length(normal_rows) > 0) {
  ref_row <- df[normal_rows[1], ]
  ref_dir <- file.path(survey_path, ref_row$block_deploy, ref_row$cell_id, ref_row$station_folder)
  if (dir.exists(ref_dir)) {
    fake_dir <- file.path(ref_dir, paste0(ref_row$site_id, "_TYPO999"))
    fs::dir_create(fake_dir)
    create_minimal_jpeg(file.path(fake_dir, "IMG_0001.jpg"))
    cat("\n[unexpected] Created extra folder that matches no camera:", fake_dir, "\n")
  }
}

cat("\nDone. Walk the workflow in the app now:\n")
cat("  1. Image Audit -> run the audit, confirm the mix of statuses above. The\n")
cat("     multi_visit camera should show status 'OK (multi-visit)', with images from\n")
cat("     both its 'a' and 'b' folders counted together -- not 'Folder missing'.\n")
cat("  2. Rename images -> preview (every camera needs renaming now, not just the\n")
cat("     sub-folder ones — check the EXIF timestamp column shows chronological\n")
cat("     order, especially for the sub-folder AND multi_visit cameras), then commit.\n")
cat("     The multi_visit camera's images from both 'a' and 'b' consolidate into one\n")
cat("     plain-named folder, and both source folders are removed once emptied.\n")
cat("  3. QA/QC -> Extract EXIF -> Check timestamps -> confirm the mismatch and\n")
cat("     paired-station cameras are flagged, everything else is OK.\n")
cat("  4. Processing -> Multi-visit handling -> point at this survey folder and\n")
cat("     detect -> confirm the multi_visit camera is found, with its 'a' and 'b'\n")
cat("     folders both listed. Note: if you already ran step 2 above, the 'a'/'b'\n")
cat("     folders will have been consolidated and removed, so nothing will be\n")
cat("     detected here anymore -- run this BEFORE Rename to see it in action.\n")
