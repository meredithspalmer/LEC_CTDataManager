# Camera Trap Data Manager

A desktop R Shiny app for managing the full camera-trap survey workflow, from
raw SD card images through quality control, species identification, and final
statistical analysis. Built for Leopard Ecology & Conservation.

It runs entirely on your own computer. No server, no account, no internet
connection required once installed, and no data ever leaves your machine.

**SEE USER_GUIDE.md FOR A FULL WALKTHROUGH**

---

## What it does

CT Data Manager covers the whole camera-trap survey pipeline, organized into
four stages:

**Ingest & QA/QC**
- Reads your deployment/retrieval sheet (.csv/.xlsx) and validates it
- Audits raw image folders (missing cameras, empty folders, file counts)
- Backs up images (to a local drive or a Synology NAS)
- Renames and consolidates images into a consistent naming convention
- Extracts EXIF timestamps and checks them against your deployment sheet
- Flags paired-camera and camera-health issues on an interactive map
- Lets you batch-correct a camera's clock drift

**Processing**
- Imports species-identification results from TrapTagger or ArgusWild
- Detects knocked-over cameras and handles multi-visit sites
- Exports a focal-species subset for individual ID work

**Visualize & Export**
- Camera effort timelines, coverage maps, and station-level summaries
- Species detection maps, time series, and RAI-vs-covariate plots
- Over ten CSV exports (Camtrap DP-style schema), including station
  metadata, search effort, occupancy-format detection histories, and
  SECR-ready capture data

**Analytics**
- Activity-pattern overlap between species (Ridout & Linkie's method)
- Species richness and diversity (Shannon, Simpson, Chao/Jackknife
  estimators, accumulation curves)
- Single-season occupancy modeling (`unmarked::occu()`) with flexible
  covariates, goodness-of-fit testing, and a predicted-occupancy map

Progress can be saved mid-survey and restored later, so nothing has to be
redone from a half-finished session.

---

## Getting started

### 1. Install R

Download and install R (version 4.2 or later recommended) from
[cran.r-project.org](https://cran.r-project.org). RStudio, a free editor for R,
makes the next steps easier: [posit.co/download/rstudio-desktop](https://posit.co/download/rstudio-desktop).

### 2. Download this app

Click the green **Code** button near the top of this page, then
**Download ZIP**, and unzip it somewhere on your computer. If you're
comfortable with git, cloning the repo works the same way.

### 3. Install dependencies (one time)

Open `install_packages.R` in RStudio and click **Source** (or run
`source("install_packages.R")` in the R console). This installs every R
package the app needs, plus the ExifTool command-line tool it relies on for
reading image timestamps.

### 4. Launch the app

Open `LAUNCH_APP.R` in RStudio and click **Source**, or just double-click
the file. The app opens in your default browser.

You only need to repeat step 4 each time you want to use the app. Step 3
only needs to happen once per computer.

---

## Try it with sample data first

The `Generate Test Data/` folder has scripts that generate a complete,
realistic synthetic survey (deployment sheet, EXIF-stamped images, TrapTagger
detections, GIS layers), so you can try every feature of the app without
needing real field data. Run `generate_full_test_data.R` for the most
complete walkthrough.

---

## Running the test suite

This app has an automated test suite (via the `testthat` package) covering
its core data-processing logic. From an R console, with this project folder
as your working directory:

```r
testthat::test_dir("Test")
```

---

## License

Released under the [MIT License](LICENSE). Free to use, modify, and adapt,
including for other camera-trap surveys and conservation organizations.

## Questions or issues

Found a bug, or have a feature request? Open an
[issue](../../issues) on this repository.
