# Sources app.R to pull in every helper function under test, without
# actually launching the Shiny app. app.R's very last line is a bare
# shinyApp(ui, server) call; shinyApp() is temporarily replaced with a
# no-op for the duration of the source() so that call does nothing,
# then restored (or removed, if it didn't exist before) immediately
# after \u2014 the real shiny::shinyApp() is untouched everywhere else,
# including if the actual app is run afterward in the same session.
#
# This app is intentionally one file with no separate R/ package
# structure, so sourcing app.R itself (rather than library()-loading a
# package) is the only way to reach these functions for testing.

app_path <- normalizePath(file.path("..", "..", "app.R"), mustWork = FALSE)
if (!file.exists(app_path)) {
  # Fallback for running testthat::test_dir() from the project root
  # directly rather than via tests/testthat.R.
  app_path <- normalizePath("app.R", mustWork = FALSE)
}
if (!file.exists(app_path)) {
  stop("helper-setup.R could not find app.R \u2014 run tests from the CamTrapManager/ ",
       "project root (e.g. `Rscript tests/testthat.R`), not from inside tests/testthat/.")
}

had_real_shinyApp <- exists("shinyApp", envir = globalenv(), inherits = FALSE)
real_shinyApp <- if (had_real_shinyApp) get("shinyApp", envir = globalenv()) else NULL

assign("shinyApp", function(...) invisible(NULL), envir = globalenv())
withCallingHandlers(
  source(app_path, local = FALSE, echo = FALSE),
  warning = function(w) invokeRestart("muffleWarning")  # package startup messages, not test-relevant
)

if (had_real_shinyApp) {
  assign("shinyApp", real_shinyApp, envir = globalenv())
} else {
  rm("shinyApp", envir = globalenv())
}
rm(had_real_shinyApp, real_shinyApp, app_path)
