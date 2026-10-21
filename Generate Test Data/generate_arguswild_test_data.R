# =============================================================================
# generate_arguswild_test_data.R
#
# Generates a realistic ArgusWild "Standard Format Export" CSV for testing
# Page 3.3 (Import ArgusWild), built from the ACTUAL images already sitting
# in your focal-species export folder (the one "Export for ArgusWild" on
# Page 3.2 created) — not independently fabricated, so the join back to our
# own data via filename is genuinely realistic, same principle as the
# TrapTagger test data reading real local EXIF timestamps.
#
# WHY THIS FORMAT: ArgusWild is built on the Wildbook/WBIA platform (Tech 4
# Conservation's GitHub confirms this directly). Its "Standard Format
# Export" mirrors Wildbook's own documented Bulk Import schema
# (https://wildbook.docs.wildme.org/data/bulk-import-beta.html) — this
# isn't guessed, it's the real, documented field set. The columns used here
# are the ones relevant to joining ArgusWild's individual-ID results back
# to our own species data:
#   - MarkedIndividual.individualID — the whole point of running images
#     through ArgusWild: which specific animal is this?
#   - Encounter.mediaAsset0 — the image filename. This is our join key:
#     since our own focal-species export copies images with their
#     original renamed filename UNCHANGED, this should match exactly.
#   - Encounter.genus / Encounter.specificEpithet — taxonomy
#   - Encounter.year/month/day/hour/minutes — from the image's own real
#     EXIF timestamp (not re-invented)
#   - Encounter.locationID — parsed from the filename itself (our renamed
#     convention already encodes the station)
#   - Encounter.sex, Encounter.lifeStage — additional metadata ArgusWild
#     commonly captures
#
# HOW TO USE:
# 1. Run "Export for ArgusWild" in the app first (Processing -> Focal
#    species export) — this script reads whatever images actually landed
#    in that export folder, organized into species sub-folders.
# 2. Edit EXPORT_DIR below to point at that exact folder.
# 3. Run this script. It writes arguswild_test_export.csv INSIDE
#    EXPORT_DIR itself (an explicit, predictable location — not a
#    relative path depending on R's working directory, which caused
#    exactly this kind of confusion with the TrapTagger test data before).
# 4. Upload that CSV on the Processing page's "Import ArgusWild" tab.
# =============================================================================

suppressWarnings(suppressMessages({
  library(exiftoolr)
  library(fs)
}))

# ---- EDIT THIS LINE to match the export folder from "Export for ArgusWild" -
EXPORT_DIR <- "~/Desktop/Work/Consultancies/Leopard Ecology & Conservation/App/Sample Data"
# -----------------------------------------------------------------------------

export_dir <- fs::path_expand(EXPORT_DIR)
if (!dir.exists(export_dir)) {
  stop("Can't find '", export_dir, "'. Did you run \"Export for ArgusWild\" in the ",
       "app first, and set EXPORT_DIR above to match that exact folder?")
}

OUTPUT_FILE <- file.path(export_dir, "arguswild_test_export.csv")

set.seed(42)

IMAGE_EXTENSION_PATTERN <- "\\.(jpg|jpeg|png)$"

# Species sub-folders (from "Export for ArgusWild") map to genus/species —
# extend this table if you export other focal species later.
species_taxonomy <- list(
  "Leopard"        = c(genus = "Panthera",   species = "pardus"),
  "Lion"           = c(genus = "Panthera",   species = "leo"),
  "Cheetah"        = c(genus = "Acinonyx",   species = "jubatus"),
  "Brown hyena"    = c(genus = "Parahyaena", species = "brunnea"),
  "Spotted hyena"  = c(genus = "Crocuta",    species = "crocuta")
)

# ---- Find every real image across all species sub-folders -----------------
species_dirs <- list.dirs(export_dir, recursive = FALSE, full.names = TRUE)
species_dirs <- species_dirs[basename(species_dirs) != "" ]

if (length(species_dirs) == 0) {
  stop("No species sub-folders found inside '", export_dir, "'. ",
       "Did \"Export for ArgusWild\" actually produce any matched images?")
}

all_images <- character(0)
image_species <- character(0)
for (d in species_dirs) {
  files <- list.files(d, full.names = TRUE, no.. = TRUE)
  files <- files[!dir.exists(files)]
  files <- files[grepl(IMAGE_EXTENSION_PATTERN, files, ignore.case = TRUE)]
  all_images <- c(all_images, files)
  image_species <- c(image_species, rep(basename(d), length(files)))
}

cat("Found", length(all_images), "image(s) across", length(species_dirs), "species folder(s).\n")
if (length(all_images) == 0) {
  stop("No images found in any species sub-folder under '", export_dir, "'.")
}

# ---- Read each image's REAL EXIF timestamp (never inventing one) ----------
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

timestamps <- read_real_timestamps(all_images)
cat(sum(!is.na(timestamps)), "of", length(all_images), "image(s) had a readable EXIF timestamp.\n")

# ---- Parse the station out of our own renamed filename convention ---------
# Filenames look like:
#   {SurveyName}_{Block}_{DeploymentPhase}_{Station}_{Site}_{CameraID}_imgNNNN.ext
# where Station itself can contain an underscore (e.g. "SiteA01st_A"), which
# makes a single split-by-underscore ambiguous. Instead: strip the known,
# fixed-shape suffix (extension, then "_imgNNNN", then the last two
# underscore-separated segments — Site and CameraID, both guaranteed
# underscore-free) off the end, then reconstruct the Station token from
# whatever's left by finding where "Site" starts and joining to the end.
parse_station_from_filename <- function(filename) {
  base <- sub("\\.[^.]+$", "", filename)         # strip extension
  base <- sub("_img[0-9]+$", "", base)           # strip "_imgNNNN"
  parts <- strsplit(base, "_")[[1]]
  if (length(parts) < 3) return(NA_character_)
  station_parts <- parts[seq_len(length(parts) - 2)]  # drop Site(=CT_Loc) + CameraID
  site_start <- which(grepl("^Site", station_parts))
  if (length(site_start) == 0) return(NA_character_)
  paste(station_parts[site_start[length(site_start)]:length(station_parts)], collapse = "_")
}

# ---- Individual ID assignment ----------------------------------------------
# Real leopard nicknames from an actual ArgusWild-using field program
# (Ingwe Research Program, South Africa), for realism — mixed with a couple
# of plain numbered IDs and one genuinely "unidentified" case, since not
# every real encounter gets confidently matched to a known individual.
individual_pool <- c("Corkwood Male", "Nigel", "Kusile", "Leopard014", "Leopard027",
                     "UNIDENTIFIED")

rows <- lapply(seq_along(all_images), function(i) {
  fname <- basename(all_images[i])
  sp <- image_species[i]
  taxon <- if (sp %in% names(species_taxonomy)) species_taxonomy[[sp]] else c(genus = NA, species = NA)
  ts <- timestamps[i]
  station <- parse_station_from_filename(fname)

  data.frame(
    `MarkedIndividual.individualID` = sample(individual_pool, 1),
    `Encounter.mediaAsset0` = fname,
    `Encounter.genus` = unname(taxon["genus"]),
    `Encounter.specificEpithet` = unname(taxon["species"]),
    `Encounter.year` = if (is.na(ts)) NA_integer_ else as.integer(format(ts, "%Y")),
    `Encounter.month` = if (is.na(ts)) NA_integer_ else as.integer(format(ts, "%m")),
    `Encounter.day` = if (is.na(ts)) NA_integer_ else as.integer(format(ts, "%d")),
    `Encounter.hour` = if (is.na(ts)) NA_integer_ else as.integer(format(ts, "%H")),
    `Encounter.minutes` = if (is.na(ts)) NA_integer_ else as.integer(format(ts, "%M")),
    `Encounter.locationID` = station,
    `Encounter.sex` = sample(c("male", "female", "unknown"), 1, prob = c(0.4, 0.4, 0.2)),
    `Encounter.lifeStage` = sample(c("adult", "juvenile", "unknown"), 1, prob = c(0.75, 0.15, 0.1)),
    check.names = FALSE, stringsAsFactors = FALSE
  )
})

final_df <- do.call(rbind, rows)
final_df <- final_df[order(final_df$`Encounter.mediaAsset0`), ]

write.csv(final_df, OUTPUT_FILE, row.names = FALSE, na = "")

cat("\nDone. Wrote", nrow(final_df), "records to\n  ", OUTPUT_FILE, "\n\n")

n_unidentified <- sum(final_df$`MarkedIndividual.individualID` == "UNIDENTIFIED")
cat("Individuals in this export:\n")
print(table(final_df$`MarkedIndividual.individualID`))
cat("\n(", n_unidentified, "of", nrow(final_df), "record(s) are UNIDENTIFIED \u2014",
    "a realistic outcome, not every encounter gets confidently matched.)\n", sep = " ")
