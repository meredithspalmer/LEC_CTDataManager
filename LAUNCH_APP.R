# =============================================================================
# CamTrap Manager — Launcher
# Double-click this file to start the app in your browser.
# R must be installed. Run install_packages.R first if launching for the first time.
# =============================================================================

app_dir <- dirname(normalizePath(sys.frame(1)$ofile, mustWork = FALSE))
if (is.null(app_dir) || !nchar(app_dir)) app_dir <- getwd()

cat("Starting CamTrap Manager...\n")
cat("App location:", app_dir, "\n")
cat("Opening in your default browser.\n\n")

shiny::runApp(
  appDir = app_dir,
  launch.browser = TRUE,
  port = 3838
)
