# =============================================================================
# Camera Trap Data Manager — UI Skeleton
# Camera trap data management app for wildlife field technicians
# Leopard Ecology & Conservation
#
# STATUS: UI skeleton only — no backend logic yet.
#         All server-side functions are stubs marked with TODO.
#
# SETUP:  Run install_packages.R first (see companion file).
#         Then: shiny::runApp("app.R")
# =============================================================================

library(shiny)
library(bslib)
library(shinyFiles)
library(leaflet)
library(DT)
library(plotly)
library(shinyjs)
library(shinycssloaders)
library(readxl)
library(openxlsx)
library(readr)
library(dplyr)
library(fs)
library(httr)
library(exiftoolr)
library(sf)
# unmarked specifically (not just AICcmodavg, which stays namespace-only
# via AICcmodavg::) needs to be actually attached here: AICcmodavg::
# mb.gof.test() dispatches on unmarked's own S4 classes/generics
# internally in a way that requires unmarked on the search path, not
# just available via :: \u2014 part of what produced the "object 'unmarked'
# not found" error without this. The rest of that same error came from
# mb.gof.test()'s bootstrap defaulting to parallel worker processes,
# which don't inherit this session's attached packages; run_occupancy_gof()
# passes parallel = FALSE for that reason, so this library() call alone
# isn't the whole fix \u2014 see that function's own comment.
library(unmarked)

# Show the actual R error message inline rather than Shiny's generic
# "An error has occurred" full-page overlay, so a bad input file shows a
# clear message instead of crashing the app.
options(shiny.sanitize.errors = FALSE)

# Bumped every time this file is handed over, so it's easy to confirm (right
# in the app itself, no guessing) whether you're running the latest version.
# Shows on Page 1 and in the navbar footer.
BUILD_LABEL <- "Build 2026-09-26-ca, quieted unmarked's benign factor-conversion message"

# =============================================================================
# THEME
# Grounded in bushveld field-survey work: limestone-grey background, deep
# bushveld green, dry-grass amber for flags. Humanist sans for UI, monospace
# reserved for data values (camera IDs, paths, coordinates) — separating
# "interface chrome" from "recorded data," the way a field ledger does.
# =============================================================================

app_theme <- bs_theme(
  version       = 5,
  bg            = "#EDEEE7",
  fg            = "#1F2E24",
  primary       = "#1F2E24",
  secondary     = "#4B6355",
  success       = "#3D6B4A",
  warning       = "#B8862E",
  danger        = "#8C3527",
  base_font     = font_google("Public Sans"),
  heading_font  = font_google("Public Sans", wght = "600"),
  code_font     = font_google("IBM Plex Mono"),
  font_scale    = 0.95
)

# =============================================================================
# HELPER UI COMPONENTS
# =============================================================================

section_header <- function(title, subtitle = NULL, icon_name = NULL) {
  tagList(
    tags$div(
      class = "section-header mb-3 pb-2",
      tags$h5(
        if (!is.null(icon_name)) tags$i(class = paste0("bi bi-", icon_name), style = "margin-right:8px; color:#1F2E24;"),
        title
      ),
      if (!is.null(subtitle)) tags$p(class = "text-muted small mb-0", subtitle)
    )
  )
}

status_badge <- function(text, type = "secondary") {
  tags$span(class = paste0("badge bg-", type, " me-1"), text)
}

warn_panel <- function(text) {
  tags$div(
    class = "alert alert-warning d-flex align-items-start py-2",
    tags$i(class = "bi bi-exclamation-triangle-fill me-2", style = "flex-shrink: 0; margin-top: 0.2em;"),
    tags$span(text, style = "min-width: 0; overflow-wrap: break-word; word-break: break-word;")
  )
}

info_panel <- function(text, title = NULL) {
  tags$div(
    class = "alert alert-info d-flex align-items-start py-2",
    tags$i(class = "bi bi-info-circle-fill me-2", style = "flex-shrink: 0; margin-top: 0.2em;"),
    tags$div(
      style = "min-width: 0; overflow-wrap: break-word; word-break: break-word;",
      if (!is.null(title)) tags$div(class = "fw-bold mb-1", title),
      tags$span(text)
    )
  )
}

# Matches the visual language of Shiny's own built-in "Upload complete"
# bar (full-width, dark, centered white text) for confirming success
# after a BUTTON-triggered action (e.g. "Extract EXIF data") — those have
# no native equivalent indicator the way file uploads do, so this fills
# that gap consistently wherever it's needed.
success_bar <- function(text) {
  tags$div(
    style = "background-color: #3C7A4D; color: white; text-align: center;
             padding: 8px 12px; border-radius: 4px; font-weight: 500; margin-top: 8px;",
    tags$i(class = "bi bi-check-circle-fill me-2"),
    text
  )
}

# A single labeled statistic (value, with an optional sub-caption),
# displayed inline so several can sit side by side in a row \u2014 used
# wherever a tab needs to show a handful of summary numbers at a glance
# (richness estimates, model AIC, goodness-of-fit statistics, etc.).
stat_box <- function(label, value, sub = NULL) {
  tags$div(style = "display: inline-block; min-width: 160px; margin: 0 16px 12px 0; vertical-align: top;",
    tags$div(class = "small text-muted", label),
    tags$div(style = "font-size: 1.4rem; font-weight: 600; color: #1F2E24;", value),
    if (!is.null(sub)) tags$div(class = "small text-muted", sub))
}

# Paired with sync_optional_upload_visibility() (server-side): a small
# link, placed right where a now-hidden "re-upload" fileInput() was,
# that reveals it again for someone who genuinely wants to replace an
# already-loaded file. Hidden by default via inline style; shinyjs
# controls actual visibility at runtime based on whether the file is
# currently loaded.
replace_file_link <- function(file_input_id) {
  actionLink(paste0(file_input_id, "_replace"), "Replace this file", icon = icon("arrow-repeat"),
    class = "small text-muted", style = "display: none;")
}

placeholder_card <- function(label) {
  tags$div(
    class = "card border-dashed text-center py-4 text-muted",
    style = "border-style: dashed !important; border-radius: 2px;",
    tags$i(class = "bi bi-tools", style = "font-size:1.5rem;"),
    tags$p(class = "mt-2 mb-0 small", label)
  )
}

# =============================================================================
# PAGE 1: INTRO & OVERVIEW
# =============================================================================

page_intro <- nav_panel(
  title = tagList(tags$i(class = "bi bi-house-fill"), " Overview"),
  value = "page_intro",

  tags$div(
    class = "container-fluid py-4",
    style = "max-width: 960px;",

    tags$div(
      class = "d-flex align-items-center mb-4 pb-3 ledger-rule",
      tags$div(
        tags$h2("Camera Trap Data Manager", class = "mb-1"),
        tags$p(
          class = "text-muted mb-0",
          "Camera trap data processing pipeline for Leopard Ecology & Conservation"
        )
      ),
      tags$div(
        class = "ms-auto",
        status_badge(BUILD_LABEL, "secondary")
      )
    ),

    tags$div(
      class = "card mb-4 p-4",
      section_header("What this app does", icon_name = "camera"),
      tags$p(
        "Camera Trap Data Manager guides you through the full camera trap data pipeline,
        from raw SD card images to species metrics ready for analysis.
        No coding required."
      ),

      tags$div(
        class = "pipeline-steps mt-3",
        tags$div(
          class = "d-flex align-items-start mb-3",
          tags$div(class = "step-num me-3 flex-shrink-0", "1"),
          tags$div(
            tags$strong("Ingest & QA/QC"),
            tags$br(),
            tags$span(class = "text-muted small",
              "Build your folder structure, load deployment data, check timestamps and coordinates,
               back up images, and prepare files for TrapTagger upload.")
          )
        ),
        tags$div(
          class = "d-flex align-items-start mb-3",
          tags$div(class = "step-num me-3 flex-shrink-0", "2"),
          tags$div(
            tags$strong("Process Classifications"),
            tags$br(),
            tags$span(class = "text-muted small",
              "Import TrapTagger species classifications, handle camera downtime and revisits,
               and export focal species data to ArgusWild for individual ID.")
          )
        ),
        tags$div(
          class = "d-flex align-items-start mb-3",
          tags$div(class = "step-num me-3 flex-shrink-0", "3"),
          tags$div(
            tags$strong("Visualize & Export"),
            tags$br(),
            tags$span(class = "text-muted small",
              "Generate effort summaries, detection maps, activity patterns,
               RAI plots, and all data exports for occupancy and SECR models.")
          )
        )
      )
    ),

    tags$div(
      class = "card mb-4 p-4",
      section_header("What you'll need", icon_name = "folder-check"),
      tags$table(
        class = "table table-sm table-borderless mb-0 ledger-table",
        tags$thead(
          tags$tr(
            tags$th("Page", class = "text-muted fw-normal small", style = "white-space: nowrap;"),
            tags$th("Inputs", class = "text-muted fw-normal small")
          )
        ),
        tags$tbody(
          tags$tr(
            tags$td(tags$strong("1. Ingest"), style = "white-space: nowrap;"),
            tags$td("Field deployment CSV/Excel · Camera trap images (SD cards)")
          ),
          tags$tr(
            tags$td(tags$strong("2. Process"), style = "white-space: nowrap;"),
            tags$td("TrapTagger classification export CSV · deployment sheet (re-upload directly here if
                     starting fresh) · ArgusWild individual ID export CSV (optional)")
          ),
          tags$tr(
            tags$td(tags$strong("3. Visualize"), style = "white-space: nowrap;"),
            tags$td("Everything can be loaded independently on its \"Load Data\" tab, without needing
                     Ingest/Process done first: deployment sheet, EXIF/timestamp data, TrapTagger data,
                     ArgusWild data, search effort CSV, GIS layers (most optional; different exports
                     need different subsets)")
          )
        )
      )
    ),

    tags$div(
      class = "card mb-4 p-4",
      section_header("Getting started", icon_name = "play-circle"),
      tags$ol(
        class = "ps-3",
        tags$li(class = "mb-2", "Go to the ", tags$strong("Ingest & QA/QC"), " tab"),
        tags$li(class = "mb-2", "Enter your survey name and upload your deployment sheet"),
        tags$li(class = "mb-2", "Generate your folder structure and copy SD card images in"),
        tags$li(class = "mb-2", "Run QA/QC checks, correct any issues, then rename images"),
        tags$li(class = "mb-2", "Upload to TrapTagger and return to the ", tags$strong("Processing"), " tab"),
        tags$li(class = "mb-2", "When classifications are ready, import and export to ArgusWild (if needed)"),
        tags$li("Use the ", tags$strong("Visualize"), " tab to explore results and download outputs")
      )
    ),

    tags$div(
      class = "card mb-4 p-4",
      section_header("Session", icon_name = "save"),
      tags$p(class = "small text-muted",
        "Your progress lives in this browser session and is lost if you refresh or close the tab.
         Save it to a file periodically \u2014 especially before a break \u2014 and load it back here to pick
         up exactly where you left off, on this computer or a different one."),
      downloadButton("dl_session", "Save session", class = "btn btn-primary btn-sm me-2 w-100 mb-2"),
      fileInput("load_session_file", NULL, buttonLabel = "Load session...",
                 placeholder = "No file selected", accept = ".rds", width = "100%"),
      uiOutput("session_load_status"),
      tags$hr(),
      actionButton("btn_new_project", "Start new project (clears everything)",
        class = "btn btn-outline-danger btn-sm"),
      tags$hr(),
      tags$p(class = "small text-muted mb-1", tags$strong("Current project:")),
      textOutput("current_project_name")
    ),

    tags$div(
      class = "card p-4",
      section_header("Contact & support", icon_name = "envelope"),
      tags$p(class = "small mb-1",
        tags$strong("App designer: "), "Meredith S. Palmer"),
      tags$p(class = "small mb-1",
        tags$strong("Email: "), tags$a(href = "mailto:mspalmer.zool@gmail.com", "mspalmer.zool@gmail.com")),
      tags$p(class = "small mb-1",
        tags$strong("Organisation: "), "Leopard Ecology & Conservation"),
      tags$p(class = "small mb-0",
        tags$strong("Version: "), BUILD_LABEL)
    )
  )
)

# =============================================================================
# PAGE 2: INGEST & QA/QC
# =============================================================================

page_ingest <- nav_panel(
  title = tagList(tags$i(class = "bi bi-sd-card"), " Ingest & QA/QC"),
  value = "page_ingest",

  tags$div(
    class = "container-fluid py-4",

    navset_pill(
      id = "ingest_steps",

      nav_panel(
        title = "1 · Survey setup",
        value  = "ingest_survey",
        tags$div(class = "py-3",
          fluidRow(
            column(5,
              tags$div(class = "card p-4",
                section_header("Survey name", icon_name = "tag",
                  subtitle = "Used to name your top-level folder. e.g. LEC_2023_S1_Dry"),
                textInput("survey_name", label = NULL,
                  placeholder = "e.g. LEC_2023_S1_Dry", width = "100%"),
                tags$small(class = "text-muted",
                  "Allowed characters: letters, numbers, underscores, hyphens. No spaces."),

                tags$hr(),
                section_header("Deployment phase", icon_name = "signpost-split",
                  subtitle = "Used in the block-level folder name for TrapTagger compatibility, e.g. First_deployment"),
                textInput("deployment_phase", label = NULL,
                  placeholder = "e.g. First_deployment", width = "100%"),
                tags$small(class = "text-muted",
                  "Folders are named {Block}_{this}, e.g. \"NW_First_deployment\"."),

                tags$hr(),
                section_header("Deployment & retrieval data", icon_name = "table",
                  subtitle = "CSV or Excel file, one row per camera, with both setup and collection details"),
                fileInput("deployment_csv", label = NULL,
                  accept = c(".csv", ".xlsx", ".xls"), buttonLabel = "Browse…", width = "100%"),

                fluidRow(
                  column(6,
                    selectInput("deployment_date_format", "Date format in file",
                      choices = c("Auto-detect" = "",
                                  "M/D/YYYY (e.g. 5/12/2026)" = "%m/%d/%Y",
                                  "D/M/YYYY (e.g. 12/5/2026)" = "%d/%m/%Y",
                                  "YYYY-MM-DD" = "%Y-%m-%d",
                                  "M/D/YY (e.g. 5/12/26)"     = "%m/%d/%y",
                                  "D/M/YY (e.g. 12/5/26)"     = "%d/%m/%y"),
                      width = "100%")
                  ),
                  column(6,
                    selectInput("deployment_time_format", "Time format in file",
                      choices = c("Auto-detect" = "",
                                  "24-hour (13:30:00)" = "%H:%M:%S",
                                  "12-hour (1:30:00 PM)" = "%I:%M:%S %p"),
                      width = "100%")
                  )
                ),
                tags$small(class = "text-muted",
                  "Only matters if dates/times are stored as plain text rather than real Excel date
                   cells; those are read unambiguously either way. If dates look wrong after
                   upload (e.g. an odd year), try a different format here; it reprocesses
                   automatically without needing to re-upload."),

                uiOutput("deployment_validation_ui"),
                DTOutput("deployment_preview_ui")
              )
            ),

            column(7,
              tags$div(class = "card p-4",
                section_header("Folder structure preview", icon_name = "folder-tree",
                  subtitle = "Generated from survey name + deployment data"),
                info_panel("Upload your deployment CSV to preview and create the folder structure."),

                uiOutput("folder_tree_ui"),

                tags$hr(),
                textInput("output_dir_path", "Output location",
                  placeholder = "Paste the full path to where the top-level folder should be created",
                  width = "100%"),
                actionButton("btn_open_output_folder_browser", "Browse\u2026",
                  class = "btn btn-outline-secondary btn-sm", icon = icon("folder2-open")),
                tags$br(), tags$br(),
                actionButton("btn_create_folders", "Create folder structure",
                  class = "btn btn-primary", icon = icon("folder-plus")),
                tags$br(), tags$br(),
                uiOutput("folder_creation_result"),
                tags$p(class = "small text-muted mt-2",
                  tags$i(class = "bi bi-info-circle me-1"),
                  "If a camera's SD card is swapped mid-deployment without fully retrieving the
                  camera, the technician needs to manually add the \"a\"/\"b\" suffix to that
                  camera's folder name on retrieval (e.g. \"F01C_LEC134a\", \"F01C_LEC134b\"); this isn't something the app can create ahead of time, since it doesn't know a
                  swap will happen. Image Audit and Rename (Step 4) both recognize this convention
                  automatically.")
              )
            )
          )
        )
      ),

      nav_panel(
        title = "2 · Image audit",
        value  = "ingest_images",
        tags$div(class = "py-3",
          fluidRow(
            column(4,
              tags$div(class = "card p-4",
                section_header("Select image folder", icon_name = "folder-symlink",
                  subtitle = "Point to your top-level survey folder after copying SD card images in"),
                textInput("image_dir_path", NULL,
                  placeholder = "Paste the full path to your survey folder", width = "100%"),
                actionButton("btn_open_folder_browser", "Browse\u2026",
                  class = "btn btn-outline-secondary btn-sm", icon = icon("folder2-open")),
                tags$br(), tags$br(),
                textOutput("selected_image_dir"),
                tags$hr(),
                actionButton("btn_audit_images", "Run image audit",
                  class = "btn btn-primary", icon = icon("search")),
                tags$br(), tags$br(),
                uiOutput("audit_summary_ui")
              )
            ),
            column(8,
              tags$div(class = "card p-4",
                section_header("Audit results", icon_name = "clipboard-check"),
                DTOutput("audit_table"),
                tags$hr(),
                section_header("Empty folder handling", icon_name = "folder-x",
                  subtitle = "For folders with no images, record a reason and flag them"),
                uiOutput("empty_folder_ui"),
                conditionalPanel(
                  condition = "output.has_flagged_empty_folders",
                  tags$div(class = "mt-2",
                    selectInput("empty_folder_select", "Folder to resolve", choices = NULL, width = "100%"),
                    textInput("empty_reason_text", "Reason (e.g. camera stolen, SD card corrupted)", width = "100%"),
                    actionButton("btn_mark_empty", "Mark as empty & save reason",
                      class = "btn btn-warning btn-sm", icon = icon("check"))
                  )
                ),
                tags$hr(),
                section_header("Camera count check", icon_name = "check-circle"),
                uiOutput("camera_count_check_ui")
              )
            )
          )
        )
      ),

      nav_panel(
        title = "3 · Backup",
        value  = "ingest_backup",
        tags$div(class = "py-3",
          fluidRow(
            column(5,

              tags$div(class = "card p-4 mb-3",
                section_header("Backup type", icon_name = "hdd-network"),
                radioButtons("backup_type", NULL,
                  choices = c("Swiss/Khutse server (via WireGuard)" = "server",
                              "Local folder / USB drive / cloud-sync folder" = "local"),
                  selected = "server", width = "100%")
              ),

              conditionalPanel(
                condition = "input.backup_type == 'server'",

                tags$div(class = "card p-4 mb-3",
                  section_header("Before you start", icon_name = "shield-lock",
                    subtitle = "One-time per session"),
                  tags$p(class = "small mb-1",
                    tags$strong("WireGuard must be Active"), ": the server is only reachable ",
                    "through the VPN tunnel (ask your camp coordinator for the config file if ",
                    "you don't have one yet)."),
                  tags$p(class = "small mb-0 text-muted",
                    "This connects directly to the server over HTTPS; no need to mount or map ",
                    "any drive. Your username and password are used only to log in for this backup ",
                    "and are not saved anywhere.")
                ),

                tags$div(class = "card p-4",
                  section_header("Server login", icon_name = "cloud-upload"),
                  textInput("syno_server_url", "Server address",
                    value = "https://192.168.13.119:5001", width = "100%"),
                  textInput("syno_username", "Username", width = "100%"),
                  passwordInput("syno_password", "Password", width = "100%"),
                  actionButton("btn_test_connection", "Test connection",
                    class = "btn btn-outline-secondary btn-sm", icon = icon("plug")),
                  tags$br(), tags$br(),
                  uiOutput("syno_test_result_ui"),

                  tags$hr(),
                  tags$strong("Survey folder to back up"),
                  tags$br(),
                  textInput("backup_source_path", NULL,
                    placeholder = "Paste the full path to your survey folder", width = "100%"),
                  actionButton("btn_open_backup_source_browser", "Browse\u2026",
                    class = "btn btn-outline-secondary btn-sm", icon = icon("folder2-open")),

                  tags$hr(),
                  actionButton("btn_run_backup_server", "Start backup to server",
                    class = "btn btn-primary", icon = icon("cloud-upload")),
                  tags$br(), tags$br(),
                  uiOutput("backup_progress_ui")
                )
              ),

              conditionalPanel(
                condition = "input.backup_type == 'local'",

                tags$div(class = "card p-4",
                  section_header("Backup destination", icon_name = "cloud-upload",
                    subtitle = "Copy the full survey folder to a local/mounted backup location"),
                  info_panel("Works with any folder your computer can see as a normal drive:
                    a USB/external hard drive, a mapped network drive, or a synced cloud folder
                    (Dropbox, OneDrive, Google Drive desktop app)."),

                  tags$strong("Source (your survey folder)"),
                  tags$br(),
                  textInput("backup_source_path_local", NULL,
                    placeholder = "Paste the full path to your survey folder", width = "100%"),
                  actionButton("btn_open_backup_source_local_browser", "Browse\u2026",
                    class = "btn btn-outline-secondary btn-sm", icon = icon("folder2-open")),

                  tags$hr(),

                  tags$strong("Destination"),
                  tags$br(),
                  textInput("backup_dest_path", NULL,
                    placeholder = "e.g. /Volumes/MyBackupDrive or Z:\\", width = "100%"),
                  actionButton("btn_open_backup_dest_browser", "Browse\u2026",
                    class = "btn btn-outline-secondary btn-sm", icon = icon("folder2-open")),

                  tags$hr(),
                  actionButton("btn_run_backup_local", "Start backup",
                    class = "btn btn-primary", icon = icon("cloud-upload")),
                  tags$br(), tags$br(),
                  uiOutput("backup_progress_ui_local")
                )
              )
            ),
            column(7,
              tags$div(class = "card p-4",
                section_header("Backup verification", icon_name = "shield-check",
                  subtitle = "Folder and file count comparison: source vs. backup"),
                DTOutput("backup_verify_table"),
                uiOutput("backup_verify_warnings")
              )
            )
          )
        )
      ),

      nav_panel(
        title = "4 · Rename images",
        value  = "ingest_rename",
        tags$div(class = "py-3",
          fluidRow(
            column(4,
              tags$div(class = "card p-4",
                section_header("Rename settings", icon_name = "pencil-square"),
                info_panel("Images will be renamed to:
                  SurveyName_Block_Phase_Station_Site_Camera_img0001.jpg, mirroring the actual
                  folder structure (e.g. \"SiteA01st_A_A01A_237\"), so a filename alone is fully
                  traceable back to its folder path. Cell ID is the one thing left out, since
                  the station name already encodes it. Numbers are zero-padded to at least 4
                  digits, more if a camera has over 9999 images."),
                tags$hr(),
                tags$h6(class = "fw-bold mb-2", "Sub-folder handling"),
                tags$p(
                  "If a camera folder contains multiple sub-folders (e.g. 100RECNX, 101RECNX
                   from a Reconyx-style camera, or CUDD1, CUDD2 from a Cuddeback-style camera),
                   images will be consolidated and numbered sequentially before renaming; this works regardless of the sub-folder naming pattern, so different camera
                   brands in the same survey are handled the same way.
                   Original sub-folders are deleted only once they're empty afterward."),
                tags$hr(),
                tags$h6(class = "fw-bold mb-2", "Multi-visit / SD-card-swap handling"),
                tags$p(
                  "If a camera was swapped mid-deployment without full retrieval, per the SOP its
                   two image batches sit in letter-suffixed folders (e.g. \"F01C_LEC134a\",
                   \"F01C_LEC134b\") instead of one plain folder. Renaming consolidates both
                   batches into one plain-named folder, in chronological order (\"a\" before
                   \"b\"), and removes the source folders once emptied."),
                tags$hr(),
                info_panel("Uses the survey folder selected in Step 2 (Image audit)."),
                actionButton("btn_preview_rename", "Preview rename",
                  class = "btn btn-outline-secondary me-2"),
                actionButton("btn_run_rename", "Rename images",
                  class = "btn btn-danger", icon = icon("arrow-repeat")),
                tags$br(),
                tags$small(class = "text-muted mt-2 d-block",
                  "Renaming is irreversible. Ensure backup is complete before proceeding."),
                tags$small(class = "text-muted d-block",
                  "Preview reads each photo's EXIF timestamp to show chronological order; takes a bit longer than an instant preview for large surveys.")
              )
            ),
            column(8,
              tags$div(class = "card p-4",
                section_header("Rename preview", icon_name = "eye"),
                DTOutput("rename_preview_table"),
                tags$hr(),
                section_header("Rename results", icon_name = "clipboard-check"),
                uiOutput("rename_result_ui"),
                DTOutput("rename_result_table")
              )
            )
          )
        )
      ),

      nav_panel(
        title = "5 · QA/QC",
        value  = "ingest_qaqc",
        tags$div(class = "py-3",
          fluidRow(
            column(12,
              tags$div(class = "card p-4 mb-3",
                section_header("EXIF extraction", icon_name = "clock-history",
                  subtitle = "Extract timestamps from image metadata to build the camera trap datasheet"),
                fluidRow(
                  column(3,
                    actionButton("btn_extract_exif", "Extract EXIF data",
                      class = "btn btn-primary", icon = icon("clock"))
                  ),
                  column(9,
                    uiOutput("exif_summary_ui")
                  )
                )
              )
            )
          ),
          fluidRow(
            column(12,
              tags$div(class = "card p-4 mb-3",
                section_header("Timestamp check", icon_name = "calendar-check",
                  subtitle = "Compare image timestamps to deployment sheet start/end dates"),
                sliderInput("timestamp_tolerance_days", "Acceptable date discrepancy (days)",
                  min = 0, max = 14, value = 3, step = 1),
                actionButton("btn_check_timestamps", "Check timestamps",
                  class = "btn btn-primary", icon = icon("calendar-check")),
                tags$hr(),
                plotlyOutput("timestamp_gantt_plot", height = "550px"),
                tags$hr(),
                uiOutput("timestamp_flags_ui")
              )
            )
          ),
          fluidRow(
            column(12,
              tags$div(class = "card p-4 mb-3",
                section_header("Paired station check", icon_name = "camera2",
                  subtitle = "Check for timestamp mismatches at A/B paired stations"),
                uiOutput("paired_station_ui")
              )
            )
          ),
          fluidRow(
            column(12,
              tags$div(class = "card p-4 mb-3",
                section_header("Camera health flags", icon_name = "exclamation-triangle",
                  subtitle = "Cameras with no images, a clock issue, or flagged in deployment notes"),
                DTOutput("camera_health_table")
              )
            )
          ),
          fluidRow(
            column(6,
              tags$div(class = "card p-4 mb-3",
                section_header("Timestamp correction", icon_name = "pen-fill",
                  subtitle = "Correct systematic clock errors (wrong year, time zone drift, etc.)"),
                selectInput("timestamp_correct_scope", "Apply correction to",
                  choices = c("All cameras in survey" = "all",
                              "Selected block" = "block",
                              "Selected grid cell" = "cell",
                              "Selected camera" = "camera"),
                  width = "100%"),
                uiOutput("ts_correction_scope_value_ui"),
                fluidRow(
                  column(6, numericInput("ts_offset_years",  "± Years",   0, width = "100%")),
                  column(6, numericInput("ts_offset_months", "± Months",  0, width = "100%"))
                ),
                fluidRow(
                  column(6, numericInput("ts_offset_days",   "± Days",    0, width = "100%")),
                  column(6, numericInput("ts_offset_minutes","± Minutes", 0, width = "100%"))
                ),
                tags$small(class = "text-muted",
                  "Original timestamps are preserved. Corrections go to a new column."),
                tags$br(), tags$br(),
                actionButton("btn_apply_ts_correction", "Apply correction",
                  class = "btn btn-primary", icon = icon("clock-fill")),
                tags$hr(),
                uiOutput("ts_correction_log_ui")
              )
            ),
            column(6,
              tags$div(class = "card p-4 mb-3",
                section_header("Cameras to exclude", icon_name = "flag",
                  subtitle = "For cameras where the timestamp couldn't be confidently fixed; recorded here now, to be included as a column in the final exported
                              camera-trap datasheet"),
                uiOutput("camera_decision_choice_ui"),
                radioButtons("camera_decision_status", "Include in final analysis?",
                  choices = c("Use" = "use", "Do not use" = "exclude"), selected = "use", inline = TRUE),
                textAreaInput("camera_decision_note", "Note (optional)",
                  placeholder = "e.g. Clock off by unknown amount, no reliable way to correct",
                  width = "100%", rows = 2),
                actionButton("btn_save_camera_decision", "Save decision",
                  class = "btn btn-outline-secondary btn-sm"),
                tags$hr(),
                DTOutput("camera_decisions_table")
              )
            )
          ),
          fluidRow(
            column(12,
              tags$div(class = "card p-4 mb-3",
                section_header("Coordinate check", icon_name = "geo-alt",
                  subtitle = "Plot camera locations, hover to see site ID, flag outliers"),
                actionButton("btn_coord_map_reset", "Zoom to stations",
                  class = "btn btn-primary mb-2", icon = icon("crosshair")),
                leafletOutput("coord_map", height = "280px"),
                tags$hr(),
                uiOutput("coord_flags_ui")
              )
            )
          ),
          fluidRow(
            column(12,
              tags$div(class = "card p-4 mb-3",
                section_header("Export corrected data", icon_name = "download",
                  subtitle = "One row per photo: original AND corrected timestamps, plus each
                              camera's use/do-not-use decision and note"),
                downloadButton("btn_download_corrected_csv", "Download corrected CSV",
                  class = "btn btn-primary"),
                tags$p(class = "small text-muted mt-2 mb-0",
                  "Includes every image's original and corrected timestamp side by side (nothing is
                   ever overwritten), plus the Use/Do not use status and note from \"Cameras to
                   exclude\" above (defaults to \"Use\" for any camera without a saved decision)."),
                tags$hr(),
                info_panel(
                  title = "How this connects to your TrapTagger upload:",
                  text = "TrapTagger reads each image's timestamp from its own EXIF metadata at
                  upload time; it never sees this CSV. So if a camera's clock was wrong, images
                  uploaded as-is will still show the WRONG date in TrapTagger, even though this
                  CSV records the corrected one, since this app doesn't write corrections back
                  into the image files themselves. Two things this CSV should still inform
                  directly: (1) exclude any \"Do not use\" camera's images from the upload
                  entirely, since they were flagged unreliable during QA/QC for a reason; (2)
                  once TrapTagger data comes back, this app's own Cross-check and \"Match to local
                  images\" (Processing) already compare/match against each image's RAW timestamp
                  (not the corrected one) for exactly this reason, since that's genuinely what
                  TrapTagger saw, so don't be surprised if a station's TrapTagger dates look
                  \"wrong\" by the same known offset recorded here.")
              )
            )
          )
        )
      )
    )
  )
)

# =============================================================================
# PAGE 3: PROCESS CLASSIFICATIONS
# =============================================================================

page_process <- nav_panel(
  title = tagList(tags$i(class = "bi bi-layers"), " Processing"),
  value = "page_process",

  tags$div(
    class = "container-fluid py-4",

    navset_pill(
      id = "process_steps",

      nav_panel(
        title = "1 · Import TrapTagger",
        value  = "process_import",
        tags$div(class = "py-3",
          fluidRow(
            column(12,
              tags$div(class = "card p-4 mb-3",
                section_header("Deployment sheet", icon_name = "table",
                  subtitle = "Gap detection and the cross-check below both need this loaded; if you're picking this back up after a break, upload it again here
                              rather than re-doing all of Ingest."),
                uiOutput("process_deployment_status_ui"),
                replace_file_link("process_deployment_csv"),
                tags$div(id = "process_deployment_csv_wrapper",
                  fileInput("process_deployment_csv", "Re-upload deployment sheet (only needed if not already loaded)",
                    accept = c(".csv", ".xlsx", ".xls"), buttonLabel = "Browse…", width = "100%")),
                fluidRow(
                  column(6,
                    tags$label("Survey name", class = "small text-muted mb-1 d-block"),
                    textInput("process_survey_name", label = NULL,
                      placeholder = "e.g. LEC_2023_S1_Dry", width = "100%")
                  ),
                  column(6,
                    tags$label("Deployment phase", class = "small text-muted mb-1 d-block"),
                    textInput("process_deployment_phase", label = NULL,
                      placeholder = "e.g. First_deployment", width = "100%")
                  )
                )
              )
            )
          ),
          fluidRow(
            column(12,
              tags$div(class = "card p-4 mb-3",
                section_header("TrapTagger classification export", icon_name = "file-earmark-spreadsheet",
                  subtitle = "Upload the CSV exported from TrapTagger after species classification"),
                fileInput("traptagger_csv", label = NULL,
                  accept = ".csv", buttonLabel = "Browse…", width = "100%"),
                uiOutput("traptagger_upload_summary_ui")
              )
            )
          ),
          fluidRow(
            column(12,
              tags$div(class = "card p-4 mb-3",
                section_header("Camera downtime gaps", icon_name = "camera-video-off",
                  subtitle = "Define periods when cameras were inactive (knocked over, dead batteries, etc.)"),
                info_panel("TrapTagger registers a knockdown by tagging affected images' Species as
                  \"Knocked Down\"; click below to detect these automatically from the uploaded
                  file. You can also add manual gap periods for anything TrapTagger doesn't capture
                  (dead batteries, etc.). Either way, the original camera-trap data is never changed; gap periods are recorded separately, to be excluded from effort calculations later."),
                actionButton("btn_detect_gaps", "Detect gaps from TrapTagger",
                  class = "btn btn-outline-primary btn-sm me-2", icon = icon("search")),
                actionButton("btn_add_gap", "Add gap period manually",
                  class = "btn btn-outline-secondary btn-sm", icon = icon("plus")),
                tags$br(), tags$br(),
                uiOutput("gap_periods_ui"),
                tags$br(),
                downloadButton("btn_download_search_effort", "Download search effort (CSV)",
                  class = "btn btn-primary"),
                tags$p(class = "small text-muted mt-2 mb-0",
                  "One row per camera's continuous operational period (not just its gaps), following Camtrap DP's \"Deployments\" schema (the open, TDWG/GBIF-backed camera
                   trap data standard), so a camera that goes offline and comes back on gets two
                   separate rows, with the gap simply absent from either. Ready to build camera
                   on/off matrices for occupancy modeling and similar analyses. Start/stop dates
                   come from the DEPLOYMENT SHEET's setup/retrieval dates (not first/last photo
                   timestamps), minus any recorded gaps above. Cameras marked \"Do not use\"
                   (\"Cameras to exclude\", QA/QC) are left out of this export entirely. Any
                   deployment/retrieval notes from the deployment sheet (e.g. \"SD card full\")
                   are included verbatim in deploymentComments, on whichever period they actually
                   explain the start or end of.")
              )
            )
          ),
          fluidRow(
            column(12,
              tags$div(class = "card p-4 mb-3",
                section_header("Cross-check against deployment sheet", icon_name = "arrow-left-right",
                  subtitle = "Compare TrapTagger's own observed activity per station against your
                              deployment sheet's setup/retrieval window"),
                sliderInput("traptagger_tolerance_days", "Acceptable date discrepancy (days)",
                  min = 0, max = 14, value = 3, step = 1),
                actionButton("btn_cross_check_traptagger", "Run cross-check",
                  class = "btn btn-primary", icon = icon("arrow-left-right")),
                tags$br(), tags$br(),
                DTOutput("traptagger_cross_check_table")
              )
            )
          ),
          fluidRow(
            column(12,
              tags$div(class = "card p-4",
                section_header("Classification summary", icon_name = "bar-chart"),
                uiOutput("classification_summary_ui"),
                downloadButton("btn_download_summary_by_species", "Download by species (CSV)",
                  class = "btn btn-primary"),
                downloadButton("btn_download_summary_by_station", "Download by station \u00d7 species (CSV)",
                  class = "btn btn-primary mt-2")
              )
            )
          )
        )
      ),

      nav_panel(
        title = "2 · Focal species export",
        value  = "process_species",
        tags$div(class = "py-3",
          fluidRow(
            column(12,
              tags$div(class = "card p-4 mb-3",
                section_header("Select focal species", icon_name = "binoculars",
                  subtitle = "Species to subset for ArgusWild individual ID upload"),
                selectInput("focal_species", "Focal species",
                  choices = c("(upload TrapTagger data first)"),
                  multiple = TRUE, width = "100%")
              )
            )
          ),
          fluidRow(
            column(12,
              tags$div(class = "card p-4 mb-3",
                section_header("Match to local images", icon_name = "link-45deg",
                  subtitle = "Matches each TrapTagger record to its local image file, by station + EXIF timestamp"),
                info_panel("Point to your survey's top-level folder, the same one used in Image Audit."),
                textInput("focal_species_image_dir_path", "Survey image folder",
                  placeholder = "Paste the full path to your survey's top-level folder", width = "100%"),
                actionButton("btn_open_focal_species_folder_browser", "Browse\u2026",
                  class = "btn btn-outline-secondary btn-sm", icon = icon("folder2-open")),
                tags$br(), tags$br(),
                actionButton("btn_match_focal_species", "Match to local images",
                  class = "btn btn-primary", icon = icon("link-45deg"))
              )
            )
          ),
          fluidRow(
            column(12,
              tags$div(class = "card p-4 mb-3",
                section_header("Focal species preview", icon_name = "table"),
                DTOutput("focal_species_table")
              )
            )
          ),
          fluidRow(
            column(12,
              tags$div(class = "card p-4",
                section_header("Export", icon_name = "box-arrow-up"),
                tags$p(class = "small text-muted",
                  "This will export: (1) filtered classification CSV and
                   (2) a copy of the focal species images into a new folder
                   ready for ArgusWild upload."),
                textInput("argus_export_dir_path", NULL,
                  placeholder = "Paste the full path to where files should be saved", width = "100%"),
                actionButton("btn_open_argus_export_browser", "Browse\u2026",
                  class = "btn btn-outline-secondary btn-sm", icon = icon("folder2-open")),
                tags$br(), tags$br(),
                actionButton("btn_export_argus", "Export for ArgusWild",
                  class = "btn btn-primary", icon = icon("box-arrow-up"))
              )
            )
          )
        )
      ),

      nav_panel(
        title = "3 · Import ArgusWild",
        value  = "process_argus",
        tags$div(class = "py-3",
          fluidRow(
            column(5,
              tags$div(class = "card p-4",
                section_header("ArgusWild individual ID results", icon_name = "person-badge",
                  subtitle = "Upload the Standard Format Export from ArgusWild (optional)"),
                fileInput("arguswild_csv", label = NULL,
                  accept = ".csv", buttonLabel = "Browse…", width = "100%"),
                uiOutput("arguswild_upload_summary_ui"),
                info_panel("Expects ArgusWild's \"Standard Format Export\" (built on the Wildbook
                  platform): MarkedIndividual.individualID, Encounter.mediaAsset0, plus optionally
                  genus/specificEpithet, date fields, locationID, sex and lifeStage. Joins back to
                  whichever species is currently selected on \"Focal species export\", by image
                  filename, so \"Match to local images\" needs to have been run there first.")
              )
            ),
            column(7,
              tags$div(class = "card p-4",
                section_header("Individual ID summary", icon_name = "people"),
                uiOutput("argus_summary_ui"),
                info_panel("Individual ID, Sex, and Life stage cells (highlighted columns) can be
                  edited directly; click a cell to fill in or correct a value ArgusWild left
                  blank or got wrong. Station/Species/Timestamp/Local file are derived from your
                  own data, not editable here."),
                tags$hr(),
                DTOutput("argus_id_table")
              )
            )
          )
        )
      )
    )
  )
)

# =============================================================================
# PAGE 4: VISUALIZE & EXPORT
# =============================================================================

page_visualize <- nav_panel(
  title = tagList(tags$i(class = "bi bi-graph-up"), " Visualize & Export"),
  value = "page_visualize",

  tags$div(
    class = "container-fluid py-4",

    navset_pill(
      id = "viz_tabs",

      nav_panel(
        title = "Load Data",
        value  = "viz_load_data",
        tags$div(class = "py-3",
          fluidRow(
            column(12,
              tags$div(class = "card p-4 mb-3",
                section_header("Deployment sheet", icon_name = "table",
                  subtitle = "Needed for camera stations, effort calculations, and deployment metadata exports"),
                uiOutput("viz_deployment_status_ui"),
                replace_file_link("viz_deployment_csv"),
                tags$div(id = "viz_deployment_csv_wrapper",
                  fileInput("viz_deployment_csv", "Re-upload deployment sheet (only needed if not already loaded)",
                    accept = c(".csv", ".xlsx", ".xls"), buttonLabel = "Browse…", width = "100%")),
                fluidRow(
                  column(6,
                    tags$label("Survey name", class = "small text-muted mb-1 d-block"),
                    textInput("viz_survey_name", label = NULL,
                      placeholder = "e.g. LEC_2023_S1_Dry", width = "100%")
                  ),
                  column(6,
                    tags$label("Deployment phase", class = "small text-muted mb-1 d-block"),
                    textInput("viz_deployment_phase", label = NULL,
                      placeholder = "e.g. First_deployment", width = "100%")
                  )
                )
              )
            )
          ),
          fluidRow(
            column(12,
              tags$div(class = "card p-4 mb-3",
                section_header("EXIF / corrected timestamp data", icon_name = "camera",
                  subtitle = "Needed for sampling effort calculations (when each camera was actually operating)"),
                info_panel("Point to your survey's top-level folder, the same one used in Image Audit.
                  If EXIF data is already loaded (e.g. from QA/QC or Focal species export earlier this
                  session), that's reused as-is."),
                textInput("viz_image_dir_path", "Survey image folder",
                  placeholder = "Paste the full path to your survey's top-level folder", width = "100%"),
                actionButton("btn_open_viz_folder_browser", "Browse\u2026",
                  class = "btn btn-outline-secondary btn-sm", icon = icon("folder2-open")),
                tags$br(), tags$br(),
                actionButton("btn_viz_extract_exif", "Extract EXIF data",
                  class = "btn btn-primary", icon = icon("camera")),
                uiOutput("viz_exif_status_ui")
              )
            )
          ),
          fluidRow(
            column(12,
              tags$div(class = "card p-4 mb-3",
                section_header("TrapTagger classification data", icon_name = "file-earmark-spreadsheet",
                  subtitle = "Needed for species detection/capture exports and activity/species visualizations"),
                uiOutput("viz_traptagger_status_ui"),
                replace_file_link("viz_traptagger_csv"),
                tags$div(id = "viz_traptagger_csv_wrapper",
                  fileInput("viz_traptagger_csv", "Re-upload TrapTagger export (only needed if not already loaded)",
                    accept = ".csv", buttonLabel = "Browse…", width = "100%"))
              )
            )
          ),
          fluidRow(
            column(12,
              tags$div(class = "card p-4 mb-3",
                section_header("ArgusWild individual ID data", icon_name = "person-badge",
                  subtitle = "Needed for individual ID / SECR exports (optional, only if your survey uses individual ID)"),
                uiOutput("viz_arguswild_status_ui"),
                replace_file_link("viz_arguswild_csv"),
                tags$div(id = "viz_arguswild_csv_wrapper",
                  fileInput("viz_arguswild_csv", "Re-upload ArgusWild export (only needed if not already loaded)",
                    accept = ".csv", buttonLabel = "Browse…", width = "100%"))
              )
            )
          ),
          fluidRow(
            column(12,
              tags$div(class = "card p-4 mb-3",
                section_header("Search effort / camera operation periods", icon_name = "camera-video-off",
                  subtitle = "Needed for accurate effort calculations: one row per continuous operational
                              period per camera (Camtrap DP format), optional if there are no recorded gaps"),
                uiOutput("viz_search_effort_status_ui"),
                replace_file_link("viz_search_effort_csv"),
                tags$div(id = "viz_search_effort_csv_wrapper",
                  fileInput("viz_search_effort_csv", "Re-upload search effort CSV (downloaded from Processing \u2192 Camera downtime gaps)",
                    accept = ".csv", buttonLabel = "Browse…", width = "100%"))
              )
            )
          ),
          fluidRow(
            column(12,
              tags$div(class = "card p-4",
                section_header("GIS layers", icon_name = "map",
                  subtitle = "Shapefiles or GeoJSON for habitat/blocks/roads/water sources, etc. (optional, for covariates in Species/Effort visualizations)"),
                uiOutput("viz_gis_status_ui"),
                fileInput("gis_files", label = NULL,
                  accept = c(".shp", ".dbf", ".shx", ".prj", ".geojson", ".gpkg"),
                  multiple = TRUE, buttonLabel = "Browse…", width = "100%"),
                tags$small(class = "text-muted",
                  "For shapefiles, select all component files (.shp, .dbf, .shx, .prj) together."),
                tags$br(), tags$br(),
                DTOutput("viz_gis_camera_count_table")
              )
            )
          )
        )
      ),

      nav_panel(
        title = "Exports",
        value  = "viz_exports",
        tags$div(class = "py-3",
          section_header("Download data outputs", icon_name = "download",
            subtitle = "All exports are CSVs unless noted; load the data each export needs on the \"Load Data\" tab first"),
          fluidRow(class = "mb-3",
            column(4, tags$div(class = "card p-3 mb-4 h-100 d-flex flex-column",
              tags$h6("Camera stations & coordinates"),
              tags$p(class = "small text-muted", "One row per station: Block, Season, Cell ID, coordinates, camera count.", tags$br(), "Needs: deployment sheet."),
              downloadButton("dl_stations", "Download", class = "btn btn-primary mt-auto"))),
            column(4, tags$div(class = "card p-3 mb-4 h-100 d-flex flex-column",
              tags$h6("Sampling effort summary"),
              tags$p(class = "small text-muted", "Total operational days per camera, gaps excluded.", tags$br(), "Needs: deployment sheet (+ search effort CSV, optional)."),
              downloadButton("dl_effort_summary", "Download", class = "btn btn-primary mt-auto"))),
            column(4, tags$div(class = "card p-3 mb-4 h-100 d-flex flex-column",
              tags$h6("Photo counts by species"),
              tags$p(class = "small text-muted", "Number of images per species, survey-wide.", tags$br(), "Needs: TrapTagger data."),
              downloadButton("dl_photo_counts", "Download", class = "btn btn-primary mt-auto")))
          ),
          fluidRow(class = "mb-3",
            column(4, tags$div(class = "card p-3 mb-4 h-100 d-flex flex-column",
              tags$h6("Species detection data"),
              tags$p(class = "small text-muted", "TrapTagger records collapsed into independent events.", tags$br(), "Needs: TrapTagger data."),
              tags$div(class = "mt-auto",
                numericInput("export_independence_threshold", "Independence threshold (minutes)",
                  value = 30, min = 1, max = 1440, width = "100%"),
                downloadButton("dl_species", "Download", class = "btn btn-primary w-100")))),
            column(4, tags$div(class = "card p-3 mb-4 h-100 d-flex flex-column",
              tags$h6("Camera operation matrix"),
              tags$p(class = "small text-muted",
                "Species-agnostic: Camera \u00d7 day matrix of each camera's status. 1 = operating, 0 = set
                 up but not operating (a recorded gap), NA = not set up at all (before setup / after
                 retrieval)."),
              tags$p(class = "small text-muted",
                "Matches ", tags$a(href = "https://jniedballa.github.io/camtrapR/reference/cameraOperation.html",
                  target = "_blank", "camtrapR's cameraOperation()"), " convention. See also the ",
                tags$a(href = "https://cran.r-project.org/web/packages/camtrapR/vignettes/camtrapr3.pdf",
                  target = "_blank", "camtrapR vignette 3"), " (data extraction for occupancy/SECR input)
                 and the ", tags$a(href = "https://cran.r-project.org/web/packages/unmarked/vignettes/unmarked.html",
                  target = "_blank", "unmarked package vignette"), "."),
              tags$p(class = "small text-muted", "Needs: deployment sheet (+ search effort CSV, optional)."),
              downloadButton("dl_effort_matrix", "Download", class = "btn btn-primary mt-auto"))),
            column(4, tags$div(class = "card p-3 mb-4 h-100 d-flex flex-column",
              tags$h6("Species captures (occupancy format)"),
              tags$p(class = "small text-muted",
                "Selected species' detection history at the STATION level (paired cameras at one
                 station share one detector \u2014 occupancy doesn't need to know which exact camera
                 triggered, and excluding those records would disproportionately drop individual-ID
                 data from paired setups). Station \u00d7 day matrix: 1 = detected, 0 = operating but not
                 detected, NA = not surveyed that day."),
              tags$p(class = "small text-muted", "Needs: TrapTagger data + deployment sheet."),
              tags$div(class = "mt-auto",
                selectInput("export_species_select", "Species", choices = c("(upload TrapTagger data first)"), width = "100%"),
                uiOutput("species_occ_exclusion_status"),
                downloadButton("dl_species_occ", "Download", class = "btn btn-primary w-100"))))
          ),
          fluidRow(class = "mb-3",
            column(4, tags$div(class = "card p-3 mb-4 h-100 d-flex flex-column",
              tags$h6("Individual ID data"),
              tags$p(class = "small text-muted", "Per-detection records matched to an individual ID, with sex and life stage.", tags$br(), "Needs: TrapTagger + ArgusWild data; EXIF data required to link them."),
              tags$div(class = "mt-auto",
                uiOutput("individual_id_prereq_status"),
                downloadButton("dl_individual_id", "Download", class = "btn btn-primary mt-2 w-100")))),
            column(4, tags$div(class = "card p-3 mb-4 h-100 d-flex flex-column",
              tags$h6("Individuals by block/season/age-sex"),
              tags$p(class = "small text-muted", "Count matrix: species \u00d7 block \u00d7 season \u00d7 sex/life stage.", tags$br(), "Needs: TrapTagger + ArgusWild + EXIF + deployment sheet."),
              tags$div(class = "mt-auto",
                uiOutput("ind_counts_prereq_status"),
                downloadButton("dl_ind_counts", "Download", class = "btn btn-primary mt-2 w-100")))),
            column(4, tags$div(class = "card p-3 mb-4 h-100 d-flex flex-column",
              tags$h6("SECR input data"),
              tags$p(class = "small text-muted", "Capture history format for the secr R package, for one species at a time \u2014 mixing species in a single SECR model isn't methodologically valid, so this is scoped to your selection below. Detector = STATION, not individual camera (SECR treats co-located cameras as one detector anyway); build the matching trap-location file from \"Camera stations & coordinates,\" deduplicated by station_folder.", tags$br(), "Needs: TrapTagger + ArgusWild + EXIF data, and a deployment sheet with coordinates."),
              tags$div(class = "mt-auto",
                selectInput("export_secr_species_select", "Species", choices = c("(upload ArgusWild data first)"), width = "100%"),
                uiOutput("secr_exclusion_status"),
                downloadButton("dl_secr", "Download", class = "btn btn-primary w-100"))))
          ),
          fluidRow(
            column(12, tags$div(class = "card p-3 mb-4",
              tags$h6("Selected deployment metadata"),
              tags$p(class = "small text-muted", "Choose which deployment sheet columns to include.", tags$br(), "Needs: deployment sheet."),
              uiOutput("metadata_col_picker"),
              downloadButton("dl_metadata", "Download", class = "btn btn-primary mt-3")))
          )
        )
      ),

      nav_panel(
        title = "Effort",
        value  = "viz_effort",
        tags$div(class = "py-3",
          section_header("Sampling effort", icon_name = "calendar-range",
            subtitle = "When each camera was actually operating, and where cameras were lost or had downtime"),
          fluidRow(
            column(4,
              tags$div(class = "card p-3",
                tags$h6("Settings"),
                uiOutput("effort_prereq_status"),
                selectInput("effort_filter_block", "Block", choices = c("All"), width = "100%"),
                tags$hr(),
                radioButtons("effort_map_basemap", "Map background",
                  choices = c("Satellite" = "satellite", "GIS layers" = "gis"), selected = "satellite"),
                tags$small(class = "text-muted",
                  "\"GIS layers\" needs shapefiles/GeoJSON loaded on the Load Data tab \u2014 falls back to a plain basemap otherwise."),
                tags$hr(),
                tags$p(class = "small text-muted",
                  "Timeline: each camera's operational period(s) \u2014 a break in a bar marks a recorded gap."),
                tags$p(class = "small text-muted",
                  "Camera status map: color-coded by whether the camera had any recorded gap or was marked \"Do not use\" during QA/QC.")
              )
            ),
            column(8,
              tags$div(class = "card p-3 mb-3",
                tags$div(class = "d-flex justify-content-between align-items-center mb-2",
                  tags$h6("Camera operation timeline", class = "mb-0"),
                  tags$button(class = "btn btn-outline-secondary btn-sm", icon("download"), "PNG",
                    onclick = "downloadPlotlyAsPng('effort_timeline_plot', 'camera_operation_timeline.png')")),
                plotlyOutput("effort_timeline_plot", height = "420px")),
              tags$div(class = "card p-3 mb-3",
                tags$div(class = "d-flex justify-content-end mb-2",
                  tags$button(class = "btn btn-outline-secondary btn-sm", icon("download"), "PNG",
                    onclick = "downloadMapAsPng('camera_loss_map', 'camera_loss_map_title', 'camera_status_map.png')")),
                tags$div(id = "camera_loss_map_capture",
                  tags$h6(textOutput("camera_loss_map_title", inline = TRUE)),
                  leafletOutput("camera_loss_map", height = "320px"))),
              tags$div(class = "card p-3",
                tags$h6("Camera placement diagnostics"),
                tags$p(class = "small text-muted",
                  "Every camera in the deployment sheet, and exactly what happened to it \u2014 whether it had its
                   own coordinates, whether one was borrowed from a paired camera at the same station, whether
                   it passes the current block filter, and whether it ends up on the map above. Rows shaded
                   pink aren't currently shown on the map; check which column says \"No\" to see why."),
                DTOutput("camera_placement_diagnostic_table"))
            )
          )
        )
      ),

      nav_panel(
        title = "Species",
        value  = "viz_species",
        tags$div(class = "py-3",
          fluidRow(
            column(3,
              tags$div(class = "card p-3",
                section_header("Settings", icon_name = "sliders"),
                uiOutput("species_tab_prereq_status"),
                selectInput("viz_species_select", "Species", choices = c("(load data first)"), width = "100%"),
                numericInput("independence_threshold", "Independence threshold (minutes)",
                  value = 30, min = 1, max = 1440, width = "100%"),
                tags$small(class = "text-muted",
                  "Captures within this window at the same site count as one event."),
                tags$hr(),
                selectInput("viz_covariate", "Environmental covariate (for RAI)",
                  choices = c("(load deployment data first)"), width = "100%")
              )
            ),
            column(9,
              tags$div(class = "card p-3 mb-3",
                tags$div(class = "d-flex justify-content-between align-items-center mb-2",
                  tags$h6("Captures through time", class = "mb-0"),
                  tags$button(class = "btn btn-outline-secondary btn-sm", icon("download"), "PNG",
                    onclick = "downloadPlotlyAsPng('species_time_plot', 'captures_through_time.png')")),
                plotlyOutput("species_time_plot", height = "220px")),
              fluidRow(
                column(6, tags$div(class = "card p-3 mb-3",
                  tags$div(class = "d-flex justify-content-end mb-2",
                    tags$button(class = "btn btn-outline-secondary btn-sm", icon("download"), "PNG",
                      onclick = "downloadMapAsPng('species_space_map', 'species_space_map_title', 'captures_through_space.png')")),
                  tags$div(id = "species_space_map_capture",
                    tags$h6(textOutput("species_space_map_title", inline = TRUE)),
                    leafletOutput("species_space_map", height = "260px")))),
                column(6, tags$div(class = "card p-3 mb-3",
                  tags$div(class = "d-flex justify-content-between align-items-center mb-2",
                    tags$h6("RAI vs covariate", class = "mb-0"),
                    tags$button(class = "btn btn-outline-secondary btn-sm", icon("download"), "PNG",
                      onclick = "downloadPlotlyAsPng('rai_covariate_plot', 'rai_vs_covariate.png')")),
                  plotlyOutput("rai_covariate_plot", height = "260px")))
              )
            )
          )
        )
      )
    )
  )
)

page_analytics <- nav_panel(
  title = tagList(tags$i(class = "bi bi-graph-up-arrow"), " Analytics"),
  value = "page_analytics",

  tags$div(
    class = "container-fluid py-4",

    navset_pill(
      id = "analytics_tabs",

      nav_panel(
        title = "Activity",
        value  = "analytics_activity",
        tags$div(class = "py-3",
          fluidRow(
            column(3,
              tags$div(class = "card p-3",
                section_header("Settings", icon_name = "sliders"),
                uiOutput("activity_tab_prereq_status"),
                selectInput("activity_species_1", "Species 1", choices = c("(load data first)"), width = "100%"),
                selectInput("activity_species_2", "Compare with (optional)",
                  choices = c("None", "(load data first)"), width = "100%"),
                tags$small(class = "text-muted",
                  "Select a second species to overlay activity patterns."),
                tags$hr(),
                selectInput("activity_covariate", "Split Species 1 by (optional)",
                  choices = c("None"), width = "100%"),
                tags$small(class = "text-muted",
                  "Compare the SAME species' activity across levels of this instead \u2014 e.g. dry vs wet
                   season. Takes over from \"Compare with\" above when set, since showing both at once
                   gets unreadable fast."),
                tags$hr(),
                radioButtons("activity_plot_type", "Plot type",
                  choices = c("Circular (kernel)" = "circular", "Linear (24hr)" = "linear"),
                  selected = "circular")
              )
            ),
            column(9,
              tags$div(class = "card p-3 mb-3",
                tags$div(class = "d-flex justify-content-between align-items-center mb-2",
                  tags$h6("Activity pattern", class = "mb-0"),
                  tags$button(class = "btn btn-outline-secondary btn-sm", icon("download"), "PNG",
                    onclick = "downloadPlotlyAsPng('activity_plot', 'activity_pattern.png')")),
                plotlyOutput("activity_plot", height = "380px")),
              tags$div(class = "card p-3",
                tags$h6("Activity-overlap coefficient (\u0394)"),
                tags$p(class = "small text-muted", style = "overflow-wrap: break-word;",
                  "How much the groups above actually coincide in time: 0 = no overlap at all, 1 = identical activity patterns. The standard, citable metric for this (Ridout & Linkie 2009, via the ",
                  tags$code("overlap"),
                  " R package) for questions like temporal niche partitioning between a predator and its prey, or between two competing species. Dhat1 is used below 50 events per group, Dhat4 otherwise (the package's own recommendation). The confidence interval uses 200 bootstrap resamples for responsiveness here, fewer than the 10,000 a published analysis would typically use, so treat it as indicative rather than publication-ready without re-running at a higher resample count."),
                uiOutput("activity_overlap_note"),
                tags$div(style = "max-width: 100%; overflow-x: auto; padding-bottom: 0.5rem;",
                  DTOutput("activity_overlap_table")))
            )
          )
        )
      ),
      nav_panel(
        title = "Diversity",
        value  = "analytics_diversity",
        tags$div(class = "py-3",
          section_header("Species richness & diversity", icon_name = "bar-chart-steps",
            subtitle = "Community-level summaries across the whole survey, not scoped to one species"),
          fluidRow(
            column(3,
              tags$div(class = "card p-3",
                section_header("Settings", icon_name = "sliders"),
                uiOutput("diversity_prereq_status"),
                selectInput("diversity_exclude_species", "Exclude from richness (optional)",
                  choices = character(0), multiple = TRUE, width = "100%"),
                tags$small(class = "text-muted",
                  "Drop non-wildlife categories your species list might include (e.g. \"Human\",
                   \"Vehicle\", \"Blank\") so they don't inflate richness."),
                tags$hr(),
                radioButtons("diversity_accum_xaxis", "Accumulation curve x-axis",
                  choices = c("Number of stations" = "stations", "Sampling effort (trap-nights)" = "effort"),
                  selected = "stations"),
                tags$small(class = "text-muted",
                  "Stations answers \"do we have enough sampling locations.\" Effort answers \"do we have
                   enough sampling time,\" which matters more when stations were deployed for very
                   different durations (staggered deployment, camera failures, recorded gaps). Otherwise
                   a station active 200 days \"counts the same\" as one active 10 days."),
                tags$hr(),
                tags$p(class = "small text-muted",
                  "Each station counts as one sampling unit. Independent events use the same
                   threshold set on the Species/Activity tabs.")
              )
            ),
            column(9,
              tags$div(class = "card p-3 mb-3",
                tags$h6("Diversity summary"),
                uiOutput("diversity_summary_ui")),
              tags$div(class = "card p-3",
                tags$div(class = "d-flex justify-content-between align-items-center mb-2",
                  tags$h6("Species accumulation curve", class = "mb-0"),
                  tags$button(class = "btn btn-outline-secondary btn-sm", icon("download"), "PNG",
                    onclick = "downloadPlotlyAsPng('species_accumulation_plot', 'species_accumulation_curve.png')")),
                tags$p(class = "small text-muted",
                  "Cumulative species richness as more stations are added, in random order. Shaded band:
                   \u00b1 standard deviation across random orderings. A curve that's still rising suggests more
                   survey effort would likely find more species; a flattened one suggests the survey has
                   largely captured the species present."),
                plotlyOutput("species_accumulation_plot", height = "380px"))
            )
          )
        )
      ),
      nav_panel(
        title = "Occupancy",
        value  = "analytics_occupancy",
        tags$div(class = "py-3",
          section_header("Occupancy modeling", icon_name = "geo-alt",
            subtitle = "Single-season, single-species occupancy (unmarked::occu()), fit at the station level"),
          fluidRow(
            column(3,
              tags$div(class = "card p-3",
                section_header("Settings", icon_name = "sliders"),
                uiOutput("occupancy_prereq_status"),
                selectInput("occupancy_species", "Species", choices = c("(load data first)"), width = "100%"),
                numericInput("occupancy_occasion_length", "Occasion length (days)", value = 7, min = 1, step = 1,
                  width = "100%"),
                tags$small(class = "text-muted",
                  "Fewer, longer occasions mean higher detection probability per occasion but less
                   temporal resolution. 7 days is a common starting point for carnivores; shorter
                   surveys or rare species often need longer occasions to get a usable number of
                   detections per occasion."),
                tags$hr(),
                uiOutput("occupancy_psi_covariates_ui"),
                tags$hr(),
                checkboxGroupInput("occupancy_p_covariates", "Detection (p) covariates",
                  choices = c("Survey effort (days operating per occasion)" = "effort",
                              "Occasion number (trend)" = "occasion_num")),
                tags$hr(),
                actionButton("btn_fit_occupancy", tagList(icon("play"), " Fit model"),
                  class = "btn btn-primary w-100"),
                tags$small(class = "text-muted d-block mt-2",
                  "Goodness-of-fit uses 100 bootstrap resamples for responsiveness here, fewer than a
                   published analysis would typically use, so treat it as indicative rather than
                   publication-ready without re-running at a higher resample count.")
              )
            ),
            column(9,
              tags$div(class = "card p-3 mb-3",
                tags$h6("Model summary"),
                uiOutput("occupancy_summary_stats_ui"),
                tags$h6("Occupancy (\u03c8) coefficients", class = "mt-3"),
                tags$div(style = "max-width: 100%; overflow-x: auto; padding-bottom: 0.5rem;",
                  DTOutput("occupancy_state_coef_table")),
                tags$h6("Detection (p) coefficients", class = "mt-3"),
                tags$div(style = "max-width: 100%; overflow-x: auto; padding-bottom: 0.5rem;",
                  DTOutput("occupancy_det_coef_table"))),
              tags$div(class = "card p-3 mb-3",
                tags$h6("Goodness-of-fit (MacKenzie & Bailey 2004)"),
                uiOutput("occupancy_gof_ui")),
              tags$div(class = "card p-3 mb-3",
                tags$div(class = "d-flex justify-content-between align-items-center mb-2",
                  tags$h6(textOutput("occupancy_psi_map_title", inline = TRUE), class = "mb-0"),
                  tags$button(class = "btn btn-outline-secondary btn-sm", icon("download"), "PNG",
                    onclick = "downloadMapAsPng('occupancy_psi_map', 'occupancy_psi_map_title', 'occupancy_by_station.png')")),
                tags$div(id = "occupancy_psi_map_capture",
                  leafletOutput("occupancy_psi_map", height = "400px"))),
              tags$div(class = "card p-3",
                tags$div(class = "d-flex justify-content-between align-items-center mb-2",
                  tags$h6("Predicted occupancy by station", class = "mb-0"),
                  downloadButton("dl_occupancy_predictions", "Download CSV", class = "btn btn-primary btn-sm")),
                tags$div(style = "max-width: 100%; overflow-x: auto; padding-bottom: 0.5rem;",
                  DTOutput("occupancy_site_predictions_table")))
            )
          )
        )
      )

    )
  )
)


# =============================================================================
# AUDIT LOG (global sidebar element)
# =============================================================================

audit_log_ui <- absolutePanel(
  id    = "audit_log_panel",
  fixed = TRUE, draggable = FALSE,
  bottom = 20, right = 20,
  width  = 320,
  tags$div(
    id    = "audit_log_toggle",
    class = "card shadow-sm",
    style = "max-height: 60px; overflow: hidden; transition: max-height 0.3s; border-radius: 2px;",
    tags$div(
      class = "card-header d-flex justify-content-between align-items-center py-2 px-3",
      style = "cursor: pointer; background: #1F2E24; color: white;",
      onclick = "this.parentElement.style.maxHeight = this.parentElement.style.maxHeight === '60px' ? '400px' : '60px';",
      tags$span(tags$i(class = "bi bi-journal-text me-1"), "Audit log"),
      tags$small(textOutput("audit_log_count", inline = TRUE))
    ),
    tags$div(
      class = "card-body p-2",
      style = "max-height: 340px; overflow-y: auto; font-size: 0.78rem; font-family: 'IBM Plex Mono', monospace;",
      uiOutput("audit_log_entries")
    )
  )
)

# =============================================================================
# DATA HELPERS — Deployment/retrieval sheet processing
# Built against Deployment_Data_Sample.xlsx (Leopard Ecology & Conservation)
# =============================================================================

# Map known raw column names to internal standardized names. Matching is
# done after trimming whitespace. Unmatched columns keep their original
# (trimmed) name so nothing is silently dropped.
# Column headers are matched case- and whitespace-insensitively (lowercased,
# underscores/multiple-spaces collapsed to a single space) — real field
# files often differ from any one template in exact case or spacing (e.g.
# "CT station" vs "CT_Station", "lock" vs "Lock"), and there's no reason to
# make the user's data conform to ours instead of the other way around.
normalize_header <- function(x) {
  x <- tolower(trimws(x))
  x <- gsub("[_[:space:]]+", " ", x)
  trimws(x)
}

# Each entry's NAME is the normalized header text; multiple raw headers
# (old template spelling vs. a real file's spelling) can map to the same
# internal column name where they represent the same concept.
DEPLOYMENT_COL_MAP <- c(
  "season"                    = "season",
  "block"                     = "block",
  "n cam per station"         = "n_cam_per_station",
  "n cam centr"               = "n_cam_per_station",
  "cell id"                   = "cell_id",
  "ct station id"             = "ct_station_id",
  "ct station"                = "ct_station",
  "ct loc"                    = "ct_loc",
  "ct id"                     = "ct_id",
  "ct type"                   = "ct_type",
  "sd id"                     = "sd_id",
  "real lat"                  = "lat",
  "real long"                 = "long",
  "survey season"             = "survey_season",
  "date setup"                = "date_setup",
  "time setup"                = "time_setup",
  "height (cm)"               = "height_cm",
  "height cm"                 = "height_cm",
  "bearing"                   = "bearing",
  "habitat"                   = "habitat",
  "attachment"                = "attachment",
  "fixed on"                  = "attachment",
  "lock"                      = "lock",
  "lock type"                 = "lock_type",
  "loc type"                  = "lock_type",
  "notes deployment"          = "notes_deployment",
  "notes"                     = "notes_deployment",
  "ct extras"                 = "ct_extras",
  "date retrieved"            = "date_retrieved",
  "time retrieved"            = "time_retrieved",
  "date retrieved ct"         = "date_retrieved_ct",
  "date on ct at retrieval"   = "date_retrieved_ct",
  "time retrieved ct"         = "time_retrieved_ct",
  "time on ct at retrieval"   = "time_retrieved_ct",
  "date last image"           = "date_last_image",
  "time last image"           = "time_last_image",
  "notes retrieval"           = "notes_retrieval",
  "note retrieved/issues"     = "notes_retrieval"
)

# Columns without which we cannot build the folder structure. "ct_loc" is
# deliberately NOT required — it's strongly recommended (site_id depends on
# it), but a file without it still works via a fallback (see
# add_derived_columns()), for backward compatibility with simpler schemas.
DEPLOYMENT_REQUIRED_COLS <- c("season", "block", "cell_id", "ct_station", "ct_id")
DEPLOYMENT_RECOMMENDED_COLS <- c("lat", "long", "date_setup", "time_setup",
                                  "date_retrieved", "time_retrieved",
                                  "date_retrieved_ct", "time_retrieved_ct",
                                  "ct_station_id", "ct_loc")


# Read the uploaded deployment/retrieval file (CSV or Excel), standardize
# column names, drop blank padding rows/columns, and report which
# required/recommended columns are missing. Never throws — reading or
# processing failures are captured and returned as an error message instead,
# so a bad file shows a clear message rather than crashing the app.
read_deployment_file <- function(filepath, original_name) {
  ext <- tolower(tools::file_ext(original_name))

  read_result <- tryCatch({

    if (ext %in% c("xlsx", "xls")) {
      # Try readxl first; fall back to openxlsx if it errors (readxl can
      # choke on some Excel files, e.g. ones containing legacy cell comments).
      df <- tryCatch({
        readxl::read_excel(filepath, sheet = 1, guess_max = 5000)
      }, error = function(e) {
        openxlsx::read.xlsx(filepath, sheet = 1, detectDates = TRUE)
      })
    } else if (ext == "csv") {
      readr::read_csv(filepath, show_col_types = FALSE)
    } else {
      stop("Unsupported file type: .", ext, ". Please upload a .csv or .xlsx file.")
    }

  }, error = function(e) {
    structure(list(), class = "read_error", message = conditionMessage(e))
  })

  if (inherits(read_result, "read_error")) {
    return(list(data = NULL, missing_required = character(0),
                missing_recommended = character(0),
                error = paste0("Could not read this file. ", read_result$message)))
  }

  df <- as.data.frame(read_result, stringsAsFactors = FALSE)

  # Drop columns with a blank/NA header — leftover Excel formatting artifacts.
  blank_header <- is.na(names(df)) | trimws(names(df)) == "" | grepl("^\\.\\.\\.", names(df))
  df <- df[, !blank_header, drop = FALSE]

  raw_names <- trimws(names(df))
  names(df) <- raw_names
  normalized <- normalize_header(raw_names)
  matched <- normalized %in% names(DEPLOYMENT_COL_MAP)
  names(df)[matched] <- DEPLOYMENT_COL_MAP[normalized[matched]]

  missing_required <- setdiff(DEPLOYMENT_REQUIRED_COLS, names(df))

  # Drop fully-blank padding rows (common Excel export artifact).
  if (length(missing_required) == 0) {
    id_cols <- df[DEPLOYMENT_REQUIRED_COLS]
    is_blank_row <- apply(id_cols, 1, function(r) all(is.na(r) | trimws(as.character(r)) == ""))
    df <- df[!is_blank_row, , drop = FALSE]
  }

  missing_recommended <- setdiff(DEPLOYMENT_RECOMMENDED_COLS, names(df))

  list(data = df, missing_required = missing_required,
       missing_recommended = missing_recommended, error = NULL)
}

# Convert an Excel date serial number (or an already-parsed Date/POSIXct) to
# a proper Date. Never throws — returns NA for anything unparseable.
#
# `format` lets the caller specify exactly how to interpret a TEXT date
# string (e.g. "%m/%d/%Y" vs "%d/%m/%Y") — this matters because a value
# like "5/7/25" is genuinely ambiguous (May 7 vs July 5), and R's default
# assumption (ISO "%Y-%m-%d") can silently misparse it into nonsense (e.g.
# reading "5" as a 4-digit year) rather than erroring, which is why this
# is user-configurable in the app rather than always auto-detected. Only
# applies when the value isn't already a real Date/POSIXct/Excel-serial
# number — those are unambiguous and never affected by this setting.
excel_serial_to_date <- function(x, format = NULL) {
  tryCatch({
    if (inherits(x, "POSIXt")) return(as.Date(x))
    if (inherits(x, "Date"))   return(x)
    if (is.numeric(x))         return(as.Date(x, origin = "1899-12-30"))
    if (!is.null(format) && nchar(format) > 0) {
      x_chr <- trimws(as.character(x))
      result <- suppressWarnings(as.Date(x_chr, format = format))

      # Manually-entered dates commonly mix 2-digit and 4-digit years
      # within the same column (e.g. "5/12/26" alongside "5/12/2026"). %y
      # is strictly 2-digit, but %Y is NOT strictly 4-digit — confirmed
      # directly by this app's own test suite catching it:
      # as.Date("5/12/26", format = "%m/%d/%Y") doesn't fail/return NA the
      # way a strict-width %Y would; it "succeeds," silently taking the
      # 2-digit value LITERALLY as year 26 (not 2026). Checking only for
      # NA to decide which values need a retry with the alternate year
      # width missed this case entirely, since the result isn't NA, just
      # wrong. Also retries any value whose parsed year came back
      # implausibly small (<100) specifically when %Y was the format
      # actually tried — a genuine 4-digit year is never that small.
      alt_format <- if (grepl("%y", format, fixed = TRUE)) {
        sub("%y", "%Y", format, fixed = TRUE)
      } else if (grepl("%Y", format, fixed = TRUE)) {
        sub("%Y", "%y", format, fixed = TRUE)
      } else {
        NULL
      }
      if (!is.null(alt_format)) {
        parsed_year <- suppressWarnings(as.numeric(format(result, "%Y")))
        implausible_year <- grepl("%Y", format, fixed = TRUE) & !is.na(parsed_year) & parsed_year < 100
        needs_retry <- (is.na(result) | implausible_year) & !is.na(x_chr) & x_chr != ""
        if (any(needs_retry)) {
          result[needs_retry] <- suppressWarnings(as.Date(x_chr[needs_retry], format = alt_format))
        }
      }
      return(result)
    }

    # Auto-detect: R's own as.Date() default assumes ISO format
    # ("%Y-%m-%d"), which silently produces nonsense for other common
    # formats rather than erroring (e.g. "5/7/25" -> year 5). Instead, try
    # several common candidate formats and use whichever parses the most
    # values into a PLAUSIBLE date (a real, recent-ish year) — far more
    # likely to get manually-entered field data right without the user
    # needing to pick a format explicitly.
    x_chr <- trimws(as.character(x))
    candidates <- c("%Y-%m-%d", "%m/%d/%Y", "%d/%m/%Y", "%m/%d/%y", "%d/%m/%y")
    best <- NULL
    best_score <- -1
    for (fmt in candidates) {
      parsed <- suppressWarnings(as.Date(x_chr, format = fmt))
      yrs <- suppressWarnings(as.numeric(format(parsed, "%Y")))
      plausible <- !is.na(parsed) & !is.na(yrs) & yrs >= 1990 & yrs <= 2100
      score <- sum(plausible)
      if (score > best_score) {
        best_score <- score
        best <- parsed
      }
    }
    if (!is.null(best) && best_score > 0) return(best)
    suppressWarnings(as.Date(x_chr))
  }, error = function(e) as.Date(rep(NA, length(x))))
}

# Convert an Excel time serial (fraction of a day) or POSIXct/hms to an
# "HH:MM:SS" string. Never throws — returns NA for unparseable values.
# `format` works the same way as excel_serial_to_date's, for a text time
# value like "1:30 PM" vs "13:30".
excel_serial_to_time <- function(x, format = NULL) {
  tryCatch({
    if (inherits(x, "POSIXt")) return(format(x, "%H:%M:%S"))
    if (is.numeric(x)) {
      secs <- round((x %% 1) * 86400)
      return(sprintf("%02d:%02d:%02d", secs %/% 3600, (secs %% 3600) %/% 60, secs %% 60))
    }
    if (!is.null(format) && nchar(format) > 0) {
      parsed <- suppressWarnings(strptime(as.character(x), format = format))
      return(format(parsed, "%H:%M:%S"))
    }
    as.character(x)
  }, error = function(e) rep(NA_character_, length(x)))
}

# Sanity-check derived Date columns for implausible years (well outside any
# reasonable survey date range) — a strong sign the date format setting is
# wrong for this file, e.g. "5/7/25" silently misread with the wrong
# format producing year 5 instead of 2025. Returns a character vector of
# human-readable warnings (empty if everything looks plausible).
check_date_plausibility <- function(df, min_year = 2000, max_year = 2100) {
  date_cols <- intersect(c("setup_date", "retrieved_date", "retrieved_ct_date", "last_image_date"),
                          names(df))
  warnings_out <- character(0)
  for (col in date_cols) {
    yrs <- suppressWarnings(as.numeric(format(df[[col]], "%Y")))
    bad <- !is.na(yrs) & (yrs < min_year | yrs > max_year)
    if (any(bad)) {
      example <- format(df[[col]][bad][1], "%Y-%m-%d")
      warnings_out <- c(warnings_out, paste0(
        "'", col, "' has ", sum(bad), " date(s) with an implausible year (e.g. ", example, "); ",
        "the selected date format is likely wrong for this file."
      ))
    }
  }
  warnings_out
}

# Sanity-check lat/long after numeric coercion: catches values that
# weren't real numbers at all (became NA after coercion, despite the
# original cell having content — e.g. stray text or a formatting quirk)
# and values genuinely outside the valid range for real-world
# coordinates. Returns a character vector of human-readable warnings
# (empty if everything looks plausible).
check_coordinate_plausibility <- function(df, raw_lat = NULL, raw_long = NULL) {
  warnings_out <- character(0)
  if (!("lat" %in% names(df)) || !("long" %in% names(df))) return(warnings_out)

  if (!is.null(raw_lat)) {
    became_na <- is.na(df$lat) & !is.na(raw_lat) & trimws(as.character(raw_lat)) != ""
    if (any(became_na)) {
      example <- trimws(as.character(raw_lat[became_na][1]))
      warnings_out <- c(warnings_out, paste0(
        "'lat' (Real Lat) has ", sum(became_na), " value(s) that aren't valid numbers ",
        "(e.g. \"", example, "\"); check for stray text or formatting in that column."
      ))
    }
  }
  if (!is.null(raw_long)) {
    became_na <- is.na(df$long) & !is.na(raw_long) & trimws(as.character(raw_long)) != ""
    if (any(became_na)) {
      example <- trimws(as.character(raw_long[became_na][1]))
      warnings_out <- c(warnings_out, paste0(
        "'long' (Real Long) has ", sum(became_na), " value(s) that aren't valid numbers ",
        "(e.g. \"", example, "\"); check for stray text or formatting in that column."
      ))
    }
  }

  out_of_range_lat  <- !is.na(df$lat)  & (df$lat  < -90  | df$lat  > 90)
  out_of_range_long <- !is.na(df$long) & (df$long < -180 | df$long > 180)
  if (any(out_of_range_lat)) {
    warnings_out <- c(warnings_out, paste0(
      "'lat' (Real Lat) has ", sum(out_of_range_lat), " value(s) outside the valid range ",
      "(-90 to 90); e.g. ", df$lat[out_of_range_lat][1], "."
    ))
  }
  if (any(out_of_range_long)) {
    warnings_out <- c(warnings_out, paste0(
      "'long' (Real Long) has ", sum(out_of_range_long), " value(s) outside the valid range ",
      "(-180 to 180); e.g. ", df$long[out_of_range_long][1], "."
    ))
  }

  warnings_out
}

# Add derived folder-hierarchy columns and combined datetime columns.
# Folder hierarchy: Survey Name / Block_Season / Cell_ID / Site (= CT Loc) / Camera (CT_ID)
#
# site_id is the TRUE per-camera physical location, taken directly from
# "CT Loc" (e.g. "A01A", "A01B") — NOT synthesized from Cell_ID + station
# letter. A station can have 1 or 2 CT Locs (single vs. co-located double
# camera setup); collapsing both cameras of a double-camera station down
# to "{cell}_{station letter}" would incorrectly give them the same
# site_id. Falls back to the old cell+station formula only if a file has
# no "CT Loc" column at all, for backward compatibility.
#
# `date_format`/`time_format` are optional user-specified overrides (see
# check_date_plausibility) for text-based date/time values that Excel
# didn't store as real date cells.
add_derived_columns <- function(df, date_format = NULL, time_format = NULL) {
  df$block_season <- paste0(df$block, "_", df$season)
  df$site_id <- if ("ct_loc" %in% names(df) && any(!is.na(df$ct_loc) & trimws(as.character(df$ct_loc)) != "")) {
    as.character(df$ct_loc)
  } else {
    paste0(df$cell_id, "_", df$ct_station)
  }

  # station_folder ("SiteA01st_A") doesn't depend on deployment_phase
  # (unlike block_deploy, computed later in get_camera_folder_table() once
  # that's entered) — computed here so it's available immediately.
  #
  # Kept WITH the underscore from ct_station_id's raw value ("A01st_A"),
  # matching the deployment sheet's own notation, even though TrapTagger's
  # real site names have no underscore ("SiteA01stA" — its site-detection
  # regex, Site[A-Z][0-9]+st[A-Z], has none). Rather than change our folder
  # naming to match TrapTagger (which would mean renaming every folder
  # already created), the underscore is normalized away ONLY when
  # comparing against TrapTagger data — see normalize_station_name() in
  # the TrapTagger import helpers below.
  df$station_folder <- if ("ct_station_id" %in% names(df)) {
    paste0("Site", df$ct_station_id)
  } else {
    paste0("Site", df$cell_id, "st", df$ct_station)
  }

  # Coordinates sometimes come through as text (stray spaces, a
  # thousands-separator, etc.) rather than real numbers — a leaflet map
  # silently plots nothing at all if lat/long aren't numeric, with no
  # error, so this is coerced explicitly rather than left to chance.
  if ("lat" %in% names(df))  df$lat  <- suppressWarnings(as.numeric(as.character(df$lat)))
  if ("long" %in% names(df)) df$long <- suppressWarnings(as.numeric(as.character(df$long)))

  if ("date_setup" %in% names(df)) df$setup_date <- excel_serial_to_date(df$date_setup, date_format)
  if ("time_setup" %in% names(df)) df$setup_time <- excel_serial_to_time(df$time_setup, time_format)
  if ("date_retrieved" %in% names(df)) df$retrieved_date <- excel_serial_to_date(df$date_retrieved, date_format)
  if ("time_retrieved" %in% names(df)) df$retrieved_time <- excel_serial_to_time(df$time_retrieved, time_format)
  if ("date_retrieved_ct" %in% names(df)) df$retrieved_ct_date <- excel_serial_to_date(df$date_retrieved_ct, date_format)
  if ("time_retrieved_ct" %in% names(df)) df$retrieved_ct_time <- excel_serial_to_time(df$time_retrieved_ct, time_format)
  if ("date_last_image" %in% names(df)) df$last_image_date <- excel_serial_to_date(df$date_last_image, date_format)
  if ("time_last_image" %in% names(df)) df$last_image_time <- excel_serial_to_time(df$time_last_image, time_format)

  # Combined POSIXct datetimes, used throughout QA/QC (timestamp checks,
  # paired-station comparison, clock-drift flagging). Built defensively —
  # missing pieces just produce NA rather than an error.
  combine_dt <- function(date_col, time_col) {
    if (!(date_col %in% names(df)) || !(time_col %in% names(df))) return(as.POSIXct(rep(NA, nrow(df))))
    suppressWarnings(as.POSIXct(paste(as.character(df[[date_col]]), df[[time_col]]),
                                 format = "%Y-%m-%d %H:%M:%S", tz = "UTC"))
  }
  df$setup_datetime        <- combine_dt("setup_date", "setup_time")
  df$retrieved_datetime    <- combine_dt("retrieved_date", "retrieved_time")
  df$retrieved_ct_datetime <- combine_dt("retrieved_ct_date", "retrieved_ct_time")

  df
}

# Build the list of unique folder paths (relative to a chosen output
# location), matching the exact hierarchy TrapTagger's own upload tool
# expects (per the client's Trap Tagger Images Processing SOP):
#   SurveyName / {Block}_{DeploymentPhase} / Cell_ID / Site{CT_Station_ID} / {CT_Loc}_{CT_ID}
# The "Site" folder is the STATION (e.g. "SiteA01stA"), not the individual
# camera location — a double-camera station's two locations are sibling
# folders inside the same Site folder. TrapTagger's own upload tool uses a
# regex (Site[A-Z][0-9]+st[A-Z]) to find this folder, so the literal "Site"
# prefix and exact spacing matter. Falls back to reconstructing the station
# ID from cell_id + ct_station if a file has no ct_station_id column.
build_folder_paths <- function(df, survey_name, deployment_phase) {
  df$block_deploy <- paste0(df$block, "_", deployment_phase)
  df$station_folder <- if ("ct_station_id" %in% names(df)) {
    paste0("Site", df$ct_station_id)
  } else {
    paste0("Site", df$cell_id, "st", df$ct_station)
  }
  df$camera_folder <- paste0(df$site_id, "_", df$ct_id)

  hierarchy <- unique(df[c("block_deploy", "cell_id", "station_folder", "camera_folder")])
  hierarchy <- hierarchy[order(hierarchy$block_deploy, hierarchy$cell_id,
                                hierarchy$station_folder, hierarchy$camera_folder), ]
  file.path(survey_name, hierarchy$block_deploy, hierarchy$cell_id,
            hierarchy$station_folder, hierarchy$camera_folder)
}

# Render a nested, collapsible tree from the hierarchy columns, so the user
# can visually verify the structure before creating folders on disk.
render_folder_tree <- function(df, survey_name, deployment_phase) {
  df$block_deploy <- paste0(df$block, "_", deployment_phase)
  df$station_folder <- if ("ct_station_id" %in% names(df)) {
    paste0("Site", df$ct_station_id)
  } else {
    paste0("Site", df$cell_id, "st", df$ct_station)
  }
  df$camera_folder <- paste0(df$site_id, "_", df$ct_id)
  hierarchy <- unique(df[c("block_deploy", "cell_id", "station_folder", "camera_folder")])

  tags$div(class = "folder-tree", style = "font-family: 'IBM Plex Mono', monospace; font-size: 0.85rem;",
    tags$div(tags$i(class = "bi bi-folder-fill", style="color:#B8862E;"), " ", tags$strong(survey_name)),
    tags$ul(style = "list-style: none; padding-left: 18px; border-left: 1px dashed #ccc;",
      lapply(sort(unique(hierarchy$block_deploy)), function(bs) {
        bs_df <- hierarchy[hierarchy$block_deploy == bs, ]
        tags$li(
          tags$div(tags$i(class = "bi bi-folder-fill", style="color:#B8862E;"), " ", bs),
          tags$ul(style = "list-style: none; padding-left: 18px; border-left: 1px dashed #ccc;",
            lapply(sort(unique(bs_df$cell_id)), function(cid) {
              cid_df <- bs_df[bs_df$cell_id == cid, ]
              tags$li(
                tags$div(tags$i(class = "bi bi-folder-fill", style="color:#B8862E;"), " ", cid),
                tags$ul(style = "list-style: none; padding-left: 18px; border-left: 1px dashed #ccc;",
                  lapply(sort(unique(cid_df$station_folder)), function(sf) {
                    sf_df <- cid_df[cid_df$station_folder == sf, ]
                    tags$li(
                      tags$div(tags$i(class = "bi bi-folder-fill", style="color:#B8862E;"), " ", sf),
                      tags$ul(style = "list-style: none; padding-left: 18px; border-left: 1px dashed #ccc;",
                        lapply(sort(unique(sf_df$camera_folder)), function(cam) {
                          tags$li(class = "text-muted",
                            tags$i(class = "bi bi-camera-fill", style="color:#4B6355;"), " ", cam)
                        })
                      )
                    )
                  })
                )
              )
            })
          )
        )
      })
    )
  )
}

# =============================================================================
# DATA HELPERS — Image audit (Page 2.2)
# =============================================================================

IMAGE_EXTENSION_PATTERN <- "\\.(jpg|jpeg|png)$"

# Build a data frame of expected camera folders (one row per camera), with
# both the hierarchy columns and the full expected path on disk, matching
# TrapTagger's required folder structure (see build_folder_paths above).
# Note: this takes the survey's TOP folder directly, since image audit asks
# the user to point at the survey folder itself (not its parent, unlike
# folder creation).
get_camera_folder_table <- function(df, base_survey_dir, deployment_phase) {
  df$block_deploy <- paste0(df$block, "_", deployment_phase)
  df$station_folder <- if ("ct_station_id" %in% names(df)) {
    paste0("Site", df$ct_station_id)
  } else {
    paste0("Site", df$cell_id, "st", df$ct_station)
  }
  df$camera_folder <- paste0(df$site_id, "_", df$ct_id)

  hierarchy <- unique(df[c("block_season", "cell_id", "site_id", "ct_id",
                            "block_deploy", "station_folder", "camera_folder")])
  hierarchy <- hierarchy[order(hierarchy$block_deploy, hierarchy$cell_id,
                                hierarchy$station_folder, hierarchy$camera_folder), ]
  hierarchy$path <- file.path(base_survey_dir, hierarchy$block_deploy,
                               hierarchy$cell_id, hierarchy$station_folder, hierarchy$camera_folder)
  hierarchy
}

# Count images/files in a camera folder. Counts recursively because at audit
# time (before the renaming step) a camera folder may still contain
# brand-specific sub-folders like "100RECNX"/"101RECNX" from the SD card.
audit_one_folder <- function(paths) {
  existing <- paths[dir.exists(paths)]
  if (length(existing) == 0) {
    return(list(exists = FALSE, n_images = NA_integer_, n_files_total = NA_integer_))
  }
  all_files <- unlist(lapply(existing, function(p) list.files(p, recursive = TRUE, full.names = FALSE)),
                       use.names = FALSE)
  list(exists = TRUE,
       n_files_total = length(all_files),
       n_images = sum(grepl(IMAGE_EXTENSION_PATTERN, all_files, ignore.case = TRUE)))
}

# A folder is considered "marked empty" if its name ends in "empty"
# (e.g. "108_empty"), per the field workflow described in the brief.
is_marked_empty <- function(path) {
  grepl("empty$", basename(path), ignore.case = TRUE)
}

# Looks for a text file explaining why an empty folder is empty.
has_empty_reason_file <- function(path) {
  if (!dir.exists(path)) return(FALSE)
  any(grepl("reason.*\\.txt$|empty.*\\.txt$", list.files(path), ignore.case = TRUE))
}

# Shared by resolve_camera_folder_path() and detect_multi_visit_cameras():
# given a parent directory and an expected folder name, find sibling
# folders that are the expected name plus exactly one trailing letter
# (e.g. "A05B_182a", "A05B_182b" for expected "A05B_182") — the SOP's
# SD-card-swap convention for a camera swapped mid-deployment without
# full retrieval. Returns paths sorted so "a" sorts before "b", etc.
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

# Given an expected camera folder path, resolve which variant(s) actually
# exist on disk:
#   - the plain path itself, or
#   - its "empty"-suffixed sibling (documents a legitimately empty
#     folder, per the SOP — e.g. "F01C_LEC152empty", no underscore), or
#   - letter-suffixed siblings from an SD-card swap (e.g. "...182a",
#     "...182b") — see find_suffixed_sibling_folders() above. Since
#     TrapTagger's images from a swapped camera still belong together as
#     ONE camera's sequence, `paths` can hold more than one source
#     folder in this case; `expected_path` is always the original plain
#     path, kept separately so callers that consolidate multiple sources
#     back into one folder (Rename) know where that destination is, even
#     though it doesn't exist on disk yet in the swap case.
resolve_camera_folder_path <- function(expected_path) {
  if (dir.exists(expected_path)) {
    return(list(paths = expected_path, exists = TRUE, expected_path = expected_path, multi_visit = FALSE))
  }
  empty_variant <- paste0(expected_path, "empty")
  if (dir.exists(empty_variant)) {
    return(list(paths = empty_variant, exists = TRUE, expected_path = expected_path, multi_visit = FALSE))
  }
  multi_paths <- find_suffixed_sibling_folders(dirname(expected_path), basename(expected_path))
  if (length(multi_paths) > 0) {
    return(list(paths = multi_paths, exists = TRUE, expected_path = expected_path, multi_visit = TRUE))
  }
  list(paths = expected_path, exists = FALSE, expected_path = expected_path, multi_visit = FALSE)
}

# Run the full audit: one row per expected camera folder, with file counts
# and a status flag. Never throws — folder-level errors just show as
# "Folder missing" rather than crashing the whole audit.
run_image_audit <- function(deployment_df, base_dir, deployment_phase) {
  cam_table <- get_camera_folder_table(deployment_df, base_dir, deployment_phase)

  rows <- lapply(seq_len(nrow(cam_table)), function(i) {
    expected_path <- cam_table$path[i]

    resolved <- tryCatch(resolve_camera_folder_path(expected_path), error = function(e) {
      list(paths = expected_path, exists = FALSE, expected_path = expected_path, multi_visit = FALSE)
    })
    p <- resolved$paths

    info <- tryCatch(audit_one_folder(p), error = function(e) {
      list(exists = FALSE, n_images = NA_integer_, n_files_total = NA_integer_)
    })

    # is_marked_empty()/has_empty_reason_file() only ever apply to the
    # single-path case — mutually exclusive with the multi-visit suffix,
    # so checking just the first path is always correct here.
    marked     <- if (isTRUE(info$exists)) is_marked_empty(p[1]) else FALSE
    has_reason <- if (isTRUE(info$exists)) has_empty_reason_file(p[1]) else FALSE

    status <- if (!isTRUE(info$exists)) {
      "Folder missing"
    } else if (identical(info$n_images, 0L) && marked && has_reason) {
      "Empty (documented)"
    } else if (identical(info$n_images, 0L) && marked && !has_reason) {
      "Empty (marked, no reason file)"
    } else if (identical(info$n_images, 0L)) {
      "Empty, needs review"
    } else if (isTRUE(resolved$multi_visit)) {
      "OK (multi-visit)"
    } else {
      "OK"
    }

    data.frame(
      block_season  = cam_table$block_season[i],
      cell_id       = cam_table$cell_id[i],
      site_id       = cam_table$site_id[i],
      ct_id         = cam_table$ct_id[i],
      path          = p[1],
      n_images      = info$n_images,
      n_files_total = info$n_files_total,
      status        = status,
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, rows)
}

# Find any subfolders that exist on disk but weren't expected from the
# deployment sheet (e.g. a typo'd camera ID, or a folder created by mistake).
# A trailing "empty" is stripped before comparing, since that's a
# recognized convention for documenting an empty camera folder, not an
# unexpected one.
find_unexpected_camera_folders <- function(cam_table) {
  site_paths <- unique(dirname(cam_table$path))
  unexpected <- character(0)

  is_expected_name <- function(name, expected_here) {
    stripped <- sub("empty$", "", name, ignore.case = TRUE)
    if (stripped %in% expected_here) return(TRUE)
    # A letter-suffixed multi-visit variant (e.g. "182a" for expected
    # "182") also counts as expected, not unexpected.
    if (nchar(name) >= 2) {
      base_part <- substr(name, 1, nchar(name) - 1)
      last_char <- substr(name, nchar(name), nchar(name))
      if (grepl("^[a-z]$", last_char, ignore.case = TRUE) && base_part %in% expected_here) return(TRUE)
    }
    FALSE
  }

  for (site_path in site_paths) {
    if (!dir.exists(site_path)) next
    actual_subdirs <- list.dirs(site_path, recursive = FALSE, full.names = FALSE)
    expected_here  <- basename(cam_table$path[dirname(cam_table$path) == site_path])
    extra <- actual_subdirs[!vapply(actual_subdirs, is_expected_name, logical(1), expected_here = expected_here)]
    if (length(extra) > 0) unexpected <- c(unexpected, file.path(site_path, extra))
  }
  unexpected
}


# =============================================================================
# DATA HELPERS — Image renaming (Page 2.4)
# =============================================================================

# Return every image inside a camera folder, in a deterministic order that
# preserves the SD card's original chronological sequence — including
# images nested in brand-specific sub-folders (e.g. "100RECNX"/"101RECNX"
# from a Reconyx-style camera, or "CUDD1"/"CUDD2" from a Cuddeback-style
# one). Camera-brand-agnostic: ANY sub-folder found directly inside the
# camera folder is treated as an SD-card dump folder needing consolidation,
# regardless of its naming convention — nothing here assumes a specific
# brand's folder-naming pattern.
#
# Order: sub-folders are processed in alphabetical order (mirroring how a
# trail camera rolls over to a new folder once one fills up), and files
# within each sub-folder are sorted alphabetically too. Any images sitting
# loose directly in the camera folder (uncommon, but possible) are placed
# first, ahead of any sub-folder contents.
# list.dirs() always includes the given path itself as one of the
# "directories" returned, even with recursive = FALSE — a well-known R
# quirk that, left unhandled, can make code treat a camera folder as if it
# were one of its own sub-folders. Returns just the REAL immediate
# sub-folders, excluding the path itself (compared via normalizePath, since
# list.dirs()'s returned paths aren't always textually identical to the
# input even when they refer to the same folder — e.g. trailing slashes).
list_real_subfolders <- function(path) {
  all_entries <- list.dirs(path, recursive = FALSE, full.names = TRUE)
  path_norm <- normalizePath(path, mustWork = FALSE)
  is_self <- vapply(all_entries, function(p) {
    identical(normalizePath(p, mustWork = FALSE), path_norm)
  }, logical(1))
  sort(all_entries[!is_self])
}

# Accepts one or more camera folder paths — normally just one, but a
# multi-visit / SD-card-swap camera (see resolve_camera_folder_path())
# has two ("...182a", "...182b"), whose images still belong together as
# one camera's sequence. Each path is processed in the order given
# (sorted "a" before "b" by the caller), so images stay chronological
# across the swap.
list_camera_images_ordered <- function(camera_paths) {
  all_files <- character(0)

  for (camera_path in camera_paths) {
    subfolders <- list_real_subfolders(camera_path)

    direct_files <- list.files(camera_path, full.names = TRUE, no.. = TRUE)
    direct_files <- direct_files[!dir.exists(direct_files)]
    direct_files <- sort(direct_files[grepl(IMAGE_EXTENSION_PATTERN, direct_files, ignore.case = TRUE)])

    nested_files <- character(0)
    for (sf in subfolders) {
      files <- list.files(sf, full.names = TRUE, no.. = TRUE)
      files <- files[!dir.exists(files)]
      files <- sort(files[grepl(IMAGE_EXTENSION_PATTERN, files, ignore.case = TRUE)])
      nested_files <- c(nested_files, files)
    }

    all_files <- c(all_files, direct_files, nested_files)
  }

  all_files
}

# Compute the rename/consolidation plan for a camera — the ordered old
# paths, their new destination paths, and any sub-folders that should be
# removed once emptied. Doesn't touch the filesystem; used for both the
# non-destructive preview and the real run.
#
# camera_paths (the source(s) to read images FROM) and dest_path (where
# renamed images land) are separate: normally the same single folder, but
# for a multi-visit/SD-card-swap camera (resolve_camera_folder_path()),
# camera_paths holds BOTH "...182a" and "...182b", while dest_path is the
# plain "...182" name they consolidate into — which may not exist on disk
# yet in that case (the caller is responsible for creating it first).
# When camera_paths differs from dest_path, those source folders are
# added to `subfolders` too, so they get cleaned up by the same
# "remove once emptied" mechanism sub-folder consolidation already uses.
#
# Leading zeros: always at least 4 digits (e.g. img0001), growing further
# only if a camera's actual image count exceeds what 4 digits can hold
# (e.g. 12000 images -> 5 digits).
#
# The filename mirrors the actual folder structure exactly (Block+Phase,
# Station, Site, Camera) so a filename alone is fully traceable back to
# its folder path — cell_id is the one thing deliberately left out, since
# station_folder already encodes it (e.g. "SiteA01st_A" starts with "A01").
plan_camera_rename <- function(camera_paths, dest_path, survey_name, block_deploy, station_folder, site_id, ct_id) {
  old_paths <- list_camera_images_ordered(camera_paths)
  subfolders <- unlist(lapply(camera_paths, list_real_subfolders), use.names = FALSE)
  extra_source_dirs <- setdiff(camera_paths, dest_path)
  subfolders <- c(subfolders, extra_source_dirs)
  n_total <- length(old_paths)

  if (n_total == 0) {
    return(list(old_paths = character(0), new_paths = character(0), subfolders = subfolders))
  }

  width <- max(4, nchar(as.character(n_total)))
  exts  <- tolower(tools::file_ext(old_paths))
  base_name <- paste(survey_name, block_deploy, station_folder, site_id, ct_id, sep = "_")
  new_names <- paste0(base_name, "_img", sprintf(paste0("%0", width, "d"), seq_len(n_total)), ".", exts)

  list(
    old_paths  = old_paths,
    new_paths  = file.path(dest_path, new_names),
    subfolders = subfolders
  )
}

# Non-destructive preview: for every camera, compute the rename plan and
# return a flat old-name -> new-name mapping, capped to a reasonable number
# of rows for display. Never touches the filesystem.
preview_image_rename <- function(deployment_df, base_dir, survey_name, deployment_phase, max_rows = 200) {
  cam_table <- get_camera_folder_table(deployment_df, base_dir, deployment_phase)
  rows <- list()
  n_shown <- 0

  for (i in seq_len(nrow(cam_table))) {
    row <- cam_table[i, ]
    resolved <- tryCatch(resolve_camera_folder_path(row$path),
                          error = function(e) list(paths = row$path, exists = FALSE, expected_path = row$path))
    # is_marked_empty() only ever applies to the single-path case — a
    # multi-visit camera's suffix ("a"/"b") and the "empty" convention are
    # mutually exclusive naming patterns, so checking just the first path
    # is always correct, not a shortcut that loses information.
    if (!isTRUE(resolved$exists) || is_marked_empty(resolved$paths[1])) next

    plan <- tryCatch(
      plan_camera_rename(resolved$paths, resolved$expected_path, survey_name, row$block_deploy,
                         row$station_folder, row$site_id, row$ct_id),
      error = function(e) NULL
    )
    if (is.null(plan) || length(plan$old_paths) == 0) next

    exif_dt <- tryCatch(extract_exif_datetimes(plan$old_paths), error = function(e) {
      as.POSIXct(rep(NA, length(plan$old_paths)))
    })

    rows[[length(rows) + 1]] <- data.frame(
      block  = row$block_deploy,
      station = row$station_folder,
      site   = row$site_id,
      camera = row$ct_id,
      old_name = basename(plan$old_paths),
      new_name = basename(plan$new_paths),
      timestamp = format(exif_dt, "%Y-%m-%d %H:%M:%S"),
      stringsAsFactors = FALSE
    )
    n_shown <- n_shown + nrow(rows[[length(rows)]])
    if (n_shown >= max_rows) break
  }

  if (length(rows) == 0) {
    return(data.frame(block = character(0), station = character(0), site = character(0),
                       camera = character(0), old_name = character(0), new_name = character(0),
                       timestamp = character(0)))
  }
  head(do.call(rbind, rows), max_rows)
}

# Perform the actual rename/consolidation for every camera folder in the
# survey. For each camera: gather all images (consolidating from any
# sub-folders present, brand-agnostic), move+rename them in one step to the
# final naming convention, then remove any sub-folder that's now empty —
# a sub-folder with unexpected leftover files is left in place and flagged
# rather than force-deleted, so nothing unexpected gets silently destroyed.
# Never aborts the whole survey on one camera's failure; collects a
# per-camera result instead.
run_image_rename <- function(deployment_df, base_dir, survey_name, deployment_phase) {
  cam_table <- get_camera_folder_table(deployment_df, base_dir, deployment_phase)
  n_cams <- nrow(cam_table)
  rows <- vector("list", n_cams)

  withProgress(message = "Renaming images...", value = 0, {
    for (i in seq_len(n_cams)) {
      row <- cam_table[i, ]
      resolved <- tryCatch(resolve_camera_folder_path(row$path),
                            error = function(e) list(paths = row$path, exists = FALSE, expected_path = row$path))

      outcome <- tryCatch({
        if (!isTRUE(resolved$exists)) {
          list(status = "skipped", detail = "Folder missing", n_images = 0L)
        } else if (is_marked_empty(resolved$paths[1])) {
          list(status = "skipped", detail = "Marked empty", n_images = 0L)
        } else {
          if (isTRUE(resolved$multi_visit)) fs::dir_create(resolved$expected_path)
          plan <- plan_camera_rename(resolved$paths, resolved$expected_path, survey_name,
                                      row$block_deploy, row$station_folder, row$site_id, row$ct_id)

          if (length(plan$old_paths) == 0) {
            list(status = "skipped", detail = "No images found", n_images = 0L)
          } else {
            for (j in seq_along(plan$old_paths)) {
              ok <- file.rename(plan$old_paths[j], plan$new_paths[j])
              if (!isTRUE(ok)) stop("Failed to rename '", basename(plan$old_paths[j]), "'")
            }

            n_removed <- 0L
            n_kept    <- 0L
            for (sf in plan$subfolders) {
              remaining <- list.files(sf, all.files = TRUE, no.. = TRUE)
              if (length(remaining) == 0) {
                fs::dir_delete(sf)
                n_removed <- n_removed + 1L
              } else {
                n_kept <- n_kept + 1L
              }
            }

            detail <- paste0(n_removed, " sub-folder(s) removed",
                              if (n_kept > 0) paste0(", ", n_kept, " left in place (not empty after move)") else "")
            list(status = "ok", detail = detail, n_images = length(plan$old_paths))
          }
        }
      }, error = function(e) {
        list(status = "error", detail = conditionMessage(e), n_images = 0L)
      })

      rows[[i]] <- data.frame(
        block_season = row$block_season, cell_id = row$cell_id,
        site_id = row$site_id, ct_id = row$ct_id,
        status = outcome$status, n_images = outcome$n_images, detail = outcome$detail,
        stringsAsFactors = FALSE
      )

      incProgress(1 / n_cams, detail = paste0(i, " / ", n_cams, " cameras"))
    }
  })

  do.call(rbind, rows)
}

# =============================================================================
# DATA HELPERS — Backup (Page 2.3)
# =============================================================================

# Copy every file from source_dir into dest_parent_dir/basename(source_dir),
# preserving the relative folder structure. Shows a progress bar (throttled
# to ~100 updates regardless of file count, to avoid flooding the UI with
# messages on large surveys). Returns the destination path and file count.
# Never throws for a single file failure — those are collected and reported
# rather than aborting the whole backup partway through.
run_backup <- function(source_dir, dest_parent_dir) {
  survey_name <- basename(source_dir)
  dest_dir <- file.path(dest_parent_dir, survey_name)

  all_files <- list.files(source_dir, recursive = TRUE, full.names = FALSE)
  n_total <- length(all_files)

  failed <- character(0)

  if (n_total == 0) {
    return(list(dest_dir = dest_dir, n_files = 0, failed = failed))
  }

  progress_step <- max(1, floor(n_total / 100))

  withProgress(message = "Backing up files...", value = 0, {
    for (i in seq_along(all_files)) {
      rel <- all_files[i]
      src_file <- file.path(source_dir, rel)
      dst_file <- file.path(dest_dir, rel)

      ok <- tryCatch({
        fs::dir_create(dirname(dst_file))
        fs::file_copy(src_file, dst_file, overwrite = TRUE)
        TRUE
      }, error = function(e) FALSE)

      if (!ok) failed <- c(failed, rel)

      if (i %% progress_step == 0 || i == n_total) {
        incProgress(progress_step / n_total, detail = paste0(i, " / ", n_total, " files"))
      }
    }
  })

  list(dest_dir = dest_dir, n_files = n_total, failed = failed)
}

# Compare a source folder against its backup destination: file/folder counts,
# and which specific files (if any) are missing from the destination.
verify_backup <- function(source_dir, dest_dir) {
  src_files <- sort(list.files(source_dir, recursive = TRUE, full.names = FALSE))
  dst_files <- if (dir.exists(dest_dir)) {
    sort(list.files(dest_dir, recursive = TRUE, full.names = FALSE))
  } else character(0)

  src_folders <- max(0, length(list.dirs(source_dir, recursive = TRUE)) - 1)
  dst_folders <- if (dir.exists(dest_dir)) {
    max(0, length(list.dirs(dest_dir, recursive = TRUE)) - 1)
  } else 0

  list(
    n_source_files   = length(src_files),
    n_dest_files     = length(dst_files),
    n_source_folders = src_folders,
    n_dest_folders   = dst_folders,
    missing_in_dest  = setdiff(src_files, dst_files),
    extra_in_dest    = setdiff(dst_files, src_files)
  )
}

# The fixed path from the mounted "Research" share down to the CameraTraps
# folder, per the server's existing structure. Kept as a constant so it's
# easy to update if the server's folder layout ever changes. Used by the
# (legacy) mounted-drive backup path.
SERVER_CAMERATRAPS_RELATIVE_PATH <- file.path("LEC_Field_Research", "CameraTraps")

# =============================================================================
# DATA HELPERS — Synology DSM File Station API (true remote server backup)
#
# The backup server is reached over a WireGuard VPN tunnel and accessed via
# Synology's DSM web interface (File Station) at a private IP — there is no
# mounted drive at all. All folder/file operations go through Synology's
# HTTPS API instead. SSL certificate verification is disabled for these
# calls since this is an internal, VPN-only address using a NAS's default
# self-signed certificate, not a publicly-exposed service.
# =============================================================================

SYNO_SHARE_NAME       <- "Research"
SYNO_CAMERATRAPS_PATH <- "/Research/LEC_Field_Research/CameraTraps"

syno_ssl_config <- function() httr::config(ssl_verifypeer = FALSE, ssl_verifyhost = FALSE)

# Log in to DSM, returning list(ok, sid, error). `base_url` should look like
# "https://192.168.13.119:5001" (no trailing slash).
syno_login <- function(base_url, username, password) {
  resp <- tryCatch({
    httr::GET(paste0(base_url, "/webapi/auth.cgi"),
      query = list(api = "SYNO.API.Auth", version = 6, method = "login",
                   account = username, passwd = password,
                   session = "FileStation", format = "sid"),
      syno_ssl_config(), httr::timeout(15))
  }, error = function(e) e)

  if (inherits(resp, "error") || inherits(resp, "condition")) {
    return(list(ok = FALSE, error = paste0(
      "Could not reach the server at ", base_url, ". Check that WireGuard is connected ",
      "and the address is correct. (Details: ", conditionMessage(resp), ")"
    )))
  }

  parsed <- tryCatch(httr::content(resp, as = "parsed", type = "application/json"),
                      error = function(e) NULL)
  if (is.null(parsed) || !isTRUE(parsed$success)) {
    code <- tryCatch(parsed$error$code, error = function(e) NULL)
    return(list(ok = FALSE, error = paste0(
      "Login failed", if (!is.null(code)) paste0(" (error code ", code, ")") else "",
      ". Check your username and password."
    )))
  }

  list(ok = TRUE, sid = parsed$data$sid)
}

syno_logout <- function(base_url, sid) {
  tryCatch({
    httr::GET(paste0(base_url, "/webapi/auth.cgi"),
      query = list(api = "SYNO.API.Auth", version = 6, method = "logout",
                   session = "FileStation", `_sid` = sid),
      syno_ssl_config(), httr::timeout(10))
  }, error = function(e) NULL)
  invisible(NULL)
}

# Does this exact folder path already exist on the server?
syno_folder_exists <- function(base_url, sid, folder_path) {
  resp <- tryCatch({
    httr::GET(paste0(base_url, "/webapi/entry.cgi"),
      query = list(api = "SYNO.FileStation.List", version = 2, method = "list",
                   folder_path = folder_path, `_sid` = sid),
      syno_ssl_config(), httr::timeout(15))
  }, error = function(e) NULL)
  if (is.null(resp)) return(FALSE)
  parsed <- tryCatch(httr::content(resp, as = "parsed", type = "application/json"),
                      error = function(e) NULL)
  isTRUE(parsed$success)
}

# Create a single folder level: `name` inside `parent_path`.
#
# folder_path and name are sent as quoted JSON array strings (e.g. ["/a/b"])
# rather than bare values — this is the format Synology's own official API
# examples use for CreateFolder, and matters in practice: a bare numeric
# folder name (e.g. "120") was being rejected as an "invalid parameter"
# (error 400) when sent as a plain string, but works with this format.
syno_json_array_param <- function(x) {
  paste0('["', gsub('"', '\\\\"', x), '"]')
}

syno_create_folder <- function(base_url, sid, parent_path, name) {
  resp <- tryCatch({
    httr::GET(paste0(base_url, "/webapi/entry.cgi"),
      query = list(api = "SYNO.FileStation.CreateFolder", version = 2, method = "create",
                   folder_path = syno_json_array_param(parent_path),
                   name = syno_json_array_param(name),
                   `_sid` = sid),
      syno_ssl_config(), httr::timeout(15))
  }, error = function(e) NULL)
  if (is.null(resp)) return(list(ok = FALSE, error_code = NA))
  parsed <- tryCatch(httr::content(resp, as = "parsed", type = "application/json"),
                      error = function(e) NULL)
  if (isTRUE(parsed$success)) return(list(ok = TRUE, error_code = NA))
  list(ok = FALSE, error_code = tryCatch(parsed$error$code, error = function(e) NA))
}

# A mutable "session" threading the current sid through a whole backup run,
# along with what's needed to silently re-authenticate if the session
# expires partway through — a real risk here, since a large backup involves
# many sequential requests over a documented-slow VPN tunnel, and can
# outlast Synology's session timeout.
syno_new_session <- function(base_url, username, password) {
  env <- new.env()
  env$base_url <- base_url
  env$username <- username
  env$password <- password
  env$sid <- NULL
  env
}

syno_connect <- function(sess) {
  login <- syno_login(sess$base_url, sess$username, sess$password)
  if (!login$ok) stop(login$error)
  sess$sid <- login$sid
  invisible(sess)
}

# Re-authenticate, updating sess$sid in place if it succeeds.
syno_refresh <- function(sess) {
  login <- syno_login(sess$base_url, sess$username, sess$password)
  if (login$ok) sess$sid <- login$sid
  login$ok
}

# Run a zero-argument Synology API call (using sess$sid internally,
# returning TRUE/FALSE). If it fails, refresh the session once and retry —
# this is what keeps a long backup going through a session timeout instead
# of aborting partway through.
syno_retry <- function(sess, call_fn) {
  if (isTRUE(call_fn())) return(TRUE)
  if (syno_refresh(sess)) return(isTRUE(call_fn()))
  FALSE
}

# Makes a raw diagnostic API call and returns the parsed response as-is,
# used only to capture the real error detail when something has already
# failed — so we get concrete data on WHY, instead of guessing.
syno_raw_call <- function(base_url, sid, api, method, extra_query) {
  resp <- tryCatch({
    httr::GET(paste0(base_url, "/webapi/entry.cgi"),
      query = c(list(api = api, version = 2, method = method, `_sid` = sid), extra_query),
      syno_ssl_config(), httr::timeout(15))
  }, error = function(e) NULL)
  if (is.null(resp)) return(list(success = FALSE, error = list(code = NA)))
  tryCatch(httr::content(resp, as = "parsed", type = "application/json"),
           error = function(e) list(success = FALSE, error = list(code = NA)))
}

# Format a Synology API error response into a short, readable string,
# including any per-path detail it provides (Synology sometimes returns a
# nested `errors` array with a specific code per path, in addition to the
# top-level error code).
format_syno_error <- function(parsed) {
  if (is.null(parsed) || isTRUE(parsed$success)) return("no error reported")
  outer <- tryCatch(parsed$error$code, error = function(e) NA)
  inner <- tryCatch({
    errs <- parsed$error$errors
    if (is.null(errs) || length(errs) == 0) "" else {
      paste(vapply(errs, function(e) {
        paste0("code=", if (!is.null(e$code)) e$code else "?",
               if (!is.null(e$path)) paste0(" path=", e$path) else "")
      }, character(1)), collapse = "; ")
    }
  }, error = function(e) "")
  paste0("code=", outer, if (nchar(inner) > 0) paste0(" [", inner, "]") else "")
}

# Ensure every level of a nested remote path exists, creating only the
# levels that are missing (never touches levels that already exist).
# Every call is retried once with a fresh session if it fails, and folder
# creation self-heals from "already exists" races (see note below) — both
# make a backup resilient to the session timeouts and connection hiccups
# that are common over this server's VPN tunnel.
syno_ensure_path <- function(sess, root_path, relative_segments) {
  cur <- root_path
  for (seg in relative_segments) {
    nxt <- paste0(cur, "/", seg)

    exists_now <- syno_retry(sess, function() syno_folder_exists(sess$base_url, sess$sid, nxt))

    if (!exists_now) {
      created <- syno_retry(sess, function() syno_create_folder(sess$base_url, sess$sid, cur, seg)$ok)
      if (!created) {
        # Re-check before giving up: a slightly-stale existence check can
        # lead to an unnecessary create attempt on a folder that's already
        # there, which Synology reports as a failure rather than a no-op.
        still_missing <- !syno_retry(sess, function() syno_folder_exists(sess$base_url, sess$sid, nxt))
        if (still_missing) {
          # Capture the REAL error detail from both calls, since guessing at
          # the cause hasn't worked so far — this gives concrete data to
          # diagnose from instead of another theory.
          diag_create <- syno_raw_call(sess$base_url, sess$sid, "SYNO.FileStation.CreateFolder", "create",
                                        list(folder_path = syno_json_array_param(cur),
                                             name = syno_json_array_param(seg)))
          diag_list   <- syno_raw_call(sess$base_url, sess$sid, "SYNO.FileStation.List", "list",
                                        list(folder_path = nxt))
          stop("Could not create folder '", seg, "' under '", cur, "' on the server.\n",
               "CreateFolder error: ", format_syno_error(diag_create), "\n",
               "Existence check (List) error: ", format_syno_error(diag_list))
        }
      }
    }
    cur <- nxt
  }
  cur
}

# Upload one local file into a remote destination folder (which must
# already exist).
syno_upload_file <- function(base_url, sid, dest_folder_path, local_file_path) {
  resp <- tryCatch({
    httr::POST(paste0(base_url, "/webapi/entry.cgi"),
      query = list(`_sid` = sid),
      body = list(api = "SYNO.FileStation.Upload", version = 2, method = "upload",
                  path = dest_folder_path, overwrite = "true",
                  file = httr::upload_file(local_file_path)),
      encode = "multipart", syno_ssl_config(), httr::timeout(120))
  }, error = function(e) NULL)
  if (is.null(resp)) return(FALSE)
  parsed <- tryCatch(httr::content(resp, as = "parsed", type = "application/json"),
                      error = function(e) list(success = FALSE))
  isTRUE(parsed$success)
}

# Recursively list every file under a remote folder, as paths relative to it.
syno_list_files_recursive <- function(base_url, sid, folder_path, rel_prefix = "") {
  resp <- tryCatch({
    httr::GET(paste0(base_url, "/webapi/entry.cgi"),
      query = list(api = "SYNO.FileStation.List", version = 2, method = "list",
                   folder_path = folder_path, `_sid` = sid),
      syno_ssl_config(), httr::timeout(30))
  }, error = function(e) NULL)
  if (is.null(resp)) return(character(0))
  parsed <- tryCatch(httr::content(resp, as = "parsed", type = "application/json"),
                      error = function(e) NULL)
  if (is.null(parsed) || !isTRUE(parsed$success) || is.null(parsed$data$files)) return(character(0))

  out <- character(0)
  for (item in parsed$data$files) {
    item_rel <- if (nchar(rel_prefix) == 0) item$name else paste0(rel_prefix, "/", item$name)
    if (isTRUE(item$isdir)) {
      out <- c(out, syno_list_files_recursive(base_url, sid, item$path, item_rel))
    } else {
      out <- c(out, item_rel)
    }
  }
  out
}

# Full server backup: login, verify CameraTraps exists (never auto-created —
# see note below), find/create BackupCTData and the survey subfolder, then
# upload every local file with a progress bar. Logs out even on error.
run_server_backup <- function(base_url, username, password, source_dir, survey_name) {
  sess <- syno_new_session(base_url, username, password)
  syno_connect(sess)
  on.exit(syno_logout(sess$base_url, sess$sid), add = TRUE)

  # Deliberately NOT auto-created if missing: this path should already exist
  # on the real server, so a missing path almost certainly means something
  # about the connection/address is wrong — better to stop clearly than
  # silently create stray folders on a shared team server.
  camera_traps_ok <- syno_retry(sess, function() syno_folder_exists(sess$base_url, sess$sid, SYNO_CAMERATRAPS_PATH))
  if (!camera_traps_ok) {
    stop("Could not find '", SYNO_CAMERATRAPS_PATH, "' on the server. ",
         "Check that WireGuard is connected and the server address is correct.")
  }

  backup_ct_data_path <- syno_ensure_path(sess, SYNO_CAMERATRAPS_PATH, "BackupCTData")
  survey_dest_path    <- syno_ensure_path(sess, backup_ct_data_path, survey_name)

  # Find out what's already on the server before uploading anything, so a
  # re-run after a partial failure only uploads what's actually missing
  # rather than re-sending everything from scratch.
  already_on_server <- gsub("\\\\", "/", syno_list_files_recursive(sess$base_url, sess$sid, survey_dest_path))

  all_files <- list.files(source_dir, recursive = TRUE, full.names = FALSE)
  n_total <- length(all_files)
  failed  <- character(0)
  n_skipped <- 0

  if (n_total > 0) {
    progress_step <- max(1, floor(n_total / 100))
    ensured_dirs <- character(0)

    withProgress(message = "Uploading to server...", value = 0, {
      for (i in seq_along(all_files)) {
        rel     <- gsub("\\\\", "/", all_files[i])
        rel_dir <- dirname(rel)
        local_file <- file.path(source_dir, all_files[i])

        if (rel %in% already_on_server) {
          n_skipped <- n_skipped + 1
        } else {
          remote_dir <- if (rel_dir == ".") {
            survey_dest_path
          } else if (rel_dir %in% ensured_dirs) {
            paste0(survey_dest_path, "/", rel_dir)
          } else {
            d <- syno_ensure_path(sess, survey_dest_path, strsplit(rel_dir, "/")[[1]])
            ensured_dirs <- c(ensured_dirs, rel_dir)
            d
          }

          ok <- syno_retry(sess, function() syno_upload_file(sess$base_url, sess$sid, remote_dir, local_file))
          if (!ok) failed <- c(failed, all_files[i])
        }

        if (i %% progress_step == 0 || i == n_total) {
          incProgress(progress_step / n_total, detail = paste0(i, " / ", n_total, " files"))
        }
      }
    })
  }

  list(dest_path = survey_dest_path, n_files = n_total, n_skipped = n_skipped, failed = failed)
}

# Verify a completed server backup by recursively listing the remote survey
# folder and comparing it against the local source.
verify_server_backup <- function(base_url, username, password, source_dir, survey_dest_path) {
  login <- syno_login(base_url, username, password)
  if (!login$ok) stop(login$error)
  sid <- login$sid
  on.exit(syno_logout(base_url, sid), add = TRUE)

  src_files    <- sort(gsub("\\\\", "/", list.files(source_dir, recursive = TRUE, full.names = FALSE)))
  remote_files <- sort(syno_list_files_recursive(base_url, sid, survey_dest_path))

  list(
    n_source_files = length(src_files),
    n_dest_files   = length(remote_files),
    missing_in_dest = setdiff(src_files, remote_files),
    extra_in_dest   = setdiff(remote_files, src_files)
  )
}

# =============================================================================
# DATA HELPERS — QA/QC (Page 2.5)
# =============================================================================

# Extract DateTimeOriginal (falling back to CreateDate) for a batch of
# images in ONE exiftool call — used both by the main EXIF extraction and
# the rename preview (so a technician can visually confirm images will be
# renamed in true chronological order before committing). Returns a
# POSIXct vector the same length as image_paths (NA for any that fail).
extract_exif_datetimes <- function(image_paths) {
  if (length(image_paths) == 0) return(as.POSIXct(character(0)))

  exif <- tryCatch(
    exiftoolr::exif_read(image_paths, tags = c("DateTimeOriginal", "CreateDate")),
    error = function(e) NULL
  )
  if (is.null(exif) || nrow(exif) == 0) return(as.POSIXct(rep(NA, length(image_paths))))

  dt_str <- if ("DateTimeOriginal" %in% names(exif)) exif$DateTimeOriginal else rep(NA_character_, nrow(exif))
  if ("CreateDate" %in% names(exif)) {
    missing <- is.na(dt_str) | dt_str == ""
    dt_str[missing] <- exif$CreateDate[missing]
  }
  suppressWarnings(as.POSIXct(dt_str, format = "%Y:%m:%d %H:%M:%S", tz = "UTC"))
}

# Extract EXIF timestamps (DateTimeOriginal, falling back to CreateDate)
# from every image in every camera folder. One exiftool call per camera
# (batched across all its images) rather than per-image, for speed.
# Cameras with no images, a missing folder, or a documented-empty folder
# are skipped rather than erroring the whole extraction.
run_exif_extraction <- function(deployment_df, base_dir, deployment_phase) {
  cam_table <- get_camera_folder_table(deployment_df, base_dir, deployment_phase)
  rows <- list()

  for (i in seq_len(nrow(cam_table))) {
    row <- cam_table[i, ]
    resolved <- tryCatch(resolve_camera_folder_path(row$path),
                          error = function(e) list(paths = row$path, exists = FALSE))
    if (!isTRUE(resolved$exists) || is_marked_empty(resolved$paths[1])) next

    images <- tryCatch(list_camera_images_ordered(resolved$paths), error = function(e) character(0))
    if (length(images) == 0) next

    dt <- extract_exif_datetimes(images)

    rows[[length(rows) + 1]] <- data.frame(
      block_season = row$block_season, cell_id = row$cell_id, station_folder = row$station_folder,
      site_id = row$site_id, ct_id = row$ct_id,
      path = images, datetime = dt, stringsAsFactors = FALSE
    )
  }

  if (length(rows) == 0) {
    return(data.frame(block_season = character(0), cell_id = character(0), station_folder = character(0),
                       site_id = character(0), ct_id = character(0),
                       path = character(0), datetime = as.POSIXct(character(0)),
                       stringsAsFactors = FALSE))
  }
  do.call(rbind, rows)
}

# One row per camera: EXIF start/end timestamps and image count. Uses the
# corrected datetime column if a batch correction has been applied (so
# every downstream check reflects it), otherwise the raw extracted one.
summarize_exif_by_camera <- function(exif_data) {
  dt_col <- if ("datetime_corrected" %in% names(exif_data) && any(!is.na(exif_data$datetime_corrected))) {
    "datetime_corrected"
  } else {
    "datetime"
  }
  exif_data$.dt <- exif_data[[dt_col]]
  exif_data <- exif_data[!is.na(exif_data$.dt), ]

  if (nrow(exif_data) == 0) {
    return(data.frame(block_season = character(0), cell_id = character(0),
                       site_id = character(0), ct_id = character(0),
                       exif_start = as.POSIXct(character(0)), exif_end = as.POSIXct(character(0)),
                       n_images = integer(0), stringsAsFactors = FALSE))
  }

  exif_data %>%
    dplyr::group_by(block_season, cell_id, site_id, ct_id) %>%
    dplyr::summarise(exif_start = min(.dt), exif_end = max(.dt), n_images = dplyr::n(), .groups = "drop")
}

# Compare each camera's EXIF start/end against its deployment sheet
# setup/retrieval dates, flagging discrepancies beyond the given tolerance.
# Cameras documented as legitimately empty (via the Image Audit "mark as
# empty" workflow) are excluded from flagging entirely — having no EXIF
# data there is expected, not a problem worth surfacing.
# Format the elapsed time between two datetimes as "X day(s), Y hr(s), Z
# min(s)" — used to show span LENGTH alongside absolute dates. If a
# mismatched camera's deployment-sheet span and photo span are nearly the
# same LENGTH (even though the absolute dates differ), that's a strong
# hint the dates are simply wrong (e.g. wrong year) rather than the survey
# itself having run differently than planned.
format_duration <- function(start, end) {
  if (is.na(start) || is.na(end)) return("n/a")
  total_mins <- round(as.numeric(difftime(end, start, units = "mins")))
  days  <- total_mins %/% 1440
  hrs   <- (total_mins %% 1440) %/% 60
  mins  <- total_mins %% 60
  paste0(days, " day", if (days != 1) "s" else "", ", ",
         hrs, " hr", if (hrs != 1) "s" else "", ", ",
         mins, " min", if (mins != 1) "s" else "")
}

# Build the per-image export used by the "Download corrected CSV" button:
# original AND corrected timestamps side by side (never just one or the
# other, so nothing is lost), plus each camera's use/do-not-use decision
# and note, joined in from the "Cameras to exclude" tool. A camera with no
# recorded decision defaults to "Use" (the normal, unflagged case).
build_corrected_export <- function(exif_data, camera_decisions) {
  cols <- c("block_season", "cell_id", "station_folder", "site_id", "ct_id", "path", "datetime")
  if (is.null(exif_data) || nrow(exif_data) == 0 || !all(cols %in% names(exif_data))) {
    return(data.frame(block_season = character(0), cell_id = character(0), station_folder = character(0),
                       site_id = character(0), ct_id = character(0), filename = character(0),
                       datetime_original = character(0), datetime_corrected = character(0),
                       use_status = character(0), note = character(0), stringsAsFactors = FALSE))
  }

  df <- exif_data[cols]
  df$filename <- basename(df$path)
  df$path <- NULL
  df$datetime_corrected <- if ("datetime_corrected" %in% names(exif_data)) exif_data$datetime_corrected else exif_data$datetime
  names(df)[names(df) == "datetime"] <- "datetime_original"

  if (!is.null(camera_decisions) && nrow(camera_decisions) > 0) {
    df <- merge(df, camera_decisions, by = c("site_id", "ct_id"), all.x = TRUE)
  } else {
    df$use_status <- NA_character_
    df$note <- NA_character_
  }
  df$use_status[is.na(df$use_status)] <- "Use"
  df$note[is.na(df$note)] <- ""

  df[c("block_season", "cell_id", "station_folder", "site_id", "ct_id", "filename",
       "datetime_original", "datetime_corrected", "use_status", "note")]
}

check_timestamps <- function(deployment_df, exif_summary, tolerance_days, image_audit = NULL) {
  # Guarantee exactly one row per camera BEFORE merging — if the deployment
  # sheet ever has more than one row for the same camera (even differing
  # only slightly, e.g. in the datetime columns), keeping all of them here
  # would multiply rows in the merge below, artificially inflating the
  # flagged count with spurious extra entries alongside a correct one.
  camera_keys <- c("block_season", "cell_id", "site_id", "ct_id")
  dep <- deployment_df[!duplicated(deployment_df[camera_keys]),
                        c(camera_keys, "setup_datetime", "retrieved_datetime")]

  merged <- merge(dep, exif_summary, by = camera_keys, all.x = TRUE)

  merged$start_diff_days <- as.numeric(abs(difftime(merged$exif_start, merged$setup_datetime, units = "days")))
  merged$end_diff_days   <- as.numeric(abs(difftime(merged$exif_end, merged$retrieved_datetime, units = "days")))

  merged$flag <- ifelse(
    is.na(merged$exif_start), "No EXIF data",
    ifelse(merged$start_diff_days > tolerance_days | merged$end_diff_days > tolerance_days,
           "Timestamp mismatch", "OK")
  )

  if (!is.null(image_audit) && nrow(image_audit) > 0) {
    empty_statuses <- c("Empty (documented)", "Empty (marked, no reason file)")
    is_marked_empty_cam <- image_audit$status %in% empty_statuses
    empty_keys <- paste(image_audit$site_id[is_marked_empty_cam], image_audit$ct_id[is_marked_empty_cam])
    merged_keys <- paste(merged$site_id, merged$ct_id)
    merged$flag[merged_keys %in% empty_keys] <- "Marked empty (skipped)"
  }

  merged
}

# Flag paired A/B stations (same block/cell, different station letter)
# whose active periods don't roughly overlap — per the brief's requirement
# that paired cameras were deployed "at the same place at the same time".
# Flag co-located "double camera" stations whose active periods don't
# roughly overlap — per the brief's requirement that paired cameras were
# deployed "at the same place at the same time".
#
# A pair is defined as: a station (grouped by ct_station_id — e.g.
# "A01st_A") that has exactly 2 distinct CT Locs (site_id values) recorded
# against it. This is deliberately NOT "2 rows in the same cell" (a cell
# can have two entirely separate single-camera stations, e.g. A04st_A and
# A04st_B, which are NOT co-located and shouldn't be timestamp-compared)
# and NOT based on trusting "N_Cam_Per_Station" blindly (real field data
# can have that column out of sync with the actual recorded locations —
# grouping by the actual data is more robust). Falls back to grouping by
# (block_season, cell_id) if a file has no ct_station_id column at all.
check_paired_stations <- function(deployment_df, exif_summary, tolerance_days) {
  has_station_id <- "ct_station_id" %in% names(deployment_df)
  cols <- c("block_season", "cell_id", "ct_station", "site_id", "ct_id")
  if (has_station_id) cols <- c(cols, "ct_station_id")
  sites <- unique(deployment_df[cols])

  group_key <- if (has_station_id) sites$ct_station_id else paste(sites$block_season, sites$cell_id)
  pair_groups <- split(sites, group_key)
  # A real pair has exactly 2 DISTINCT locations at the same station —
  # duplicate rows for the same location (data-entry repeats) don't count.
  pair_groups <- pair_groups[sapply(pair_groups, function(g) length(unique(g$site_id)) == 2)]

  empty_result <- data.frame(cell_id = character(0), site_a = character(0), site_b = character(0),
                              ct_id_a = character(0), ct_id_b = character(0),
                              start_a = as.POSIXct(character(0)), end_a = as.POSIXct(character(0)),
                              start_b = as.POSIXct(character(0)), end_b = as.POSIXct(character(0)),
                              mismatch_days = numeric(0), stringsAsFactors = FALSE)
  if (length(pair_groups) == 0) return(empty_result)

  rows <- lapply(pair_groups, function(g) {
    g <- g[!duplicated(g$site_id), ]
    g <- g[order(g$site_id), ]
    exif_a <- exif_summary[exif_summary$site_id == g$site_id[1], ]
    exif_b <- exif_summary[exif_summary$site_id == g$site_id[2], ]
    if (nrow(exif_a) == 0 || nrow(exif_b) == 0) return(NULL)

    start_diff <- as.numeric(abs(difftime(exif_a$exif_start[1], exif_b$exif_start[1], units = "days")))
    end_diff   <- as.numeric(abs(difftime(exif_a$exif_end[1], exif_b$exif_end[1], units = "days")))
    mismatch <- suppressWarnings(max(start_diff, end_diff, na.rm = TRUE))
    if (!is.finite(mismatch) || mismatch <= tolerance_days) return(NULL)

    data.frame(cell_id = g$cell_id[1], site_a = g$site_id[1], site_b = g$site_id[2],
               ct_id_a = g$ct_id[1], ct_id_b = g$ct_id[2],
               start_a = exif_a$exif_start[1], end_a = exif_a$exif_end[1],
               start_b = exif_b$exif_start[1], end_b = exif_b$exif_end[1],
               mismatch_days = round(mismatch, 1), stringsAsFactors = FALSE)
  })

  rows <- rows[!sapply(rows, is.null)]
  if (length(rows) == 0) return(empty_result)
  do.call(rbind, rows)
}

# Cross-check N_Cam_Per_Station's claim against the ACTUAL number of
# distinct CT Locs recorded for that station — real field data can have
# these out of sync (confirmed against a real file: several stations
# claimed 1 camera but had 2 locations recorded, or vice versa). Returns a
# data.frame of mismatches only.
check_station_camera_count <- function(deployment_df) {
  empty_result <- data.frame(ct_station_id = character(0), claimed = integer(0),
                              actual = integer(0), locations = character(0), stringsAsFactors = FALSE)
  if (!all(c("ct_station_id", "n_cam_per_station") %in% names(deployment_df))) return(empty_result)

  sites <- unique(deployment_df[c("ct_station_id", "site_id", "n_cam_per_station")])
  groups <- split(sites, sites$ct_station_id)

  rows <- lapply(groups, function(g) {
    actual <- length(unique(g$site_id))
    claimed <- suppressWarnings(as.integer(g$n_cam_per_station[1]))
    if (is.na(claimed) || claimed == actual) return(NULL)
    data.frame(ct_station_id = g$ct_station_id[1], claimed = claimed, actual = actual,
               locations = paste(sort(unique(g$site_id)), collapse = ", "), stringsAsFactors = FALSE)
  })
  rows <- rows[!sapply(rows, is.null)]
  if (length(rows) == 0) return(empty_result)
  do.call(rbind, rows)
}

# =============================================================================
# DATA HELPERS — TrapTagger import (Page 3.1)
# =============================================================================

# TrapTagger's real "Site Name" values have no underscore ("SiteA01stA"),
# but our station_folder keeps one, matching the deployment sheet's own
# notation ("SiteA01st_A") — confirmed directly against a real TrapTagger
# export, whose site-detection regex (Site[A-Z][0-9]+st[A-Z]) has no
# underscore in it. Rather than change our folder naming (which would mean
# renaming every folder already created) to match TrapTagger, the two are
# normalized to the same form ONLY for comparison, right here.
normalize_station_name <- function(x) gsub("_", "", x)

# Read a TrapTagger classification export. The real export has exactly
# these 7 columns: Site Name, Latitude, Longitude, Timestamp, Species,
# Sighting Count, Image URL. "Site Name" is TrapTagger's own station-level
# identifier (e.g. "SiteA01stA") — matches our station_folder (once
# normalized, see normalize_station_name() above), NOT an individual
# CT_Loc, since TrapTagger's "Folder" camera-identifier mode doesn't
# distinguish which camera within a double-camera station produced a
# given image.
read_traptagger_csv <- function(filepath) {
  raw <- tryCatch(utils::read.csv(filepath, stringsAsFactors = FALSE, encoding = "UTF-8-BOM"),
                   error = function(e) NULL)
  if (is.null(raw)) {
    raw <- tryCatch(utils::read.csv(filepath, stringsAsFactors = FALSE),
                     error = function(e) NULL)
  }
  if (is.null(raw)) return(list(data = NULL, error = "Could not read this file as a CSV."))

  names(raw) <- trimws(names(raw))
  col_map <- c("Site.Name" = "station_folder", "Site Name" = "station_folder",
               "Latitude" = "lat", "Longitude" = "long", "Timestamp" = "timestamp",
               "Species" = "species", "Sighting.Count" = "sighting_count",
               "Sighting Count" = "sighting_count", "Image.URL" = "image_url", "Image URL" = "image_url")
  matched <- names(raw) %in% names(col_map)
  names(raw)[matched] <- col_map[names(raw)[matched]]

  required <- c("station_folder", "timestamp", "species")
  missing_req <- setdiff(required, names(raw))
  if (length(missing_req) > 0) {
    return(list(data = NULL, error = paste0(
      "This doesn't look like a TrapTagger export, missing column(s): ",
      paste(missing_req, collapse = ", "))))
  }

  raw$timestamp <- suppressWarnings(as.POSIXct(raw$timestamp, format = "%Y-%m-%d %H:%M:%S", tz = "UTC"))
  list(data = raw, error = NULL)
}

# ArgusWild is built on the Wildbook/WBIA platform, and its "Standard
# Format Export" mirrors Wildbook's own documented Bulk Import schema
# (https://wildbook.docs.wildme.org/data/bulk-import-beta.html) — real,
# documented field names, not guessed. Only the columns relevant to
# joining ArgusWild's individual-ID results back to our own species data
# are mapped; every other Wildbook field (genetic, project, submitter,
# etc.) is ignored, since this app has no use for them.
read_arguswild_csv <- function(filepath) {
  raw <- tryCatch(utils::read.csv(filepath, stringsAsFactors = FALSE, encoding = "UTF-8-BOM"),
                   error = function(e) NULL)
  if (is.null(raw)) {
    raw <- tryCatch(utils::read.csv(filepath, stringsAsFactors = FALSE),
                     error = function(e) NULL)
  }
  if (is.null(raw)) return(list(data = NULL, error = "Could not read this file as a CSV."))

  names(raw) <- trimws(names(raw))
  col_map <- c(
    "MarkedIndividual.individualID" = "individual_id",
    "Encounter.individualID" = "individual_id",
    "Encounter.mediaAsset0" = "media_asset",
    "Encounter.genus" = "genus",
    "Encounter.specificEpithet" = "species_epithet",
    "Encounter.year" = "year", "Encounter.month" = "month", "Encounter.day" = "day",
    "Encounter.hour" = "hour", "Encounter.minutes" = "minutes",
    "Encounter.locationID" = "location_id",
    "Encounter.sex" = "sex", "Encounter.lifeStage" = "life_stage",
    "MarkedIndividual.nickname" = "nickname"
  )
  matched <- names(raw) %in% names(col_map)
  names(raw)[matched] <- col_map[names(raw)[matched]]

  required <- c("individual_id", "media_asset")
  missing_req <- setdiff(required, names(raw))
  if (length(missing_req) > 0) {
    return(list(data = NULL, error = paste0(
      "This doesn't look like an ArgusWild/Wildbook Standard Format export, missing column(s): ",
      paste(missing_req, collapse = ", "))))
  }

  list(data = raw, error = NULL)
}

# Splits a camera's full deployment window into its operational
# sub-periods by subtracting recorded gaps — e.g. a camera running
# 01.01-01.10, then a gap, then 02.01-02.10 produces two rows, not one
# spanning both with the gap silently included. Handles multiple,
# possibly overlapping gaps by merging them first. Returns a data.frame
# with one row per resulting "on" period (period_start, period_end); a
# camera with no gaps at all returns a single row covering the whole
# deployment window unchanged.
compute_operational_periods <- function(start, end, gap_starts, gap_ends) {
  if (is.na(start) || is.na(end) || end <= start) {
    return(data.frame(period_start = as.POSIXct(character(0)), period_end = as.POSIXct(character(0))))
  }
  valid_gaps <- !is.na(gap_starts) & !is.na(gap_ends)
  gap_starts <- gap_starts[valid_gaps]; gap_ends <- gap_ends[valid_gaps]
  # Clip gaps to the deployment window, drop any entirely outside it
  gap_starts <- pmax(gap_starts, start); gap_ends <- pmin(gap_ends, end)
  keep <- gap_starts < gap_ends
  gap_starts <- gap_starts[keep]; gap_ends <- gap_ends[keep]

  if (length(gap_starts) == 0) {
    return(data.frame(period_start = start, period_end = end))
  }

  ord <- order(gap_starts)
  gap_starts <- gap_starts[ord]; gap_ends <- gap_ends[ord]

  merged_starts <- gap_starts[1]; merged_ends <- gap_ends[1]
  if (length(gap_starts) > 1) {
    for (i in 2:length(gap_starts)) {
      if (gap_starts[i] <= merged_ends[length(merged_ends)]) {
        merged_ends[length(merged_ends)] <- max(merged_ends[length(merged_ends)], gap_ends[i])
      } else {
        merged_starts <- c(merged_starts, gap_starts[i])
        merged_ends <- c(merged_ends, gap_ends[i])
      }
    }
  }

  period_starts <- c(start, merged_ends)
  period_ends <- c(merged_starts, end)
  keep2 <- period_starts < period_ends
  data.frame(period_start = period_starts[keep2], period_end = period_ends[keep2])
}

# Builds a camera-operation-periods table following Camtrap DP's
# "Deployments" schema (https://camtrap-dp.tdwg.org/data/#deployments) —
# the real, TDWG/GBIF-backed open standard for exactly this purpose,
# rather than an invented format. Its key design choice is exactly what
# was asked for: deploymentID is unique per OPERATIONAL PERIOD, not per
# camera — the same physical camera can have multiple rows if it went
# offline and came back on, with the gap in between simply absent from
# either row rather than folded into one row that silently spans it.
# Only the columns relevant here are populated; the rest of Camtrap DP's
# optional deployment-level fields (cameraModel, cameraHeight, etc.) are
# left out since this app doesn't capture that information.
build_camera_operation_export <- function(deployment_df, gap_periods, camera_decisions) {
  empty_result <- data.frame(deploymentID = character(0), locationID = character(0),
                              locationName = character(0), latitude = numeric(0), longitude = numeric(0),
                              deploymentStart = character(0), deploymentEnd = character(0),
                              cameraID = character(0), deploymentComments = character(0),
                              stringsAsFactors = FALSE)
  if (is.null(deployment_df) || nrow(deployment_df) == 0) return(empty_result)

  cams <- unique(deployment_df[c("site_id", "ct_id", "station_folder",
                                  "setup_datetime", "retrieved_datetime")])
  if ("lat" %in% names(deployment_df))  cams$lat  <- deployment_df$lat[match(cams$site_id, deployment_df$site_id)]
  if ("long" %in% names(deployment_df)) cams$long <- deployment_df$long[match(cams$site_id, deployment_df$site_id)]

  # Raw deployment/retrieval notes (e.g. "SD card full") can speak directly
  # to why a camera's operational window ended when it did — surfaced here
  # verbatim rather than keyword-matched against specific phrases, since
  # field notes vary too much in wording for that to be reliable.
  if ("notes_deployment" %in% names(deployment_df)) {
    cams$notes_deployment <- trimws(as.character(
      deployment_df$notes_deployment[match(cams$site_id, deployment_df$site_id)]))
  } else {
    cams$notes_deployment <- NA_character_
  }
  if ("notes_retrieval" %in% names(deployment_df)) {
    cams$notes_retrieval <- trimws(as.character(
      deployment_df$notes_retrieval[match(cams$site_id, deployment_df$site_id)]))
  } else {
    cams$notes_retrieval <- NA_character_
  }

  # Cameras marked "Do not use" (QA/QC, "Cameras to exclude") are dropped
  # entirely, before computing anything for them — their downtime isn't
  # "search effort" at all if the camera's own data was excluded as
  # unreliable in the first place.
  if (!is.null(camera_decisions) && nrow(camera_decisions) > 0) {
    excluded <- camera_decisions[camera_decisions$use_status == "Do not use", c("site_id", "ct_id")]
    if (nrow(excluded) > 0) {
      is_excluded <- paste(cams$site_id, cams$ct_id) %in% paste(excluded$site_id, excluded$ct_id)
      cams <- cams[!is_excluded, ]
    }
  }
  if (nrow(cams) == 0) return(empty_result)

  has_gaps <- !is.null(gap_periods) && nrow(gap_periods) > 0

  rows <- lapply(seq_len(nrow(cams)), function(i) {
    cam <- cams[i, ]
    cam_gaps <- if (has_gaps) gap_periods[gap_periods$site_id == cam$site_id & gap_periods$ct_id == cam$ct_id, ]
                else data.frame(site_id = character(0), ct_id = character(0),
                                 gap_start = as.POSIXct(character(0)), gap_end = as.POSIXct(character(0)))
    periods <- compute_operational_periods(cam$setup_datetime, cam$retrieved_datetime,
                                            if (nrow(cam_gaps) > 0) cam_gaps$gap_start else as.POSIXct(character(0)),
                                            if (nrow(cam_gaps) > 0) cam_gaps$gap_end else as.POSIXct(character(0)))
    if (nrow(periods) == 0) return(NULL)

    comments <- rep(if (nrow(periods) > 1)
      paste0("Split from a single deployment window by ", nrow(cam_gaps), " recorded gap period(s)")
      else "Continuous, no recorded gaps", nrow(periods))

    # Deployment notes only explain the START of the whole window (first
    # period); retrieval notes only explain the END (last period) \u2014
    # attaching either to every split period would misleadingly suggest
    # it applies to gaps/splits it has nothing to do with.
    dep_note <- cam$notes_deployment
    if (!is.na(dep_note) && nchar(dep_note) > 0 && dep_note != "NA") {
      comments[1] <- paste0(comments[1], "; Deployment note: ", dep_note)
    }
    ret_note <- cam$notes_retrieval
    if (!is.na(ret_note) && nchar(ret_note) > 0 && ret_note != "NA") {
      comments[nrow(periods)] <- paste0(comments[nrow(periods)], "; Retrieval note: ", ret_note)
    }

    data.frame(
      deploymentID = paste0(cam$site_id, "_", cam$ct_id, "_", seq_len(nrow(periods))),
      locationID = cam$site_id,
      locationName = cam$station_folder,
      latitude = if ("lat" %in% names(cam)) cam$lat else NA_real_,
      longitude = if ("long" %in% names(cam)) cam$long else NA_real_,
      deploymentStart = format(periods$period_start, "%Y-%m-%dT%H:%M:%SZ"),
      deploymentEnd = format(periods$period_end, "%Y-%m-%dT%H:%M:%SZ"),
      cameraID = cam$ct_id,
      deploymentComments = comments,
      stringsAsFactors = FALSE
    )
  })
  rows <- rows[!sapply(rows, is.null)]
  if (length(rows) == 0) return(empty_result)
  do.call(rbind, rows)
}

# Reads back the CSV produced by Processing's "Download search effort
# (CSV)" button — Camtrap DP's Deployments schema (deploymentID,
# locationID, deploymentStart, deploymentEnd required; see
# build_camera_operation_export() above for the exact shape this app
# writes) — the way camera operation periods (computed from the
# deployment sheet + recorded gaps, no other file format) can be carried
# into a fresh session starting at Visualize & Export.
read_search_effort_csv <- function(filepath) {
  raw <- tryCatch(utils::read.csv(filepath, stringsAsFactors = FALSE, encoding = "UTF-8-BOM"),
                   error = function(e) NULL)
  if (is.null(raw)) {
    raw <- tryCatch(utils::read.csv(filepath, stringsAsFactors = FALSE),
                     error = function(e) NULL)
  }
  if (is.null(raw)) return(list(data = NULL, error = "Could not read this file as a CSV."))

  names(raw) <- trimws(names(raw))
  required <- c("deploymentID", "locationID", "deploymentStart", "deploymentEnd")
  missing_req <- setdiff(required, names(raw))
  if (length(missing_req) > 0) {
    return(list(data = NULL, error = paste0(
      "This doesn't look like a Camtrap DP-format camera operation export, missing column(s): ",
      paste(missing_req, collapse = ", "))))
  }

  raw$deploymentStart <- suppressWarnings(as.POSIXct(raw$deploymentStart, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  raw$deploymentEnd   <- suppressWarnings(as.POSIXct(raw$deploymentEnd, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  list(data = raw, error = NULL)
}

# =============================================================================
# PAGE 4 (Visualize & Export) — shared data-building helpers for "Exports"
# =============================================================================

# The single bridge every Individual-ID-aware export on this page relies
# on. TrapTagger's own export has NO local filename at all (only a remote
# image_url) — the only way to link its species/station/timestamp records
# back to ArgusWild's individual_id (keyed by local filename) is via
# match_traptagger_to_local_images(), the same EXIF-based station+timestamp
# match Processing's "Focal species export" already does — generalized
# here to ALL TrapTagger records at once, not just one selected species.
# Also joins back to the deployment sheet (by normalized station name) to
# recover block/season/cell_id, which TrapTagger's own export doesn't
# carry either. Every join is a left join — a record with no local image
# match, or no ArgusWild data at all, still appears with NA in the columns
# that couldn't be filled in, rather than being silently dropped.
build_enriched_detections <- function(traptagger_df, exif_df, arguswild_df, deployment_df) {
  if (is.null(traptagger_df) || nrow(traptagger_df) == 0) return(NULL)
  matched <- match_traptagger_to_local_images(traptagger_df, exif_df)
  matched$local_filename <- ifelse(is.na(matched$matched_local_path), NA_character_,
                                    basename(matched$matched_local_path))

  if (!is.null(arguswild_df) && nrow(arguswild_df) > 0) {
    argus_cols <- intersect(c("media_asset", "individual_id", "sex", "life_stage"), names(arguswild_df))
    argus_df <- unique(arguswild_df[argus_cols])
    for (mc in setdiff(c("individual_id", "sex", "life_stage"), argus_cols)) argus_df[[mc]] <- NA_character_
    matched <- merge(matched, argus_df, by.x = "local_filename", by.y = "media_asset", all.x = TRUE)
  } else {
    matched$individual_id <- NA_character_
    matched$sex <- NA_character_
    matched$life_stage <- NA_character_
  }

  if (!is.null(deployment_df) && nrow(deployment_df) > 0 && "station_folder" %in% names(deployment_df)) {
    dep_cols <- intersect(c("station_folder", "block", "season", "block_season", "cell_id", "ct_id"), names(deployment_df))
    dep_stations <- unique(deployment_df[dep_cols])
    dep_stations$station_norm <- normalize_station_name(dep_stations$station_folder)
    # A station with more than one camera has no single unambiguous ct_id
    # to assign a TrapTagger record to (which doesn't track camera-level
    # detail) — ct_id is only kept where the station is unambiguous
    # (exactly one camera), left NA otherwise rather than guessing.
    station_cam_counts <- table(dep_stations$station_norm)
    single_cam_stations <- names(station_cam_counts)[station_cam_counts == 1]
    dep_stations$ct_id[!(dep_stations$station_norm %in% single_cam_stations)] <- NA_character_
    dep_stations <- dep_stations[!duplicated(dep_stations$station_norm), ]
    join_cols <- c("station_norm", setdiff(dep_cols, "station_folder"))
    matched$station_norm <- normalize_station_name(matched$station_folder)
    matched <- merge(matched, dep_stations[join_cols], by = "station_norm", all.x = TRUE)
    matched$station_norm <- NULL
  } else {
    matched$block <- NA_character_; matched$season <- NA_character_
    matched$block_season <- NA_character_; matched$cell_id <- NA_character_; matched$ct_id <- NA_character_
  }
  matched
}

# Collapses consecutive detections of the same species at the same
# station within `threshold_mins` into a single "independent event" — the
# standard camera-trap approach for avoiding pseudo-replication from one
# animal triggering a burst of photos. Returns one row per event (its
# start/end time and photo count), not one row per photo.
collapse_to_independent_events <- function(df, threshold_mins) {
  empty <- data.frame(station_folder = character(0), species = character(0),
                       event_start = as.POSIXct(character(0)), event_end = as.POSIXct(character(0)),
                       n_photos = integer(0), stringsAsFactors = FALSE)
  if (is.null(df) || nrow(df) == 0) return(empty)
  # A record with no timestamp at all can't meaningfully participate in
  # time-threshold grouping — previously it became its own single-record
  # "event" whose start/end were computed via min()/max() on an all-NA,
  # na.rm-emptied vector, which silently produces Inf/-Inf (with a
  # warning) rather than a real date. Dropped here before grouping
  # starts, rather than letting a degenerate event through.
  df <- df[!is.na(df$timestamp), ]
  if (nrow(df) == 0) return(empty)
  df <- df[order(df$station_folder, df$species, df$timestamp), ]

  event_id <- integer(nrow(df))
  counter <- 0L
  last_station <- NA_character_; last_species <- NA_character_; last_time <- as.POSIXct(NA)
  for (i in seq_len(nrow(df))) {
    # A raw `!=` on two values that could each be NA (a record with a
    # missing station or species) evaluates to NA, not TRUE/FALSE — and
    # `if (NA)` throws a hard R error ("missing value where TRUE/FALSE
    # needed"), not just a wrong result. !identical() is NA-safe: it
    # correctly treats two NAs as "the same" and an NA next to a real
    # value as "different," always returning TRUE/FALSE.
    is_new <- is.na(last_time) ||
              !identical(df$station_folder[i], last_station) ||
              !identical(df$species[i], last_species) ||
              is.na(df$timestamp[i]) ||
              as.numeric(difftime(df$timestamp[i], last_time, units = "mins")) > threshold_mins
    if (is_new) counter <- counter + 1L
    event_id[i] <- counter
    last_station <- df$station_folder[i]; last_species <- df$species[i]; last_time <- df$timestamp[i]
  }

  agg <- do.call(rbind, lapply(split(seq_len(nrow(df)), event_id), function(idx) {
    sub <- df[idx, ]
    data.frame(station_folder = sub$station_folder[1], species = sub$species[1],
               event_start = min(sub$timestamp, na.rm = TRUE), event_end = max(sub$timestamp, na.rm = TRUE),
               n_photos = nrow(sub), stringsAsFactors = FALSE)
  }))
  agg[order(agg$station_folder, agg$event_start), ]
}

# Computes pairwise activity-overlap coefficients (Ridout & Linkie's
# method, via the "overlap" package) between every pair of groups in a
# named list of hour-of-day vectors (the same `groups` structure the
# Activity tab's plot already builds, from 2-species comparison or a
# covariate split). Delta ranges from 0 (no overlap at all) to 1
# (identical activity patterns) \u2014 the standard, citable metric in the
# camera-trap literature for questions like temporal niche partitioning
# between a predator and its prey, or between two competing species.
#
# Dhat1 is used whenever the smaller of the two groups has fewer than 50
# independent events (the package's own documented recommendation,
# since Dhat4/Dhat5 are only reliable at larger samples); Dhat4
# otherwise. A bootstrap confidence interval (basic0: bias-corrected
# percentile, per Meredith & Ridout's own overlap package vignette) is
# included since a point estimate alone, with no sense of its precision,
# is of limited scientific use \u2014 kept to a modest number of resamples
# (200) to stay responsive in an interactive app; the package's own
# vignette recommends 10,000 for a real publication, so this trades some
# CI precision for usability here and that trade-off is stated plainly
# in the UI, not hidden.
compute_activity_overlap_table <- function(groups, n_boot = 200) {
  if (length(groups) < 2) return(data.frame())
  group_names <- names(groups)
  pairs <- combn(seq_along(groups), 2, simplify = FALSE)

  rows <- lapply(pairs, function(idx) {
    a_hrs <- groups[[idx[1]]]; b_hrs <- groups[[idx[2]]]
    n_a <- length(a_hrs); n_b <- length(b_hrs)
    base_row <- data.frame(Group_1 = group_names[idx[1]], Group_2 = group_names[idx[2]],
                            n_1 = n_a, n_2 = n_b, Dhat = NA_real_, Method = NA_character_,
                            CI_low = NA_real_, CI_high = NA_real_, stringsAsFactors = FALSE)
    if (n_a < 2 || n_b < 2) return(base_row)

    a_rad <- a_hrs * (2 * pi / 24)
    b_rad <- b_hrs * (2 * pi / 24)
    method <- if (min(n_a, n_b) < 50) "Dhat1" else "Dhat4"
    dhat <- tryCatch(as.numeric(overlap::overlapEst(a_rad, b_rad, type = method)),
                      error = function(e) NA_real_)
    if (is.na(dhat)) { base_row$Method <- method; return(base_row) }

    ci <- tryCatch({
      boots <- overlap::bootstrap(a_rad, b_rad, n_boot, type = method)
      overlap::bootCI(dhat, boots)["basic0", ]
    }, error = function(e) c(NA_real_, NA_real_))

    data.frame(Group_1 = group_names[idx[1]], Group_2 = group_names[idx[2]],
               n_1 = n_a, n_2 = n_b, Dhat = round(dhat, 3), Method = method,
               CI_low = round(unname(ci[1]), 3), CI_high = round(unname(ci[2]), 3),
               stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

# Builds a STATION x SPECIES community matrix (cell values = count of
# independent events) \u2014 the standard "sites x species" input vegan's
# community-ecology functions expect, built on the same
# collapse_to_independent_events() pipeline the rest of this app already
# uses for species-level analysis, not a new, separate detection-counting
# approach. exclude_species lets the user drop non-wildlife categories a
# TrapTagger species list can include (e.g. "Human", "Vehicle", "Blank")
# that shouldn't count toward richness, since this app has no built-in
# assumption about exactly which category names a given account uses.
build_community_matrix <- function(traptagger_df, threshold_mins, exclude_species = character(0)) {
  if (is.null(traptagger_df) || nrow(traptagger_df) == 0) return(NULL)
  df <- traptagger_df[!is.na(traptagger_df$species) & !(traptagger_df$species %in% exclude_species), ]
  if (nrow(df) == 0) return(NULL)
  events <- collapse_to_independent_events(df, threshold_mins)
  if (nrow(events) == 0) return(NULL)
  # FUN = length, not sum: counting independent EVENTS per
  # station/species (each row in `events` is already one event), not
  # the photos within them.
  agg <- aggregate(n_photos ~ station_folder + species, data = events, FUN = length)
  names(agg)[3] <- "n_events"
  mat <- xtabs(n_events ~ station_folder + species, data = agg)
  as.data.frame.matrix(mat)
}

# Observed richness, Shannon/Simpson diversity (vegan::diversity(), on
# total counts summed across all stations \u2014 one survey-wide value, not
# one per station), and extrapolated richness estimators (chao,
# jackknife1/2, bootstrap, all from a single vegan::specpool() call,
# incidence-based across stations \u2014 the appropriate approach for
# multiple sampling sites, as opposed to estimateR()'s single-site,
# abundance-based alternative).
compute_diversity_summary <- function(comm_matrix) {
  if (is.null(comm_matrix) || nrow(comm_matrix) == 0 || ncol(comm_matrix) == 0) return(NULL)
  total_by_species <- colSums(comm_matrix)
  pool <- tryCatch(vegan::specpool(comm_matrix), error = function(e) NULL)
  list(
    observed_richness = sum(total_by_species > 0),
    shannon = tryCatch(vegan::diversity(total_by_species, index = "shannon"), error = function(e) NA_real_),
    simpson = tryCatch(vegan::diversity(total_by_species, index = "simpson"), error = function(e) NA_real_),
    n_stations = nrow(comm_matrix),
    n_events = sum(comm_matrix),
    pool = pool
  )
}

# Builds a camera x day matrix from camera operation periods. Without
# detections_by_cam_day: 1 = operational that day, NA = not operational,
# matching the standard camera-trap-analysis convention (e.g. camtrapR's
# "camera operation matrix") for occupancy-model input. With
# detections_by_cam_day supplied (a data.frame with cameraID + Date
# columns, one row per detection day): 1 = detected AND operational that
# day, 0 = operational but not detected, NA = not operational.
# get_operation_periods()'s result can come from two different sources:
# freshly computed by build_camera_operation_export() (deploymentStart/End
# are plain ISO 8601 text, "...T...Z"), or a re-uploaded search effort CSV
# via read_search_effort_csv() (already converted to POSIXct there). A
# bare as.character() on an already-POSIXct value uses R's own default
# print format ("YYYY-MM-DD HH:MM:SS", no "T", no "Z") rather than the ISO
# one, which silently fails to re-parse against the ISO format string and
# turns every value into NA — exactly the "no rows to aggregate" failure
# this was causing. Handles both representations explicitly instead of
# assuming text.
parse_deployment_datetime <- function(x) {
  if (inherits(x, "POSIXct")) return(x)
  as.POSIXct(as.character(x), format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

# Unions camera-level operational periods (from build_camera_operation_export(),
# or get_operation_periods()'s re-uploaded-CSV path \u2014 both share the same
# column structure) up to the STATION level. For occupancy and SECR
# specifically, the station \u2014 not the individual camera \u2014 is the
# methodologically correct sampling/detector unit: occupancy doesn't
# care which camera at a station triggered, just whether the species
# was detected at that station on a given day, and SECR treats two
# co-located detectors as redundant (never two at the same point).
# Paired cameras at a station are also often deliberately set up to
# capture both flanks of an animal for individual ID (e.g. leopards) \u2014
# excluding records that can't be pinned to one specific camera would
# systematically drop exactly that data, not just an edge case.
#
# A station is OPERATING on a given day if AT LEAST ONE of its
# camera(s) was operating that day (the union of their individual
# windows) \u2014 even with one camera down, the other could still detect
# (and potentially one-flank-ID) an animal.
#
# locationID/cameraID here are the NORMALIZED station key (matching
# normalize_station_name()'s convention used throughout this app for
# TrapTagger-to-deployment-sheet matching, since TrapTagger's own
# station_folder usually drops the underscore the deployment sheet
# keeps) \u2014 so any caller joining detections against this only needs to
# normalize their own side the same way. locationName keeps the
# original, human-readable station folder name for display/filenames.
build_station_operation_periods <- function(cam_level_periods) {
  if (is.null(cam_level_periods) || nrow(cam_level_periods) == 0) return(cam_level_periods)

  merge_intervals <- function(starts, ends) {
    ord <- order(starts)
    starts <- starts[ord]; ends <- ends[ord]
    out_starts <- starts[1]; out_ends <- ends[1]
    for (i in seq_along(starts)[-1]) {
      if (starts[i] <= out_ends[length(out_ends)]) {
        out_ends[length(out_ends)] <- max(out_ends[length(out_ends)], ends[i])
      } else {
        out_starts <- c(out_starts, starts[i])
        out_ends   <- c(out_ends, ends[i])
      }
    }
    list(starts = out_starts, ends = out_ends)
  }

  df <- cam_level_periods
  df$start_dt <- parse_deployment_datetime(df$deploymentStart)
  df$end_dt   <- parse_deployment_datetime(df$deploymentEnd)
  df <- df[!is.na(df$start_dt) & !is.na(df$end_dt), ]
  if (nrow(df) == 0) return(cam_level_periods[0, ])
  df$station_norm <- normalize_station_name(df$locationName)

  stations <- unique(df$station_norm)
  rows <- lapply(stations, function(st_norm) {
    sub <- df[df$station_norm == st_norm, ]
    sub <- sub[order(sub$start_dt), ]
    merged <- merge_intervals(sub$start_dt, sub$end_dt)
    n <- length(merged$starts)
    n_cams_here <- length(unique(sub$locationID))
    data.frame(
      deploymentID = paste0(st_norm, "_", seq_len(n)),
      locationID = st_norm,
      locationName = sub$locationName[1],
      latitude = sub$latitude[1],
      longitude = sub$longitude[1],
      deploymentStart = format(merged$starts, "%Y-%m-%dT%H:%M:%SZ"),
      deploymentEnd = format(merged$ends, "%Y-%m-%dT%H:%M:%SZ"),
      cameraID = st_norm,
      n_cameras = n_cams_here,
      deploymentComments = paste0(
        "Station-level: combines ", n_cams_here, " camera(s) at this station; ",
        if (n > 1) paste0("split by ", n - 1, " gap period(s) where NO camera here was operating")
        else "continuously covered by at least one camera here"),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

build_camera_day_matrix <- function(operation_df, detections_by_cam_day = NULL) {
  if (is.null(operation_df) || nrow(operation_df) == 0) return(data.frame())
  # cameraID can be read as numeric (camera IDs like "237" look purely
  # numeric to a spreadsheet reader) \u2014 R indexes a NAMED matrix
  # POSITIONALLY when given a numeric subscript, not by name, so an
  # un-coerced numeric camera ID silently becomes "row number 237" rather
  # than "the row named 237", which is well beyond how many rows the
  # matrix actually has (one per unique camera). Coerced once here so
  # every downstream use (dimnames, row indexing) is guaranteed
  # character, and therefore guaranteed name-based.
  operation_df$cameraID <- as.character(operation_df$cameraID)
  starts <- as.Date(parse_deployment_datetime(operation_df$deploymentStart))
  ends   <- as.Date(parse_deployment_datetime(operation_df$deploymentEnd))
  valid <- !is.na(starts) & !is.na(ends)
  operation_df <- operation_df[valid, ]; starts <- starts[valid]; ends <- ends[valid]
  if (nrow(operation_df) == 0) return(data.frame())

  all_days <- seq(min(starts), max(ends), by = "day")
  cameras <- sort(unique(operation_df$cameraID))
  mat <- matrix(NA_integer_, nrow = length(cameras), ncol = length(all_days),
                dimnames = list(cameras, as.character(all_days)))

  has_detections <- !is.null(detections_by_cam_day) && nrow(detections_by_cam_day) > 0

  if (!has_detections) {
    # Plain effort matrix: matches camtrapR's cameraOperation() convention
    # exactly (NA: camera(s) not set up, 0: camera(s) not operational, 1:
    # operational) \u2014 https://jniedballa.github.io/camtrapR/reference/cameraOperation.html.
    # A gap WITHIN a camera's overall deployment window (it was physically
    # there, just not working that day) is a meaningfully different thing
    # from a day OUTSIDE that window entirely (it wasn't there at all) \u2014
    # the former should be 0, not NA, to match that convention. Each
    # camera's full window (its earliest start to its latest end, across
    # however many gap-split periods it has) is marked 0 first; only then
    # are its specific "on" sub-periods overlaid as 1, leaving any gap
    # within that window sitting at 0 rather than indistinguishable NA.
    windows <- data.frame(cameraID = operation_df$cameraID, win_start = starts, win_end = ends)
    win_start_agg <- aggregate(win_start ~ cameraID, data = windows, FUN = min)
    win_end_agg   <- aggregate(win_end ~ cameraID, data = windows, FUN = max)
    for (k in seq_len(nrow(win_start_agg))) {
      cam <- win_start_agg$cameraID[k]
      win_days <- seq(win_start_agg$win_start[k], win_end_agg$win_end[win_end_agg$cameraID == cam], by = "day")
      mat[cam, as.character(win_days)] <- 0L
    }
  }

  operating_value <- if (has_detections) 0L else 1L
  for (i in seq_len(nrow(operation_df))) {
    cam <- operation_df$cameraID[i]
    days_on <- seq(starts[i], ends[i], by = "day")
    mat[cam, as.character(days_on)] <- operating_value
  }

  if (has_detections) {
    for (j in seq_len(nrow(detections_by_cam_day))) {
      cam <- as.character(detections_by_cam_day$cameraID[j])
      day <- as.character(detections_by_cam_day$Date[j])
      if (cam %in% rownames(mat) && day %in% colnames(mat) && !is.na(mat[cam, day])) mat[cam, day] <- 1L
    }
  }

  data.frame(cameraID = rownames(mat), mat, check.names = FALSE, row.names = NULL, stringsAsFactors = FALSE)
}

# =============================================================================
# DATA HELPERS \u2014 Occupancy modeling (Analytics tab)
# =============================================================================

# Collapses a DAILY camera/station-operation matrix (as build_camera_day_matrix()
# produces, NA/0/1 convention) into an OCCASION-level detection history for
# an occupancy model: unmarked::occu() expects discrete occasions, not raw
# daily records. Occasions are built as consecutive, non-overlapping blocks
# of `occasion_length` days spanning the full survey (the last occasion may
# be shorter if the survey length isn't an exact multiple of occasion_length).
# Within an occasion: NA if the station had NO operating days at all in that
# window (not yet deployed there, or already retrieved); 1 if detected on ANY
# operating day within the window; 0 if it operated on at least one day with
# no detection. Also returns, for every station x occasion cell, the number
# of days actually OPERATING within that occasion \u2014 a standard effort
# covariate for detection probability, since an occasion where the camera
# only ran 2 of 7 days should often show a lower chance of detecting the
# species than one that ran the full 7, independent of true occupancy.
build_occupancy_occasion_matrix <- function(daily_df, occasion_length) {
  if (is.null(daily_df) || nrow(daily_df) == 0 || occasion_length < 1) return(NULL)
  date_cols <- setdiff(names(daily_df), "cameraID")
  if (length(date_cols) == 0) return(NULL)
  all_dates <- as.Date(date_cols)
  ord <- order(all_dates)
  date_cols <- date_cols[ord]
  n_days <- length(date_cols)
  n_occasions <- ceiling(n_days / occasion_length)
  occasion_idx <- ceiling(seq_len(n_days) / occasion_length)

  stations <- as.character(daily_df$cameraID)
  mat <- as.matrix(daily_df[date_cols])
  rownames(mat) <- stations

  occasion_names <- paste0("o", seq_len(n_occasions))
  y <- matrix(NA_integer_, nrow = length(stations), ncol = n_occasions,
              dimnames = list(stations, occasion_names))
  effort <- matrix(NA_integer_, nrow = length(stations), ncol = n_occasions,
                    dimnames = list(stations, occasion_names))

  for (occ in seq_len(n_occasions)) {
    cols <- which(occasion_idx == occ)
    sub <- mat[, cols, drop = FALSE]
    n_operating <- rowSums(!is.na(sub))
    any_detect  <- rowSums(sub == 1L, na.rm = TRUE) > 0
    y[, occ]      <- ifelse(n_operating == 0, NA_integer_, ifelse(any_detect, 1L, 0L))
    effort[, occ] <- n_operating
  }

  list(y = y, effort = effort, n_occasions = n_occasions)
}

# Builds one row of site-level covariates per STATION (matching
# get_station_operation_periods()'s own locationID key) for the occupancy
# model. "Block" and "season" come straight from the deployment sheet (the
# survey's own spatial/temporal design, so always available once a
# deployment sheet is loaded); "paired station" and lat/long come from
# station_ops itself (n_cameras, added to build_station_operation_periods()
# specifically to support this); "habitat" comes from an uploaded GIS layer,
# if any, via the SAME point-in-polygon spatial join
# viz_gis_camera_count_table already uses, so the two features never
# disagree about which feature a station falls in.
build_occupancy_site_covariates <- function(station_ops, deployment_df, gis_layers = NULL,
                                             gis_layer_name = NULL) {
  if (is.null(station_ops) || nrow(station_ops) == 0) return(NULL)
  keep <- !duplicated(station_ops$locationID)
  df <- data.frame(
    locationID = station_ops$locationID[keep],
    latitude   = station_ops$latitude[keep],
    longitude  = station_ops$longitude[keep],
    paired     = ifelse(station_ops$n_cameras[keep] >= 2, "Paired", "Single"),
    stringsAsFactors = FALSE
  )

  df$block  <- NA_character_
  df$season <- NA_character_
  if (!is.null(deployment_df) && "station_folder" %in% names(deployment_df)) {
    dep <- deployment_df
    dep$station_norm <- normalize_station_name(dep$station_folder)
    if ("block" %in% names(dep))  df$block  <- dep$block[match(df$locationID, dep$station_norm)]
    if ("season" %in% names(dep)) df$season <- dep$season[match(df$locationID, dep$station_norm)]
  }

  df$habitat <- NA_character_
  has_coords <- all(!is.na(df$latitude) & !is.na(df$longitude))
  if (!is.null(gis_layers) && length(gis_layers) > 0 && has_coords) {
    use_name <- if (!is.null(gis_layer_name) && gis_layer_name %in% names(gis_layers)) gis_layer_name
                else names(gis_layers)[1]
    habitat_result <- tryCatch({
      pts <- sf::st_as_sf(df, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)
      layer <- tryCatch(sf::st_transform(gis_layers[[use_name]], 4326), error = function(e) gis_layers[[use_name]])
      within_list <- suppressMessages(sf::st_within(pts, layer, sparse = TRUE))
      label_col <- intersect(c("name", "habitat", "type", "label", "Name", "NAME", "Habitat"), names(layer))
      poly_labels <- if (length(label_col) > 0) as.character(sf::st_drop_geometry(layer)[[label_col[1]]]) else
        paste0("Feature ", seq_len(nrow(layer)))
      vapply(within_list, function(idx) if (length(idx) == 0) NA_character_ else poly_labels[idx[1]], character(1))
    }, error = function(e) NULL)
    if (!is.null(habitat_result)) df$habitat <- habitat_result
  }
  df
}

# Fits a single-season, single-species occupancy model (unmarked::occu())
# from an occasion-level detection history, with user-chosen covariates on
# occupancy (psi) and/or detection (p). occ_covariates/det_covariates are
# each a (possibly empty) character vector of column names to include
# ("~1", intercept-only, if empty \u2014 matching unmarked's own convention for
# a null sub-model). Returns a structured list rather than the raw fit
# object alone, since the UI needs several different derived views of the
# same fit (coefficient tables, AIC, naive-vs-model occupancy, per-site
# predictions) without re-deriving them from the fit object in several
# different places. Every unmarked call is wrapped defensively: a
# convergence failure or a malformed covariate selection should surface as
# a clear message in the UI, not an uncaught error.
fit_occupancy_model <- function(y, site_covs, obs_covs, occ_covariates = character(0),
                                 det_covariates = character(0)) {
  if (is.null(y) || nrow(y) == 0) return(list(error = "No detection history to fit."))
  if (is.null(site_covs) || nrow(site_covs) == 0) return(list(error = "No site covariates available."))

  site_covs_df <- site_covs[match(rownames(y), site_covs$locationID), , drop = FALSE]
  umf <- tryCatch(
    suppressWarnings(unmarked::unmarkedFrameOccu(y = y, siteCovs = site_covs_df, obsCovs = obs_covs)),
    error = function(e) e)
  if (inherits(umf, "error")) return(list(error = paste("Could not build the model frame:", conditionMessage(umf))))

  occ_form <- if (length(occ_covariates) == 0) "~1" else paste0("~", paste(occ_covariates, collapse = " + "))
  det_form <- if (length(det_covariates) == 0) "~1" else paste0("~", paste(det_covariates, collapse = " + "))
  full_formula <- tryCatch(stats::as.formula(paste(det_form, occ_form)), error = function(e) e)
  if (inherits(full_formula, "error"))
    return(list(error = "Could not build a model formula from the selected covariates."))

  fit <- tryCatch(unmarked::occu(full_formula, data = umf), error = function(e) e)
  if (inherits(fit, "error")) return(list(error = paste("Model failed to fit:", conditionMessage(fit))))

  naive_occupancy <- mean(apply(y, 1, function(r) any(r == 1, na.rm = TRUE)))
  psi_hat <- tryCatch(unmarked::predict(fit, type = "state"), error = function(e) NULL)
  model_occupancy <- if (!is.null(psi_hat)) mean(psi_hat$Predicted, na.rm = TRUE) else NA_real_

  state_summary <- tryCatch(as.data.frame(summary(fit["state"])), error = function(e) NULL)
  det_summary   <- tryCatch(as.data.frame(summary(fit["det"])),   error = function(e) NULL)

  list(
    fit = fit,
    formula_text = paste0("Detection: ", det_form, "    Occupancy: ", occ_form),
    aic = tryCatch(fit@AIC, error = function(e) tryCatch(stats::AIC(fit), error = function(e2) NA_real_)),
    naive_occupancy = naive_occupancy,
    model_occupancy = model_occupancy,
    n_sites = nrow(y),
    n_occasions = ncol(y),
    state_summary = state_summary,
    det_summary = det_summary,
    site_predictions = if (!is.null(psi_hat))
      data.frame(locationID = rownames(y), psi_hat, stringsAsFactors = FALSE) else NULL,
    error = NULL
  )
}

# MacKenzie & Bailey (2004)'s chi-square goodness-of-fit test for a
# single-season occupancy model, via AICcmodavg::mb.gof.test() \u2014 the
# standard, citable, purpose-built implementation of this specific test
# statistic for occu() fits (unmarked's own parboot() is a generic
# bootstrap framework, not this test itself). nsim kept well below the
# thousands a published analysis would typically use, matching the same
# responsiveness-over-publication-precision tradeoff already made for the
# activity-overlap bootstrap CI elsewhere in this app, so treat this as
# indicative rather than publication-ready without re-running at a much
# higher nsim. parallel = FALSE is required, not just a performance
# choice: mb.gof.test()'s bootstrap defaults to parallel worker
# processes, and a parallel worker starts a fresh R session that doesn't
# automatically inherit this session's attached packages \u2014 confirmed as
# the actual remaining cause of an "object 'unmarked' not found" error
# that persisted even after unmarked was properly attached at the top of
# this file.
run_occupancy_gof <- function(fit, nsim = 100) {
  result <- tryCatch(
    AICcmodavg::mb.gof.test(fit, nsim = nsim, plot.hist = FALSE, parallel = FALSE),
    error = function(e) e)
  if (inherits(result, "error")) return(list(error = paste("Goodness-of-fit test failed:", conditionMessage(result))))
  has_fields <- all(c("chi.square", "p.value", "c.hat.est") %in% names(result))
  if (!has_fields) return(list(error = "Goodness-of-fit test ran but returned an unexpected result structure."))
  list(
    chi_square = result$chi.square,
    p_value = result$p.value,
    c_hat = result$c.hat.est,
    nsim = nsim,
    error = NULL
  )
}

# Joins ArgusWild's individual-ID results back to our own focal-species
# records, matching app.R's build-plan goal ("ArgusWild CSV reader + join
# to species data"). The join key is the image filename: our own
# focal-species export copies images with their original renamed filename
# UNCHANGED, so ArgusWild's Encounter.mediaAsset0 should match
# basename(matched_local_path) exactly for any image that was
# successfully identified.
# Fixed column order shared between join_arguswild_to_species_data()'s
# output and the editable "Individual ID summary" table on Processing —
# the cell-edit handler needs to know exactly which column index (0-based,
# per DT's JS convention) corresponds to which field, so this order must
# stay in sync between the two rather than being re-derived independently.
ARGUS_ID_TABLE_COLS <- c("station_folder", "species", "timestamp", "local_filename",
                         "individual_id", "sex", "life_stage")

join_arguswild_to_species_data <- function(arguswild_df, focal_matched_df) {
  base_cols <- c("station_folder", "species", "timestamp", "matched_local_path")
  out_cols <- ARGUS_ID_TABLE_COLS
  if (is.null(focal_matched_df) || nrow(focal_matched_df) == 0 ||
      !all(base_cols %in% names(focal_matched_df))) {
    return(data.frame(station_folder = character(0), species = character(0),
                       timestamp = as.POSIXct(character(0)), local_filename = character(0),
                       individual_id = character(0), sex = character(0), life_stage = character(0),
                       stringsAsFactors = FALSE))
  }

  species_df <- focal_matched_df[base_cols]
  species_df$local_filename <- ifelse(is.na(species_df$matched_local_path), NA_character_,
                                       basename(species_df$matched_local_path))
  species_df$matched_local_path <- NULL

  # individual_id/sex/life_stage always exist in the result, even if the
  # uploaded ArgusWild CSV didn't supply sex/life_stage — otherwise there'd
  # be no column at all for the user to manually fill those in later.
  argus_cols <- intersect(c("media_asset", "individual_id", "sex", "life_stage"), names(arguswild_df))
  argus_df <- unique(arguswild_df[argus_cols])
  for (missing_col in setdiff(c("individual_id", "sex", "life_stage"), argus_cols)) {
    argus_df[[missing_col]] <- NA_character_
  }

  merged <- merge(species_df, argus_df, by.x = "local_filename", by.y = "media_asset", all.x = TRUE)
  merged[out_cols]
}

# Auto-detect knockdown gaps: TrapTagger has no separate "gap" field — a
# knockdown period is registered by tagging the affected images'
# Species as "Knocked Down". Finds the min/max timestamp of those tags
# per station, treating it as ONE contiguous gap (a station with more
# than one separate knockdown incident across the survey would currently
# show as a single gap spanning both — a reasonable starting point, worth
# revisiting if that turns out to matter in practice).
#
# Since TrapTagger's export is station-level (can't tell which camera in a
# double-camera pair was affected), this returns ONE ROW PER CAMERA at the
# affected station — conservatively treating both as down, since there's
# no way to disambiguate from this data alone.
detect_knockdown_gaps <- function(traptagger_df, deployment_df) {
  empty_result <- data.frame(site_id = character(0), ct_id = character(0),
                              gap_start = as.POSIXct(character(0)), gap_end = as.POSIXct(character(0)),
                              reason = character(0), source = character(0), stringsAsFactors = FALSE)
  if (is.null(traptagger_df) || !("species" %in% names(traptagger_df))) return(empty_result)

  kd <- traptagger_df[traptagger_df$species == "Knocked Down" & !is.na(traptagger_df$timestamp), ]
  if (nrow(kd) == 0) return(empty_result)

  by_station <- split(kd$timestamp, kd$station_folder)
  dep_norm <- normalize_station_name(deployment_df$station_folder)

  rows <- lapply(names(by_station), function(station) {
    ts <- by_station[[station]]
    cams <- unique(deployment_df[dep_norm == normalize_station_name(station), c("site_id", "ct_id")])
    if (nrow(cams) == 0) return(NULL)
    data.frame(
      site_id = cams$site_id, ct_id = cams$ct_id,
      gap_start = min(ts), gap_end = max(ts),
      reason = paste0("Auto-detected from TrapTagger (station ", station,
                       ", station-level data, can't distinguish individual cameras)"),
      source = "Auto (TrapTagger)", stringsAsFactors = FALSE
    )
  })
  rows <- rows[!sapply(rows, is.null)]
  if (length(rows) == 0) return(empty_result)
  do.call(rbind, rows)
}

# Cross-check TrapTagger's own observed activity per station against our
# deployment sheet's setup/retrieval window — same idea as the QA/QC
# timestamp check, but using TrapTagger's classification data as the
# source instead of raw EXIF, so genuine discrepancies between the two
# pipelines are visible. "Knocked Down" tagged rows are excluded from the
# observed range (they represent downtime, not real activity). A station
# with zero non-knockdown records is flagged as not found — either it was
# never uploaded, or the camera never captured anything usable.
cross_check_traptagger <- function(traptagger_df, deployment_df, tolerance_days) {
  # One row per STATION, not per camera — a station's two co-located
  # cameras can have slightly different setup/retrieved dates in the
  # deployment sheet (real-world field variation), and grouping on the
  # exact date too (as a plain unique() on all these columns together
  # would) produces a confusing duplicate row for the same station
  # instead of one properly-aggregated deployment window. The station's
  # window is the min setup and max retrieved across all its cameras.
  dep_key <- paste(deployment_df$block_season, deployment_df$cell_id, deployment_df$station_folder, sep = "\u0001")
  setup_by_station     <- split(deployment_df$setup_datetime, dep_key)
  retrieved_by_station  <- split(deployment_df$retrieved_datetime, dep_key)

  stations <- unique(deployment_df[c("block_season", "cell_id", "station_folder")])
  station_key <- paste(stations$block_season, stations$cell_id, stations$station_folder, sep = "\u0001")

  stations$setup_datetime <- as.POSIXct(sapply(station_key, function(k) {
    as.numeric(min(setup_by_station[[k]], na.rm = TRUE))
  }), origin = "1970-01-01", tz = "UTC")
  stations$retrieved_datetime <- as.POSIXct(sapply(station_key, function(k) {
    as.numeric(max(retrieved_by_station[[k]], na.rm = TRUE))
  }), origin = "1970-01-01", tz = "UTC")

  if (is.null(traptagger_df)) {
    stations$tt_start <- as.POSIXct(NA); stations$tt_end <- as.POSIXct(NA)
    stations$n_records <- 0L; stations$flag <- "No TrapTagger data loaded"
    return(stations)
  }

  active <- traptagger_df[traptagger_df$species != "Knocked Down" & !is.na(traptagger_df$timestamp), ]
  by_station <- split(active$timestamp, normalize_station_name(active$station_folder))
  n_by_station <- table(normalize_station_name(active$station_folder))
  stations_norm <- normalize_station_name(stations$station_folder)

  stations$tt_start   <- as.POSIXct(sapply(stations_norm, function(s) {
    if (s %in% names(by_station)) as.numeric(min(by_station[[s]])) else NA
  }), origin = "1970-01-01", tz = "UTC")
  stations$tt_end <- as.POSIXct(sapply(stations_norm, function(s) {
    if (s %in% names(by_station)) as.numeric(max(by_station[[s]])) else NA
  }), origin = "1970-01-01", tz = "UTC")
  stations$n_records <- sapply(stations_norm, function(s) {
    if (s %in% names(n_by_station)) as.integer(n_by_station[[s]]) else 0L
  })

  start_diff <- as.numeric(abs(difftime(stations$tt_start, stations$setup_datetime, units = "days")))
  end_diff   <- as.numeric(abs(difftime(stations$tt_end, stations$retrieved_datetime, units = "days")))

  stations$flag <- ifelse(
    stations$n_records == 0, "Not found in TrapTagger export",
    ifelse(start_diff > tolerance_days | end_diff > tolerance_days,
           "Timestamp mismatch vs deployment sheet", "OK")
  )
  stations
}

# Matches each TrapTagger record back to the local image file it came
# from, since TrapTagger's CSV only has a remote Image URL (an ID, not a
# local path or original filename) — there's no direct link otherwise.
# Matches on station (normalized, since our station_folder keeps an
# underscore TrapTagger's doesn't) + EXACT EXIF timestamp: both
# read_traptagger_csv() and extract_exif_datetimes() parse as UTC
# consistently, so a genuine match should line up exactly, not just
# approximately — a small tolerance (2 seconds) is kept only as a safety
# margin for edge-case rounding, not because a bigger drift is expected.
# Uses raw `datetime`, never `datetime_corrected` — TrapTagger saw the
# image's original EXIF timestamp when it was uploaded, before any
# in-app corrections existed.
match_traptagger_to_local_images <- function(traptagger_rows, exif_data) {
  n <- nrow(traptagger_rows)
  matched_path <- rep(NA_character_, n)
  match_diff_secs <- rep(NA_real_, n)

  if (is.null(exif_data) || nrow(exif_data) == 0) {
    traptagger_rows$matched_local_path <- matched_path
    traptagger_rows$match_diff_secs <- match_diff_secs
    return(traptagger_rows)
  }

  exif_station_norm <- normalize_station_name(exif_data$station_folder)
  by_station <- split(seq_len(nrow(exif_data)), exif_station_norm)
  tt_station_norm <- normalize_station_name(traptagger_rows$station_folder)

  for (i in seq_len(n)) {
    station <- tt_station_norm[i]
    ts <- traptagger_rows$timestamp[i]
    if (is.na(ts) || !(station %in% names(by_station))) next

    candidate_idx <- by_station[[station]]
    diffs <- abs(as.numeric(difftime(exif_data$datetime[candidate_idx], ts, units = "secs")))
    best <- which.min(diffs)
    if (length(best) == 0 || is.na(diffs[best]) || diffs[best] > 2) next

    matched_path[i] <- exif_data$path[candidate_idx[best]]
    match_diff_secs[i] <- diffs[best]
  }

  traptagger_rows$matched_local_path <- matched_path
  traptagger_rows$match_diff_secs <- match_diff_secs
  traptagger_rows
}

# Coordinate sanity checks: definitely-wrong values (missing or 0,0), plus
# a simple robust-statistical check for points far from the rest of the
# survey. Visual inspection via the map is still the primary QA tool here —
# this just surfaces the more obvious cases automatically.
find_coordinate_issues <- function(deployment_df) {
  df <- unique(deployment_df[c("block_season", "cell_id", "site_id", "ct_id", "lat", "long")])

  missing <- is.na(df$lat) | is.na(df$long) | (df$lat == 0 & df$long == 0)
  missing_rows <- df[missing, c("site_id", "ct_id")]

  valid <- df[!missing, ]
  outlier_rows <- valid[0, c("site_id", "ct_id", "lat", "long")]

  if (nrow(valid) >= 3) {
    center_lat  <- median(valid$lat)
    center_long <- median(valid$long)
    dist <- sqrt((valid$lat - center_lat)^2 + (valid$long - center_long)^2)
    spread <- stats::mad(dist)
    thresh <- max(median(dist) + 3 * spread, 0.1)  # ~0.1 degree (~11km) minimum floor
    outlier_rows <- valid[dist > thresh, c("site_id", "ct_id", "lat", "long")]
  }

  list(missing = missing_rows, outliers = outlier_rows)
}

# Apply a batch offset to every EXIF timestamp within the chosen scope,
# writing to a NEW column (datetime_corrected) so the original is
# preserved. Year/month offsets are calendar-aware (via POSIXlt); day/
# minute offsets are applied as plain elapsed time.
#
# IMPORTANT: the offset is always computed from the RAW `datetime` column,
# never from a previously-corrected value — so clicking "Apply correction"
# a second time (e.g. trying +2 years after +1 year didn't look right)
# always REPLACES the correction for that scope, rather than compounding
# on top of the last attempt.
#
# "camera" scope matches on site_id + CT_ID together (as
# "site_id|ct_id", matching the composite value the UI's dropdown sends) —
# NOT CT_ID alone, since a physical camera unit's ID isn't guaranteed
# globally unique across the whole deployment sheet (the same unit can be
# redeployed under a different site/season). Matching on CT_ID alone would
# apply the correction to every row sharing that ID, not just the one
# instance the user selected.
apply_timestamp_correction <- function(exif_data, scope_type, scope_value, years, months, days, minutes) {
  if (!("datetime_corrected" %in% names(exif_data))) {
    exif_data$datetime_corrected <- exif_data$datetime
  }

  in_scope <- switch(scope_type,
    "all"    = rep(TRUE, nrow(exif_data)),
    "block"  = exif_data$block_season == scope_value,
    "cell"   = exif_data$cell_id == scope_value,
    "camera" = paste(exif_data$site_id, exif_data$ct_id, sep = "|") == scope_value,
    rep(FALSE, nrow(exif_data))
  )
  in_scope[is.na(in_scope)] <- FALSE

  if (!any(in_scope)) return(exif_data)

  base <- exif_data$datetime[in_scope]
  lt <- as.POSIXlt(base)
  lt$year <- lt$year + years
  lt$mon  <- lt$mon + months
  corrected <- as.POSIXct(lt) + (days * 86400) + (minutes * 60)

  exif_data$datetime_corrected[in_scope] <- corrected
  exif_data
}

# Cameras worth flagging for follow-up: a large clock drift noted at
# retrieval, free-text notes mentioning a problem, or an image-audit status
# indicating a missing/empty folder.
# Read the actual reason text from a folder's EMPTY_REASON.txt (or similar),
# so a documented-empty camera's health flag shows WHY it's empty, not just
# that it is. Never throws — returns NA if nothing readable is found.
read_empty_reason_file <- function(folder_path) {
  if (is.na(folder_path) || !dir.exists(folder_path)) return(NA_character_)
  reason_files <- list.files(folder_path, pattern = "reason.*\\.txt$|empty.*\\.txt$",
                              ignore.case = TRUE, full.names = TRUE)
  if (length(reason_files) == 0) return(NA_character_)
  tryCatch({
    txt <- paste(readLines(reason_files[1], warn = FALSE), collapse = " ")
    trimws(txt)
  }, error = function(e) NA_character_)
}

build_camera_health_flags <- function(deployment_df, image_audit) {
  dep <- unique(deployment_df[c("block_season", "cell_id", "site_id", "ct_id",
                                 "retrieved_datetime", "retrieved_ct_datetime",
                                 "notes_deployment", "notes_retrieval")])

  dep$clock_drift_hours <- as.numeric(abs(difftime(dep$retrieved_datetime, dep$retrieved_ct_datetime, units = "hours")))

  flag_reason <- character(nrow(dep))
  for (i in seq_len(nrow(dep))) {
    reasons <- character(0)

    if (!is.na(dep$clock_drift_hours[i]) && dep$clock_drift_hours[i] > 24) {
      reasons <- c(reasons, paste0("Clock drift: ", round(dep$clock_drift_hours[i] / 24, 1), " day(s)"))
    }

    note_dep <- if ("notes_deployment" %in% names(dep)) trimws(as.character(dep$notes_deployment[i])) else ""
    note_ret <- if ("notes_retrieval"  %in% names(dep)) trimws(as.character(dep$notes_retrieval[i]))  else ""
    notes <- trimws(paste(note_dep, note_ret))
    if (nchar(notes) > 0 && !is.na(notes) && notes != "NA NA" && notes != "NA") {
      reasons <- c(reasons, paste0("Note: ", notes))
    }

    if (!is.null(image_audit) && nrow(image_audit) > 0) {
      match <- image_audit[image_audit$ct_id == dep$ct_id[i] & image_audit$site_id == dep$site_id[i], ]
      if (nrow(match) > 0) {
        status <- match$status[1]
        if (status %in% c("Folder missing", "Empty, needs review", "Empty (marked, no reason file)")) {
          reasons <- c(reasons, paste0("Image audit: ", status))
        } else if (status == "Empty (documented)") {
          reason_text <- read_empty_reason_file(match$path[1])
          if (!is.na(reason_text) && nchar(reason_text) > 0) {
            reasons <- c(reasons, paste0("Documented empty: ", reason_text))
          } else {
            reasons <- c(reasons, "Documented empty (no reason text found in folder)")
          }
        }
      }
    }

    flag_reason[i] <- paste(reasons, collapse = "; ")
  }

  dep$flag_reason <- flag_reason
  dep[nchar(dep$flag_reason) > 0, c("block_season", "cell_id", "site_id", "ct_id", "flag_reason")]
}

# =============================================================================
# MAIN UI
# =============================================================================

ui <- tagList(
page_navbar(
  title = actionLink("brand_home_link", "CT Data Manager",
    style = "color: white; text-decoration: none; font-weight: 600;"),
  id      = "main_nav",
  theme   = app_theme,
  bg      = "#1F2E24",
  inverse = TRUE,
  collapsible = TRUE,

  header = tags$head(
    tags$link(rel = "stylesheet",
      href = "https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css"),
    useShinyjs(),
    tags$style(HTML("
      body { background: #EDEEE7; padding-bottom: 48px; }
      .card { border: 1px solid #D7D9CD; border-radius: 4px; background: #fff; box-shadow: none; }
      .nav-pills .nav-link.active { background: #1F2E24; }
      .nav-pills .nav-link { color: #4B6355; }
      .section-header h5 { font-size: 0.95rem; margin-bottom: 2px; }
      .ledger-rule { border-bottom: 2px solid #1F2E24; }
      .ledger-table td, .ledger-table th { border-bottom: 1px solid #E4E5DC; padding: 6px 8px; }
      .btn-primary { background: #1F2E24; border-color: #1F2E24; border-radius: 3px; }
      .btn-primary:hover { background: #16211A; border-color: #16211A; }
      .btn-outline-secondary { border-radius: 3px; }
      .btn-outline-primary { border-radius: 3px; }
      .alert-warning { background: #FBF3E3; border-color: #B8862E; color: #6B4E1C; border-radius: 3px; }
      .alert-info    { background: #E9EEE9; border-color: #4B6355; color: #253A2C; border-radius: 3px; }
      .navbar-brand  { font-weight: 600; letter-spacing: -0.01em; }
      .step-num {
        width: 30px; height: 30px; border-radius: 50%;
        background: #1F2E24; color: white; font-weight: 600; font-size: 0.85rem;
        display: flex; align-items: center; justify-content: center;
      }
      code, .font-mono { font-family: 'IBM Plex Mono', monospace; }
      /* 'Overview' is reached by clicking the 'CT Data Manager' title
         instead of a separate tab; the tab itself stays in the
         underlying tabset (so the title-click can still switch to it),
         just hidden from the visible nav bar. */
      .navbar-nav a[data-value='page_intro'] { display: none !important; }
    ")),
    tags$script(HTML("
      // Number inputs change value on mouse-wheel scroll by default in most
      // browsers; surprising and easy to trigger by accident while
      // scrolling the page. Blur the field immediately on wheel so scrolling
      // over it just scrolls the page instead of silently changing the
      // value; the user must click/type to change it explicitly.
      $(document).on('wheel', 'input[type=number]', function() { $(this).blur(); });
    ")),
    # Leaflet has no native "download as image" the way plotly charts do
    # (every plotly chart already gets one for free, via the camera icon
    # in its hover toolbar). leaflet-image (not the more generic
    # html2canvas, which was tried first and had a real, confirmed
    # alignment bug: it doesn't correctly account for the CSS transform
    # Leaflet uses to position its tile layer, so the captured tiles and
    # the captured markers ended up visibly offset from each other) is
    # purpose-built for exactly this \u2014 it reconstructs the map's current
    # view directly via Canvas+CORS rather than screenshotting the DOM,
    # which is also why every downloadable map now sets
    # preferCanvas = TRUE (leaflet-image can only rasterize Canvas-drawn
    # markers/polygons, not Leaflet's default SVG ones). It does NOT
    # capture HTML-based map elements (zoom controls, the legend) at all
    # \u2014 only genuine map content (tiles, Canvas-drawn markers/polygons)
    # \u2014 so the dynamic title is drawn directly onto the resulting canvas
    # below to keep that context in the downloaded image; the legend
    # itself isn't currently reproduced this way.
    tags$script(src = "https://cdn.jsdelivr.net/npm/leaflet-image@0.4.0/leaflet-image.js"),
    tags$script(HTML("
      window.downloadMapAsPng = function(mapElementId, titleElementId, filename) {
        var mapWidget = HTMLWidgets.find('#' + mapElementId);
        if (!mapWidget) { alert('Could not find the map to export.'); return; }
        var map = mapWidget.getMap();
        leafletImage(map, function(err, canvas) {
          if (err || !canvas) {
            alert('Could not capture the map as an image' + (err ? (': ' + err.message) : '') +
                  '. Your browser\\'s own screenshot tool is the reliable fallback.');
            return;
          }
          var titleEl = document.getElementById(titleElementId);
          var titleText = titleEl ? titleEl.textContent : '';
          var ctx = canvas.getContext('2d');
          if (titleText) {
            var barHeight = 32;
            var padded = document.createElement('canvas');
            padded.width = canvas.width;
            padded.height = canvas.height + barHeight;
            var pctx = padded.getContext('2d');
            pctx.fillStyle = '#FFFFFF';
            pctx.fillRect(0, 0, padded.width, padded.height);
            pctx.drawImage(canvas, 0, barHeight);
            pctx.fillStyle = '#1F2E24';
            pctx.font = 'bold 16px sans-serif';
            pctx.textBaseline = 'middle';
            pctx.fillText(titleText, 10, barHeight / 2);
            canvas = padded;
          }
          var link = document.createElement('a');
          link.download = filename;
          link.href = canvas.toDataURL('image/png');
          link.click();
        });
      };
      // Every plotly chart already has a PNG download built into its own
      // hover-toolbar (the camera icon) \u2014 this calls that same built-in
      // Plotly.downloadImage() API directly instead, so an explicit button
      // can trigger it, consistent with the map's button above rather
      // than needing to find and hover over a toolbar icon for two of the
      // three figures but not the third.
      window.downloadPlotlyAsPng = function(elementId, filename) {
        // The output div IS the plotly graph div itself (plotly.js adds
        // the \"js-plotly-plot\" class directly to it, not to a nested
        // child) \u2014 searching it for a CHILD with that class (the actual
        // previous bug) always came back empty, so the function returned
        // early and Plotly.downloadImage() was never even called.
        var el = document.getElementById(elementId);
        if (!el) { return; }
        // Plotly.downloadImage()'s filename option is documented to be
        // WITHOUT an extension \u2014 it appends one itself based on the
        // format option below, so passing a name that already ends in
        // .png (as every call site originally did) produced .png.png.
        // Stripped here defensively so call sites don't all need to
        // remember this.
        var baseFilename = filename.replace(/\\.png$/i, '');
        Plotly.downloadImage(el, {format: 'png', filename: baseFilename}).catch(function(err) {
          alert('Could not download this chart as an image (' + err.message + ').');
        });
      };
      // fileInput()'s \"Browse...\" jumps the page to the top on click.
      // Targets the underlying <input type=file> element's own events
      // directly, not a guessed wrapper class name (the previous attempt
      // assumed Bootstrap-3-era \".btn-file\", which this app's Bootstrap 5
      // setup likely doesn't actually use, so that handler probably never
      // fired at all) \u2014 a <label> associated with a file input natively
      // triggers click/focus on the input itself no matter which visible
      // element (button, label, span) was actually clicked, so this
      // should catch it regardless of the exact DOM/class structure.
      // Scroll position captured on mousedown (before the jump can
      // happen) and re-asserted repeatedly afterward, since the exact
      // timing of the jump relative to click/focus isn't known for
      // certain either.
      (function() {
        var savedScroll = null;
        var restoreTimers = [];
        function saveScroll() { savedScroll = window.scrollY; }
        function restoreScroll() {
          if (savedScroll === null) return;
          restoreTimers.forEach(clearTimeout);
          restoreTimers = [0, 10, 50, 100, 250, 500].map(function(delay) {
            return setTimeout(function() { window.scrollTo(0, savedScroll); }, delay);
          });
        }
        $(document).on('mousedown focusin', 'input[type=file]', saveScroll);
        $(document).on('click focusin change', 'input[type=file]', restoreScroll);
      })();
    "))
  ),

  # Fixed/sticky so "Save session" is reachable from any tab without
  # scrolling to the bottom of a long page \u2014 unlike the fuller Session
  # card on Overview (which also has Load session / New project, less
  # urgent to reach from every screen), this is specifically for "save
  # as you go" from wherever you currently are. Reuses dl_session's
  # existing download handler rather than a second one \u2014 Shiny allows
  # more than one UI element to bind to the same output id.
  footer = tags$div(
    style = "position: fixed; bottom: 0; left: 0; right: 0; z-index: 1030;
             background: rgba(201, 163, 99, 0.88); padding: 6px 16px; display: flex;
             justify-content: flex-end; align-items: center; gap: 12px;
             box-shadow: 0 -1px 4px rgba(0,0,0,0.12);",
    tags$span(class = "small", style = "color: #3A2E10;",
      "Progress is lost on refresh \u2014 save as you go"),
    downloadButton("dl_session_footer", "Save session", class = "btn btn-light btn-sm")
  ),

  page_intro,
  page_ingest,
  page_process,
  page_visualize,
  page_analytics,

  nav_spacer(),
  nav_item(
    tags$span(
      class = "navbar-text text-light opacity-50 small",
      textOutput("session_project_label", inline = TRUE)
    )
  ),
  nav_item(
    tags$span(
      class = "navbar-text text-light opacity-25 small",
      style = "font-family: 'IBM Plex Mono', monospace;",
      BUILD_LABEL
    )
  )
),
audit_log_ui
)

# =============================================================================
# SERVER (STUBS ONLY)
# All reactive logic to be implemented page by page.
# TODOs indicate where each backend function goes.
# =============================================================================

server <- function(input, output, session) {

  # Clicking "CT Data Manager" in the navbar returns to the Overview page.
  # Uses updateNavbarPage (the supported mechanism for programmatically
  # switching a page_navbar tab) rather than setting the underlying input
  # directly — Bootstrap's tab framework drives the actual visual switch,
  # so just poking the Shiny input value alone doesn't work.
  observeEvent(input$brand_home_link, {
    updateNavbarPage(session, "main_nav", selected = "page_intro")
  })


  rv <- reactiveValues(
    survey_name      = NULL,
    deployment_data  = NULL,
    deployment_missing_required    = character(0),
    deployment_missing_recommended = character(0),
    deployment_last_datapath = NULL,
    deployment_last_filename = NULL,
    deployment_date_warnings = character(0),
    deployment_coord_warnings = character(0),
    browse_current_path = NULL,
    browse_target_input = NULL,
    folder_structure = NULL,
    folder_creation_summary = NULL,
    image_audit      = NULL,
    image_audit_base_dir = NULL,
    unexpected_folders    = character(0),
    backup_summary   = NULL,
    backup_verify    = NULL,
    syno_test_result = NULL,
    rename_preview   = NULL,
    rename_result    = NULL,
    camera_decisions = NULL,
    exif_data             = NULL,
    timestamp_check       = NULL,
    paired_station_check  = NULL,
    station_count_check   = NULL,
    traptagger_data  = NULL,
    gap_periods      = NULL,
    arguswild_data   = NULL,
    gis_layers       = NULL,
    camera_operation_periods = NULL,
    argus_manual_edits = NULL,
    audit_log        = character(0)
  )

  log_action <- function(msg) {
    entry <- paste0("[", format(Sys.time(), "%H:%M:%S"), "] ", msg)
    rv$audit_log <- c(rv$audit_log, entry)
  }

  # Shared by every "Re-upload X (only needed if not already loaded)"
  # field (deployment sheet x2, TrapTagger, ArgusWild, search effort):
  # hides the file input once its data is actually present \u2014 shown
  # instead, a small link to reveal the upload again for someone who
  # genuinely wants to replace the file \u2014 rather than leaving a
  # redundant "re-upload" prompt sitting right under a status message
  # that already says it's loaded. This got a lot more visible once
  # session save/restore made landing on a tab with data already present
  # the common case, not the exception.
  sync_optional_upload_visibility <- function(file_input_id, is_loaded_reactive) {
    # Targets a WRAPPER div's id (see optional_upload_input() below), not
    # file_input_id itself \u2014 fileInput()'s own id lands on the inner
    # <input type=file>, which is already CSS-hidden and replaced
    # visually by a styled label/wrapper, so hiding that element directly
    # would have had no visible effect on the actual widget at all.
    wrapper_id <- paste0(file_input_id, "_wrapper")
    replace_id <- paste0(file_input_id, "_replace")
    show_upload <- reactiveVal(FALSE)
    observeEvent(input[[replace_id]], { show_upload(TRUE) }, ignoreInit = TRUE)
    observe({
      if (isTRUE(is_loaded_reactive()) && !show_upload()) {
        shinyjs::hide(wrapper_id)
        shinyjs::show(replace_id)
      } else {
        shinyjs::show(wrapper_id)
        shinyjs::hide(replace_id)
      }
    })
  }


  # ---------- PAGE 1: Session / project management ---------------------------

  output$current_project_name <- renderText({
    if (is.null(input$survey_name) || nchar(input$survey_name) == 0) {
      "No project loaded yet"
    } else {
      input$survey_name
    }
  })

  output$session_project_label <- renderText({
    if (is.null(input$survey_name) || nchar(input$survey_name) == 0) "" else paste0("Survey: ", input$survey_name)
  })

  # Fields holding only live, in-session UI state (which folder the custom
  # browser dialog currently has open) rather than meaningful project data
  # \u2014 not worth persisting, and browse_target_input in particular holds a
  # Shiny input ID that has no meaning in a future session anyway.
  SESSION_TRANSIENT_FIELDS <- c("browse_current_path", "browse_target_input")

  # survey_name/deployment_phase (and their Processing/Visualize-page
  # counterparts) are plain text inputs, not rv$ fields at all \u2014 see
  # get_survey_name()/get_deployment_phase() \u2014 so they need to be saved
  # and restored separately from the rv$ snapshot below.
  SESSION_INPUT_IDS <- c("survey_name", "process_survey_name", "viz_survey_name",
                          "deployment_phase", "process_deployment_phase", "viz_deployment_phase",
                          "independence_threshold")

  # Shared by both download buttons below (Overview's Session card, and
  # the global fixed footer visible from every tab) \u2014 two SEPARATE
  # output ids/handlers rather than one downloadButton() reused twice in
  # the UI, since two <a> elements sharing one HTML id would be invalid
  # markup, even though the download itself would likely still work.
  save_session_filename <- function() {
    prefix <- tryCatch(build_export_prefix(), error = function(e) "camtrap_session")
    paste0(prefix, "_session_", format(Sys.time(), "%Y%m%d_%H%M"), ".rds")
  }
  save_session_content <- function(file) {
    rv_snapshot <- reactiveValuesToList(rv)
    rv_snapshot[SESSION_TRANSIENT_FIELDS] <- NULL
    input_snapshot <- setNames(lapply(SESSION_INPUT_IDS, function(id) input[[id]]), SESSION_INPUT_IDS)
    session_state <- list(
      app_build = BUILD_LABEL,
      saved_at  = Sys.time(),
      rv_fields = rv_snapshot,
      inputs    = input_snapshot
    )
    saveRDS(session_state, file)
    log_action("Session saved to file.")
  }
  output$dl_session        <- downloadHandler(filename = save_session_filename, content = save_session_content)
  output$dl_session_footer <- downloadHandler(filename = save_session_filename, content = save_session_content)

  # The file is read and held here as soon as it's uploaded, but NOT
  # applied to rv$ yet \u2014 applying it is deferred to a confirmation modal
  # (below) since doing so silently overwrites/discards whatever is
  # already in the current session, unsaved.
  pending_session <- reactiveVal(NULL)
  session_load_status_msg <- reactiveVal(NULL)
  output$session_load_status <- renderUI({ session_load_status_msg() })

  observeEvent(input$load_session_file, {
    req(input$load_session_file)
    result <- tryCatch(readRDS(input$load_session_file$datapath), error = function(e) e)
    if (inherits(result, "error") || !is.list(result) || is.null(result$rv_fields)) {
      session_load_status_msg(warn_panel("Could not read that file as a saved session \u2014 is it a .rds file this app saved?"))
      return(invisible())
    }
    pending_session(result)
    showModal(modalDialog(
      title = tagList(icon("exclamation-triangle-fill", class = "text-danger me-2"), "Load session"),
      tags$p("This replaces everything in the current session with the saved one."),
      if (!is.null(result$saved_at))
        tags$p(class = "text-muted small", "Saved: ", format(result$saved_at, "%Y-%m-%d %H:%M")),
      tags$p("Anything unsaved in the current session will be lost. Continue?"),
      footer = tagList(
        modalButton("Cancel"),
        actionButton("btn_confirm_load_session", "Load session", class = "btn btn-danger")
      )
    ))
  })

  observeEvent(input$btn_confirm_load_session, {
    removeModal()
    result <- pending_session()
    req(result)
    for (field_name in names(result$rv_fields)) {
      rv[[field_name]] <- result$rv_fields[[field_name]]
    }
    for (input_id in names(result$inputs)) {
      val <- result$inputs[[input_id]]
      if (!is.null(val)) {
        if (input_id == "independence_threshold") {
          updateNumericInput(session, input_id, value = val)
        } else {
          updateTextInput(session, input_id, value = val)
        }
      }
    }
    # Fill forward: survey_name/process_survey_name/viz_survey_name (and
    # the three deployment_phase equivalents) are fully independent text
    # inputs \u2014 confirmed via get_survey_name()/get_deployment_phase()'s
    # own fallback logic, which exists specifically because nothing
    # currently keeps these three in sync with each other. Without this,
    # a session where the user only ever filled in Survey Setup's field
    # restores with Processing's and Load Data's own copies still blank,
    # so they'd have to retype the same value on every page separately
    # even though it was always "the same survey."  If more than one
    # variant has a genuinely DIFFERENT saved value, the first non-empty
    # one found wins for filling in the blanks only \u2014 an already-filled
    # field is never overwritten, respecting whatever the user actually
    # set on that specific page.
    fill_forward_group <- function(ids) {
      current_vals <- setNames(lapply(ids, function(id) {
        v <- result$inputs[[id]]
        if (is.null(v)) "" else trimws(v)
      }), ids)
      non_empty <- current_vals[vapply(current_vals, nchar, integer(1)) > 0]
      if (length(non_empty) == 0) return(invisible())
      shared_val <- non_empty[[1]]
      for (id in ids) {
        if (nchar(current_vals[[id]]) == 0) {
          updateTextInput(session, id, value = shared_val)
        }
      }
    }
    fill_forward_group(c("survey_name", "process_survey_name", "viz_survey_name"))
    fill_forward_group(c("deployment_phase", "process_deployment_phase", "viz_deployment_phase"))

    log_action(paste0("Session restored from file (saved ",
                       if (!is.null(result$saved_at)) format(result$saved_at, "%Y-%m-%d %H:%M") else "unknown time", ")."))
    session_load_status_msg(success_bar("Session restored."))
    showNotification("Session restored.", type = "message")
  })

  observeEvent(input$btn_new_project, {
    showModal(modalDialog(
      title = tagList(icon("exclamation-triangle-fill", class = "text-danger me-2"), "Start new project"),
      tags$p("This clears everything in the current session \u2014 all uploaded data, QA/QC decisions, and
              results. This cannot be undone unless the current session was saved first."),
      tags$p("Continue?"),
      footer = tagList(
        modalButton("Cancel"),
        actionButton("btn_confirm_new_project", "Clear everything", class = "btn btn-danger")
      )
    ))
  })

  observeEvent(input$btn_confirm_new_project, {
    removeModal()
    rv_fields_to_clear <- setdiff(names(reactiveValuesToList(rv)), "audit_log")
    for (field_name in rv_fields_to_clear) {
      rv[[field_name]] <- NULL
    }
    rv$audit_log <- character(0)
    for (input_id in SESSION_INPUT_IDS) {
      if (input_id == "independence_threshold") {
        updateNumericInput(session, input_id, value = 30)
      } else {
        updateTextInput(session, input_id, value = "")
      }
    }
    log_action("Started new project; previous session cleared.")
    showNotification("Started a new project.", type = "message")
  })

  # ---------- PAGE 2.1: Survey setup -----------------------------------------

  # Shared processing logic, used both when a file is uploaded AND when the
  # date/time format dropdowns change afterward (so changing the format
  # reprocesses automatically without needing to re-upload the file).
  process_deployment_file <- function(datapath, filename, date_format, time_format) {
    tryCatch({
      result <- read_deployment_file(datapath, filename)

      if (!is.null(result$error)) {
        rv$deployment_data <- NULL
        showNotification(paste("Could not read file:", result$error), type = "error", duration = 10)
        log_action(paste("Deployment file upload FAILED:", result$error))
        return(invisible())
      }

      if (length(result$missing_required) > 0) {
        rv$deployment_data <- NULL
        showNotification(
          paste0("Missing required column(s): ", paste(result$missing_required, collapse = ", "),
                 ". Folder structure cannot be built until these are present."),
          type = "error", duration = 10
        )
        log_action(paste("Deployment file missing required columns:",
                          paste(result$missing_required, collapse = ", ")))
        rv$deployment_missing_required    <- result$missing_required
        rv$deployment_missing_recommended <- result$missing_recommended
        return(invisible())
      }

      raw_lat  <- if ("lat" %in% names(result$data))  result$data$lat  else NULL
      raw_long <- if ("long" %in% names(result$data)) result$data$long else NULL

      df <- add_derived_columns(result$data, date_format, time_format)
      rv$deployment_data <- df
      rv$deployment_missing_required    <- character(0)
      rv$deployment_missing_recommended <- result$missing_recommended
      rv$deployment_date_warnings <- check_date_plausibility(df)
      rv$deployment_coord_warnings <- check_coordinate_plausibility(df, raw_lat, raw_long)

      n_cameras <- length(unique(df$ct_id))
      n_sites   <- length(unique(df$site_id))
      log_action(paste0("Deployment file processed: ", nrow(df), " rows, ",
                         n_cameras, " cameras, ", n_sites, " sites",
                         if (length(rv$deployment_date_warnings) > 0) " (date plausibility warnings found)" else "",
                         if (length(rv$deployment_coord_warnings) > 0) " (coordinate plausibility warnings found)" else ""))
      showNotification(paste0("Loaded ", nrow(df), " deployment records."), type = "message")

    }, error = function(e) {
      rv$deployment_data <- NULL
      showNotification(
        paste0("Something went wrong processing this file: ", conditionMessage(e),
               ". Please check the file's format, or share it with the developer for debugging."),
        type = "error", duration = 15
      )
      log_action(paste("Deployment file processing FAILED:", conditionMessage(e)))
    })
  }

  observeEvent(input$deployment_csv, {
    req(input$deployment_csv)
    rv$deployment_last_datapath <- input$deployment_csv$datapath
    rv$deployment_last_filename <- input$deployment_csv$name
    process_deployment_file(input$deployment_csv$datapath, input$deployment_csv$name,
                             input$deployment_date_format, input$deployment_time_format)
  })

  # Re-process automatically when the format dropdowns change, IF a file has
  # already been uploaded this session — lets the user fix a misread date
  # without needing to re-upload.
  observeEvent(list(input$deployment_date_format, input$deployment_time_format), {
    req(rv$deployment_last_datapath)
    process_deployment_file(rv$deployment_last_datapath, rv$deployment_last_filename,
                             input$deployment_date_format, input$deployment_time_format)
  }, ignoreInit = TRUE)

  output$deployment_validation_ui <- renderUI({
    if (is.null(rv$deployment_data) && length(rv$deployment_missing_required) == 0) return(NULL)

    if (length(rv$deployment_missing_required) > 0) {
      return(warn_panel(paste0(
        "Missing required column(s): ", paste(rv$deployment_missing_required, collapse = ", "),
        ". Check your column headers match the expected names."
      )))
    }

    tagList(
      tags$div(class = "alert alert-success py-2 d-flex align-items-center",
        tags$i(class = "bi bi-check-circle-fill me-2"),
        tags$span(paste0(
          nrow(rv$deployment_data), " records loaded: ",
          length(unique(rv$deployment_data$ct_id)), " cameras across ",
          length(unique(rv$deployment_data$block_season)), " block/season groupings."
        ))
      ),
      if (length(rv$deployment_missing_recommended) > 0) {
        warn_panel(paste0(
          "Optional but recommended column(s) not found: ",
          paste(rv$deployment_missing_recommended, collapse = ", "),
          ". Some QA/QC checks later on will be skipped without these."
        ))
      },
      if (length(rv$deployment_date_warnings) > 0) {
        tagList(
          lapply(rv$deployment_date_warnings, function(w) warn_panel(w)),
          tags$p(class = "small text-muted mb-0",
            "Try a different \"Date format in file\" selection above; it will reprocess automatically.")
        )
      },
      if (length(rv$deployment_coord_warnings) > 0) {
        lapply(rv$deployment_coord_warnings, function(w) warn_panel(w))
      }
    )
  })

  output$deployment_preview_ui <- renderDT({
    req(rv$deployment_data)
    tryCatch({
      preview_cols <- intersect(
        c("season", "block", "cell_id", "ct_station", "ct_loc", "ct_id", "ct_type", "lat", "long",
          "setup_date", "setup_time", "retrieved_date", "retrieved_time"),
        names(rv$deployment_data)
      )
      datatable(
        head(rv$deployment_data[, preview_cols, drop = FALSE], 5),
        options = list(dom = "t", scrollX = TRUE, ordering = FALSE),
        rownames = FALSE
      )
    }, error = function(e) {
      datatable(data.frame(Error = paste("Could not build preview:", conditionMessage(e))),
                options = list(dom = "t"), rownames = FALSE)
    })
  })

  output$folder_tree_ui <- renderUI({
    req(rv$deployment_data)
    validate(need(nchar(trimws(input$survey_name)) > 0,
                   "Enter a survey name above to preview the folder structure."))
    validate(need(nchar(trimws(input$deployment_phase)) > 0,
                   "Enter a deployment phase above to preview the folder structure."))
    tryCatch({
      render_folder_tree(rv$deployment_data, trimws(input$survey_name), trimws(input$deployment_phase))
    }, error = function(e) {
      warn_panel(paste("Could not build folder tree preview:", conditionMessage(e)))
    })
  })

  observeEvent(input$btn_create_folders, {
    if (is.null(rv$deployment_data)) {
      showNotification("Upload a deployment sheet first (above).", type = "error")
      return(invisible())
    }

    survey_name <- trimws(input$survey_name)
    if (nchar(survey_name) == 0) {
      showNotification("Enter a survey name before creating folders.", type = "error")
      return(invisible())
    }
    if (grepl("[^A-Za-z0-9_-]", survey_name)) {
      showNotification("Survey name can only contain letters, numbers, underscores, and hyphens.",
                        type = "error")
      return(invisible())
    }
    deployment_phase <- trimws(input$deployment_phase)
    if (nchar(deployment_phase) == 0) {
      showNotification("Enter a deployment phase before creating folders (e.g. First_deployment).",
                        type = "error")
      return(invisible())
    }
    base_dir <- trimws(input$output_dir_path)
    if (nchar(base_dir) == 0) {
      showNotification("Choose an output location before creating folders.", type = "error")
      return(invisible())
    }
    if (!dir.exists(base_dir)) {
      showNotification("That output location doesn't seem to exist. Please re-select it.", type = "error")
      return(invisible())
    }

    tryCatch({
      rel_paths <- build_folder_paths(rv$deployment_data, survey_name, deployment_phase)
      full_paths <- file.path(base_dir, rel_paths)

      created <- vapply(full_paths, function(p) {
        tryCatch({ fs::dir_create(p, recurse = TRUE); TRUE },
                 error = function(e) FALSE)
      }, logical(1))

      rv$folder_structure <- list(
        base_path   = file.path(base_dir, survey_name),
        survey_name = survey_name,
        paths       = full_paths
      )

      n_ok   <- sum(created)
      n_fail <- sum(!created)
      log_action(paste0("Folder structure created: ", n_ok, " camera folders under ",
                         file.path(base_dir, survey_name),
                         if (n_fail > 0) paste0(" (", n_fail, " failed)") else ""))

      rv$folder_creation_summary <- list(n_ok = n_ok, n_fail = n_fail,
                                          base_path = file.path(base_dir, survey_name))

      if (n_fail == 0) {
        showNotification(paste0("Created ", n_ok, " camera folders."), type = "message")
      } else {
        showNotification(paste0(n_fail, " folder(s) could not be created; see result panel."),
                          type = "warning")
      }
    }, error = function(e) {
      showNotification(paste0("Folder creation failed: ", conditionMessage(e)), type = "error", duration = 15)
      log_action(paste("Folder creation FAILED:", conditionMessage(e)))
    })
  })

  output$folder_creation_result <- renderUI({
    req(rv$folder_creation_summary)
    s <- rv$folder_creation_summary
    tagList(
      tags$div(class = "alert alert-success py-2",
        tags$i(class = "bi bi-check-circle-fill me-2"),
        paste0("Created ", s$n_ok, " camera folders under:")),
      tags$code(s$base_path),
      if (s$n_fail > 0) warn_panel(paste0(s$n_fail, " folder(s) failed to create; check permissions on the chosen location."))
    )
  })

  # ---------- PAGE 2.2: Image audit ------------------------------------------

  # Custom folder browser (replaces the shinyFiles tree widget, whose tiny
  # expand arrows and unclickable file-contents pane made navigating deeply
  # nested folders tedious): full-row-clickable folder names, plus a
  # breadcrumb to jump back up several levels at once. Folders only —
  # nothing here can be clicked that shouldn't be. Generalized so any text
  # input can be a browse target: pass its id, current value, and a modal
  # title; "Select this folder" writes back to whichever input opened it.
  open_folder_browser <- function(target_input, current_value, title) {
    start <- trimws(current_value)
    if (nchar(start) == 0 || !dir.exists(start)) {
      start <- path.expand("~")
      if (!dir.exists(start)) start <- "/"
    }
    rv$browse_current_path <- start
    rv$browse_target_input <- target_input

    showModal(modalDialog(
      title = title, size = "l", easyClose = TRUE,
      uiOutput("browse_breadcrumb_ui"),
      tags$div(
        style = "max-height: 320px; overflow-y: auto; border: 1px solid #D7D9CD;
                  border-radius: 4px; padding: 4px;",
        uiOutput("browse_folder_list_ui")
      ),
      footer = tagList(
        modalButton("Cancel"),
        actionButton("btn_confirm_folder_browse", "Select this folder", class = "btn btn-primary")
      )
    ))
  }

  observeEvent(input$btn_open_folder_browser, {
    open_folder_browser("image_dir_path", input$image_dir_path, "Select survey folder")
  })

  observeEvent(input$btn_open_output_folder_browser, {
    open_folder_browser("output_dir_path", input$output_dir_path, "Select output location")
  })

  output$browse_breadcrumb_ui <- renderUI({
    req(rv$browse_current_path)
    path <- rv$browse_current_path
    is_windows <- .Platform$OS.type == "windows"
    parts <- strsplit(path, "[/\\\\]")[[1]]
    parts <- parts[nchar(parts) > 0]
    if (length(parts) == 0) return(tags$div(class = "mb-2 text-muted small", path))

    cumulative <- character(length(parts))
    for (i in seq_along(parts)) {
      cumulative[i] <- if (is_windows && i == 1) paste0(parts[i], "\\") else {
        if (i == 1 && !is_windows) paste0("/", parts[i]) else file.path(cumulative[i - 1], parts[i])
      }
    }

    root_crumb <- if (!is_windows) {
      # A clickable root ("/") makes sibling top-level folders reachable —
      # e.g. /Volumes (where macOS mounts network shares and external
      # drives) is a SIBLING of /Users, not a descendant, so without this
      # there'd be no way to navigate there once starting from Home.
      tagList(
        tags$a(href = "#", style = "text-decoration: underline; color: #1F2E24;",
          onclick = "Shiny.setInputValue('browse_nav_input', '/', {priority: 'event'}); return false;",
          "/"),
        " "
      )
    } else {
      NULL
      # Note: on Windows, reaching a DIFFERENT drive letter than the one
      # currently being browsed isn't supported by this browser — paste
      # the full path (e.g. "D:\...") into the text field directly instead.
    }

    tags$div(class = "mb-2 small",
      root_crumb,
      lapply(seq_along(parts), function(i) {
        tagList(
          tags$a(href = "#", style = "text-decoration: underline; color: #1F2E24;",
            onclick = sprintf(
              "Shiny.setInputValue('browse_nav_input', %s, {priority: 'event'}); return false;",
              jsonlite::toJSON(cumulative[i], auto_unbox = TRUE)),
            parts[i]),
          if (i < length(parts)) " / " else NULL
        )
      })
    )
  })

  output$browse_folder_list_ui <- renderUI({
    req(rv$browse_current_path)
    subdirs <- tryCatch({
      all <- list.dirs(rv$browse_current_path, recursive = FALSE, full.names = TRUE)
      all[!grepl("^\\.", basename(all))]  # hide hidden/system folders for a cleaner list
    }, error = function(e) character(0))

    if (length(subdirs) == 0) {
      return(tags$p(class = "text-muted small mb-0 p-2", "No sub-folders here."))
    }

    tagList(lapply(sort(subdirs), function(d) {
      tags$div(
        style = "padding: 7px 10px; cursor: pointer; border-radius: 3px;",
        onmouseover = "this.style.background='#EDEEE7'",
        onmouseout  = "this.style.background='transparent'",
        onclick = sprintf(
          "Shiny.setInputValue('browse_nav_input', %s, {priority: 'event'});",
          jsonlite::toJSON(d, auto_unbox = TRUE)),
        tags$i(class = "bi bi-folder-fill me-2", style = "color: #B8862E;"),
        basename(d)
      )
    }))
  })

  observeEvent(input$browse_nav_input, {
    if (dir.exists(input$browse_nav_input)) rv$browse_current_path <- input$browse_nav_input
  })

  observeEvent(input$btn_confirm_folder_browse, {
    req(rv$browse_current_path, rv$browse_target_input)
    updateTextInput(session, rv$browse_target_input, value = rv$browse_current_path)
    removeModal()
  })

  output$selected_image_dir <- renderText({
    path <- trimws(input$image_dir_path)
    if (nchar(path) == 0) "No folder chosen yet." else path
  })

  observeEvent(input$btn_audit_images, {
    if (is.null(rv$deployment_data)) {
      showNotification("Upload a deployment sheet first (Step 1: Survey setup).", type = "error")
      return(invisible())
    }

    base_dir <- trimws(input$image_dir_path)
    if (nchar(base_dir) == 0) {
      showNotification("Choose the survey folder before running the audit.", type = "error")
      return(invisible())
    }
    deployment_phase <- trimws(input$deployment_phase)
    if (nchar(deployment_phase) == 0) {
      showNotification("Enter a deployment phase (Step 1: Survey setup) before running the audit.",
                        type = "error")
      return(invisible())
    }

    tryCatch({
      if (!dir.exists(base_dir)) {
        showNotification("That folder doesn't seem to exist anymore. Please re-select it.",
                          type = "error")
        return(invisible())
      }

      audit_df <- run_image_audit(rv$deployment_data, base_dir, deployment_phase)
      cam_table <- get_camera_folder_table(rv$deployment_data, base_dir, deployment_phase)
      unexpected <- find_unexpected_camera_folders(cam_table)

      rv$image_audit          <- audit_df
      rv$image_audit_base_dir <- base_dir
      rv$unexpected_folders   <- unexpected

      n_missing <- sum(audit_df$status == "Folder missing")
      n_flagged <- sum(audit_df$status %in% c("Empty, needs review", "Empty (marked, no reason file)"))
      n_ok      <- sum(audit_df$status == "OK")

      log_action(paste0("Image audit run on ", base_dir, ": ", n_ok, " OK, ",
                         n_flagged, " flagged empty, ", n_missing, " missing, ",
                         length(unexpected), " unexpected folder(s)"))
      showNotification(paste0("Audit complete: ", n_ok, " OK, ", n_flagged,
                               " flagged, ", n_missing, " missing."), type = "message")

    }, error = function(e) {
      showNotification(paste0("Image audit failed: ", conditionMessage(e)), type = "error", duration = 15)
      log_action(paste("Image audit FAILED:", conditionMessage(e)))
    })
  })

  output$audit_table <- renderDT({
    req(rv$image_audit)
    dt <- datatable(
      rv$image_audit[, c("block_season", "cell_id", "site_id", "ct_id",
                          "n_images", "n_files_total", "status")],
      colnames = c("Block/Season", "Cell", "Site", "Camera",
                   "Images", "Total files", "Status"),
      options = list(pageLength = 15, scrollX = TRUE),
      rownames = FALSE
    )
    formatStyle(dt, "status",
      backgroundColor = styleEqual(
        c("OK", "OK (multi-visit)", "Empty (documented)", "Empty, needs review",
          "Empty (marked, no reason file)", "Folder missing"),
        c("#EAF2EA", "#EAF2EA", "#EAF2EA", "#FBF3E3", "#FBF3E3", "#F8E9E6")
      )
    )
  })

  output$audit_summary_ui <- renderUI({
    req(rv$image_audit)
    a <- rv$image_audit
    n_expected <- nrow(a)
    n_missing  <- sum(a$status == "Folder missing")
    n_flagged  <- sum(a$status %in% c("Empty, needs review", "Empty (marked, no reason file)"))
    total_images <- sum(a$n_images, na.rm = TRUE)

    tagList(
      tags$div(class = "small",
        tags$div(tags$strong(n_expected), " camera folders expected"),
        tags$div(tags$strong(total_images), " images found total"),
        if (n_missing > 0) tags$div(class = "text-danger", tags$strong(n_missing), " folder(s) missing"),
        if (n_flagged > 0) tags$div(class = "text-warning", tags$strong(n_flagged), " folder(s) need review"),
        if (n_missing == 0 && n_flagged == 0)
          tags$div(class = "text-success", tags$i(class = "bi bi-check-circle-fill"), " All folders look good")
      ),
      if (n_expected > 0 && n_missing == n_expected) {
        warn_panel(paste0(
          "Every expected folder is missing; this usually means the selected folder above is the ",
          "\"output location\" you chose during folder creation, not the survey's OWN folder one level ",
          "inside it (e.g. select \".../", basename(trimws(input$image_dir_path)), "/", trimws(input$survey_name),
          "\", not \".../", basename(trimws(input$image_dir_path)), "\" itself). Browse one level deeper and try again."
        ))
      }
    )
  })


  # Rows the user still needs to resolve (empty + not already documented).
  # Returns an empty (zero-row) data frame with the right columns when there's
  # no audit yet, rather than using req() — avoids fighting Shiny's special
  # "not ready yet" signal with a tryCatch elsewhere in this chain.
  flagged_rows <- reactive({
    if (is.null(rv$image_audit)) {
      return(data.frame(path = character(0), site_id = character(0),
                         ct_id = character(0), status = character(0),
                         stringsAsFactors = FALSE))
    }
    rv$image_audit[rv$image_audit$status %in%
                     c("Empty, needs review", "Empty (marked, no reason file)"), ]
  })

  output$has_flagged_empty_folders <- reactive({
    nrow(flagged_rows()) > 0
  })
  outputOptions(output, "has_flagged_empty_folders", suspendWhenHidden = FALSE)


  observe({
    fr <- flagged_rows()
    if (nrow(fr) == 0) {
      updateSelectInput(session, "empty_folder_select", choices = character(0))
    } else {
      choices <- setNames(fr$path, paste0(fr$site_id, " / ", fr$ct_id, "  (", fr$status, ")"))
      updateSelectInput(session, "empty_folder_select", choices = choices)
    }
  })


  output$empty_folder_ui <- renderUI({
    req(rv$image_audit)
    fr <- flagged_rows()
    if (nrow(fr) == 0) {
      return(tags$div(class = "alert alert-success py-2",
        tags$i(class = "bi bi-check-circle-fill me-2"),
        "No empty folders need attention."))
    }
    warn_panel(paste0(nrow(fr), " folder(s) have no images. Select one below to document why, ",
                       "or leave for now and re-run the audit later."))
  })

  observeEvent(input$btn_mark_empty, {
    if (is.null(input$empty_folder_select) || nchar(input$empty_folder_select) == 0) {
      showNotification("No folder selected to mark as empty.", type = "error")
      return(invisible())
    }

    tryCatch({
      old_path <- input$empty_folder_select
      reason   <- trimws(input$empty_reason_text)

      if (!dir.exists(old_path)) {
        showNotification("That folder no longer exists; try re-running the audit.", type = "error")
        return(invisible())
      }
      if (nchar(reason) == 0) {
        showNotification("Enter a reason before marking this folder as empty.", type = "error")
        return(invisible())
      }

      new_path <- if (grepl("empty$", basename(old_path), ignore.case = TRUE)) {
        old_path
      } else {
        file.path(dirname(old_path), paste0(basename(old_path), "empty"))
      }

      if (new_path != old_path) {
        # Use base R's file.rename (a single, fast, atomic OS-level rename)
        # rather than fs::file_move, which can fall back to a slow copy+delete
        # for directories on some systems.
        rename_ok <- file.rename(old_path, new_path)
        if (!isTRUE(rename_ok)) {
          stop("file.rename() returned FALSE; the folder may be open elsewhere, ",
               "read-only, or on a network/cloud-synced drive that's blocking the rename.")
        }
      }

      reason_con <- file(file.path(new_path, "EMPTY_REASON.txt"), open = "wt")
      on.exit(close(reason_con), add = TRUE)
      writeLines(reason, reason_con)

      rv$image_audit$path[rv$image_audit$path == old_path] <- new_path
      rv$image_audit$status[rv$image_audit$path == new_path] <- "Empty (documented)"

      log_action(paste0("Marked folder as empty: ", new_path, "; reason: ", reason))
      showNotification("Folder marked as empty and reason saved.", type = "message")
      updateTextInput(session, "empty_reason_text", value = "")

    }, error = function(e) {
      showNotification(paste0("Could not mark folder as empty: ", conditionMessage(e)),
                        type = "error", duration = 10)
      log_action(paste("Mark-empty FAILED:", conditionMessage(e)))
    })
  })

  output$camera_count_check_ui <- renderUI({
    req(rv$image_audit)
    n_expected  <- nrow(rv$image_audit)
    n_found     <- sum(rv$image_audit$status != "Folder missing")
    n_missing   <- n_expected - n_found
    n_unexpected <- length(rv$unexpected_folders)

    base <- rv$image_audit_base_dir
    to_relative <- function(p) {
      if (is.null(base) || nchar(base) == 0) return(p)
      sub("^[/\\\\]+", "", sub(base, "", p, fixed = TRUE))
    }

    tagList(
      tags$p(class = "small mb-1",
        tags$strong(n_expected), " cameras in deployment sheet · ",
        tags$strong(n_found), " matching folders found on disk"),
      if (n_missing > 0) {
        missing_paths <- to_relative(rv$image_audit$path[rv$image_audit$status == "Folder missing"])
        tagList(
          warn_panel(paste0(n_missing, " camera folder(s) from the deployment sheet were not found on disk. ",
                             "Expected structure:")),
          tags$ul(class = "small text-muted",
            lapply(missing_paths, function(p) tags$li(tags$code(p)))
          )
        )
      },
      if (n_unexpected > 0) {
        tagList(
          warn_panel(paste0(n_unexpected, " unexpected folder(s) found that don't match any camera in the deployment sheet:")),
          tags$ul(class = "small text-muted",
            lapply(rv$unexpected_folders, function(p) tags$li(tags$code(p)))
          )
        )
      },
      if (n_missing == 0 && n_unexpected == 0) {
        tags$div(class = "alert alert-success py-2",
          tags$i(class = "bi bi-check-circle-fill me-2"),
          "Folder count matches the deployment sheet exactly.")
      }
    )
  })

  # ---------- PAGE 2.3: Backup -----------------------------------------------

  observeEvent(input$btn_open_backup_source_browser, {
    open_folder_browser("backup_source_path", input$backup_source_path, "Select survey folder to back up")
  })

  observeEvent(input$btn_open_backup_source_local_browser, {
    open_folder_browser("backup_source_path_local", input$backup_source_path_local,
                         "Select survey folder to back up")
  })

  observeEvent(input$btn_open_backup_dest_browser, {
    open_folder_browser("backup_dest_path", input$backup_dest_path, "Select backup destination")
  })

  observeEvent(input$btn_open_argus_export_browser, {
    open_folder_browser("argus_export_dir_path", input$argus_export_dir_path, "Select ArgusWild export folder")
  })

  # ---- Server mode: test connection ----

  observeEvent(input$btn_test_connection, {
    server_url <- trimws(input$syno_server_url)
    username   <- trimws(input$syno_username)
    password   <- input$syno_password

    rv$syno_test_result <- NULL

    if (nchar(server_url) == 0 || nchar(username) == 0 || nchar(password) == 0) {
      rv$syno_test_result <- list(ok = FALSE, message = "Enter the server address, username, and password first.")
      return(invisible())
    }

    tryCatch({
      login <- syno_login(server_url, username, password)
      if (!login$ok) {
        rv$syno_test_result <- list(ok = FALSE, message = login$error)
        return(invisible())
      }
      on.exit(syno_logout(server_url, login$sid), add = TRUE)

      if (!syno_folder_exists(server_url, login$sid, SYNO_CAMERATRAPS_PATH)) {
        rv$syno_test_result <- list(ok = FALSE, message = paste0(
          "Logged in successfully, but could not find '", SYNO_CAMERATRAPS_PATH, "' on the server."))
        return(invisible())
      }

      rv$syno_test_result <- list(ok = TRUE, message = "Connected successfully; login works and the CameraTraps folder was found.")
      log_action("Server connection test succeeded")

    }, error = function(e) {
      rv$syno_test_result <- list(ok = FALSE, message = paste0("Connection test failed: ", conditionMessage(e)))
    })
  })

  output$syno_test_result_ui <- renderUI({
    req(rv$syno_test_result)
    r <- rv$syno_test_result
    if (isTRUE(r$ok)) {
      tags$div(class = "alert alert-success py-2", tags$i(class = "bi bi-check-circle-fill me-2"), r$message)
    } else {
      warn_panel(r$message)
    }
  })

  # ---- Server mode: run backup ----

  observeEvent(input$btn_run_backup_server, {
    server_url  <- trimws(input$syno_server_url)
    username    <- trimws(input$syno_username)
    password    <- input$syno_password
    source_dir  <- trimws(input$backup_source_path)

    if (nchar(server_url) == 0 || nchar(username) == 0 || nchar(password) == 0) {
      showNotification("Enter the server address, username, and password first.", type = "error")
      return(invisible())
    }
    if (nchar(source_dir) == 0) {
      showNotification("Enter or browse to the survey folder to back up first.", type = "error")
      return(invisible())
    }

    tryCatch({
      if (!dir.exists(source_dir)) {
        showNotification(paste0("Source folder not found: ", source_dir), type = "error", duration = 10)
        return(invisible())
      }

      survey_name <- basename(source_dir)
      backup_result <- run_server_backup(server_url, username, password, source_dir, survey_name)
      verify_result <- verify_server_backup(server_url, username, password, source_dir, backup_result$dest_path)

      rv$backup_summary <- list(
        source_dir = source_dir,
        dest_dir   = backup_result$dest_path,
        n_files    = backup_result$n_files,
        n_skipped  = backup_result$n_skipped,
        failed     = backup_result$failed
      )
      rv$backup_verify <- verify_result

      n_missing <- length(verify_result$missing_in_dest)
      n_uploaded <- backup_result$n_files - backup_result$n_skipped
      log_action(paste0("Server backup completed: ", n_uploaded, " file(s) uploaded",
                         if (backup_result$n_skipped > 0) paste0(", ", backup_result$n_skipped, " already on server (skipped)") else "",
                         ", from ", source_dir, " to ", backup_result$dest_path,
                         if (length(backup_result$failed) > 0) paste0(" (", length(backup_result$failed), " upload failures)") else "",
                         if (n_missing > 0) paste0("; verification found ", n_missing, " missing file(s)") else ""))

      if (length(backup_result$failed) == 0 && n_missing == 0) {
        showNotification(paste0("Backup complete: ", n_uploaded, " file(s) uploaded",
                                 if (backup_result$n_skipped > 0) paste0(" (", backup_result$n_skipped, " already on server, skipped)") else "",
                                 ", all verified."), type = "message")
      } else {
        showNotification("Backup finished with some issues; see verification panel.", type = "warning")
      }

    }, error = function(e) {
      showNotification(paste0("Backup failed: ", conditionMessage(e)), type = "error", duration = 15)
      log_action(paste("Server backup FAILED:", conditionMessage(e)))
    })
  })

  # ---- Local mode: run backup ----

  observeEvent(input$btn_run_backup_local, {
    source_dir  <- trimws(input$backup_source_path_local)
    dest_root   <- trimws(input$backup_dest_path)

    if (nchar(source_dir) == 0) {
      showNotification("Enter or browse to the survey folder to back up first.", type = "error")
      return(invisible())
    }
    if (nchar(dest_root) == 0) {
      showNotification("Enter or browse to a backup destination first.", type = "error")
      return(invisible())
    }

    tryCatch({
      if (!dir.exists(source_dir)) {
        showNotification(paste0("Source folder not found: ", source_dir), type = "error", duration = 10)
        return(invisible())
      }
      if (!dir.exists(dest_root)) {
        showNotification(paste0("Destination not found: ", dest_root,
                                 ". Double-check the path (and that any drive is still connected)."),
                          type = "error", duration = 10)
        return(invisible())
      }

      backup_result <- run_backup(source_dir, dest_root)
      verify_result <- verify_backup(source_dir, backup_result$dest_dir)

      rv$backup_summary <- list(
        source_dir = source_dir,
        dest_dir   = backup_result$dest_dir,
        n_files    = backup_result$n_files,
        failed     = backup_result$failed
      )
      rv$backup_verify <- verify_result

      n_missing <- length(verify_result$missing_in_dest)
      log_action(paste0("Local backup completed: ", backup_result$n_files, " files from ", source_dir,
                         " to ", backup_result$dest_dir,
                         if (length(backup_result$failed) > 0) paste0(" (", length(backup_result$failed), " copy failures)") else "",
                         if (n_missing > 0) paste0("; verification found ", n_missing, " missing file(s)") else ""))

      if (length(backup_result$failed) == 0 && n_missing == 0) {
        showNotification(paste0("Backup complete: ", backup_result$n_files, " files copied and verified."), type = "message")
      } else {
        showNotification("Backup finished with some issues; see verification panel.", type = "warning")
      }

    }, error = function(e) {
      showNotification(paste0("Backup failed: ", conditionMessage(e)), type = "error", duration = 15)
      log_action(paste("Local backup FAILED:", conditionMessage(e)))
    })
  })

  # ---- Shared: progress/result and verification display (both modes) ----

  backup_progress_content <- reactive({
    req(rv$backup_summary)
    s <- rv$backup_summary
    n_skipped <- if (!is.null(s$n_skipped)) s$n_skipped else 0
    n_uploaded <- s$n_files - n_skipped
    tagList(
      tags$div(class = "alert alert-success py-2",
        tags$i(class = "bi bi-check-circle-fill me-2"),
        paste0(n_uploaded, " file(s) copied",
               if (n_skipped > 0) paste0(" (", n_skipped, " already present, skipped)") else "",
               " to:")),
      tags$code(s$dest_dir),
      if (length(s$failed) > 0) {
        warn_panel(paste0(length(s$failed), " file(s) failed to copy; see list below."))
      }
    )
  })

  output$backup_progress_ui       <- renderUI({ backup_progress_content() })
  output$backup_progress_ui_local <- renderUI({ backup_progress_content() })

  output$backup_verify_table <- renderDT({
    req(rv$backup_verify)
    v <- rv$backup_verify
    has_folder_counts <- !is.null(v$n_source_folders)

    df <- if (has_folder_counts) {
      data.frame(
        Metric      = c("Files", "Folders"),
        Source      = c(v$n_source_files, v$n_source_folders),
        Destination = c(v$n_dest_files, v$n_dest_folders),
        stringsAsFactors = FALSE
      )
    } else {
      data.frame(
        Metric      = "Files",
        Source      = v$n_source_files,
        Destination = v$n_dest_files,
        stringsAsFactors = FALSE
      )
    }

    datatable(df, options = list(dom = "t", ordering = FALSE), rownames = FALSE)
  })

  output$backup_verify_warnings <- renderUI({
    req(rv$backup_verify)
    v <- rv$backup_verify
    n_missing <- length(v$missing_in_dest)
    n_extra   <- length(v$extra_in_dest)

    if (n_missing == 0 && n_extra == 0) {
      return(tags$div(class = "alert alert-success py-2",
        tags$i(class = "bi bi-check-circle-fill me-2"),
        "All files verified; source and backup match exactly."))
    }

    tagList(
      if (n_missing > 0) {
        tagList(
          warn_panel(paste0(n_missing, " file(s) present in the source but NOT found in the backup:")),
          tags$ul(class = "small text-muted", style = "max-height: 200px; overflow-y: auto;",
            lapply(head(v$missing_in_dest, 50), function(f) tags$li(tags$code(f)))
          ),
          if (n_missing > 50) tags$p(class = "small text-muted", paste0("...and ", n_missing - 50, " more."))
        )
      },
      if (n_extra > 0) {
        info_panel(paste0(n_extra, " file(s) exist in the backup but not in the source ",
                           "(likely left over from a previous backup of a survey with the same name)."))
      }
    )
  })

  # ---------- PAGE 2.4: Rename images ----------------------------------------

  observeEvent(input$btn_preview_rename, {
    if (is.null(rv$deployment_data)) {
      showNotification("Upload a deployment sheet first (Step 1: Survey setup).", type = "error")
      return(invisible())
    }
    if (is.null(rv$image_audit_base_dir)) {
      showNotification("Run Image Audit (step 2) first to select your survey folder.", type = "error")
      return(invisible())
    }

    tryCatch({
      survey_name <- trimws(input$survey_name)
      preview <- preview_image_rename(rv$deployment_data, rv$image_audit_base_dir, survey_name,
                                       trimws(input$deployment_phase))
      rv$rename_preview <- preview
      log_action(paste0("Rename preview generated (", nrow(preview), " row(s) shown)"))
    }, error = function(e) {
      showNotification(paste0("Could not build rename preview: ", conditionMessage(e)), type = "error", duration = 10)
      log_action(paste("Rename preview FAILED:", conditionMessage(e)))
    })
  })

  output$rename_preview_table <- renderDT({
    req(rv$rename_preview)
    datatable(rv$rename_preview,
      colnames = c("Block", "Station", "Site", "Camera", "Old name", "New name", "EXIF timestamp"),
      options = list(pageLength = 15, scrollX = TRUE), rownames = FALSE)
  })

  observeEvent(input$btn_run_rename, {
    if (is.null(rv$deployment_data)) {
      showNotification("Upload a deployment sheet first (Step 1: Survey setup).", type = "error")
      return(invisible())
    }
    if (is.null(rv$image_audit_base_dir)) {
      showNotification("Run Image Audit (step 2) first to select your survey folder.", type = "error")
      return(invisible())
    }
    # Pre-checks happen BEFORE the confirmation modal, not after \u2014 a click
    # that's doomed to fail anyway (no deployment sheet, no folder
    # selected) shouldn't make the user confirm something that was never
    # going to happen.
    showModal(modalDialog(
      title = tagList(icon("exclamation-triangle-fill", class = "text-danger me-2"), "Confirm rename"),
      tags$p("This renames every image file in the survey folder and is ", tags$strong("irreversible"), "."),
      tags$p("Make sure the backup (Step 3) completed successfully before continuing \u2014 if the rename
              produces unexpected results, the backup is the only way back to the original filenames."),
      footer = tagList(
        modalButton("Cancel"),
        actionButton("btn_confirm_rename", "Rename images", class = "btn btn-danger", icon = icon("arrow-repeat"))
      )
    ))
  })

  observeEvent(input$btn_confirm_rename, {
    removeModal()
    tryCatch({
      survey_name <- trimws(input$survey_name)
      result <- run_image_rename(rv$deployment_data, rv$image_audit_base_dir, survey_name,
                                  trimws(input$deployment_phase))
      rv$rename_result <- result

      n_ok      <- sum(result$status == "ok")
      n_err     <- sum(result$status == "error")
      n_skipped <- sum(result$status == "skipped")
      total_images <- sum(result$n_images)

      log_action(paste0("Image rename completed: ", n_ok, " camera(s) processed (",
                         total_images, " images), ", n_skipped, " skipped, ", n_err, " error(s)"))

      if (n_err == 0) {
        showNotification(paste0("Renamed ", total_images, " images across ", n_ok, " camera folder(s)."),
                          type = "message")
      } else {
        showNotification(paste0(n_err, " camera(s) had errors; see results table."), type = "warning")
      }
    }, error = function(e) {
      showNotification(paste0("Rename failed: ", conditionMessage(e)), type = "error", duration = 15)
      log_action(paste("Image rename FAILED:", conditionMessage(e)))
    })
  })

  output$rename_result_ui <- renderUI({
    req(rv$rename_result)
    r <- rv$rename_result
    n_err <- sum(r$status == "error")
    if (n_err == 0) {
      tags$div(class = "alert alert-success py-2",
        tags$i(class = "bi bi-check-circle-fill me-2"),
        paste0(sum(r$n_images), " images renamed across ", sum(r$status == "ok"), " camera folder(s)."))
    } else {
      warn_panel(paste0(n_err, " camera(s) had errors during rename; see table below."))
    }
  })

  output$rename_result_table <- renderDT({
    req(rv$rename_result)
    dt <- datatable(rv$rename_result,
      colnames = c("Block/Season", "Cell", "Site", "Camera", "Status", "Images", "Detail"),
      options = list(pageLength = 15, scrollX = TRUE), rownames = FALSE)
    formatStyle(dt, "status",
      backgroundColor = styleEqual(c("ok", "skipped", "error"), c("#EAF2EA", "#F0F0EC", "#F8E9E6")))
  })

  # ---------- PAGE 2.5: QA/QC ------------------------------------------------

  observeEvent(input$btn_extract_exif, {
    if (is.null(rv$deployment_data)) {
      showNotification("Upload a deployment sheet first (Step 1: Survey setup).", type = "error")
      return(invisible())
    }
    if (is.null(rv$image_audit_base_dir)) {
      showNotification("Run Image Audit (step 2) first to select your survey folder.", type = "error")
      return(invisible())
    }

    tryCatch({
      withProgress(message = "Extracting EXIF data...", value = 0.3, {
        exif <- run_exif_extraction(rv$deployment_data, rv$image_audit_base_dir, trimws(input$deployment_phase))
        incProgress(0.7)
      })
      rv$exif_data <- exif

      n_images <- nrow(exif)
      n_cameras <- length(unique(paste(exif$site_id, exif$ct_id)))
      n_no_timestamp <- sum(is.na(exif$datetime))

      log_action(paste0("EXIF extracted: ", n_images, " image(s) across ", n_cameras, " camera(s)",
                         if (n_no_timestamp > 0) paste0(" (", n_no_timestamp, " with no readable timestamp)") else ""))
      showNotification(paste0("Extracted timestamps from ", n_images, " images across ", n_cameras, " cameras."),
                        type = "message")
    }, error = function(e) {
      showNotification(paste0("EXIF extraction failed: ", conditionMessage(e)), type = "error", duration = 15)
      log_action(paste("EXIF extraction FAILED:", conditionMessage(e)))
    })
  })

  output$exif_summary_ui <- renderUI({
    req(rv$exif_data)
    if (nrow(rv$exif_data) == 0) {
      return(warn_panel("No images with readable EXIF data were found."))
    }
    n_no_timestamp <- sum(is.na(rv$exif_data$datetime))
    tagList(
      tags$div(class = "alert alert-success py-2",
        tags$i(class = "bi bi-check-circle-fill me-2"),
        paste0(nrow(rv$exif_data), " image(s) processed, ",
               length(unique(paste(rv$exif_data$site_id, rv$exif_data$ct_id))), " camera(s).")),
      if (n_no_timestamp > 0) {
        warn_panel(paste0(n_no_timestamp, " image(s) had no readable timestamp (corrupted or non-standard EXIF)."))
      }
    )
  })

  observeEvent(input$btn_check_timestamps, {
    if (is.null(rv$exif_data)) {
      showNotification("Extract EXIF data first (above).", type = "error")
      return(invisible())
    }

    tryCatch({
      exif_summary <- summarize_exif_by_camera(rv$exif_data)
      rv$timestamp_check <- check_timestamps(rv$deployment_data, exif_summary,
                                              input$timestamp_tolerance_days, rv$image_audit)
      rv$paired_station_check <- check_paired_stations(rv$deployment_data, exif_summary, input$timestamp_tolerance_days)
      rv$station_count_check <- check_station_camera_count(rv$deployment_data)

      n_flagged <- sum(rv$timestamp_check$flag %in% c("Timestamp mismatch", "No EXIF data"))
      n_pairs_flagged <- nrow(rv$paired_station_check)
      log_action(paste0("Timestamp check: ", nrow(rv$timestamp_check), " row(s) total, ",
                         n_flagged, " camera(s) flagged, ",
                         n_pairs_flagged, " paired-station mismatch(es)"))
      showNotification(paste0(n_flagged, " camera(s) flagged for timestamp discrepancies."),
                        type = if (n_flagged > 0) "warning" else "message")
    }, error = function(e) {
      showNotification(paste0("Timestamp check failed: ", conditionMessage(e)), type = "error", duration = 10)
      log_action(paste("Timestamp check FAILED:", conditionMessage(e)))
    })
  })

  output$timestamp_gantt_plot <- renderPlotly({
    req(rv$exif_data)
    exif_summary <- summarize_exif_by_camera(rv$exif_data)
    validate(need(nrow(exif_summary) > 0, "No EXIF timestamps to plot yet."))

    exif_summary$label <- paste0(exif_summary$site_id, " / ", exif_summary$ct_id)

    # Color bars by tolerance status if a check has been run; otherwise a
    # single neutral color (matches the pre-check appearance).
    if (!is.null(rv$timestamp_check)) {
      flag_lookup <- unique(rv$timestamp_check[c("site_id", "ct_id", "flag")])
      exif_summary <- merge(exif_summary, flag_lookup, by = c("site_id", "ct_id"), all.x = TRUE)
      exif_summary$flag[is.na(exif_summary$flag)] <- "OK"
    } else {
      exif_summary$flag <- "Not checked yet"
    }

    exif_summary <- exif_summary[order(exif_summary$label), ]
    exif_summary$label <- factor(exif_summary$label, levels = rev(unique(exif_summary$label)))

    # Custom hover text — camera + exact date range — so a bar can always
    # be identified even when the y-axis is dense, WITHOUT repeating the
    # flag name (that detail lives in the flagged list below the chart).
    exif_summary$hover_text <- paste0(
      as.character(exif_summary$label), "<br>",
      format(exif_summary$exif_start, "%Y-%m-%d %H:%M"), " \u2192 ",
      format(exif_summary$exif_end, "%Y-%m-%d %H:%M")
    )

    color_map <- c(
      "OK"                      = "#3D6B4A",
      "Timestamp mismatch"      = "#8C3527",
      "No EXIF data"            = "#8C3527",
      "Marked empty (skipped)"  = "#ABABA1",
      "Not checked yet"         = "#B8862E"
    )

    # No auto-zoom: the full range is always shown so an outlier is never
    # hidden. Instead, a marker dot is drawn at each bar's start AND end —
    # a dot has a fixed pixel size regardless of the axis scale, so even a
    # bar compressed to sub-pixel width by a far-away outlier is still
    # visible as two adjacent colored dots.
    p <- plotly::plot_ly(data = exif_summary) %>%
      plotly::add_segments(x = ~exif_start, xend = ~exif_end, y = ~label, yend = ~label,
                            color = ~flag, colors = color_map,
                            line = list(width = 10), showlegend = TRUE, legendgroup = ~flag,
                            text = ~hover_text, hoverinfo = "text") %>%
      plotly::add_markers(x = ~exif_start, y = ~label, color = ~flag, colors = color_map,
                           marker = list(size = 9, line = list(color = "white", width = 1)),
                           showlegend = FALSE, legendgroup = ~flag,
                           text = ~hover_text, hoverinfo = "text") %>%
      plotly::add_markers(x = ~exif_end, y = ~label, color = ~flag, colors = color_map,
                           marker = list(size = 9, line = list(color = "white", width = 1)),
                           showlegend = FALSE, legendgroup = ~flag,
                           text = ~hover_text, hoverinfo = "text")

    # Reference lines marking the survey's overall expected start/end dates
    # (earliest setup, latest retrieval across the whole deployment sheet),
    # so it's visually obvious where the data is SUPPOSED to fall, and any
    # bar far outside those lines stands out immediately.
    shapes <- list()
    annotations <- list()
    if (!is.null(rv$deployment_data)) {
      survey_start <- suppressWarnings(min(rv$deployment_data$setup_datetime, na.rm = TRUE))
      survey_end   <- suppressWarnings(max(rv$deployment_data$retrieved_datetime, na.rm = TRUE))

      if (is.finite(survey_start)) {
        shapes[[length(shapes) + 1]] <- list(
          type = "line", x0 = survey_start, x1 = survey_start, y0 = 0, y1 = 1, yref = "paper",
          line = list(color = "#4B6355", dash = "dot", width = 1.5))
        annotations[[length(annotations) + 1]] <- list(
          x = survey_start, y = 1.04, yref = "paper", showarrow = FALSE,
          text = "Survey start", font = list(size = 10, color = "#4B6355"))
      }
      if (is.finite(survey_end)) {
        shapes[[length(shapes) + 1]] <- list(
          type = "line", x0 = survey_end, x1 = survey_end, y0 = 0, y1 = 1, yref = "paper",
          line = list(color = "#4B6355", dash = "dot", width = 1.5))
        annotations[[length(annotations) + 1]] <- list(
          x = survey_end, y = 1.04, yref = "paper", showarrow = FALSE,
          text = "Survey end", font = list(size = 10, color = "#4B6355"))
      }
    }

    p %>% plotly::layout(xaxis = list(title = ""), yaxis = list(title = ""),
                          margin = list(l = 100, t = 40), shapes = shapes, annotations = annotations,
                          legend = list(orientation = "h", y = -0.15))
  })

  output$timestamp_flags_ui <- renderUI({
    req(rv$timestamp_check)
    n_total <- nrow(rv$timestamp_check)
    flagged <- rv$timestamp_check[rv$timestamp_check$flag %in% c("Timestamp mismatch", "No EXIF data"), ]
    if (nrow(flagged) == 0) {
      return(tags$div(class = "alert alert-success py-2",
        tags$i(class = "bi bi-check-circle-fill me-2"),
        paste0("All ", n_total, " camera(s) within tolerance.")))
    }
    tagList(
      warn_panel(paste0(nrow(flagged), " of ", n_total, " camera(s) flagged:")),
      tags$ul(class = "small text-muted", style = "max-height: 260px; overflow-y: auto;",
        lapply(seq_len(nrow(flagged)), function(i) {
          r <- flagged[i, ]
          if (r$flag == "No EXIF data") {
            tags$li(tags$code(paste0(r$site_id, " / ", r$ct_id)), ": No EXIF data found")
          } else {
            tags$li(
              tags$code(paste0(r$site_id, " / ", r$ct_id)), ": Timestamp mismatch", tags$br(),
              tags$span(style = "padding-left: 1em;",
                "Deployment sheet: ", format(r$setup_datetime, "%Y-%m-%d %H:%M"), " \u2192 ",
                format(r$retrieved_datetime, "%Y-%m-%d %H:%M"),
                " (", format_duration(r$setup_datetime, r$retrieved_datetime), ")"),
              tags$br(),
              tags$span(style = "padding-left: 1em;",
                "Photos actually span: ", format(r$exif_start, "%Y-%m-%d %H:%M"), " \u2192 ",
                format(r$exif_end, "%Y-%m-%d %H:%M"),
                " (", format_duration(r$exif_start, r$exif_end), ")"),
              tags$br(),
              tags$span(style = "padding-left: 1em;",
                "Off by: ", round(r$start_diff_days, 1), " day(s) at start, ",
                round(r$end_diff_days, 1), " day(s) at end")
            )
          }
        })
      )
    )
  })

  # Shared by the initial render and the "Zoom to stations" reset button
  # below, so the two can never drift apart on what counts as a valid
  # coordinate to plot/fit bounds to.
  coord_map_valid_coords <- reactive({
    if (is.null(rv$deployment_data)) return(NULL)
    df <- tryCatch(unique(rv$deployment_data[c("site_id", "ct_id", "lat", "long")]),
                    error = function(e) NULL)
    if (is.null(df)) return(NULL)
    df <- df[!is.na(df$lat) & !is.na(df$long) & !(df$lat == 0 & df$long == 0), ]
    if (nrow(df) == 0) return(NULL)
    df
  })

  output$coord_map <- renderLeaflet({
    m <- leaflet() %>% addProviderTiles("Esri.WorldImagery")
    df <- coord_map_valid_coords()

    if (is.null(df)) {
      return(m %>% setView(lng = 24.7, lat = -21.9, zoom = 6))  # No data yet: generic default view
    }

    m %>%
      addCircleMarkers(
        data = df, lng = ~long, lat = ~lat,
        radius = 6, color = "#1F2E24", fillColor = "#1F2E24", fillOpacity = 0.85, stroke = TRUE, weight = 2,
        label = ~paste0(site_id, " / ", ct_id),
        labelOptions = labelOptions(noHide = FALSE)
      ) %>%
      fitBounds(min(df$long), min(df$lat), max(df$long), max(df$lat))
  })

  # Re-fits the same bounds as the initial render, via a proxy so the
  # existing map updates in place rather than being torn down and
  # rebuilt \u2014 the fix for "zoomed out too far and can't find the site
  # again."
  observeEvent(input$btn_coord_map_reset, {
    df <- coord_map_valid_coords()
    if (is.null(df)) {
      showNotification("No valid coordinates to zoom to yet.", type = "message")
      return(invisible())
    }
    leafletProxy("coord_map") %>%
      fitBounds(min(df$long), min(df$lat), max(df$long), max(df$lat))
  })

  output$coord_flags_ui <- renderUI({
    req(rv$deployment_data)
    issues <- find_coordinate_issues(rv$deployment_data)

    if (nrow(issues$missing) == 0 && nrow(issues$outliers) == 0) {
      return(tags$div(class = "alert alert-success py-2",
        tags$i(class = "bi bi-check-circle-fill me-2"), "No obvious coordinate issues found."))
    }

    tagList(
      if (nrow(issues$missing) > 0) {
        tagList(
          warn_panel(paste0(nrow(issues$missing), " camera(s) with missing or (0,0) coordinates:")),
          tags$ul(class = "small text-muted",
            lapply(seq_len(nrow(issues$missing)), function(i) {
              tags$li(tags$code(paste0(issues$missing$site_id[i], " / ", issues$missing$ct_id[i])))
            })
          )
        )
      },
      if (nrow(issues$outliers) > 0) {
        tagList(
          warn_panel(paste0(nrow(issues$outliers), " camera(s) unusually far from the rest of the survey ",
                             "(check the map above):")),
          tags$ul(class = "small text-muted",
            lapply(seq_len(nrow(issues$outliers)), function(i) {
              r <- issues$outliers[i, ]
              tags$li(tags$code(paste0(r$site_id, " / ", r$ct_id)), ": ", r$lat, ", ", r$long)
            })
          )
        )
      }
    )
  })

  output$paired_station_ui <- renderUI({
    req(rv$paired_station_check)

    pair_panel <- if (nrow(rv$paired_station_check) == 0) {
      tags$div(class = "alert alert-success py-2",
        tags$i(class = "bi bi-check-circle-fill me-2"), "No paired-station timestamp mismatches found.")
    } else {
      tagList(
        warn_panel(paste0(nrow(rv$paired_station_check), " paired station(s) with mismatched active periods:")),
        tags$ul(class = "small text-muted",
          lapply(seq_len(nrow(rv$paired_station_check)), function(i) {
            r <- rv$paired_station_check[i, ]
            tags$li(
              tags$code(paste0(r$site_a, " (cam ", r$ct_id_a, ") vs ", r$site_b, " (cam ", r$ct_id_b, ")")),
              ": ", r$mismatch_days, " day(s) apart", tags$br(),
              tags$span(style = "padding-left: 1em;",
                r$site_a, ": ", format(r$start_a, "%Y-%m-%d %H:%M"), " \u2192 ", format(r$end_a, "%Y-%m-%d %H:%M"),
                " (", format_duration(r$start_a, r$end_a), ")"),
              tags$br(),
              tags$span(style = "padding-left: 1em;",
                r$site_b, ": ", format(r$start_b, "%Y-%m-%d %H:%M"), " \u2192 ", format(r$end_b, "%Y-%m-%d %H:%M"),
                " (", format_duration(r$start_b, r$end_b), ")")
            )
          })
        )
      )
    }

    count_panel <- NULL
    if (!is.null(rv$station_count_check) && nrow(rv$station_count_check) > 0) {
      count_panel <- tagList(
        tags$hr(),
        warn_panel(paste0(nrow(rv$station_count_check), " station(s) where N_Cam_Per_Station ",
                           "doesn't match the number of CT Locs actually recorded:")),
        tags$ul(class = "small text-muted",
          lapply(seq_len(nrow(rv$station_count_check)), function(i) {
            r <- rv$station_count_check[i, ]
            tags$li(tags$code(r$ct_station_id), ": claims ", r$claimed, ", but has ", r$actual,
                     " location(s) recorded: ", r$locations)
          })
        )
      )
    }

    tagList(pair_panel, count_panel)
  })

  output$ts_correction_scope_value_ui <- renderUI({
    req(rv$deployment_data)
    scope <- input$timestamp_correct_scope
    if (scope == "block") {
      choices <- sort(unique(rv$deployment_data$block_season))
    } else if (scope == "cell") {
      choices <- sort(unique(rv$deployment_data$cell_id))
    } else if (scope == "camera") {
      # CT_ID isn't guaranteed globally unique — the same physical camera
      # unit can be redeployed under a different site/season. Use a
      # composite "site_id|ct_id" as the actual value (so the correction
      # can target exactly one instance), with a disambiguating label only
      # when a CT_ID genuinely repeats — the common case (one row per
      # CT_ID) stays a plain, uncluttered label.
      cams <- unique(rv$deployment_data[c("site_id", "ct_id")])
      dupe_ct_id <- cams$ct_id[duplicated(cams$ct_id) | duplicated(cams$ct_id, fromLast = TRUE)]
      labels <- ifelse(cams$ct_id %in% dupe_ct_id,
                        paste0(cams$ct_id, " (", cams$site_id, ")"),
                        as.character(cams$ct_id))
      values <- paste(cams$site_id, cams$ct_id, sep = "|")
      choices <- setNames(values, labels)
      choices <- choices[order(labels)]
    } else {
      choices <- NULL
    }
    if (is.null(choices)) return(NULL)
    selectInput("ts_correction_scope_value", "Which one?", choices = choices, width = "100%")
  })

  observeEvent(input$btn_apply_ts_correction, {
    if (is.null(rv$exif_data)) {
      showNotification("Extract EXIF data first (above).", type = "error")
      return(invisible())
    }

    scope <- input$timestamp_correct_scope
    scope_value <- if (scope == "all") NA else input$ts_correction_scope_value
    if (scope != "all" && (is.null(scope_value) || is.na(scope_value))) {
      showNotification("Choose which block/cell/camera to apply the correction to.", type = "error")
      return(invisible())
    }

    years   <- if (is.null(input$ts_offset_years))   0 else input$ts_offset_years
    months  <- if (is.null(input$ts_offset_months))  0 else input$ts_offset_months
    days    <- if (is.null(input$ts_offset_days))    0 else input$ts_offset_days
    minutes <- if (is.null(input$ts_offset_minutes)) 0 else input$ts_offset_minutes

    if (years == 0 && months == 0 && days == 0 && minutes == 0) {
      showNotification("Enter a non-zero offset before applying a correction.", type = "error")
      return(invisible())
    }

    tryCatch({
      rv$exif_data <- apply_timestamp_correction(rv$exif_data, scope, scope_value, years, months, days, minutes)

      # Always refresh both checks immediately after a correction, so the
      # diagnostics reflect the new timestamps right away — regardless of
      # whether "Check timestamps" had been clicked before.
      exif_summary <- summarize_exif_by_camera(rv$exif_data)
      rv$timestamp_check <- check_timestamps(rv$deployment_data, exif_summary,
                                              input$timestamp_tolerance_days, rv$image_audit)
      rv$paired_station_check <- check_paired_stations(rv$deployment_data, exif_summary, input$timestamp_tolerance_days)

      scope_desc <- if (scope == "all") {
        "all cameras"
      } else if (scope == "camera") {
        paste0("camera = ", sub("\\|", " / ", scope_value))
      } else {
        paste0(scope, " = ", scope_value)
      }
      log_action(paste0("Timestamp correction applied to ", scope_desc, ": ",
                         years, "yr ", months, "mo ", days, "day ", minutes, "min"))
      showNotification(paste0("Correction applied to ", scope_desc, "."), type = "message")
    }, error = function(e) {
      showNotification(paste0("Correction failed: ", conditionMessage(e)), type = "error", duration = 10)
      log_action(paste("Timestamp correction FAILED:", conditionMessage(e)))
    })
  })

  output$ts_correction_log_ui <- renderUI({
    req(rv$exif_data)
    if (!("datetime_corrected" %in% names(rv$exif_data))) return(NULL)
    n_corrected <- sum(rv$exif_data$datetime != rv$exif_data$datetime_corrected, na.rm = TRUE)
    if (n_corrected == 0) return(NULL)
    tags$div(class = "alert alert-info py-2",
      tags$i(class = "bi bi-info-circle-fill me-2"),
      paste0(n_corrected, " image timestamp(s) currently corrected (original values preserved)."))
  })

  # ---- Cameras to exclude (use/do-not-use decision + note) -----------------
  # Recorded now so it's ready to become a column in the final exported
  # camera-trap datasheet once Page 4's real CSV export is built (still a
  # stub) — see README revisit list.

  output$camera_decision_choice_ui <- renderUI({
    req(rv$deployment_data)
    cams <- unique(rv$deployment_data[c("site_id", "ct_id")])
    choices <- setNames(paste(cams$site_id, cams$ct_id, sep = "|"),
                         paste0(cams$site_id, " / ", cams$ct_id))
    selectInput("camera_decision_choice", "Camera", choices = choices, width = "100%")
  })

  observeEvent(input$btn_save_camera_decision, {
    if (is.null(input$camera_decision_choice) || nchar(input$camera_decision_choice) == 0) {
      showNotification("Choose a camera first.", type = "error")
      return(invisible())
    }

    parts <- strsplit(input$camera_decision_choice, "\\|")[[1]]
    site_id <- parts[1]
    ct_id   <- parts[2]

    new_row <- data.frame(
      site_id = site_id, ct_id = ct_id,
      use_status = if (input$camera_decision_status == "use") "Use" else "Do not use",
      note = trimws(input$camera_decision_note),
      stringsAsFactors = FALSE
    )

    if (is.null(rv$camera_decisions) || nrow(rv$camera_decisions) == 0) {
      rv$camera_decisions <- new_row
    } else {
      # Replace any existing decision for this camera rather than duplicating.
      existing <- rv$camera_decisions$site_id == site_id & rv$camera_decisions$ct_id == ct_id
      rv$camera_decisions <- rbind(rv$camera_decisions[!existing, ], new_row)
    }

    log_action(paste0("Camera decision saved: ", site_id, " / ", ct_id, " \u2192 ", new_row$use_status,
                       if (nchar(new_row$note) > 0) paste0(" (", new_row$note, ")") else ""))
    showNotification(paste0("Saved: ", site_id, " / ", ct_id, ": ", new_row$use_status), type = "message")
    updateTextAreaInput(session, "camera_decision_note", value = "")
  })

  output$camera_decisions_table <- renderDT({
    req(rv$camera_decisions)
    validate(need(nrow(rv$camera_decisions) > 0, "No camera decisions recorded yet."))
    dt <- datatable(rv$camera_decisions,
      colnames = c("Site", "Camera", "Status", "Note"),
      options = list(pageLength = 10, scrollX = TRUE), rownames = FALSE)
    formatStyle(dt, "use_status",
      backgroundColor = styleEqual(c("Use", "Do not use"), c("#EAF2EA", "#F8E9E6")))
  })

  # Survey Setup's own survey_name/deployment_phase inputs can't simply be
  # duplicated with the same widget ID on another page (that would create
  # two DOM elements sharing one ID, breaking Shiny's reactivity) — so
  # Processing and Visualize & Export each have their OWN separate inputs
  # (process_survey_name/process_deployment_phase,
  # viz_survey_name/viz_deployment_phase) for people who arrive there
  # without having visited Survey Setup this session. These two helpers
  # are the single place that decides which value wins: the CURRENT
  # page's own entry if it's been filled in, then Processing's, then
  # falling back to Survey Setup's. Used anywhere either value is needed,
  # regardless of which page the person actually typed it into.
  get_survey_name <- function() {
    v <- trimws(input$viz_survey_name)
    if (nchar(v) > 0) return(v)
    p <- trimws(input$process_survey_name)
    if (nchar(p) > 0) return(p)
    trimws(input$survey_name)
  }
  get_deployment_phase <- function() {
    v <- trimws(input$viz_deployment_phase)
    if (nchar(v) > 0) return(v)
    p <- trimws(input$process_deployment_phase)
    if (nchar(p) > 0) return(p)
    trimws(input$deployment_phase)
  }

  # Shared filename prefix for downloads: "{survey}_{deployment_phase}", or
  # just "{survey}" if no phase is entered, or "camtrap" as a last resort.
  build_export_prefix <- function() {
    survey_name <- get_survey_name()
    deployment_phase <- get_deployment_phase()
    prefix <- if (nchar(survey_name) > 0) survey_name else "camtrap"
    if (nchar(deployment_phase) > 0) prefix <- paste0(prefix, "_", deployment_phase)
    prefix
  }

  output$btn_download_corrected_csv <- downloadHandler(
    filename = function() {
      paste0(build_export_prefix(), "_corrected_", format(Sys.Date(), "%Y%m%d"), ".csv")
    },
    content = function(file) {
      export_df <- build_corrected_export(rv$exif_data, rv$camera_decisions)
      write.csv(export_df, file, row.names = FALSE, na = "")
      log_action(paste0("Downloaded corrected CSV: ", nrow(export_df), " image row(s)"))
    }
  )

  output$camera_health_table <- renderDT({
    req(rv$deployment_data)
    flags <- build_camera_health_flags(rv$deployment_data, rv$image_audit)
    validate(need(nrow(flags) > 0, "No camera health issues flagged."))
    datatable(flags,
      colnames = c("Block/Season", "Cell", "Site", "Camera", "Flag reason"),
      options = list(pageLength = 15, scrollX = TRUE), rownames = FALSE)
  })

  # ---------- PAGE 3.1: Import TrapTagger ------------------------------------

  observeEvent(input$process_deployment_csv, {
    req(input$process_deployment_csv)
    # Re-uses the SAME processing logic as Survey Setup's own upload — no
    # date/time format selector here, since this is meant for re-loading a
    # file that's already been successfully processed once. If dates come
    # through wrong, go to Survey Setup where the explicit format picker
    # (and the fuller validation panel) live.
    process_deployment_file(input$process_deployment_csv$datapath, input$process_deployment_csv$name, "", "")
  })

  output$process_deployment_status_ui <- renderUI({
    if (is.null(rv$deployment_data)) return(NULL)
    d <- rv$deployment_data
    tags$div(class = "alert alert-success py-2",
      tags$i(class = "bi bi-check-circle-fill me-2"),
      paste0(nrow(d), " records loaded: ", length(unique(d$ct_id)), " camera(s) across ",
             length(unique(d$station_folder)), " station(s)."))
  })
  sync_optional_upload_visibility("process_deployment_csv", reactive(!is.null(rv$deployment_data)))

  observeEvent(input$traptagger_csv, {
    req(input$traptagger_csv)
    tryCatch({
      result <- read_traptagger_csv(input$traptagger_csv$datapath)
      if (!is.null(result$error)) {
        rv$traptagger_data <- NULL
        showNotification(paste("Could not read file:", result$error), type = "error", duration = 10)
        log_action(paste("TrapTagger import FAILED:", result$error))
        return(invisible())
      }
      rv$traptagger_data <- result$data
      n_stations <- length(unique(result$data$station_folder))
      log_action(paste0("TrapTagger data uploaded: ", nrow(result$data), " row(s), ",
                         n_stations, " station(s)"))
      showNotification(paste0("Loaded ", nrow(result$data), " records across ",
                               n_stations, " station(s)."), type = "message")
    }, error = function(e) {
      rv$traptagger_data <- NULL
      showNotification(paste0("Something went wrong: ", conditionMessage(e)), type = "error", duration = 15)
      log_action(paste("TrapTagger import FAILED:", conditionMessage(e)))
    })
  })

  output$traptagger_upload_summary_ui <- renderUI({
    req(rv$traptagger_data)
    d <- rv$traptagger_data
    n_kd <- sum(d$species == "Knocked Down", na.rm = TRUE)
    tags$div(class = "small text-muted mt-2",
      tags$div(tags$strong(nrow(d)), " records \u00b7 ",
               tags$strong(length(unique(d$station_folder))), " station(s) \u00b7 date range ",
               format(min(d$timestamp, na.rm = TRUE), "%Y-%m-%d"), " \u2192 ",
               format(max(d$timestamp, na.rm = TRUE), "%Y-%m-%d")),
      if (n_kd > 0) tags$div(tags$strong(n_kd), " image(s) tagged \"Knocked Down\"")
    )
  })

  output$classification_summary_ui <- renderUI({
    req(rv$traptagger_data)
    d <- rv$traptagger_data
    top_species <- sort(table(d$species[d$species %in% c("None", "Knocked Down") == FALSE]),
                         decreasing = TRUE)
    top_species <- head(top_species, 10)
    tagList(
      tags$p(class = "small mb-2",
        tags$strong(nrow(d)), " total records across ",
        tags$strong(length(unique(d$station_folder))), " station(s)"),
      if (length(top_species) > 0) {
        tags$ul(class = "small",
          lapply(seq_along(top_species), function(i) {
            tags$li(names(top_species)[i], ": ", top_species[i], " record(s)")
          })
        )
      }
    )
  })

  output$btn_download_summary_by_station <- downloadHandler(
    filename = function() {
      paste0(build_export_prefix(), "_classification_summary_by_station_species_",
             format(Sys.Date(), "%Y%m%d"), ".csv")
    },
    content = function(file) {
      d <- rv$traptagger_data
      # Full per-station x per-species breakdown (not just the top-10 shown
      # inline above) — a standard long-format table, ready to pivot for
      # further analysis. Includes "None" (blank) and "Knocked Down" rows
      # as-is, rather than arbitrarily excluding them from the download.
      summary_df <- as.data.frame(table(station_folder = d$station_folder, species = d$species),
                                   stringsAsFactors = FALSE)
      names(summary_df) <- c("station_folder", "species", "n_records")
      summary_df <- summary_df[summary_df$n_records > 0, ]
      summary_df <- summary_df[order(summary_df$station_folder, -summary_df$n_records), ]
      write.csv(summary_df, file, row.names = FALSE)
      log_action(paste0("Downloaded classification summary (by station \u00d7 species): ", nrow(summary_df), " row(s)"))
    }
  )

  output$btn_download_summary_by_species <- downloadHandler(
    filename = function() {
      paste0(build_export_prefix(), "_classification_summary_by_species_",
             format(Sys.Date(), "%Y%m%d"), ".csv")
    },
    content = function(file) {
      d <- rv$traptagger_data
      # Total records per species across the whole survey, collapsing the
      # per-station breakdown above into one row per species.
      summary_df <- as.data.frame(table(species = d$species), stringsAsFactors = FALSE)
      names(summary_df) <- c("species", "n_records")
      summary_df <- summary_df[summary_df$n_records > 0, ]
      summary_df <- summary_df[order(-summary_df$n_records), ]
      write.csv(summary_df, file, row.names = FALSE)
      log_action(paste0("Downloaded classification summary (by species): ", nrow(summary_df), " row(s)"))
    }
  )

  # ---- Camera downtime gaps: auto-detect + manual entry ----

  observeEvent(input$btn_detect_gaps, {
    if (is.null(rv$traptagger_data)) {
      showNotification("Upload a TrapTagger export first.", type = "error")
      return(invisible())
    }
    if (is.null(rv$deployment_data)) {
      showNotification("Upload a deployment sheet first (Survey setup).", type = "error")
      return(invisible())
    }
    tryCatch({
      detected <- detect_knockdown_gaps(rv$traptagger_data, rv$deployment_data)
      if (nrow(detected) == 0) {
        showNotification("No \"Knocked Down\" tags found in this TrapTagger export.", type = "message")
        return(invisible())
      }
      existing <- rv$gap_periods
      if (is.null(existing)) {
        existing <- detected[0, ]
      }
      # Replace any previous auto-detected gaps (re-running detection
      # shouldn't duplicate), keep manual ones untouched.
      existing <- existing[existing$source != "Auto (TrapTagger)" |
                            !(paste(existing$site_id, existing$ct_id) %in%
                              paste(detected$site_id, detected$ct_id)), ]
      rv$gap_periods <- rbind(existing, detected)
      log_action(paste0("Auto-detected ", nrow(detected), " gap period(s) from TrapTagger"))
      showNotification(paste0("Detected ", nrow(detected), " gap period(s) (",
                               length(unique(detected$gap_start)), " incident(s))."), type = "message")
    }, error = function(e) {
      showNotification(paste0("Gap detection failed: ", conditionMessage(e)), type = "error", duration = 10)
      log_action(paste("Gap detection FAILED:", conditionMessage(e)))
    })
  })

  output$gap_camera_choice_ui <- renderUI({
    req(rv$deployment_data)
    cams <- unique(rv$deployment_data[c("site_id", "ct_id")])
    choices <- setNames(paste(cams$site_id, cams$ct_id, sep = "|"),
                         paste0(cams$site_id, " / ", cams$ct_id))
    selectInput("gap_camera_choice", "Camera", choices = choices, width = "100%")
  })

  observeEvent(input$btn_add_gap, {
    if (is.null(rv$deployment_data)) {
      showNotification("Upload a deployment sheet first (Survey setup).", type = "error")
      return(invisible())
    }
    showModal(modalDialog(
      title = "Add gap period", size = "m", easyClose = TRUE,
      uiOutput("gap_camera_choice_ui"),
      fluidRow(
        column(6, dateInput("gap_start_date", "Gap start date")),
        column(6, textInput("gap_start_time", "Gap start time", value = "00:00:00",
                             placeholder = "HH:MM:SS"))
      ),
      fluidRow(
        column(6, dateInput("gap_end_date", "Gap end date")),
        column(6, textInput("gap_end_time", "Gap end time", value = "00:00:00",
                             placeholder = "HH:MM:SS"))
      ),
      textAreaInput("gap_reason", "Reason (optional)",
        placeholder = "e.g. Camera knocked down by elephant, found and reset on retrieval",
        width = "100%", rows = 2),
      footer = tagList(
        modalButton("Cancel"),
        actionButton("btn_confirm_add_gap", "Save gap period", class = "btn btn-primary")
      )
    ))
  })

  observeEvent(input$btn_confirm_add_gap, {
    tryCatch({
      if (is.null(input$gap_camera_choice) || nchar(input$gap_camera_choice) == 0) {
        showNotification("Choose a camera.", type = "error")
        return(invisible())
      }
      parts <- strsplit(input$gap_camera_choice, "\\|")[[1]]
      gap_start <- as.POSIXct(paste(input$gap_start_date, input$gap_start_time),
                               format = "%Y-%m-%d %H:%M:%S", tz = "UTC")
      gap_end   <- as.POSIXct(paste(input$gap_end_date, input$gap_end_time),
                               format = "%Y-%m-%d %H:%M:%S", tz = "UTC")
      if (is.na(gap_start) || is.na(gap_end)) {
        showNotification("Enter valid dates/times (time as HH:MM:SS).", type = "error")
        return(invisible())
      }
      if (gap_end <= gap_start) {
        showNotification("Gap end must be after gap start.", type = "error")
        return(invisible())
      }

      new_row <- data.frame(
        site_id = parts[1], ct_id = parts[2],
        gap_start = gap_start, gap_end = gap_end,
        reason = trimws(input$gap_reason), source = "Manual",
        stringsAsFactors = FALSE
      )
      existing <- rv$gap_periods
      if (is.null(existing)) {
        rv$gap_periods <- new_row
      } else {
        rv$gap_periods <- rbind(existing, new_row)
      }
      log_action(paste0("Manual gap period added: ", parts[1], " / ", parts[2],
                         " (", format(gap_start, "%Y-%m-%d"), " \u2192 ", format(gap_end, "%Y-%m-%d"), ")"))
      showNotification("Gap period saved.", type = "message")
      removeModal()
    }, error = function(e) {
      showNotification(paste0("Could not save gap period: ", conditionMessage(e)), type = "error", duration = 10)
      log_action(paste("Add gap period FAILED:", conditionMessage(e)))
    })
  })

  output$gap_periods_ui <- renderUI({
    gaps <- rv$gap_periods
    if (is.null(gaps) || nrow(gaps) == 0) {
      return(tags$p(class = "small text-muted mb-0", "No gap periods recorded yet."))
    }
    tags$ul(class = "small",
      lapply(seq_len(nrow(gaps)), function(i) {
        r <- gaps[i, ]
        tags$li(
          tags$code(paste0(r$site_id, " / ", r$ct_id)), ": ",
          format(r$gap_start, "%Y-%m-%d %H:%M"), " \u2192 ", format(r$gap_end, "%Y-%m-%d %H:%M"),
          tags$span(class = "text-muted", " (", r$source, ")"),
          if (nchar(r$reason) > 0) tags$div(class = "text-muted", r$reason)
        )
      })
    )
  })

  # Only known way to carry gap periods (built interactively here, via
  # detection or manual entry) to a fresh session elsewhere — e.g.
  # Visualize & Export's "Load Data" tab, which can re-upload this same
  # file back into rv$gap_periods (see build_gap_periods_export() below
  # for the exact column shape both sides agree on).
  output$btn_download_search_effort <- downloadHandler(
    filename = function() {
      paste0(build_export_prefix(), "_search_effort_", format(Sys.Date(), "%Y%m%d"), ".csv")
    },
    content = function(file) {
      export_df <- build_camera_operation_export(rv$deployment_data, rv$gap_periods, rv$camera_decisions)
      write.csv(export_df, file, row.names = FALSE, na = "")
      log_action(paste0("Downloaded search effort CSV: ", nrow(export_df), " operational period(s)"))
    }
  )

  # ---- Cross-check against deployment sheet ----

  observeEvent(input$btn_cross_check_traptagger, {
    if (is.null(rv$deployment_data)) {
      showNotification("Upload a deployment sheet first (Survey setup).", type = "error")
      return(invisible())
    }
    tryCatch({
      rv$traptagger_cross_check <- cross_check_traptagger(
        rv$traptagger_data, rv$deployment_data, input$traptagger_tolerance_days)
      n_flagged <- sum(rv$traptagger_cross_check$flag != "OK")
      log_action(paste0("TrapTagger cross-check: ", n_flagged, " station(s) flagged"))
      showNotification(paste0(n_flagged, " station(s) flagged."),
                        type = if (n_flagged > 0) "warning" else "message")
    }, error = function(e) {
      showNotification(paste0("Cross-check failed: ", conditionMessage(e)), type = "error", duration = 10)
      log_action(paste("TrapTagger cross-check FAILED:", conditionMessage(e)))
    })
  })

  output$traptagger_cross_check_table <- renderDT({
    req(rv$traptagger_cross_check)
    d <- rv$traptagger_cross_check
    display <- data.frame(
      block_season = d$block_season, cell_id = d$cell_id, station = d$station_folder,
      deployment_window = paste0(format(d$setup_datetime, "%Y-%m-%d"), " \u2192 ",
                                  format(d$retrieved_datetime, "%Y-%m-%d")),
      traptagger_window = ifelse(is.na(d$tt_start), "N/A",
                                  paste0(format(d$tt_start, "%Y-%m-%d"), " \u2192 ", format(d$tt_end, "%Y-%m-%d"))),
      n_records = d$n_records, status = d$flag, stringsAsFactors = FALSE
    )
    dt <- datatable(display,
      colnames = c("Block/Season", "Cell", "Station", "Deployment window",
                   "TrapTagger window", "Records", "Status"),
      options = list(pageLength = 15, scrollX = TRUE), rownames = FALSE)
    formatStyle(dt, "status",
      backgroundColor = styleEqual(
        c("OK", "Timestamp mismatch vs deployment sheet", "Not found in TrapTagger export"),
        c("#EAF2EA", "#FBF3E3", "#F8E9E6")))
  })

  # ---------- PAGE 3.2: Focal species export ---------------------------------

  observeEvent(input$btn_open_focal_species_folder_browser, {
    open_folder_browser("focal_species_image_dir_path", input$focal_species_image_dir_path,
                         "Select survey folder")
  })

  observeEvent(input$btn_match_focal_species, {
    if (!is.null(rv$exif_data)) {
      showNotification("EXIF data already loaded; preview below is already up to date.",
                        type = "message")
      return(invisible())
    }
    if (is.null(rv$deployment_data)) {
      showNotification("Upload a deployment sheet first (above, or Survey Setup).", type = "error")
      return(invisible())
    }
    base_dir <- trimws(input$focal_species_image_dir_path)
    if (nchar(base_dir) == 0) {
      showNotification("Enter or browse to your survey's image folder first.", type = "error")
      return(invisible())
    }
    if (!dir.exists(base_dir)) {
      showNotification("That folder doesn't seem to exist. Please re-select it.", type = "error")
      return(invisible())
    }
    deployment_phase <- get_deployment_phase()
    if (nchar(deployment_phase) == 0) {
      showNotification("Enter the deployment phase (above, or Survey Setup) before matching.",
                        type = "error")
      return(invisible())
    }

    tryCatch({
      withProgress(message = "Extracting EXIF data for matching...", value = 0.3, {
        exif <- run_exif_extraction(rv$deployment_data, base_dir, deployment_phase)
        incProgress(0.7)
      })
      rv$exif_data <- exif
      log_action(paste0("EXIF extracted for focal species matching: ", nrow(exif), " image(s)"))
      showNotification(paste0("Extracted EXIF for ", nrow(exif), " image(s). Preview updated below."),
                        type = "message")
    }, error = function(e) {
      showNotification(paste0("Extraction failed: ", conditionMessage(e)), type = "error", duration = 15)
      log_action(paste("Focal species EXIF extraction FAILED:", conditionMessage(e)))
    })
  })

  observe({
    if (is.null(rv$traptagger_data)) {
      updateSelectInput(session, "focal_species", choices = c("(upload TrapTagger data first)"))
      return(invisible())
    }
    species_choices <- sort(setdiff(unique(rv$traptagger_data$species), c("None", "Knocked Down")))
    updateSelectInput(session, "focal_species", choices = species_choices)
  })

  observe({
    if (is.null(rv$traptagger_data)) {
      updateSelectInput(session, "export_species_select", choices = c("(upload TrapTagger data first)"))
      return(invisible())
    }
    species_choices <- sort(setdiff(unique(rv$traptagger_data$species), c("None", "Knocked Down")))
    updateSelectInput(session, "export_species_select", choices = species_choices)
  })

  # Scoped to species that actually HAVE an individual ID, not every
  # TrapTagger species \u2014 selecting a species here with no individual IDs
  # at all would just produce an empty SECR export, so there's no reason
  # to offer it in the first place. The join needs TrapTagger data AND
  # EXIF data AND ArgusWild data together (TrapTagger's station+timestamp
  # record is matched to a local file via EXIF, which is then matched to
  # ArgusWild's filename) \u2014 checked individually and in that order, so
  # the placeholder names whichever ONE is actually missing rather than
  # always blaming ArgusWild regardless of the real cause.
  observe({
    if (is.null(rv$traptagger_data)) {
      updateSelectInput(session, "export_secr_species_select", choices = c("(upload TrapTagger data first)"))
      return(invisible())
    }
    if (is.null(rv$exif_data)) {
      updateSelectInput(session, "export_secr_species_select", choices = c("(extract EXIF data first)"))
      return(invisible())
    }
    if (is.null(rv$arguswild_data)) {
      updateSelectInput(session, "export_secr_species_select", choices = c("(upload ArgusWild data first)"))
      return(invisible())
    }
    enriched <- get_enriched_detections()
    if (is.null(enriched) || !any(!is.na(enriched$individual_id))) {
      updateSelectInput(session, "export_secr_species_select", choices = c("(no individual ID matches found \u2014 check filenames line up)"))
      return(invisible())
    }
    secr_species_choices <- sort(unique(enriched$species[!is.na(enriched$individual_id)]))
    updateSelectInput(session, "export_secr_species_select", choices = secr_species_choices)
  })

  # Shared by "Individual ID data" and "Individuals by block/season" \u2014
  # both need the exact same chain (TrapTagger -> EXIF-matched local file
  # -> ArgusWild filename match) that export_secr_species_select's
  # observer diagnoses above. Visible before clicking Download, not just
  # inferable afterward from an empty resulting file.
  individual_id_prereq_status <- reactive({
    if (is.null(rv$traptagger_data)) return(warn_panel("Upload TrapTagger data first (Load Data tab)."))
    if (is.null(rv$exif_data)) return(warn_panel("Extract EXIF data first (Load Data tab)."))
    if (is.null(rv$arguswild_data)) return(warn_panel("Upload ArgusWild data first (Load Data tab)."))
    enriched <- get_enriched_detections()
    if (is.null(enriched) || !any(!is.na(enriched$individual_id))) {
      return(warn_panel("All three are loaded, but no individual ID matches were found \u2014 check that
        ArgusWild's filenames line up with your local image filenames."))
    }
    success_bar(paste0(sum(!is.na(enriched$individual_id)), " record(s) matched to an individual ID,
      ready to export."))
  })
  output$individual_id_prereq_status <- renderUI({ individual_id_prereq_status() })
  output$ind_counts_prereq_status <- renderUI({ individual_id_prereq_status() })

  focal_species_matched <- reactive({
    req(rv$traptagger_data, input$focal_species)
    rows <- rv$traptagger_data[rv$traptagger_data$species %in% input$focal_species, ]
    if (nrow(rows) == 0) return(rows)
    match_traptagger_to_local_images(rows, rv$exif_data)
  })

  output$focal_species_table <- renderDT({
    if (is.null(rv$traptagger_data) || is.null(input$focal_species) || length(input$focal_species) == 0) {
      return(datatable(data.frame(Message = "Select one or more focal species above."),
                        options = list(dom = "t"), rownames = FALSE))
    }
    matched <- focal_species_matched()
    if (nrow(matched) == 0) {
      return(datatable(data.frame(Message = "No records found for the selected species."),
                        options = list(dom = "t"), rownames = FALSE))
    }
    display <- data.frame(
      station = matched$station_folder, species = matched$species,
      timestamp = format(matched$timestamp, "%Y-%m-%d %H:%M:%S"),
      local_file = ifelse(is.na(matched$matched_local_path), "Not found",
                           basename(matched$matched_local_path)),
      stringsAsFactors = FALSE
    )
    n_matched <- sum(!is.na(matched$matched_local_path))
    dt <- datatable(display,
      colnames = c("Station", "Species", "Timestamp", "Local file"),
      caption = paste0(n_matched, " of ", nrow(matched), " record(s) matched to a local image file.",
                        if (n_matched < nrow(matched)) " Unmatched records need \"Match to local images\" run first, or their image may not exist locally." else ""),
      options = list(pageLength = 15, scrollX = TRUE), rownames = FALSE)
    formatStyle(dt, "local_file",
      backgroundColor = styleEqual("Not found", "#F8E9E6"))
  })

  observeEvent(input$btn_export_argus, {
    if (is.null(rv$traptagger_data) || is.null(input$focal_species) || length(input$focal_species) == 0) {
      showNotification("Select at least one focal species first.", type = "error")
      return(invisible())
    }
    export_dir <- trimws(input$argus_export_dir_path)
    if (nchar(export_dir) == 0) {
      showNotification("Choose an export folder first.", type = "error")
      return(invisible())
    }
    if (is.null(rv$exif_data)) {
      showNotification("Click \"Match to local images\" above first; image matching needs EXIF data.",
                        type = "error")
      return(invisible())
    }

    tryCatch({
      fs::dir_create(export_dir)
      matched <- focal_species_matched()
      if (nrow(matched) == 0) {
        showNotification("No records found for the selected species.", type = "error")
        return(invisible())
      }

      csv_path <- file.path(export_dir, paste0(build_export_prefix(), "_focal_species_",
                                                 format(Sys.Date(), "%Y%m%d"), ".csv"))
      write.csv(matched[c("station_folder", "species", "timestamp", "sighting_count",
                           "image_url", "matched_local_path")], csv_path, row.names = FALSE, na = "")

      n_copied <- 0L
      n_skipped <- 0L
      withProgress(message = "Exporting focal species images...", value = 0, {
        for (i in seq_len(nrow(matched))) {
          src <- matched$matched_local_path[i]
          if (is.na(src) || !file.exists(src)) {
            n_skipped <- n_skipped + 1L
          } else {
            species_dir <- file.path(export_dir, matched$species[i])
            fs::dir_create(species_dir)
            dest <- file.path(species_dir, basename(src))
            if (!file.exists(dest)) file.copy(src, dest)
            n_copied <- n_copied + 1L
          }
          incProgress(1 / nrow(matched))
        }
      })

      detail <- paste0(n_copied, " image(s) copied into species sub-folders")
      if (n_skipped > 0) detail <- paste0(detail, ", ", n_skipped, " skipped (no local match)")
      log_action(paste0("ArgusWild export: ", paste(input$focal_species, collapse = ", "), ": ", detail))
      showNotification(paste0("Export complete. ", detail, ". CSV saved to ", basename(csv_path), "."),
                        type = "message", duration = 10)
    }, error = function(e) {
      showNotification(paste0("Export failed: ", conditionMessage(e)), type = "error", duration = 10)
      log_action(paste("ArgusWild export FAILED:", conditionMessage(e)))
    })
  })

  # ---------- PAGE 3.3: Import ArgusWild -------------------------------------

  observeEvent(input$arguswild_csv, {
    req(input$arguswild_csv)
    tryCatch({
      result <- read_arguswild_csv(input$arguswild_csv$datapath)
      if (!is.null(result$error)) {
        rv$arguswild_data <- NULL
        showNotification(paste("Could not read file:", result$error), type = "error", duration = 10)
        log_action(paste("ArgusWild import FAILED:", result$error))
        return(invisible())
      }
      rv$arguswild_data <- result$data
      n_individuals <- length(unique(result$data$individual_id))
      log_action(paste0("ArgusWild data uploaded: ", nrow(result$data), " row(s), ",
                         n_individuals, " individual(s)"))
      showNotification(paste0("Loaded ", nrow(result$data), " record(s), ",
                               n_individuals, " individual(s)."), type = "message")
    }, error = function(e) {
      rv$arguswild_data <- NULL
      showNotification(paste0("Something went wrong: ", conditionMessage(e)), type = "error", duration = 15)
      log_action(paste("ArgusWild import FAILED:", conditionMessage(e)))
    })
  })

  output$arguswild_upload_summary_ui <- renderUI({
    req(rv$arguswild_data)
    d <- rv$arguswild_data
    n_unidentified <- if ("individual_id" %in% names(d)) {
      sum(toupper(trimws(d$individual_id)) %in% c("UNIDENTIFIED", "UNKNOWN", ""))
    } else 0L
    tags$div(class = "small text-muted mt-2",
      tags$div(tags$strong(nrow(d)), " record(s) \u00b7 ",
               tags$strong(length(unique(d$individual_id))), " unique individual(s)"),
      if (n_unidentified > 0) tags$div(tags$strong(n_unidentified), " record(s) unidentified")
    )
  })

  # req() failing partway through focal_species_matched() (e.g. no species
  # currently selected on "Focal species export", or no TrapTagger data
  # loaded there) throws a SILENT error that would otherwise propagate up
  # through here and make output$argus_summary_ui/argus_id_table render
  # as completely blank, with no visible message at all — checked
  # explicitly instead, so there's always a clear reason shown.
  focal_species_ready <- reactive({
    !is.null(rv$traptagger_data) && !is.null(input$focal_species) && length(input$focal_species) > 0
  })

  argus_joined <- reactive({
    req(rv$arguswild_data)
    if (!focal_species_ready()) {
      return(data.frame(station_folder = character(0), species = character(0),
                         timestamp = as.POSIXct(character(0)), local_filename = character(0),
                         individual_id = character(0), sex = character(0), life_stage = character(0),
                         stringsAsFactors = FALSE))
    }
    joined <- join_arguswild_to_species_data(rv$arguswild_data, focal_species_matched())

    # Manual edits (typed directly into the table below) apply ON TOP of
    # whatever ArgusWild supplied, keyed by local_filename — lets someone
    # fill in a "no match" individual ID, or a missing sex/life stage, by
    # hand without needing to re-upload a modified ArgusWild CSV.
    edits <- rv$argus_manual_edits
    if (!is.null(edits) && nrow(edits) > 0 && nrow(joined) > 0) {
      idx <- match(joined$local_filename, edits$local_filename)
      has_edit <- !is.na(idx)
      if (any(has_edit)) {
        for (col in c("individual_id", "sex", "life_stage")) {
          edit_vals <- edits[[col]][idx[has_edit]]
          overwrite <- has_edit
          overwrite[has_edit] <- !is.na(edit_vals)
          joined[[col]][overwrite] <- edits[[col]][idx[overwrite]]
        }
      }
    }
    joined
  })

  output$argus_summary_ui <- renderUI({
    if (is.null(rv$arguswild_data)) {
      return(tags$p(class = "small text-muted mb-0",
        "Upload an ArgusWild export above to see individual ID results here."))
    }
    if (!focal_species_ready()) {
      return(warn_panel("Select a focal species on \"Focal species export\" first; the join
        needs to know which species' records to match against."))
    }
    joined <- argus_joined()
    n_matched <- sum(!is.na(joined$individual_id))
    tagList(
      tags$p(class = "small mb-1",
        tags$strong(nrow(joined)), " focal-species record(s) from \"Focal species export\": ",
        tags$strong(n_matched), " matched to an ArgusWild individual ID"),
      if (nrow(joined) > 0 && n_matched < nrow(joined)) {
        warn_panel(paste0(nrow(joined) - n_matched, " record(s) have no matching ArgusWild row; ",
                           "check that \"Match to local images\" (Focal species export) has been run, ",
                           "and that the selected species there matches this ArgusWild export."))
      }
    )
  })

  output$argus_id_table <- renderDT({
    req(rv$arguswild_data)
    joined <- argus_joined()
    if (nrow(joined) == 0) {
      return(datatable(data.frame(Message = "No focal-species records to join against; select a species and run \"Match to local images\" on the Focal species export page first."),
                        options = list(dom = "t"), rownames = FALSE))
    }
    # Fixed column order/set (not intersect()-derived) so column indices
    # here always match ARGUS_ID_TABLE_COLS below, which the cell-edit
    # handler relies on to know which column was edited.
    display_cols <- ARGUS_ID_TABLE_COLS
    display <- joined[display_cols]
    display$timestamp <- format(display$timestamp, "%Y-%m-%d %H:%M:%S")
    # Editable cells show empty, not placeholder text like "no match" —
    # that text would otherwise look like a real value sitting in an
    # editable field, rather than an invitation to fill it in.
    for (col in c("individual_id", "sex", "life_stage")) {
      display[[col]][is.na(display[[col]])] <- ""
    }
    col_labels <- c(station_folder = "Station", species = "Species", timestamp = "Timestamp",
                    local_filename = "Local file", individual_id = "Individual ID",
                    sex = "Sex", life_stage = "Life stage")
    # Columns 4-6 (individual_id, sex, life_stage) are editable; 0-3
    # (station/species/timestamp/local file) are derived from our own
    # data, not ArgusWild's, so editing them here wouldn't make sense.
    dt <- datatable(display, colnames = unname(col_labels[display_cols]),
      editable = list(target = "cell", disable = list(columns = 0:3)),
      options = list(pageLength = 15, scrollX = TRUE), rownames = FALSE)
    formatStyle(dt, "individual_id", backgroundColor = styleEqual("", "#F8E9E6"))
  })

  # Captures a manual edit to the Individual ID summary table (only
  # individual_id/sex/life_stage are editable — see `disable` above) and
  # stores it in rv$argus_manual_edits, keyed by local_filename, since
  # argus_joined() is a computed reactive that would otherwise discard
  # the edit the next time anything it depends on changes. An empty
  # string clears a previous manual edit for that field rather than
  # storing an empty value that would then override a real one.
  observeEvent(input$argus_id_table_cell_edit, {
    edit <- input$argus_id_table_cell_edit
    joined <- argus_joined()
    if (edit$row < 1 || edit$row > nrow(joined)) return(invisible())

    local_filename <- joined$local_filename[edit$row]
    if (is.na(local_filename)) {
      showNotification("Can't save an edit for a record with no matched local file.", type = "error")
      return(invisible())
    }

    edited_col <- ARGUS_ID_TABLE_COLS[edit$col + 1]  # DT's col index is 0-based
    if (!edited_col %in% c("individual_id", "sex", "life_stage")) return(invisible())

    new_value <- trimws(as.character(edit$value))
    if (nchar(new_value) == 0) new_value <- NA_character_

    edits <- rv$argus_manual_edits
    if (is.null(edits)) {
      edits <- data.frame(local_filename = character(0), individual_id = character(0),
                           sex = character(0), life_stage = character(0), stringsAsFactors = FALSE)
    }
    existing_idx <- which(edits$local_filename == local_filename)
    if (length(existing_idx) == 0) {
      new_row <- data.frame(local_filename = local_filename, individual_id = NA_character_,
                             sex = NA_character_, life_stage = NA_character_, stringsAsFactors = FALSE)
      new_row[[edited_col]] <- new_value
      edits <- rbind(edits, new_row)
    } else {
      edits[[edited_col]][existing_idx[1]] <- new_value
    }
    rv$argus_manual_edits <- edits
    log_action(paste0("Manually edited ", edited_col, " for ", local_filename, ": ",
                       if (is.na(new_value)) "(cleared)" else new_value))
  })

  # ---------- PAGE 4: Load Data -----------------------------------------------
  # Lets someone start fresh at Visualize & Export without having completed
  # Ingest or Processing in the same session — a different person entirely
  # (an analyst, not the field tech) may be picking this up. Reuses the
  # exact same helper functions Processing's own uploads use
  # (process_deployment_file, read_traptagger_csv, read_arguswild_csv,
  # run_exif_extraction), writing into the SAME rv$ fields — so if any of
  # this is already loaded from earlier in the session, it's reused as-is
  # everywhere, regardless of which page it was loaded from.

  observeEvent(input$viz_deployment_csv, {
    req(input$viz_deployment_csv)
    process_deployment_file(input$viz_deployment_csv$datapath, input$viz_deployment_csv$name, "", "")
  })

  output$viz_deployment_status_ui <- renderUI({
    if (is.null(rv$deployment_data)) return(NULL)
    d <- rv$deployment_data
    success_bar(paste0(nrow(d), " records loaded: ", length(unique(d$ct_id)), " camera(s) across ",
                        length(unique(d$station_folder)), " station(s)."))
  })
  sync_optional_upload_visibility("viz_deployment_csv", reactive(!is.null(rv$deployment_data)))

  observeEvent(input$btn_open_viz_folder_browser, {
    open_folder_browser("viz_image_dir_path", input$viz_image_dir_path, "Select survey folder")
  })

  observeEvent(input$btn_viz_extract_exif, {
    if (!is.null(rv$exif_data)) {
      showNotification("EXIF data already loaded; reused as-is.", type = "message")
      return(invisible())
    }
    if (is.null(rv$deployment_data)) {
      showNotification("Load a deployment sheet first (above).", type = "error")
      return(invisible())
    }
    base_dir <- trimws(input$viz_image_dir_path)
    if (nchar(base_dir) == 0) {
      showNotification("Enter or browse to your survey's image folder first.", type = "error")
      return(invisible())
    }
    if (!dir.exists(base_dir)) {
      showNotification("That folder doesn't seem to exist. Please re-select it.", type = "error")
      return(invisible())
    }
    deployment_phase <- get_deployment_phase()
    if (nchar(deployment_phase) == 0) {
      showNotification("Enter the deployment phase (above, or Survey Setup) before extracting.",
                        type = "error")
      return(invisible())
    }
    tryCatch({
      withProgress(message = "Extracting EXIF data...", value = 0.3, {
        exif <- run_exif_extraction(rv$deployment_data, base_dir, deployment_phase)
        incProgress(0.7)
      })
      rv$exif_data <- exif
      log_action(paste0("EXIF extracted (Visualize & Export): ", nrow(exif), " image(s)"))
      showNotification(paste0("Extracted EXIF for ", nrow(exif), " image(s)."), type = "message")
    }, error = function(e) {
      showNotification(paste0("Extraction failed: ", conditionMessage(e)), type = "error", duration = 15)
      log_action(paste("Visualize & Export EXIF extraction FAILED:", conditionMessage(e)))
    })
  })

  output$viz_exif_status_ui <- renderUI({
    if (is.null(rv$exif_data)) return(NULL)
    d <- rv$exif_data
    success_bar(paste0(nrow(d), " image(s) with EXIF data loaded."))
  })

  observeEvent(input$viz_traptagger_csv, {
    req(input$viz_traptagger_csv)
    tryCatch({
      result <- read_traptagger_csv(input$viz_traptagger_csv$datapath)
      if (!is.null(result$error)) {
        showNotification(paste("Could not read file:", result$error), type = "error", duration = 10)
        log_action(paste("TrapTagger import (Visualize & Export) FAILED:", result$error))
        return(invisible())
      }
      rv$traptagger_data <- result$data
      log_action(paste0("TrapTagger data uploaded (Visualize & Export): ", nrow(result$data), " row(s)"))
      showNotification(paste0("Loaded ", nrow(result$data), " record(s)."), type = "message")
    }, error = function(e) {
      showNotification(paste0("Something went wrong: ", conditionMessage(e)), type = "error", duration = 15)
      log_action(paste("TrapTagger import (Visualize & Export) FAILED:", conditionMessage(e)))
    })
  })

  output$viz_traptagger_status_ui <- renderUI({
    if (is.null(rv$traptagger_data)) return(NULL)
    d <- rv$traptagger_data
    success_bar(paste0(nrow(d), " record(s) loaded across ", length(unique(d$station_folder)), " station(s)."))
  })
  sync_optional_upload_visibility("viz_traptagger_csv", reactive(!is.null(rv$traptagger_data)))

  observeEvent(input$viz_arguswild_csv, {
    req(input$viz_arguswild_csv)
    tryCatch({
      result <- read_arguswild_csv(input$viz_arguswild_csv$datapath)
      if (!is.null(result$error)) {
        showNotification(paste("Could not read file:", result$error), type = "error", duration = 10)
        log_action(paste("ArgusWild import (Visualize & Export) FAILED:", result$error))
        return(invisible())
      }
      rv$arguswild_data <- result$data
      log_action(paste0("ArgusWild data uploaded (Visualize & Export): ", nrow(result$data), " row(s)"))
      showNotification(paste0("Loaded ", nrow(result$data), " record(s)."), type = "message")
    }, error = function(e) {
      showNotification(paste0("Something went wrong: ", conditionMessage(e)), type = "error", duration = 15)
      log_action(paste("ArgusWild import (Visualize & Export) FAILED:", conditionMessage(e)))
    })
  })

  output$viz_arguswild_status_ui <- renderUI({
    if (is.null(rv$arguswild_data)) return(NULL)
    d <- rv$arguswild_data
    success_bar(paste0(nrow(d), " record(s) loaded, ", length(unique(d$individual_id)), " individual(s)."))
  })
  sync_optional_upload_visibility("viz_arguswild_csv", reactive(!is.null(rv$arguswild_data)))

  observeEvent(input$viz_search_effort_csv, {
    req(input$viz_search_effort_csv)
    tryCatch({
      result <- read_search_effort_csv(input$viz_search_effort_csv$datapath)
      if (!is.null(result$error)) {
        showNotification(paste("Could not read file:", result$error), type = "error", duration = 10)
        log_action(paste("Search effort import FAILED:", result$error))
        return(invisible())
      }
      rv$camera_operation_periods <- result$data
      log_action(paste0("Search effort CSV uploaded (Visualize & Export): ", nrow(result$data), " operational period(s)"))
      showNotification(paste0("Loaded ", nrow(result$data), " operational period(s)."), type = "message")
    }, error = function(e) {
      showNotification(paste0("Something went wrong: ", conditionMessage(e)), type = "error", duration = 15)
      log_action(paste("Search effort import FAILED:", conditionMessage(e)))
    })
  })

  # get_operation_periods() (defined further below) already automatically
  # falls back to computing fresh from Processing's own rv$gap_periods
  # whenever nothing's been explicitly re-uploaded here \u2014 the actual
  # Effort/Species/Activity calculations were never blocked on this
  # upload at all. The status indicator just didn't reflect that: it
  # checked rv$camera_operation_periods (the re-uploaded variant)
  # directly, so it showed "nothing loaded" even when Processing's data
  # was already in active use, making a re-upload look necessary when it
  # wasn't. Fixed to check the same source the real calculations use,
  # and to say which source that actually is.
  output$viz_search_effort_status_ui <- renderUI({
    periods <- get_operation_periods()
    if (is.null(periods) || nrow(periods) == 0) return(NULL)
    if (!is.null(rv$camera_operation_periods) && nrow(rv$camera_operation_periods) > 0) {
      success_bar(paste0(nrow(periods), " camera operational period(s) loaded (re-uploaded CSV)."))
    } else {
      success_bar(paste0(nrow(periods), " camera operational period(s) available \u2014 ",
                          "auto-computed from Processing's camera downtime gaps. No re-upload needed."))
    }
  })
  sync_optional_upload_visibility("viz_search_effort_csv",
    reactive({ p <- get_operation_periods(); !is.null(p) && nrow(p) > 0 }))

  observeEvent(input$gis_files, {
    req(input$gis_files)
    tryCatch({
      # Shiny's multi-file upload gives each file a random temp name that
      # doesn't match its original filename — but sf::st_read() needs a
      # shapefile's .shp/.dbf/.shx/.prj components to share the same base
      # name in the same directory to find each other. Copy each upload
      # into a fresh temp directory under its ORIGINAL filename first, so
      # that relationship is restored before sf ever sees them.
      tmp_dir <- tempfile("gis_upload_")
      fs::dir_create(tmp_dir)
      for (i in seq_len(nrow(input$gis_files))) {
        file.copy(input$gis_files$datapath[i], file.path(tmp_dir, input$gis_files$name[i]))
      }
      layer_files <- list.files(tmp_dir, pattern = "\\.(shp|geojson|gpkg)$",
                                 full.names = TRUE, ignore.case = TRUE)
      if (length(layer_files) == 0) {
        showNotification("No .shp/.geojson/.gpkg file found among the uploaded files.", type = "error")
        return(invisible())
      }
      layers <- lapply(layer_files, function(f) sf::st_read(f, quiet = TRUE))
      names(layers) <- tools::file_path_sans_ext(basename(layer_files))
      rv$gis_layers <- layers
      n_features <- sum(vapply(layers, nrow, integer(1)))
      log_action(paste0("GIS layers uploaded: ", length(layers), " layer(s), ", n_features, " feature(s) total"))
      showNotification(paste0("Loaded ", length(layers), " layer(s), ", n_features, " feature(s) total."),
                        type = "message")
    }, error = function(e) {
      showNotification(paste0("Could not read GIS files: ", conditionMessage(e)), type = "error", duration = 15)
      log_action(paste("GIS layer upload FAILED:", conditionMessage(e)))
    })
  })

  output$viz_gis_status_ui <- renderUI({
    if (is.null(rv$gis_layers)) return(NULL)
    n_features <- sum(vapply(rv$gis_layers, nrow, integer(1)))
    success_bar(paste0(length(rv$gis_layers), " layer(s) loaded, ", n_features, " feature(s) total."))
  })

  # Spatial join: for each uploaded polygon layer, which feature (if any)
  # does each camera's coordinate fall inside? Answers exactly the kind of
  # question GIS layers exist for here — "how many cameras are in habitat
  # A vs habitat B" — as a covariate for later analysis (e.g. the RAI vs
  # covariate plot on the Species tab).
  output$viz_gis_camera_count_table <- renderDT({
    req(rv$gis_layers, rv$deployment_data)
    d <- rv$deployment_data
    if (!all(c("lat", "long") %in% names(d))) {
      return(datatable(data.frame(Message = "Deployment sheet has no lat/long columns to spatially join against."),
                        options = list(dom = "t"), rownames = FALSE))
    }
    cams <- unique(d[c("ct_id", "site_id", "lat", "long")])
    cams <- cams[!is.na(cams$lat) & !is.na(cams$long), ]
    if (nrow(cams) == 0) {
      return(datatable(data.frame(Message = "No valid camera coordinates found in the deployment sheet."),
                        options = list(dom = "t"), rownames = FALSE))
    }

    result_rows <- tryCatch({
      cam_points <- sf::st_as_sf(cams, coords = c("long", "lat"), crs = 4326)
      results <- list()
      for (layer_name in names(rv$gis_layers)) {
        layer <- tryCatch(sf::st_transform(rv$gis_layers[[layer_name]], 4326),
                           error = function(e) rv$gis_layers[[layer_name]])
        within_list <- suppressMessages(sf::st_within(cam_points, layer, sparse = TRUE))
        label_col <- intersect(c("name", "habitat", "type", "label", "Name", "NAME", "Habitat"), names(layer))
        poly_labels <- if (length(label_col) > 0) as.character(sf::st_drop_geometry(layer)[[label_col[1]]]) else
          paste0("Feature ", seq_len(nrow(layer)))

        assigned <- vapply(within_list, function(idx) {
          if (length(idx) == 0) "(outside all features)" else poly_labels[idx[1]]
        }, character(1))

        tab <- table(assigned)
        results[[layer_name]] <- data.frame(layer = layer_name, feature = names(tab),
                                             n_cameras = as.integer(tab), stringsAsFactors = FALSE)
      }
      do.call(rbind, results)
    }, error = function(e) NULL)

    if (is.null(result_rows)) {
      return(datatable(data.frame(Message = "Could not spatially join cameras to these layers; check that the GIS layer(s) have valid geometry and a known coordinate system."),
                        options = list(dom = "t"), rownames = FALSE))
    }
    datatable(result_rows, colnames = c("Layer", "Feature", "Cameras"),
      options = list(pageLength = 15), rownames = FALSE)
  })

  # ---------- PAGE 4: Exports ------------------------------------------------

  # Prefers camera operation periods already loaded from a re-uploaded
  # search effort CSV (Load Data) — respects someone's own edits/re-import
  # over recomputing — falling back to computing fresh from the
  # deployment sheet + gaps + camera decisions otherwise.
  get_operation_periods <- reactive({
    if (!is.null(rv$camera_operation_periods) && nrow(rv$camera_operation_periods) > 0) {
      return(rv$camera_operation_periods)
    }
    build_camera_operation_export(rv$deployment_data, rv$gap_periods, rv$camera_decisions)
  })

  # Station-level version, for occupancy/SECR exports specifically \u2014
  # built on top of get_operation_periods() so both the re-uploaded-CSV
  # and freshly-computed paths get unioned to station level the same way,
  # rather than duplicating that source-selection logic here too.
  get_station_operation_periods <- reactive({
    build_station_operation_periods(get_operation_periods())
  })

  get_enriched_detections <- reactive({
    build_enriched_detections(rv$traptagger_data, rv$exif_data, rv$arguswild_data, rv$deployment_data)
  })

  # Every export's content() function below is wrapped in tryCatch(). An
  # uncaught R error inside a downloadHandler makes Shiny serve its
  # default HTML error page in place of the file — a CSV download that
  # silently turns into a broken .html is exactly that failure mode. This
  # guarantees a real CSV always comes back (even if, on a genuine bug,
  # that CSV just contains an error message) instead of an opaque HTML
  # page, and surfaces the exact error via notification + audit log so a
  # real bug can be pinpointed immediately rather than guessed at blind.
  export_error_csv <- function(file, context, e) {
    write.csv(data.frame(Error = paste0(context, " failed: ", conditionMessage(e))), file, row.names = FALSE)
    log_action(paste0(context, " EXPORT FAILED: ", conditionMessage(e)))
    showNotification(paste0(context, " failed: ", conditionMessage(e)), type = "error", duration = 20)
  }

  output$dl_stations <- downloadHandler(
    filename = function() paste0(build_export_prefix(), "_camera_stations_", format(Sys.Date(), "%Y%m%d"), ".csv"),
    content = function(file) {
      tryCatch({
        d <- rv$deployment_data
        if (is.null(d) || nrow(d) == 0) { write.csv(data.frame(), file, row.names = FALSE); return(invisible()) }
        cols <- intersect(c("block", "season", "block_season", "cell_id", "site_id", "station_folder",
                             "ct_loc", "lat", "long", "habitat"), names(d))
        stations <- unique(d[cols])
        # n_cameras per STATION (station_folder), not per camera location
        # (site_id) \u2014 site_id is already unique per camera (A01A/A01B are
        # different site_id values), so counting rows per site_id would
        # always return 1 regardless of how many cameras share a station.
        # Counts DISTINCT site_id values per station_folder, not raw row
        # counts, in case a camera ever has more than one row in the sheet.
        station_cam_map <- unique(d[c("station_folder", "site_id")])
        cam_counts <- table(station_cam_map$station_folder)
        stations$n_cameras <- as.integer(cam_counts[stations$station_folder])
        write.csv(stations, file, row.names = FALSE, na = "")
        log_action(paste0("Downloaded camera stations CSV: ", nrow(stations), " station(s)"))
      }, error = function(e) export_error_csv(file, "Camera stations", e))
    }
  )

  output$dl_effort_summary <- downloadHandler(
    filename = function() paste0(build_export_prefix(), "_effort_summary_", format(Sys.Date(), "%Y%m%d"), ".csv"),
    content = function(file) {
      tryCatch({
        ops <- get_operation_periods()
        if (is.null(ops) || nrow(ops) == 0) { write.csv(data.frame(), file, row.names = FALSE); return(invisible()) }
        starts <- parse_deployment_datetime(ops$deploymentStart)
        ends   <- parse_deployment_datetime(ops$deploymentEnd)
        ops$op_days <- as.numeric(difftime(ends, starts, units = "days"))
        # cameraID and locationID are both already per-camera (not
        # per-station) — e.g. A01A and A01B are different locationID
        # values even though they're paired at the same station — so
        # each row here is already one individual camera's own total,
        # never merged with its pair. locationName (the shared station,
        # e.g. "SiteA01st_A") is included so that pairing is visible
        # directly in the output, not just true under the hood.
        summary_df <- aggregate(op_days ~ cameraID + locationID + locationName, data = ops, FUN = sum)
        names(summary_df) <- c("cameraID", "locationID", "locationName", "total_operational_days")
        summary_df <- summary_df[order(summary_df$locationName, summary_df$locationID), ]
        write.csv(summary_df, file, row.names = FALSE, na = "")
        log_action(paste0("Downloaded effort summary CSV: ", nrow(summary_df), " camera(s)"))
      }, error = function(e) export_error_csv(file, "Effort summary", e))
    }
  )

  output$dl_effort_matrix <- downloadHandler(
    filename = function() paste0(build_export_prefix(), "_camera_operation_matrix_", format(Sys.Date(), "%Y%m%d"), ".csv"),
    content = function(file) {
      tryCatch({
        mat <- build_camera_day_matrix(get_operation_periods())
        write.csv(mat, file, row.names = FALSE, na = "NA")
        log_action(paste0("Downloaded camera operation matrix CSV: ", nrow(mat), " camera(s)"))
      }, error = function(e) export_error_csv(file, "Effort matrix", e))
    }
  )

  output$dl_species <- downloadHandler(
    filename = function() paste0(build_export_prefix(), "_species_events_", format(Sys.Date(), "%Y%m%d"), ".csv"),
    content = function(file) {
      tryCatch({
        threshold <- if (is.null(input$export_independence_threshold)) 30 else input$export_independence_threshold
        events <- collapse_to_independent_events(rv$traptagger_data, threshold)
        if (nrow(events) > 0) {
          events$event_start <- format(events$event_start, "%Y-%m-%d %H:%M:%S")
          events$event_end   <- format(events$event_end, "%Y-%m-%d %H:%M:%S")
        }
        write.csv(events, file, row.names = FALSE, na = "")
        log_action(paste0("Downloaded species detection CSV: ", nrow(events), " independent event(s), ",
                           threshold, "-minute threshold"))
      }, error = function(e) export_error_csv(file, "Species detection", e))
    }
  )

  output$species_occ_exclusion_status <- renderUI({
    species_sel <- input$export_species_select
    enriched <- get_enriched_detections()
    if (is.null(enriched) || is.null(species_sel) || nchar(species_sel) == 0 || grepl("^\\(", species_sel)) {
      return(NULL)
    }
    # is.na(ct_id) is still a reliable proxy for "at a multi-camera
    # station" (build_enriched_detections() still can't assign one of
    # those a single camera) \u2014 no longer a warning about data being
    # dropped, since it isn't anymore: this is now purely informational,
    # confirming the station-level combining this export actually does.
    n_paired <- sum(enriched$species == species_sel & is.na(enriched$ct_id) & !is.na(enriched$timestamp), na.rm = TRUE)
    if (n_paired == 0) return(NULL)
    info_panel(paste0(n_paired, " detection(s) of ", species_sel, " are at multi-camera (paired) stations \u2014",
      " included here at the STATION level (both cameras combined), since occupancy doesn't need to know",
      " which exact camera triggered."))
  })

  output$dl_species_occ <- downloadHandler(
    filename = function() {
      species_label <- if (is.null(input$export_species_select)) "species" else input$export_species_select
      paste0(build_export_prefix(), "_", gsub("[^A-Za-z0-9]+", "_", species_label),
             "_occupancy_", format(Sys.Date(), "%Y%m%d"), ".csv")
    },
    content = function(file) {
      tryCatch({
        # STATION-level, not camera-level: occupancy doesn't care which
        # specific camera at a paired station triggered, and excluding
        # those records (the old behavior) would have systematically
        # dropped exactly the records most valuable for individual ID
        # (paired setups exist specifically to catch both flanks).
        station_ops <- get_station_operation_periods()
        enriched <- get_enriched_detections()
        species_sel <- input$export_species_select
        if (is.null(enriched) || is.null(species_sel) || nchar(species_sel) == 0 ||
            grepl("^\\(", species_sel)) {
          write.csv(data.frame(), file, row.names = FALSE); return(invisible())
        }
        sp <- enriched[enriched$species == species_sel & !is.na(enriched$timestamp), ]
        det_by_day <- if (nrow(sp) > 0) {
          data.frame(cameraID = normalize_station_name(sp$station_folder), Date = as.Date(sp$timestamp))
        } else NULL
        mat <- build_camera_day_matrix(station_ops, det_by_day)
        if (nrow(mat) > 0) {
          # Relabel the normalized matching key back to the original,
          # human-readable station folder name for the actual CSV \u2014 the
          # normalized form is an internal matching key, not meant for
          # display.
          station_labels <- setNames(station_ops$locationName[!duplicated(station_ops$locationID)],
                                       station_ops$locationID[!duplicated(station_ops$locationID)])
          mat$cameraID <- unname(station_labels[mat$cameraID])
          names(mat)[1] <- "stationID"
        }
        write.csv(mat, file, row.names = FALSE, na = "NA")
        log_action(paste0("Downloaded species occupancy CSV for ", species_sel, ": ", nrow(mat),
                           " station(s) \u2014 camera pairs combined at the station level, not excluded."))
      }, error = function(e) export_error_csv(file, "Species occupancy", e))
    }
  )

  output$dl_individual_id <- downloadHandler(
    filename = function() paste0(build_export_prefix(), "_individual_id_", format(Sys.Date(), "%Y%m%d"), ".csv"),
    content = function(file) {
      tryCatch({
        enriched <- get_enriched_detections()
        if (is.null(enriched)) { write.csv(data.frame(), file, row.names = FALSE); return(invisible()) }
        # Only records that actually have an individual ID - a record with
        # no ArgusWild match contributes nothing to what this specific
        # export is for, and would just be noise mixed in with the real
        # individual-level data.
        enriched <- enriched[!is.na(enriched$individual_id), ]
        out_cols <- intersect(c("station_folder", "species", "timestamp", "local_filename",
                                 "individual_id", "sex", "life_stage", "block", "season", "cell_id"), names(enriched))
        out <- enriched[out_cols]
        if ("timestamp" %in% names(out)) out$timestamp <- format(out$timestamp, "%Y-%m-%d %H:%M:%S")
        write.csv(out, file, row.names = FALSE, na = "")
        log_action(paste0("Downloaded individual ID CSV: ", nrow(out), " record(s)"))
      }, error = function(e) export_error_csv(file, "Individual ID", e))
    }
  )

  output$secr_exclusion_status <- renderUI({
    species_sel <- input$export_secr_species_select
    enriched <- get_enriched_detections()
    if (is.null(enriched) || is.null(species_sel) || nchar(species_sel) == 0 || grepl("^\\(", species_sel)) {
      return(NULL)
    }
    # No longer a warning about data loss, since nothing is dropped
    # anymore \u2014 purely informational, confirming the station-level
    # combining this export does. SECR specifically treats two
    # co-located detectors as redundant anyway (never two at the exact
    # same point), so a shared detector at the station is also the
    # methodologically correct choice here, not just a workaround.
    n_paired <- sum(enriched$species == species_sel & !is.na(enriched$individual_id) &
                     is.na(enriched$ct_id), na.rm = TRUE)
    if (n_paired == 0) return(NULL)
    info_panel(paste0(n_paired, " individual detection(s) of ", species_sel, " are at multi-camera (paired)",
      " stations \u2014 included here with the detector set to the STATION (both cameras combined), since",
      " SECR treats co-located cameras as one detector anyway, never two at the same point."))
  })

  output$dl_secr <- downloadHandler(
    filename = function() {
      species_label <- if (is.null(input$export_secr_species_select)) "species" else input$export_secr_species_select
      paste0(build_export_prefix(), "_", gsub("[^A-Za-z0-9]+", "_", species_label),
             "_secr_capture_history_", format(Sys.Date(), "%Y%m%d"), ".csv")
    },
    content = function(file) {
      tryCatch({
        # STATION-level detector, not camera-level \u2014 see
        # species_occ_exclusion_status above for the full reasoning
        # (also applies here: SECR treats two co-located cameras as one
        # detector anyway, and excluding ambiguous-camera records would
        # have disproportionately dropped individual-ID data, since
        # paired setups exist specifically to catch both flanks).
        enriched <- get_enriched_detections()
        ops <- get_operation_periods()
        station_ops <- get_station_operation_periods()
        if (is.null(enriched) || is.null(ops) || nrow(ops) == 0) {
          write.csv(data.frame(), file, row.names = FALSE); return(invisible())
        }
        species_sel <- input$export_secr_species_select
        if (is.null(species_sel) || nchar(species_sel) == 0 || grepl("^\\(", species_sel)) {
          write.csv(data.frame(), file, row.names = FALSE); return(invisible())
        }
        survey_start <- suppressWarnings(min(as.Date(parse_deployment_datetime(ops$deploymentStart)), na.rm = TRUE))
        sub <- enriched[!is.na(enriched$individual_id) & !is.na(enriched$timestamp) &
                           enriched$species == species_sel, ]
        if (nrow(sub) == 0 || is.infinite(survey_start)) {
          write.csv(data.frame(), file, row.names = FALSE); return(invisible())
        }
        # Relabeled to the SAME canonical, deployment-sheet-formatted
        # station name "Camera stations & coordinates" uses (via
        # station_ops$locationName, which traces back to the deployment
        # sheet) \u2014 not TrapTagger's own raw station_folder directly,
        # which is often formatted differently (e.g. without the
        # underscore the deployment sheet keeps) and would silently fail
        # to match the trap-location file secr also needs.
        station_labels <- setNames(station_ops$locationName[!duplicated(station_ops$locationID)],
                                     station_ops$locationID[!duplicated(station_ops$locationID)])
        sub$canonical_station <- unname(station_labels[normalize_station_name(sub$station_folder)])
        out <- unique(data.frame(
          Session = 1,
          ID = sub$individual_id,
          Occasion = as.integer(as.Date(sub$timestamp) - survey_start) + 1L,
          Detector = sub$canonical_station,
          stringsAsFactors = FALSE
        ))
        out <- out[order(out$ID, out$Occasion), ]
        write.csv(out, file, row.names = FALSE, na = "")
        log_action(paste0("Downloaded SECR capture history CSV for ", species_sel, ": ", nrow(out), " capture(s), ",
                           length(unique(out$ID)), " individual(s), detector = station (camera pairs combined,",
                           " not excluded). Build the matching trap-location file from \"Camera stations &",
                           " coordinates,\" deduplicated by station_folder (not site_id)."))
      }, error = function(e) export_error_csv(file, "SECR capture history", e))
    }
  )

  output$dl_photo_counts <- downloadHandler(
    filename = function() paste0(build_export_prefix(), "_photo_counts_by_species_", format(Sys.Date(), "%Y%m%d"), ".csv"),
    content = function(file) {
      tryCatch({
        if (is.null(rv$traptagger_data) || nrow(rv$traptagger_data) == 0) {
          write.csv(data.frame(), file, row.names = FALSE); return(invisible())
        }
        tab <- table(rv$traptagger_data$species)
        out <- data.frame(species = names(tab), n_photos = as.integer(tab), stringsAsFactors = FALSE)
        out <- out[order(-out$n_photos), ]
        write.csv(out, file, row.names = FALSE)
        log_action(paste0("Downloaded photo counts by species CSV: ", nrow(out), " species"))
      }, error = function(e) export_error_csv(file, "Photo counts", e))
    }
  )

  output$dl_ind_counts <- downloadHandler(
    filename = function() paste0(build_export_prefix(), "_individuals_by_block_season_", format(Sys.Date(), "%Y%m%d"), ".csv"),
    content = function(file) {
      tryCatch({
        enriched <- get_enriched_detections()
        if (is.null(enriched)) { write.csv(data.frame(), file, row.names = FALSE); return(invisible()) }
        sub <- enriched[!is.na(enriched$individual_id), ]
        if (nrow(sub) == 0) { write.csv(data.frame(), file, row.names = FALSE); return(invisible()) }
        unique_ind <- unique(sub[c("individual_id", "species", "block", "season", "sex", "life_stage")])
        unique_ind$species[is.na(unique_ind$species)] <- "(unknown)"
        unique_ind$block[is.na(unique_ind$block)] <- "(unknown)"
        unique_ind$season[is.na(unique_ind$season)] <- "(unknown)"
        unique_ind$sex[is.na(unique_ind$sex)] <- "(unknown)"
        unique_ind$life_stage[is.na(unique_ind$life_stage)] <- "(unknown)"
        agg <- aggregate(individual_id ~ species + block + season + sex + life_stage, data = unique_ind, FUN = length)
        names(agg)[names(agg) == "individual_id"] <- "n_individuals"
        agg <- agg[order(agg$species, agg$block, agg$season, agg$sex, agg$life_stage), ]
        write.csv(agg, file, row.names = FALSE, na = "")
        log_action(paste0("Downloaded individuals by block/season CSV: ", sum(agg$n_individuals), " individual(s) total"))
      }, error = function(e) export_error_csv(file, "Individuals by block/season", e))
    }
  )

  output$metadata_col_picker <- renderUI({
    if (is.null(rv$deployment_data) || nrow(rv$deployment_data) == 0) {
      return(tags$p(class = "small text-muted mb-2", "Load a deployment sheet first (Load Data tab)."))
    }
    default_cols <- intersect(c("block", "season", "cell_id", "site_id", "ct_id", "station_folder",
                                 "lat", "long", "habitat"), names(rv$deployment_data))
    # Three genuine checkboxGroupInputs (one per Bootstrap column), not a
    # CSS multi-column wrapper around a single checkboxGroupInput \u2014 that
    # wrapper had only one direct child (the whole checkbox-group block),
    # so there was nothing for column-width to actually distribute, which
    # collapsed the rendering instead of producing the intended layout.
    # Combined back into one list server-side (dl_metadata).
    all_cols <- names(rv$deployment_data)
    n <- length(all_cols)
    thirds <- split(all_cols, cut(seq_len(n), breaks = 3, labels = FALSE))
    tagList(
      tags$label("Columns to include", class = "control-label"),
      fluidRow(
        column(4, checkboxGroupInput("metadata_selected_cols_1", NULL, choices = thirds[["1"]],
                                      selected = intersect(default_cols, thirds[["1"]]))),
        column(4, checkboxGroupInput("metadata_selected_cols_2", NULL, choices = thirds[["2"]],
                                      selected = intersect(default_cols, thirds[["2"]]))),
        column(4, checkboxGroupInput("metadata_selected_cols_3", NULL, choices = thirds[["3"]],
                                      selected = intersect(default_cols, thirds[["3"]])))
      )
    )
  })

  output$dl_metadata <- downloadHandler(
    filename = function() paste0(build_export_prefix(), "_deployment_metadata_", format(Sys.Date(), "%Y%m%d"), ".csv"),
    content = function(file) {
      tryCatch({
        d <- rv$deployment_data
        selected_cols <- c(input$metadata_selected_cols_1, input$metadata_selected_cols_2, input$metadata_selected_cols_3)
        if (is.null(d) || length(selected_cols) == 0) {
          write.csv(data.frame(), file, row.names = FALSE); return(invisible())
        }
        # Preserve the deployment sheet's own column order, not the
        # (arbitrary, split-by-thirds) order the checkboxes happen to be
        # selected in across the three groups.
        cols <- intersect(names(d), selected_cols)
        write.csv(d[cols], file, row.names = FALSE, na = "")
        log_action(paste0("Downloaded selected deployment metadata CSV: ", length(cols), " column(s)"))
      }, error = function(e) export_error_csv(file, "Deployment metadata", e))
    }
  )

  observe({
    if (is.null(rv$deployment_data) || !("block" %in% names(rv$deployment_data))) {
      updateSelectInput(session, "effort_filter_block", choices = c("All"))
      return(invisible())
    }
    block_choices <- c("All", sort(unique(stats::na.omit(rv$deployment_data$block))))
    updateSelectInput(session, "effort_filter_block", choices = block_choices)
  })

  output$effort_prereq_status <- renderUI({
    if (is.null(rv$deployment_data)) {
      return(warn_panel("Load a deployment sheet first (Load Data tab)."))
    }
    ops <- get_operation_periods()
    n_cams <- if (is.null(ops)) 0 else length(unique(ops$cameraID))
    success_bar(paste0(n_cams, " camera(s) ready to plot."))
  })

  # Camera operation periods don't carry `block` directly (it's a
  # deployment-sheet concept, not part of Camtrap DP's Deployments
  # schema) \u2014 joined back in here by site_id/locationID, the same key
  # both sides share, so the block filter has something to filter by.
  effort_filtered_ops <- reactive({
    ops <- get_operation_periods()
    if (is.null(ops) || nrow(ops) == 0 || is.null(rv$deployment_data)) return(NULL)
    block_map <- unique(rv$deployment_data[c("site_id", "block")])
    ops <- merge(ops, block_map, by.x = "locationID", by.y = "site_id", all.x = TRUE)
    if (!is.null(input$effort_filter_block) && input$effort_filter_block != "All") {
      ops <- ops[!is.na(ops$block) & ops$block == input$effort_filter_block, ]
    }
    ops
  })

  output$effort_timeline_plot <- renderPlotly({
    ops <- effort_filtered_ops()
    validate(need(!is.null(ops) && nrow(ops) > 0,
      "No camera operation data to plot yet \u2014 load a deployment sheet (Load Data tab)."))

    ops$start <- parse_deployment_datetime(ops$deploymentStart)
    ops$end   <- parse_deployment_datetime(ops$deploymentEnd)
    ops$label <- paste0(ops$locationID, " (", ops$locationName, ")")
    ops <- ops[order(ops$label), ]
    ops$label <- factor(ops$label, levels = rev(unique(ops$label)))
    ops$hover_text <- paste0(as.character(ops$label), "<br>",
      format(ops$start, "%Y-%m-%d"), " \u2192 ", format(ops$end, "%Y-%m-%d"), "<br>", ops$deploymentComments)

    # A camera with more than one row here had at least one recorded gap
    # (build_camera_operation_export() split it) \u2014 colored differently so
    # a camera that lost operational time stands out at a glance, without
    # needing to read every bar's hover text. "Marked \"Do not use\""
    # (QA/QC) takes priority over a recorded gap, matching the camera
    # status map's own worst-first logic and color scheme.
    period_counts <- table(ops$locationID)
    ops$had_gap <- period_counts[ops$locationID] > 1
    excluded <- rv$camera_decisions
    excluded_ids <- if (!is.null(excluded) && nrow(excluded) > 0) {
      trimws(as.character(excluded$site_id[excluded$use_status == "Do not use"]))
    } else character(0)
    ops$status <- ifelse(trimws(as.character(ops$locationID)) %in% excluded_ids, "Marked \"Do not use\"",
                   ifelse(ops$had_gap, "Had a recorded gap", "Continuous"))
    color_map <- c("Continuous" = "#3D6B4A", "Had a recorded gap" = "#B8862E", "Marked \"Do not use\"" = "#8C3527")

    plotly::plot_ly(data = ops) %>%
      plotly::add_segments(x = ~start, xend = ~end, y = ~label, yend = ~label,
                            color = ~status, colors = color_map,
                            line = list(width = 10), showlegend = TRUE, legendgroup = ~status,
                            text = ~hover_text, hoverinfo = "text") %>%
      plotly::add_markers(x = ~start, y = ~label, color = ~status, colors = color_map,
                           marker = list(size = 8, line = list(color = "white", width = 1)),
                           showlegend = FALSE, legendgroup = ~status,
                           text = ~hover_text, hoverinfo = "text") %>%
      plotly::add_markers(x = ~end, y = ~label, color = ~status, colors = color_map,
                           marker = list(size = 8, line = list(color = "white", width = 1)),
                           showlegend = FALSE, legendgroup = ~status,
                           text = ~hover_text, hoverinfo = "text") %>%
      plotly::layout(
        title = list(text = paste0("Camera operation timeline",
                       if (!is.null(input$effort_filter_block) && input$effort_filter_block != "All")
                         paste0(" \u2014 Block: ", input$effort_filter_block) else ""),
                     font = list(size = 14)),
        xaxis = list(title = ""), yaxis = list(title = ""),
        margin = list(l = 140, t = 50), legend = list(orientation = "h", y = -0.1))
  })

  output$camera_loss_map_title <- renderText({
    if (!is.null(input$effort_filter_block) && input$effort_filter_block != "All") {
      paste0("Camera status map \u2014 Block: ", input$effort_filter_block)
    } else {
      "Camera status map"
    }
  })

  # Full placement status for EVERY camera in the deployment sheet \u2014
  # shared by the map (filtered to on_map == TRUE) and the diagnostic
  # table below (shown as-is, unfiltered), so the two can never disagree
  # with each other about what happened to any given camera. Built after
  # three earlier narrower fixes in a row each missed the real cause for
  # this specific case \u2014 a fragile one-line "here's probably what's
  # wrong" summary kept being wrong in a new way each time, so this
  # computes and exposes the actual state at every stage instead of
  # guessing which stage to summarize.
  camera_placement_status <- reactive({
    req(rv$deployment_data)
    full_d <- rv$deployment_data
    is_valid_coord <- function(lat, long) !is.na(lat) & !is.na(long) & !(lat == 0 & long == 0)

    all_cams <- unique(full_d[c("site_id", "ct_id", "station_folder", "block", "lat", "long")])
    all_cams$site_id <- trimws(as.character(all_cams$site_id))
    all_cams$ct_id   <- trimws(as.character(all_cams$ct_id))

    block_filter <- input$effort_filter_block
    if (!is.null(block_filter) && block_filter != "All" && "block" %in% names(full_d)) {
      # Station-level, not row-by-row \u2014 see the map below for why.
      matching_stations <- unique(full_d$station_folder[!is.na(full_d$block) & full_d$block == block_filter])
      all_cams$passes_block_filter <- all_cams$station_folder %in% matching_stations
    } else {
      all_cams$passes_block_filter <- TRUE
    }

    # Backfill computed from ALL cameras, regardless of block filter \u2014
    # the filter should only decide what's ultimately SHOWN, not limit
    # which rows are allowed to donate a coordinate to their pair.
    backfill_by <- function(df, group_col) {
      valid_rows <- df[is_valid_coord(df$lat, df$long), ]
      groups <- valid_rows[[group_col]]
      g_lat  <- setNames(valid_rows$lat[!duplicated(groups)],  groups[!duplicated(groups)])
      g_long <- setNames(valid_rows$long[!duplicated(groups)], groups[!duplicated(groups)])
      needs <- !is_valid_coord(df$lat, df$long)
      if (any(needs)) {
        f_lat  <- g_lat[df[[group_col]][needs]]
        f_long <- g_long[df[[group_col]][needs]]
        df$lat[needs]  <- ifelse(!is.na(f_lat),  unname(f_lat),  df$lat[needs])
        df$long[needs] <- ifelse(!is.na(f_long), unname(f_long), df$long[needs])
      }
      df
    }
    all_cams$had_own_coords <- is_valid_coord(all_cams$lat, all_cams$long)
    all_cams <- backfill_by(all_cams, "station_folder")
    all_cams$site_prefix <- sub("[A-Za-z]+$", "", all_cams$site_id)
    all_cams <- backfill_by(all_cams, "site_prefix")
    all_cams$site_prefix <- NULL

    all_cams$has_coords_now <- is_valid_coord(all_cams$lat, all_cams$long)
    all_cams$on_map <- all_cams$passes_block_filter & all_cams$has_coords_now
    all_cams
  })

  output$camera_placement_diagnostic_table <- renderDT({
    status <- camera_placement_status()
    display <- data.frame(
      Camera           = status$site_id,
      Station          = status$station_folder,
      Block            = status$block,
      `Had coordinates on its own row` = ifelse(status$had_own_coords, "Yes", "No"),
      `Has coordinates now (after checking paired cameras)` = ifelse(status$has_coords_now, "Yes", "No"),
      Latitude         = round(status$lat, 6),
      Longitude        = round(status$long, 6),
      `Passes current block filter` = ifelse(status$passes_block_filter, "Yes", "No"),
      `Shown on map` = ifelse(status$on_map, "Yes", "No"),
      check.names = FALSE
    )
    datatable(display, options = list(pageLength = 15, order = list(list(8, "asc"))), rownames = FALSE) %>%
      formatStyle("Shown on map", target = "row",
                  backgroundColor = styleEqual(c("Yes", "No"), c("#FFFFFF", "#F8E9E6")))
  })

  output$camera_loss_map <- renderLeaflet({
    use_gis <- identical(input$effort_map_basemap, "gis") && !is.null(rv$gis_layers) && length(rv$gis_layers) > 0
    # preferCanvas = TRUE: required for leaflet-image (the library behind
    # this map's PNG download, replacing html2canvas) to actually
    # capture markers/polygons at all \u2014 by default leaflet draws them as
    # SVG, which leaflet-image explicitly cannot rasterize.
    base_map <- leaflet(options = leafletOptions(preferCanvas = TRUE))
    m <- if (use_gis) base_map %>% addProviderTiles("Esri.WorldGrayCanvas") else base_map %>% addProviderTiles("Esri.WorldImagery")
    if (use_gis) {
      # Blues/purples, deliberately NOT greens/golds/reds \u2014 those are
      # already the camera status legend's own colors (no issues / had a
      # gap / do not use), and reusing them for habitat polygons made the
      # two unrelated color schemes visually indistinguishable from each
      # other on the same map.
      gis_palette <- c("#6B8CAE", "#9B7EBD", "#5C8A99", "#7B6B8C", "#4E7A96")
      layer_names <- names(rv$gis_layers)
      for (i in seq_along(rv$gis_layers)) {
        layer <- tryCatch(sf::st_transform(rv$gis_layers[[i]], 4326), error = function(e) rv$gis_layers[[i]])
        # Color each individual FEATURE (row) by its own name/label
        # attribute, not the whole layer with one color per FILE \u2014 a
        # single uploaded file can contain multiple named polygons (e.g.
        # "Woodland"/"Grassland" both in one GeoJSON), which previously
        # all got the same color and looked like one undifferentiated
        # shape rather than distinct habitat zones.
        label_col <- intersect(c("name", "habitat", "habitat_type", "type", "label", "Name", "NAME", "Habitat"),
                                names(layer))
        feature_labels <- if (length(label_col) > 0) {
          as.character(sf::st_drop_geometry(layer)[[label_col[1]]])
        } else {
          paste0(layer_names[i], " ", seq_len(nrow(layer)))
        }
        unique_labels <- unique(feature_labels)
        feature_colors <- gis_palette[((match(feature_labels, unique_labels) - 1) %% length(gis_palette)) + 1]
        m <- m %>% addPolygons(data = layer, color = feature_colors, fillColor = feature_colors,
                                weight = 1.5, fillOpacity = 0.4, label = feature_labels)
      }
    }
    if (is.null(rv$deployment_data)) return(m %>% setView(lng = 24.7, lat = -21.9, zoom = 6))

    cams <- camera_placement_status()
    cams <- cams[cams$on_map, c("site_id", "ct_id", "station_folder", "lat", "long")]
    if (nrow(cams) == 0) return(m %>% setView(lng = 24.7, lat = -21.9, zoom = 6))

    # Paired (or larger) camera groups at one station now share identical
    # coordinates \u2014 natively, since they ARE at the same physical spot,
    # or via the backfill just above \u2014 which means they'd be plotted at
    # the exact same pixel and completely overlap: the marker drawn last
    # visually hides every other one underneath it entirely, including
    # (this is what the user actually hit) a red "do not use" camera
    # hidden directly behind a green "no issues" one at the same station.
    # Spread into a small, evenly-arranged ring around the real point
    # instead.
    #
    # Grouped by STATION IDENTITY (station_folder), not by exact
    # coordinate equality \u2014 this was the actual remaining gap, found
    # from the diagnostic table: two cameras at one station can each
    # have their OWN, genuinely slightly different GPS reading (a few
    # real meters apart) rather than identical coordinates, so the
    # earlier "only jitter exact duplicates" check never fired for them
    # at all. Their small, real separation stayed exactly as recorded \u2014
    # but that's still many times smaller than the spacing BETWEEN
    # stations, so it read as invisible at the zoomed-out default view
    # regardless of how large the jitter coefficient was tuned.
    #
    # Every camera at a multi-camera station is first re-centered to
    # ONE shared reference point (that station's first camera's own
    # coordinates) before jittering, so the resulting separation is
    # consistent and guaranteed, rather than compounding with whatever
    # small, real GPS difference the cameras might already have had.
    dup_idx <- ave(seq_len(nrow(cams)), cams$station_folder, FUN = seq_along)
    dup_n   <- ave(seq_len(nrow(cams)), cams$station_folder, FUN = length)
    needs_offset <- dup_n > 1
    if (any(needs_offset)) {
      first_in_station <- !duplicated(cams$station_folder)
      center_lat  <- setNames(cams$lat[first_in_station],  cams$station_folder[first_in_station])
      center_long <- setNames(cams$long[first_in_station], cams$station_folder[first_in_station])
      base_lat  <- unname(center_lat[cams$station_folder])
      base_long <- unname(center_long[cams$station_folder])

      unique_stations <- data.frame(lat = unname(center_lat), long = unname(center_long))
      if (nrow(unique_stations) > 1) {
        # Nearest-neighbor distance between distinct STATION centers
        # (Euclidean on lat/long \u2014 a relative-scale proxy, not meant to
        # be a precise ground distance). The offset is set as a healthy
        # fraction of that, so paired cameras separate clearly from each
        # other while staying well within their own station's "personal
        # space," not encroaching toward a neighboring station.
        station_dists <- as.matrix(dist(unique_stations))
        diag(station_dists) <- NA
        nearest_dist <- suppressWarnings(min(apply(station_dists, 1, min, na.rm = TRUE), na.rm = TRUE))
        offset_deg <- if (is.finite(nearest_dist) && nearest_dist > 0) nearest_dist * 0.3 else 0.0008
      } else {
        offset_deg <- 0.0008  # only one distinct station on the whole map: nothing to scale against
      }
      angle <- 2 * pi * (dup_idx[needs_offset] - 1) / dup_n[needs_offset]
      cams$lat[needs_offset]  <- base_lat[needs_offset]  + offset_deg * sin(angle)
      cams$long[needs_offset] <- base_long[needs_offset] + offset_deg * cos(angle)
    }

    # Status per camera, worst-first: excluded (QA/QC "Do not use") beats
    # a recorded gap beats no issues at all \u2014 so a camera with both is
    # shown as excluded, the more serious/actionable status of the two.
    #
    # "Had a gap" is derived from get_operation_periods() (more than one
    # row for the same camera means build_camera_operation_export() split
    # it around a gap) \u2014 the SAME source the timeline above reads, not
    # raw rv$gap_periods directly. Those two can disagree: if a search
    # effort CSV was ever re-uploaded on Load Data, get_operation_periods()
    # prefers it (gaps already "baked in" from whenever it was generated),
    # but rv$gap_periods itself is separate state that upload never
    # touches, so it can still be empty in the current session even
    # though the timeline is correctly showing split bars.
    ops_for_gaps <- get_operation_periods()
    had_gap_ids <- if (!is.null(ops_for_gaps) && nrow(ops_for_gaps) > 0) {
      period_counts_by_cam <- table(ops_for_gaps$locationID)
      names(period_counts_by_cam)[period_counts_by_cam > 1]
    } else character(0)
    excluded <- rv$camera_decisions
    # site_id/ct_id normalized (trimmed, forced to character) on BOTH
    # sides before matching \u2014 ct_id in particular could plausibly be read
    # as numeric from certain deployment sheet formats while
    # rv$camera_decisions always stores it as character (from splitting a
    # dropdown's text value), and %in% doesn't forgive that kind of
    # mismatch even when both values print identically.
    excluded_ids <- if (!is.null(excluded) && nrow(excluded) > 0) {
      do_not_use <- excluded[excluded$use_status == "Do not use", ]
      paste(trimws(as.character(do_not_use$site_id)), trimws(as.character(do_not_use$ct_id)))
    } else character(0)

    cams$key <- paste(trimws(as.character(cams$site_id)), trimws(as.character(cams$ct_id)))
    cams$status <- ifelse(cams$key %in% excluded_ids, "Marked \"Do not use\"",
                    ifelse(trimws(as.character(cams$site_id)) %in% trimws(as.character(had_gap_ids)),
                           "Had a recorded gap", "No issues recorded"))
    color_map <- c("No issues recorded" = "#3D6B4A", "Had a recorded gap" = "#B8862E", "Marked \"Do not use\"" = "#8C3527")
    cams$color <- color_map[cams$status]

    m %>%
      addCircleMarkers(
        data = cams, lng = ~long, lat = ~lat,
        radius = 7, color = ~color, fillColor = ~color, fillOpacity = 0.85, stroke = TRUE, weight = 2,
        label = ~paste0(site_id, " / ", ct_id, " \u2014 ", status),
        labelOptions = labelOptions(noHide = FALSE)
      ) %>%
      addLegend(position = "bottomright", colors = unname(color_map), labels = names(color_map), opacity = 0.9) %>%
      fitBounds(min(cams$long), min(cams$lat), max(cams$long), max(cams$lat))
  })

  observe({
    if (is.null(rv$traptagger_data)) {
      updateSelectInput(session, "viz_species_select", choices = c("(load data first)"))
      updateSelectInput(session, "activity_species_1", choices = c("(load data first)"))
      updateSelectInput(session, "activity_species_2", choices = c("None", "(load data first)"))
      updateSelectInput(session, "occupancy_species", choices = c("(load data first)"))
      return(invisible())
    }
    species_choices <- sort(setdiff(unique(rv$traptagger_data$species), c("None", "Knocked Down")))
    updateSelectInput(session, "viz_species_select", choices = species_choices)
    updateSelectInput(session, "activity_species_1", choices = species_choices)
    updateSelectInput(session, "activity_species_2", choices = c("None", species_choices))
    updateSelectInput(session, "occupancy_species", choices = species_choices)
  })

  observe({
    if (is.null(rv$deployment_data)) {
      updateSelectInput(session, "viz_covariate", choices = c("(load deployment data first)"))
      return(invisible())
    }
    covariate_choices <- intersect(c("habitat", "block", "season"), names(rv$deployment_data))
    if (length(covariate_choices) == 0) covariate_choices <- c("(no covariate columns found)")
    updateSelectInput(session, "viz_covariate", choices = covariate_choices)
  })

  output$species_tab_prereq_status <- renderUI({
    if (is.null(rv$traptagger_data)) return(warn_panel("Upload TrapTagger data first (Load Data tab)."))
    success_bar(paste0(length(unique(rv$traptagger_data$species)), " species available."))
  })
  output$activity_tab_prereq_status <- renderUI({
    if (is.null(rv$traptagger_data)) return(warn_panel("Upload TrapTagger data first (Load Data tab)."))
    success_bar(paste0(length(unique(rv$traptagger_data$species)), " species available."))
  })

  # Total trap-nights per STATION (not per camera \u2014 aggregated up via
  # locationName, since TrapTagger's own detections are station-level,
  # not camera-level, the same granularity mismatch build_enriched_
  # detections() already has to bridge elsewhere). Shared by the RAI plot.
  station_trap_nights <- reactive({
    ops <- get_operation_periods()
    if (is.null(ops) || nrow(ops) == 0) return(NULL)
    starts <- parse_deployment_datetime(ops$deploymentStart)
    ends <- parse_deployment_datetime(ops$deploymentEnd)
    ops$days <- as.numeric(difftime(ends, starts, units = "days"))
    agg <- aggregate(days ~ locationName, data = ops, FUN = sum)
    names(agg) <- c("station_folder", "trap_nights")
    agg
  })

  # Shared by the time plot, space map, and RAI plot \u2014 one species'
  # TrapTagger records collapsed into independent events, using whichever
  # independence threshold is currently set.
  species_tab_events <- reactive({
    species_sel <- input$viz_species_select
    if (is.null(rv$traptagger_data) || is.null(species_sel) || nchar(species_sel) == 0 ||
        grepl("^\\(", species_sel)) {
      return(NULL)
    }
    sp_data <- rv$traptagger_data[rv$traptagger_data$species == species_sel, ]
    threshold <- if (is.null(input$independence_threshold)) 30 else input$independence_threshold
    collapse_to_independent_events(sp_data, threshold)
  })

  output$species_time_plot <- renderPlotly({
    events <- species_tab_events()
    validate(need(!is.null(events) && nrow(events) > 0,
      "No independent events to plot yet \u2014 select a species with TrapTagger data loaded."))

    events$week <- as.Date(cut(as.Date(events$event_start), "week"))
    weekly <- aggregate(station_folder ~ week, data = events, FUN = length)
    names(weekly) <- c("week", "n_events")
    weekly <- weekly[order(weekly$week), ]

    plotly::plot_ly(data = weekly, x = ~week, y = ~n_events, type = "bar",
                     marker = list(color = "#3D6B4A"), hovertemplate = "%{x}<br>%{y} event(s)<extra></extra>") %>%
      plotly::layout(title = list(text = paste0("Captures through time: ", input$viz_species_select), font = list(size = 14)),
                      xaxis = list(title = ""), yaxis = list(title = "Independent events / week"),
                      margin = list(t = 50))
  })

  output$species_space_map_title <- renderText({
    species_sel <- input$viz_species_select
    if (is.null(species_sel) || nchar(species_sel) == 0 || grepl("^\\(", species_sel)) {
      "Captures through space"
    } else {
      paste0("Captures through space: ", species_sel)
    }
  })

  output$species_space_map <- renderLeaflet({
    # preferCanvas = TRUE: see camera_loss_map above for why this is
    # required for the PNG download to actually capture the markers.
    m <- leaflet(options = leafletOptions(preferCanvas = TRUE)) %>% addProviderTiles("Esri.WorldImagery")
    events <- species_tab_events()
    if (is.null(events) || nrow(events) == 0 || is.null(rv$deployment_data)) {
      return(m %>% setView(lng = 24.7, lat = -21.9, zoom = 6))
    }
    counts <- aggregate(event_start ~ station_folder, data = events, FUN = length)
    names(counts) <- c("station_folder", "n_events")
    # Joined by NORMALIZED station name: TrapTagger's own station_folder
    # strips the underscore our own folder naming keeps (e.g. "SiteA01stA"
    # vs "SiteA01st_A") \u2014 the same mismatch handled throughout Processing.
    dep <- unique(rv$deployment_data[c("station_folder", "lat", "long")])
    dep$station_norm <- normalize_station_name(dep$station_folder)
    counts$station_norm <- normalize_station_name(counts$station_folder)
    counts <- merge(counts, dep[c("station_norm", "lat", "long")], by = "station_norm", all.x = TRUE)
    counts <- counts[!is.na(counts$lat) & !is.na(counts$long) & !(counts$lat == 0 & counts$long == 0), ]
    if (nrow(counts) == 0) return(m %>% setView(lng = 24.7, lat = -21.9, zoom = 6))

    m %>%
      addCircleMarkers(data = counts, lng = ~long, lat = ~lat,
        radius = ~pmin(6 + n_events * 2, 24), color = "#1F2E24", fillColor = "#3D6B4A",
        fillOpacity = 0.8, stroke = TRUE, weight = 2,
        label = ~paste0(station_folder, ": ", n_events, " independent event(s)"),
        labelOptions = labelOptions(noHide = FALSE)) %>%
      fitBounds(min(counts$long), min(counts$lat), max(counts$long), max(counts$lat))
  })

  output$rai_covariate_plot <- renderPlotly({
    covariate_col <- input$viz_covariate
    validate(need(!is.null(rv$deployment_data) && !is.null(covariate_col) &&
                  covariate_col %in% names(rv$deployment_data),
                  "Load a deployment sheet with a habitat/block/season column first (Load Data tab)."))
    tn <- station_trap_nights()
    validate(need(!is.null(tn) && nrow(tn) > 0, "No camera operation data available yet."))
    events <- species_tab_events()
    validate(need(!is.null(events), "Select a species with TrapTagger data loaded."))

    counts <- if (nrow(events) > 0) {
      agg <- aggregate(event_start ~ station_folder, data = events, FUN = length)
      names(agg) <- c("station_folder", "n_events")
      agg
    } else {
      data.frame(station_folder = character(0), n_events = integer(0))
    }

    tn$station_norm <- normalize_station_name(tn$station_folder)
    counts$station_norm <- normalize_station_name(counts$station_folder)
    rai_df <- merge(unique(tn[c("station_norm", "trap_nights")]), counts[c("station_norm", "n_events")],
                     by = "station_norm", all.x = TRUE)
    rai_df$n_events[is.na(rai_df$n_events)] <- 0
    rai_df$rai <- ifelse(rai_df$trap_nights > 0, (rai_df$n_events / rai_df$trap_nights) * 100, NA)

    dep_cov <- unique(rv$deployment_data[c("station_folder", covariate_col)])
    names(dep_cov)[2] <- "covariate_value"
    dep_cov$station_norm <- normalize_station_name(dep_cov$station_folder)
    rai_df <- merge(rai_df, dep_cov[c("station_norm", "covariate_value")], by = "station_norm", all.x = TRUE)
    rai_df <- rai_df[!is.na(rai_df$covariate_value) & !is.na(rai_df$rai), ]
    validate(need(nrow(rai_df) > 0, "No matching covariate data to plot yet."))

    plotly::plot_ly(data = rai_df, x = ~covariate_value, y = ~rai, type = "box",
                     boxpoints = "all", jitter = 0.4, pointpos = 0,
                     marker = list(color = "#3D6B4A"), line = list(color = "#1F2E24")) %>%
      plotly::layout(title = list(text = paste0("RAI vs ", covariate_col, ": ", input$viz_species_select), font = list(size = 14)),
                      xaxis = list(title = covariate_col), yaxis = list(title = "RAI (events / 100 trap-nights)"),
                      margin = list(t = 50))
  })

  observe({
    if (is.null(rv$deployment_data)) {
      updateSelectInput(session, "activity_covariate", choices = c("None"))
      return(invisible())
    }
    cov_choices <- c("None", "Month" = "month")
    for (col in c("season", "habitat", "block")) {
      if (col %in% names(rv$deployment_data)) {
        label <- paste0(toupper(substr(col, 1, 1)), substr(col, 2, nchar(col)))
        cov_choices <- c(cov_choices, setNames(col, label))
      }
    }
    updateSelectInput(session, "activity_covariate", choices = cov_choices)
  })

  # Circular kernel density of hour-of-day, wrapped at the 0/24 boundary:
  # the data is tripled (shifted -24h, as-is, +24h) before smoothing,
  # then only the central [0,24) window is kept \u2014 avoids a false
  # drop-off right at midnight that a plain, non-wrapped density would
  # otherwise show. Bandwidth computed from the REAL 24h data first (not
  # letting density() compute "nrd0" itself on the 72h padded data, which
  # inflates the apparent spread ~3x and over-smooths any real peak into
  # near-uniform noise), then applied as a fixed value when smoothing the
  # padded data. nrd0 rather than Sheather-Jones specifically because SJ
  # can error outright on a small/sparse sample, which a species or
  # covariate level with few detections would otherwise hit.
  circular_density <- function(hrs) {
    if (length(hrs) < 2) return(NULL)
    bw_val <- tryCatch(stats::bw.nrd0(hrs), error = function(e) NA)
    if (!is.finite(bw_val) || bw_val <= 0) bw_val <- 1
    padded <- c(hrs - 24, hrs, hrs + 24)
    d <- tryCatch(stats::density(padded, bw = bw_val, from = 0, to = 24, n = 144), error = function(e) NULL)
    if (is.null(d)) return(NULL)
    d$y <- d$y / sum(d$y)
    d
  }

  # A qualitative palette cycling if there are more groups than colors
  # (a habitat covariate could plausibly have more than 2-3 levels, unlike
  # the fixed 2-species comparison this app started with).
  activity_palette <- c("#3D6B4A", "#B8862E", "#8C3527", "#4A6FA5", "#7A4F8C", "#5F8C6B")

  activity_groups_data <- reactive({
    sp1 <- input$activity_species_1
    validate(need(!is.null(rv$traptagger_data) && !is.null(sp1) && nchar(sp1) > 0 && !grepl("^\\(", sp1),
                  "Upload TrapTagger data and select a species first (Load Data tab)."))
    threshold <- if (is.null(input$independence_threshold)) 30 else input$independence_threshold

    covariate_col <- input$activity_covariate
    use_covariate <- !is.null(covariate_col) && covariate_col != "None" && nchar(covariate_col) > 0

    # Each group is hours (numeric, hour-of-day of each independent
    # event) + a label \u2014 built once here, then both plot types (linear,
    # circular) loop over the exact same list below, so a species
    # comparison and a covariate-split comparison are never two separate
    # code paths that could quietly drift apart from each other.
    groups <- list()
    plot_title <- paste0("Activity pattern: ", sp1)
    if (use_covariate) {
      sp_data <- rv$traptagger_data[rv$traptagger_data$species == sp1, ]
      events <- collapse_to_independent_events(sp_data, threshold)
      validate(need(nrow(events) > 0, paste0("No independent events found for ", sp1, ".")))

      if (identical(covariate_col, "month")) {
        events$covariate_value <- format(events$event_start, "%B")
      } else {
        validate(need(!is.null(rv$deployment_data), "Load a deployment sheet first (Load Data tab)."))
        dep_cov <- unique(rv$deployment_data[c("station_folder", covariate_col)])
        names(dep_cov) <- c("station_folder_dep", "covariate_value")
        dep_cov$station_norm <- normalize_station_name(dep_cov$station_folder_dep)
        events$station_norm <- normalize_station_name(events$station_folder)
        events <- merge(events, dep_cov[c("station_norm", "covariate_value")], by = "station_norm", all.x = TRUE)
      }
      events <- events[!is.na(events$covariate_value), ]
      validate(need(nrow(events) > 0, "No matching covariate data to split by yet."))

      for (level in sort(unique(events$covariate_value))) {
        hrs <- events$event_start[events$covariate_value == level]
        hrs <- as.numeric(format(hrs, "%H")) + as.numeric(format(hrs, "%M")) / 60
        groups[[level]] <- hrs
      }
      plot_title <- paste0("Activity pattern: ", sp1, " by ", covariate_col)
    } else {
      get_event_hours <- function(species_name) {
        sp_data <- rv$traptagger_data[rv$traptagger_data$species == species_name, ]
        events <- collapse_to_independent_events(sp_data, threshold)
        if (nrow(events) == 0) return(NULL)
        as.numeric(format(events$event_start, "%H")) + as.numeric(format(events$event_start, "%M")) / 60
      }
      hours1 <- get_event_hours(sp1)
      validate(need(!is.null(hours1), paste0("No independent events found for ", sp1, ".")))
      groups[[sp1]] <- hours1

      sp2 <- input$activity_species_2
      has_sp2 <- !is.null(sp2) && sp2 != "None" && nchar(sp2) > 0 && !grepl("^\\(", sp2)
      if (has_sp2) {
        hours2 <- get_event_hours(sp2)
        if (!is.null(hours2)) {
          groups[[sp2]] <- hours2
          plot_title <- paste0("Activity pattern: ", sp1, " vs ", sp2)
        }
      }
    }
    validate(need(length(groups) > 0, "Not enough independent events to plot."))
    list(groups = groups, plot_title = plot_title)
  })

  output$activity_plot <- renderPlotly({
    gd <- activity_groups_data()
    groups <- gd$groups
    plot_title <- gd$plot_title

    if (identical(input$activity_plot_type, "linear")) {
      breaks <- seq(0, 24, by = 1)
      p <- NULL
      for (i in seq_along(groups)) {
        h <- hist(groups[[i]], breaks = breaks, plot = FALSE)
        color <- activity_palette[((i - 1) %% length(activity_palette)) + 1]
        if (is.null(p)) {
          p <- plotly::plot_ly(x = h$mids, y = h$counts, type = "bar", name = names(groups)[i],
                                marker = list(color = color))
        } else {
          p <- p %>% plotly::add_bars(x = h$mids, y = h$counts, name = names(groups)[i],
                                       marker = list(color = color))
        }
      }
      p %>% plotly::layout(title = list(text = plot_title, font = list(size = 14)),
                            xaxis = list(title = "Hour of day", dtick = 2, range = c(0, 24)),
                            yaxis = list(title = "Independent events"), barmode = "overlay",
                            margin = list(t = 50))
    } else {
      p <- NULL
      any_valid <- FALSE
      for (i in seq_along(groups)) {
        d <- circular_density(groups[[i]])
        if (is.null(d)) next
        any_valid <- TRUE
        color <- activity_palette[((i - 1) %% length(activity_palette)) + 1]
        rgb_vals <- grDevices::col2rgb(color)
        fill_color <- sprintf("rgba(%d,%d,%d,0.3)", rgb_vals[1], rgb_vals[2], rgb_vals[3])
        if (is.null(p)) {
          p <- plotly::plot_ly(type = "scatterpolar", mode = "lines", fill = "toself",
                                r = d$y, theta = d$x * 15, name = names(groups)[i],
                                line = list(color = color), fillcolor = fill_color)
        } else {
          p <- p %>% plotly::add_trace(type = "scatterpolar", mode = "lines", fill = "toself",
                                        r = d$y, theta = d$x * 15, name = names(groups)[i],
                                        line = list(color = color), fillcolor = fill_color)
        }
      }
      validate(need(any_valid, "Not enough independent events to estimate an activity pattern."))

      # 12 ticks at 30° apart = 2 hours apart (360deg / 24hr = 15deg/hr).
      tick_hours <- seq(0, 22, by = 2)
      p %>% plotly::layout(
        title = list(text = plot_title, font = list(size = 14)),
        polar = list(
          angularaxis = list(rotation = 90, direction = "clockwise",
                              tickvals = tick_hours * 15, ticktext = sprintf("%02d:00", tick_hours)),
          radialaxis = list(visible = TRUE, title = "", showticklabels = FALSE, ticks = "")),
        margin = list(t = 50))
    }
  })

  output$activity_overlap_note <- renderUI({
    gd <- activity_groups_data()
    n_groups <- length(gd$groups)
    if (n_groups < 2) return(NULL)
    n_pairs <- n_groups * (n_groups - 1) / 2
    if (n_pairs <= 3) return(NULL)
    # Only shown once there's actually enough going on to need it — a
    # 2-species comparison or a 2-3-level covariate split never hits
    # this, but splitting by month (up to 12 levels, 66 possible pairs)
    # very much does.
    tags$p(class = "small text-muted mb-2",
      paste0(n_groups, " groups \u2192 ", n_pairs, " pairwise comparison(s) below. ",
             "Sorted by \u0394 (highest overlap first) by default \u2014 click any column header to re-sort, ",
             "or use the search box to filter to one group."))
  })

  output$activity_overlap_table <- renderDT({
    gd <- activity_groups_data()
    overlap_df <- compute_activity_overlap_table(gd$groups)
    validate(need(nrow(overlap_df) > 0,
      "Need at least two groups (two species, or a covariate split) to compute an overlap coefficient."))
    display <- overlap_df
    names(display) <- c("Group 1", "Group 2", "n (Group 1)", "n (Group 2)", "\u0394", "Method",
                         "95% CI low", "95% CI high")
    # Search + pagination (not just the bare table) once there's enough
    # to actually need navigating — e.g. a month-level covariate split
    # can produce dozens of pairs. Sorted by Delta descending by
    # default so the most-overlapping pairs surface immediately without
    # scrolling through an arbitrary order; still fully re-sortable by
    # clicking any column header.
    dom <- if (nrow(display) > 8) "ftip" else "t"
    datatable(display, options = list(pageLength = 10, dom = dom, order = list(list(4, "desc"))),
              rownames = FALSE)
  })

  observe({
    if (is.null(rv$traptagger_data)) {
      updateSelectInput(session, "diversity_exclude_species", choices = character(0))
      return(invisible())
    }
    updateSelectInput(session, "diversity_exclude_species", choices = sort(unique(rv$traptagger_data$species)))
  })

  output$diversity_prereq_status <- renderUI({
    if (is.null(rv$traptagger_data)) return(warn_panel("Upload TrapTagger data first (Load Data tab)."))
    success_bar(paste0(length(unique(rv$traptagger_data$species)), " species available."))
  })

  # Shared by the summary stats and the accumulation curve below, so
  # they can't show numbers computed from different underlying data.
  diversity_community_matrix <- reactive({
    req(rv$traptagger_data)
    threshold <- if (is.null(input$independence_threshold)) 30 else input$independence_threshold
    exclude <- input$diversity_exclude_species
    if (is.null(exclude)) exclude <- character(0)
    build_community_matrix(rv$traptagger_data, threshold, exclude)
  })

  output$diversity_summary_ui <- renderUI({
    comm <- diversity_community_matrix()
    validate(need(!is.null(comm) && nrow(comm) > 0 && ncol(comm) > 0,
      "No independent events to summarize yet \u2014 upload TrapTagger data (Load Data tab)."))
    summ <- compute_diversity_summary(comm)
    validate(need(!is.null(summ), "Could not compute a diversity summary for this data."))
    pool_row <- if (!is.null(summ$pool) && nrow(summ$pool) > 0) summ$pool[1, ] else NULL

    tagList(
      tags$div(
        stat_box("Observed richness", summ$observed_richness,
                 paste0(summ$n_stations, " station(s), ", summ$n_events, " independent event(s)")),
        stat_box("Shannon (H')", round(summ$shannon, 2)),
        stat_box("Simpson (1\u2212D)", round(summ$simpson, 2)),
        if (!is.null(pool_row))
          stat_box("Chao estimate", paste0(round(pool_row$chao, 1), " \u00b1 ", round(pool_row$chao.se, 1))),
        if (!is.null(pool_row))
          stat_box("Jackknife1 estimate", paste0(round(pool_row$jack1, 1), " \u00b1 ", round(pool_row$jack1.se, 1)))
      ),
      tags$p(class = "small text-muted mt-2", style = "overflow-wrap: break-word;",
        "Chao/Jackknife1 (via the ",
        tags$code("vegan"),
        " package) estimate the TRUE richness, including species never detected, based on how many species were detected only once or twice. Well above the observed count suggests the survey hasn't yet captured every species present at these stations; close to it suggests it likely has.")
    )
  })

  # Per-station trap-nights, keyed by normalized station name (matching
  # get_station_operation_periods()'s own locationID convention) — the
  # "effort" x-axis option below needs this to pass as specaccum()'s w
  # (weights) argument.
  diversity_station_effort <- reactive({
    station_ops <- get_station_operation_periods()
    # req() alone isn't enough here: get_station_operation_periods()
    # returns a valid-but-EMPTY (0-row) data frame when no deployment
    # sheet is loaded (by design, so other callers can handle it
    # gracefully) — req() only checks for NULL, so that empty result
    # passed straight through into aggregate() on 0 rows, which is
    # exactly what crashed with "no rows to aggregate."
    validate(need(!is.null(station_ops) && nrow(station_ops) > 0,
      "No camera operation data available for trap-night effort \u2014 load a deployment sheet (Processing
       or Load Data tab) first. \"Number of stations\" doesn't need this and works without it."))
    start_dt <- parse_deployment_datetime(station_ops$deploymentStart)
    end_dt   <- parse_deployment_datetime(station_ops$deploymentEnd)
    days <- as.numeric(difftime(end_dt, start_dt, units = "days"))
    agg <- aggregate(days ~ locationID, data = data.frame(locationID = station_ops$locationID, days = days), FUN = sum)
    setNames(agg$days, agg$locationID)
  })

  output$species_accumulation_plot <- renderPlotly({
    comm <- diversity_community_matrix()
    validate(need(!is.null(comm) && nrow(comm) >= 2,
      "Need independent events from at least 2 stations to plot an accumulation curve."))

    use_effort <- identical(input$diversity_accum_xaxis, "effort")
    if (use_effort) {
      # vegan's w (effort weights) argument only works with
      # method = "random"/"collector", NOT "exact" (confirmed directly
      # from the package's own documentation) — so this isn't just a
      # different x-axis label, it's a different underlying method.
      # 100 random permutations (vegan's own default) averaged together
      # gives the same mean richness/effort curve "exact" would give for
      # the unweighted case, just effort-weighted here.
      effort_lookup <- diversity_station_effort()
      w <- unname(effort_lookup[normalize_station_name(rownames(comm))])
      validate(need(!any(is.na(w)),
        "Could not match trap-night data to every station with detections \u2014 try \"Number of stations\"
         instead, or check that search effort / camera downtime gaps are loaded (Processing or Load Data)."))
      sac <- tryCatch(vegan::specaccum(comm, method = "random", w = w, permutations = 100),
                       error = function(e) NULL)
    } else {
      sac <- tryCatch(vegan::specaccum(comm, method = "exact"), error = function(e) NULL)
    }
    validate(need(!is.null(sac), "Could not compute the accumulation curve for this data."))

    x_vals <- if (use_effort) sac$effort else sac$sites
    x_title <- if (use_effort) "Cumulative sampling effort (trap-nights)" else "Number of stations sampled"
    upper <- sac$richness + sac$sd
    lower <- pmax(sac$richness - sac$sd, 0)

    plotly::plot_ly() %>%
      plotly::add_ribbons(x = x_vals, ymin = lower, ymax = upper, name = "\u00b1 SD",
                           fillcolor = "rgba(61,107,74,0.2)", line = list(color = "transparent")) %>%
      plotly::add_lines(x = x_vals, y = sac$richness, name = "Observed richness",
                         line = list(color = "#3D6B4A", width = 2)) %>%
      plotly::layout(
        title = list(text = "Species accumulation curve", font = list(size = 14)),
        xaxis = list(title = x_title),
        yaxis = list(title = "Cumulative species richness"),
        margin = list(t = 50))
  })

  # ---- Occupancy modeling (Analytics tab) ----------------------------------

  output$occupancy_prereq_status <- renderUI({
    if (is.null(rv$traptagger_data)) return(warn_panel("Upload TrapTagger data first (Load Data tab)."))
    if (is.null(rv$deployment_data))
      return(warn_panel("Upload a deployment sheet first (Load Data tab) \u2014 needed for station
                          operation periods and site covariates."))
    success_bar(paste0(length(unique(rv$traptagger_data$species)), " species available."))
  })

  output$occupancy_psi_covariates_ui <- renderUI({
    choices <- c("Block" = "block", "Season" = "season", "Paired station" = "paired",
                 "Latitude" = "latitude", "Longitude" = "longitude")
    if (!is.null(rv$gis_layers) && length(rv$gis_layers) > 0) {
      choices <- c("Habitat (GIS layer)" = "habitat", choices)
    }
    checkboxGroupInput("occupancy_psi_covariates", "Occupancy (\u03c8) covariates", choices = choices)
  })

  # Daily (NA/0/1) station-level detection matrix for the selected species,
  # the same building block dl_species_occ already uses \u2014 kept as its own
  # reactive since both the occasion-collapse step below and (potentially)
  # future features need this same intermediate result.
  occupancy_daily_matrix <- reactive({
    station_ops <- get_station_operation_periods()
    validate(need(!is.null(station_ops) && nrow(station_ops) > 0,
      "No camera operation data available \u2014 load a deployment sheet (Processing or Load Data tab)."))
    enriched <- get_enriched_detections()
    sp <- input$occupancy_species
    validate(need(!is.null(enriched) && !is.null(sp) && nchar(sp) > 0 && !grepl("^\\(", sp),
      "Select a species to model."))
    det <- enriched[enriched$species == sp & !is.na(enriched$timestamp), ]
    det_by_day <- if (nrow(det) > 0)
      data.frame(cameraID = normalize_station_name(det$station_folder), Date = as.Date(det$timestamp))
    else NULL
    build_camera_day_matrix(station_ops, det_by_day)
  })

  occupancy_occasion_data <- reactive({
    daily <- occupancy_daily_matrix()
    occ_len <- input$occupancy_occasion_length
    validate(need(!is.null(occ_len) && !is.na(occ_len) && occ_len >= 1,
      "Occasion length must be at least 1 day."))
    result <- build_occupancy_occasion_matrix(daily, occ_len)
    validate(need(!is.null(result), "Could not build occasion-level detection history from this data."))
    result
  })

  occupancy_site_covs <- reactive({
    station_ops <- get_station_operation_periods()
    build_occupancy_site_covariates(station_ops, rv$deployment_data, rv$gis_layers)
  })

  # Gated behind the "Fit model" button rather than an automatic reactive:
  # fitting plus the goodness-of-fit bootstrap below can take a few seconds,
  # so re-fitting on every covariate checkbox click (before the person has
  # finished choosing a model) would be wasted, confusing work.
  occupancy_fit_result <- eventReactive(input$btn_fit_occupancy, {
    occ_data <- occupancy_occasion_data()
    site_covs <- occupancy_site_covs()
    validate(need(!is.null(site_covs) && nrow(site_covs) > 0,
      "No site covariates available \u2014 load a deployment sheet first (Load Data tab)."))

    obs_covs <- list()
    if ("effort" %in% input$occupancy_p_covariates) obs_covs$effort <- occ_data$effort
    if ("occasion_num" %in% input$occupancy_p_covariates) {
      occasion_num_mat <- matrix(rep(seq_len(occ_data$n_occasions), each = nrow(occ_data$y)),
                                  nrow = nrow(occ_data$y))
      dimnames(occasion_num_mat) <- dimnames(occ_data$y)
      obs_covs$occasion_num <- occasion_num_mat
    }
    if (length(obs_covs) == 0) obs_covs <- NULL

    fit_occupancy_model(
      y = occ_data$y,
      site_covs = site_covs,
      obs_covs = obs_covs,
      occ_covariates = input$occupancy_psi_covariates,
      det_covariates = input$occupancy_p_covariates
    )
  })

  # Depends on occupancy_fit_result(), an eventReactive already gated behind
  # the button \u2014 this bootstrap only re-runs when that upstream result
  # actually changes (a new "Fit model" click), not on every input change.
  occupancy_gof_result <- reactive({
    fit_result <- occupancy_fit_result()
    validate(need(is.null(fit_result$error), fit_result$error))
    run_occupancy_gof(fit_result$fit, nsim = 100)
  })

  output$occupancy_summary_stats_ui <- renderUI({
    fit_result <- occupancy_fit_result()
    if (!is.null(fit_result$error)) return(warn_panel(fit_result$error))
    tagList(
      tags$p(class = "small text-muted mb-2", fit_result$formula_text),
      fluidRow(
        column(3, stat_box("AIC", round(fit_result$aic, 1))),
        column(3, stat_box("Naive occupancy", round(fit_result$naive_occupancy, 3))),
        column(3, stat_box("Model occupancy (\u03c8)", round(fit_result$model_occupancy, 3))),
        column(3, stat_box("Stations / occasions", paste0(fit_result$n_sites, " / ", fit_result$n_occasions)))
      )
    )
  })

  render_occupancy_coef_table <- function(summary_df) {
    validate(need(!is.null(summary_df), "Could not extract this coefficient table from the fitted model."))
    df <- data.frame(Term = rownames(summary_df), summary_df, row.names = NULL, check.names = FALSE)
    num_cols <- setdiff(names(df), "Term")
    datatable(df, options = list(dom = "t", pageLength = 20), rownames = FALSE) %>%
      formatRound(columns = num_cols, digits = 3)
  }

  output$occupancy_state_coef_table <- renderDT({
    fit_result <- occupancy_fit_result()
    validate(need(is.null(fit_result$error), fit_result$error))
    render_occupancy_coef_table(fit_result$state_summary)
  })

  output$occupancy_det_coef_table <- renderDT({
    fit_result <- occupancy_fit_result()
    validate(need(is.null(fit_result$error), fit_result$error))
    render_occupancy_coef_table(fit_result$det_summary)
  })

  output$occupancy_gof_ui <- renderUI({
    gof <- occupancy_gof_result()
    if (!is.null(gof$error)) return(warn_panel(gof$error))
    fit_note <- if (gof$p_value < 0.05)
      "a p-value below 0.05 may indicate poor model fit; consider additional covariates"
    else "no evidence of lack of fit"
    disp_note <- if (gof$c_hat > 1)
      paste0("a c-hat of ", round(gof$c_hat, 2), " suggests some overdispersion; standard errors above may be mildly too narrow")
    else paste0("a c-hat of ", round(gof$c_hat, 2), " is close to 1, with no meaningful overdispersion")
    tagList(
      fluidRow(
        column(4, stat_box("Chi-square", round(gof$chi_square, 2))),
        column(4, stat_box("Bootstrap p-value", round(gof$p_value, 3))),
        column(4, stat_box("c-hat", round(gof$c_hat, 2)))
      ),
      tags$p(class = "small text-muted mt-2",
        paste0("Based on ", gof$nsim, " bootstrap resamples: ", fit_note, "; ", disp_note, "."))
    )
  })

  output$occupancy_psi_map_title <- renderText({
    sp <- input$occupancy_species
    if (is.null(sp) || nchar(sp) == 0 || grepl("^\\(", sp)) "Predicted occupancy by station"
    else paste0("Predicted occupancy by station: ", sp)
  })

  output$occupancy_psi_map <- renderLeaflet({
    # preferCanvas = TRUE: see camera_loss_map above for why this is
    # required for the PNG download to actually capture the markers.
    m <- leaflet(options = leafletOptions(preferCanvas = TRUE)) %>% addProviderTiles("Esri.WorldImagery")
    fit_result <- occupancy_fit_result()
    if (is.null(fit_result) || !is.null(fit_result$error) || is.null(fit_result$site_predictions)) {
      return(m %>% setView(lng = 24.7, lat = -21.9, zoom = 6))
    }
    # fit_result$site_predictions carries locationID + the model's own
    # predicted psi/SE/CI columns, but no coordinates \u2014 those live on
    # the site-covariates table instead, joined back in here.
    site_covs <- occupancy_site_covs()
    preds <- merge(fit_result$site_predictions, site_covs[c("locationID", "latitude", "longitude")],
                    by = "locationID", all.x = TRUE)
    preds <- preds[!is.na(preds$latitude) & !is.na(preds$longitude), ]
    if (nrow(preds) == 0) return(m %>% setView(lng = 24.7, lat = -21.9, zoom = 6))

    # Tan-to-green gradient (not the camera-status map's green/amber/red
    # palette, which means something different there): low occupancy
    # reads as the app's existing goldenrod accent color, high occupancy
    # as its signature green, so this stays visually distinct from other
    # maps' color meanings rather than reusing them for something new.
    # Domain scaled to this fit's OWN range of predicted values, not a
    # fixed 0-1: a species predicted everywhere between (say) 0.02 and
    # 0.14 would otherwise sit in one tiny sliver of a 0-1 gradient and
    # look like one undifferentiated color, hiding real differences
    # between stations. If every station happens to have the identical
    # predicted value, widen the domain slightly so colorNumeric() isn't
    # handed a zero-width range.
    psi_range <- range(preds$Predicted, na.rm = TRUE)
    if (diff(psi_range) == 0) psi_range <- psi_range + c(-0.01, 0.01)
    pal <- colorNumeric(palette = c("#D9CBA3", "#3D6B4A"), domain = psi_range)
    m %>%
      addCircleMarkers(data = preds, lng = ~longitude, lat = ~latitude,
        radius = 10, color = "#1F2E24", weight = 1.5, stroke = TRUE,
        fillColor = ~pal(Predicted), fillOpacity = 0.85,
        label = ~paste0(locationID, ": \u03c8 = ", round(Predicted, 2),
                         " (", round(lower, 2), "\u2013", round(upper, 2), ")"),
        labelOptions = labelOptions(noHide = FALSE)) %>%
      addLegend(position = "bottomright", pal = pal, values = preds$Predicted,
                 title = "Predicted \u03c8", opacity = 0.9) %>%
      fitBounds(min(preds$longitude), min(preds$latitude), max(preds$longitude), max(preds$latitude))
  })

  output$occupancy_site_predictions_table <- renderDT({
    fit_result <- occupancy_fit_result()
    validate(need(is.null(fit_result$error), fit_result$error))
    validate(need(!is.null(fit_result$site_predictions), "No site-level predictions available."))
    df <- fit_result$site_predictions
    names(df) <- c("Station", "Predicted \u03c8", "SE", "Lower 95% CI", "Upper 95% CI")
    datatable(df, options = list(pageLength = 15), rownames = FALSE) %>%
      formatRound(columns = c("Predicted \u03c8", "SE", "Lower 95% CI", "Upper 95% CI"), digits = 3)
  })

  output$dl_occupancy_predictions <- downloadHandler(
    filename = function() {
      species_label <- if (is.null(input$occupancy_species)) "species" else input$occupancy_species
      paste0(build_export_prefix(), "_", gsub("[^A-Za-z0-9]+", "_", species_label),
             "_occupancy_model_", format(Sys.Date(), "%Y%m%d"), ".csv")
    },
    content = function(file) {
      tryCatch({
        fit_result <- occupancy_fit_result()
        if (!is.null(fit_result$error) || is.null(fit_result$site_predictions)) {
          write.csv(data.frame(), file, row.names = FALSE); return(invisible())
        }
        df <- fit_result$site_predictions
        names(df) <- c("locationID", "predicted_psi", "SE", "lower_CI", "upper_CI")
        write.csv(df, file, row.names = FALSE)
        log_action(paste0("Downloaded occupancy model predictions CSV for ", input$occupancy_species, ": ",
                           nrow(df), " station(s), ", fit_result$formula_text))
      }, error = function(e) export_error_csv(file, "Occupancy model predictions", e))
    }
  )

  output$audit_log_count <- renderText({
    paste0(length(rv$audit_log), " entries")
  })

  output$audit_log_entries <- renderUI({
    if (length(rv$audit_log) == 0) {
      tags$p(class = "text-muted", "No actions logged yet.")
    } else {
      tagList(lapply(rev(rv$audit_log), function(e) {
        tags$div(e, style = "border-bottom: 1px solid #eee; padding: 2px 0;")
      }))
    }
  })

}

# =============================================================================
# RUN
# =============================================================================

shinyApp(ui, server)
