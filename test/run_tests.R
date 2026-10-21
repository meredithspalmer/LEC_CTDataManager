# Run the test suite. From an R/RStudio console, with the CamTrapManager/
# project folder as your working directory:
#
#   testthat::test_dir("tests/testthat")
#
# If you've instead copied these files into one flat folder together
# with app.R (rather than this tests/testthat/ layout), run this from
# that folder instead:
#
#   testthat::test_dir(".")
#
# Either way, tests/testthat/helper-setup.R sources app.R itself (with
# shinyApp() temporarily disabled, so it doesn't try to launch) to pull
# in every helper function under test — there's no separate R/ package
# structure to load, since this app is one file by design. For that to
# work, app.R needs to be reachable at "../../app.R" relative to the
# test files (the normal tests/testthat/ layout) OR directly in the
# current folder (the flat layout) — helper-setup.R tries both.
#
# NOTE: this file is named run_tests.R, not testthat.R — a file named
# testthat.R sitting in the SAME folder as the test files themselves
# matches testthat's own file-detection pattern and gets run AS a test
# rather than treated as a separate runner script.
