# =============================================================================
# CamTrap Manager — Package Installer
# Run this script ONCE before launching the app for the first time.
# Double-click this file in RStudio, then click "Source".
# =============================================================================

cat("Installing CamTrap Manager dependencies...\n\n")

pkgs <- c(
  "shiny",            # Core framework
  "bslib",            # Modern Bootstrap themes
  "jsonlite",         # Safe JS-string embedding for the custom folder browser
  "shinyFiles",       # File/folder browser dialogs
  "shinyjs",          # JavaScript helpers
  "shinycssloaders",  # Loading spinners
  "leaflet",          # Interactive maps
  "DT",               # Interactive tables
  "plotly",           # Interactive charts
  "fs",               # Filesystem operations (folder creation, renaming)
  "httr",             # Synology DSM File Station API calls (server backup)
  "readr",            # CSV reading
  "readxl",           # Excel (.xlsx/.xls) reading
  "openxlsx",         # Fallback Excel reader
  "dplyr",            # Data manipulation
  "tidyr",            # Data reshaping
  "lubridate",        # Date/time handling
  "sf",               # GIS / spatial data (shapefiles, GeoJSON)
  "exiftoolr",        # EXIF metadata extraction (auto-installs its own exiftool binary — no Perl needed)
  NULL
)

missing <- pkgs[!pkgs %in% installed.packages()[, "Package"]]

if (length(missing) == 0) {
  cat("All packages already installed. You're good to go!\n")
} else {
  cat("Installing:", paste(missing, collapse = ", "), "\n\n")
  install.packages(missing, repos = "https://cloud.r-project.org")
  cat("\nInstallation complete.\n")
}

# Optional: only needed to run the test suite under tests/ (see
# tests/testthat.R) — NOT required to run the app itself.
if (!"testthat" %in% installed.packages()[, "Package"]) {
  cat("\n(Optional) 'testthat' isn't installed \u2014 only needed if you want to run\n")
  cat("the test suite under tests/. Install it with:\n")
  cat('  install.packages("testthat")\n')
}

# exiftool is REQUIRED (not optional) — the app uses it to read timestamps
# off camera trap images on the QA/QC page. It's a separate command-line
# tool (not an R package). The exiftoolr package can download and install
# its own standalone copy automatically — no Perl required on Windows.

cat("\n--- Installing exiftool binary (required for EXIF/timestamp extraction) ---\n")

exiftool_ok <- tryCatch({
  exiftoolr::install_exiftool()
  TRUE
}, error = function(e) {
  cat("\nAutomatic exiftool install failed with this error:\n")
  cat(conditionMessage(e), "\n")
  FALSE
})

if (exiftool_ok) {
  cat("exiftool installed successfully.\n")
} else {
  cat("\n=====================================================================\n")
  cat("Automatic install didn't work. Please install ExifTool manually:\n")
  cat("=====================================================================\n\n")
  cat("1. Go to this page in your web browser: https://exiftool.org\n\n")
  cat("2. Download the version for your computer:\n")
  cat("     Mac:     click the link under 'MacOS Package' (a file ending in .pkg)\n")
  cat("     Windows: click the link under 'Windows Executable' (a .zip file)\n")
  cat("     Linux:   easiest option is to open your distro's software/app store\n")
  cat("              and search for 'exiftool' or 'libimage-exiftool-perl'\n\n")
  cat("3. Mac: double-click the downloaded .pkg file and follow the installer.\n")
  cat("   Windows: unzip the downloaded file, then rename the program inside\n")
  cat("            from 'exiftool(-k).exe' to 'exiftool.exe'.\n\n")
  cat("4. That's it — no need to re-run this script. The app will find ExifTool\n")
  cat("   automatically the next time it needs it. You can go ahead and launch\n")
  cat("   the app now (see LAUNCH_APP.R).\n")
}

cat("\nTo launch the app, open app.R and click 'Run App' in RStudio.\n")
