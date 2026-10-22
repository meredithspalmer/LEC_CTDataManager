# Camera Trap Data Manager: Step-by-Step User Guide

This is a complete walkthrough for anyone using Camera Trap Data Manager to process a
camera-trap survey, from raw SD card images through final exports and
analysis. It assumes the app is already installed and running. If it isn't
yet, see `README.md` first.

---

## Table of contents

1. [Before you start](#before-you-start)
2. [The app's layout](#the-apps-layout)
3. [Stage 1: Ingest & QA/QC](#stage-1-ingest--qaqc)
4. [Stage 2: Processing](#stage-2-processing)
5. [Stage 3: Visualize & Export](#stage-3-visualize--export)
6. [Stage 4: Analytics](#stage-4-analytics)
7. [Saving and restoring your progress](#saving-and-restoring-your-progress)
8. [Troubleshooting](#troubleshooting)

---

## Before you start

You'll get the most out of this guide if you have on hand:

- **A deployment/retrieval spreadsheet** (.csv or .xlsx), one row per camera,
  with at minimum these columns: `season`, `block`, `cell_id`, `ct_station`,
  `ct_id`. Strongly recommended, if you have them: `lat`, `long`,
  `date_setup`, `time_setup`, `date_retrieved`, `time_retrieved`,
  `date_retrieved_ct`, `time_retrieved_ct`, `ct_station_id`, `ct_loc`. The app
  will still run without the recommended columns, but some features (maps,
  effort calculations) will be limited without them.
- **Your raw camera images**, copied off SD cards onto your computer or an
  external drive, organized in whatever folder structure they came off the
  cards in (the app handles reorganizing them).
- If you're past the identification stage: a **TrapTagger CSV export** (and
  optionally an **ArgusWild Standard Format Export**, if you're using it for
  individual ID work).

Don't have real data yet, or just want to try the app first? The
`Generate Test Data/` folder in this repo has scripts that build a complete,
realistic fake survey for exactly this purpose. Run
`generate_full_test_data.R` and use its output to follow along with this
guide risk-free.

---

## The app's layout

<img width="821" height="207" alt="Screenshot 2026-10-21 at 6 03 26 PM" src="https://github.com/user-attachments/assets/a87c952c-1455-4640-a4a7-58c5d39f96a1" />

Along the top of the app are five tabs, used roughly left to right as a
survey moves through its lifecycle:

- **Overview**: a landing page summarizing what the app does
- **Ingest & QA/QC**: getting raw images organized, backed up, renamed, and
  quality-checked
- **Processing**: importing species identifications and preparing
  individual-ID work
- **Visualize & Export**: maps, charts, and the CSV exports you'll actually
  hand off or archive
- **Analytics**: statistical analyses, including activity patterns,
  diversity, and occupancy modeling

Each tab has its own row of numbered or named sub-steps running along the
top of that page. Work through them left to right within a tab.

---

## Stage 1: Ingest & QA/QC

### 1 · Survey setup

<img width="1268" height="579" alt="Screenshot 2026-10-21 at 6 07 43 PM" src="https://github.com/user-attachments/assets/f4914c55-a444-4960-9b0a-1d4da6e2636e" />

This is where every session starts.

1. **Survey name**: a short identifier used to name your top-level folder
   (letters, numbers, underscores, and hyphens only, no spaces), e.g.
   `LEC_2023_S1_Dry`.
2. **Deployment phase**: used in block-level folder names, e.g.
   `First_deployment`. Folders end up named `{Block}_{deployment phase}`,
   e.g. `NW_First_deployment`.
3. **Deployment & retrieval data**: upload your spreadsheet here. The app
   reads it and shows a preview, along with any missing required or
   recommended columns.
4. If your file stores dates or times as plain text rather than real
   spreadsheet date cells, and they come through looking wrong after upload
   (an odd year, a flipped day/month), use the **Date format** and
   **Time format** dropdowns to tell the app how to read them. This only
   matters for text-stored dates. Real date cells in Excel are read
   correctly either way. Changing the dropdown reprocesses the file
   automatically; no need to re-upload.
5. Once your file looks right, set an **Output location** (or use
   **Browse…** to pick a folder) and click **Create folder structure**. This
   builds the full block/station folder tree your images will go into.

If a camera's SD card gets swapped mid-deployment without fully retrieving
the camera, add an `a`/`b` suffix to that camera's folder manually when you
get back (e.g. `F01C_LEC134a`, `F01C_LEC134b`). The folder structure can't
anticipate this ahead of time, but Image Audit and Rename (steps 2 and 4)
both recognize the convention automatically once it's there.

### 2 · Image audit

<img width="1444" height="504" alt="Screenshot 2026-10-22 at 4 23 56 PM" src="https://github.com/user-attachments/assets/535fbda2-6d0b-4aa1-88ba-e03d868b636a" />

1. Point **Select image folder** at your top-level survey folder, the one
   containing the images you copied off your SD cards.
2. Click **Run image audit**. The app walks every camera folder, counts
   images, and flags anything that needs attention: missing cameras, empty
   folders, unexpected folder names.
3. For any folder that's legitimately empty (camera failed, stolen, etc.),
   record a reason, so that's preserved for anyone reviewing the data later
   rather than just looking like an unexplained gap. This will be saved in
   the folder as a text file for later reference. 

<img width="957" height="556" alt="Screenshot 2026-10-22 at 4 24 14 PM" src="https://github.com/user-attachments/assets/69286e7b-8f50-4635-b022-e64e37cd2a79" />

4. Rerun the image audit after updating the flagged camera folders. 

### 3 · Backup

<img width="1433" height="661" alt="Screenshot 2026-10-22 at 4 32 52 PM" src="https://github.com/user-attachments/assets/e99103b1-6e96-4c6a-ac87-46891e34554b" />

Back up your images before doing anything else to them. Two options:

- **Local/mounted backup**: copies the full survey folder to another drive
  or network location.
- **Synology server backup**: if your organization uses a Synology NAS, this
  uses its File Station API directly. You'll need to log in once per
  session.

Either way, the app shows a progress bar and then a folder/file count
comparison between source and backup, so you can confirm nothing was missed
before moving on.

For the Swiss Server, files will copy to the directory 
`/Research/LEC_Field_Research/CameraTraps/BackupCTData/NAME OF SURVEY`. 

### 4 · Rename images

<img width="1436" height="657" alt="4  Image Rename" src="https://github.com/user-attachments/assets/c24c342a-9f65-4b03-a735-7bbf37fe7368" />

This step consolidates images into a single, consistent naming convention:
`SurveyName_Block_Site_Camera_imgNNNN.ext`. It reuses the folder you picked
in Image Audit, so run that step first. Review the preview table, then
confirm to actually rename files on disk. This is a real, on-disk change,
so the app asks you to confirm before doing it.

### 5 · QA/QC

<img width="1100" height="503" alt="5  QA:QC" src="https://github.com/user-attachments/assets/26df119c-02f1-421f-96fe-cbd1648bd8ee" />

This is the busiest step, with several sub-sections:

1. **EXIF extraction**: pulls the actual timestamp off every image's
   metadata. This is the foundation the rest of QA/QC runs on.
2. **Timestamp check**: compares image timestamps against your deployment
   sheet's setup/retrieval window for that camera, and flags mismatches.
3. **Paired station check**: for A/B paired camera setups, flags cases where
   the two cameras' timestamps don't agree with each other.
4. **Camera health flags**: a consolidated list of cameras with no images, a
   clock issue, or anything flagged in your deployment notes, including
   cameras you've already documented as empty with a reason, so that context
   isn't lost.
5. **Timestamp correction**: for cameras with a known, systematic clock
   error (wrong year, a timezone offset, clock drift), apply a correction.
   The original timestamp is never overwritten; a corrected version is kept
   alongside it.
6. **Cameras to exclude**: for a camera whose timestamp couldn't be
   confidently fixed, mark it "Use" or "Do not use" with an optional note.
   This gets carried through to later exports as its own column, so the
   decision and its reasoning travel with the data.
7. **Coordinate map**: plots every camera's location, so you can spot an
   obviously wrong coordinate (a camera in the ocean, or far from the rest of
   the survey) at a glance.
8. **Export corrected data**: downloads one CSV with a row per photo, showing
   its original and corrected timestamp side by side (nothing is ever overwritten),
   plus each camera's Use/Do-not-use decision and note from the step above.

### How this connects to your TrapTagger upload

This is worth understanding clearly, since it isn't obvious from the app
alone: **a timestamp correction made in this app never changes the actual
image files on disk.** Only the app's own internal record of that photo
changes (and, from there, this exported CSV). When you upload the original
image files to TrapTagger, TrapTagger reads each photo's own, unmodified
EXIF timestamp directly, the same one it always had, correction or not.

In practice, this means:

- **If a camera had a clock error, TrapTagger's own dates for that
  camera's photos will still reflect the original, wrong timestamp**, not
  whatever correction you applied here. TrapTagger has no way to know a
  correction happened in this app at all.
- Treat the exported corrected CSV as **your survey's own permanent
  record of the true timestamps**, kept alongside your data, separate from
  whatever date TrapTagger itself reports for those same photos. This is
  exactly why the export keeps both columns side by side rather than
  replacing one with the other: the app's own record and TrapTagger's
  record will genuinely disagree for any corrected camera, and this file
  is what lets you reconcile the two later if needed.
- **A camera marked "Do not use"** is a signal worth acting on before you
  spend time uploading its images to TrapTagger at all, since its
  timestamps can't be trusted for anything that depends on *when* a photo
  was taken (activity patterns, effort calculations, and similar).
- You don't need to do anything special to protect later steps from this
  mismatch: when you eventually use **Match to local images** (on
  Processing, to link TrapTagger's species results back to your local
  files), that matching deliberately uses each photo's original timestamp,
  the same one TrapTagger saw, specifically so a correction made here
  doesn't cause a mismatch there.

Because of all this, it's worth finishing QA/QC, including timestamp
corrections and Use/Do-not-use decisions, before uploading images to
TrapTagger, rather than after. Nothing breaks if you do it the other way
around, but you'll have already made every judgment call you can from the
data itself, before committing time to having TrapTagger classify photos
whose timestamps (or usability) are already in question.

---

## Stage 2: Processing

### 1 · Import TrapTagger

<img width="1100" height="503" alt="6  TrapTagger" src="https://github.com/user-attachments/assets/52571e00-01ed-4e09-a616-3a4c5eb6c116" />

1. Upload the CSV exported from TrapTagger after species classification is
   done.
2. If any camera was knocked over or otherwise inactive for a stretch during
   the survey, define that gap period here, so it's excluded from effort
   calculations later rather than counted as "operating with zero
   detections."
3. The cross-check section compares TrapTagger's own observed activity per
   station against your deployment sheet's expected window, which is a good
   way to catch a station mismatch before it causes confusing results
   downstream.

**If you applied any timestamp corrections during QA/QC**, see "How this
connects to your TrapTagger upload" at the end of that section before
uploading here. In short: TrapTagger reads each photo's original,
unmodified timestamp directly, not any correction made in this app, so a
corrected camera's dates will still look uncorrected on TrapTagger's side.

If you're returning to this page after working elsewhere in the app, you'll
need to upload the TrapTagger CSV again here. It isn't carried over
automatically between pages within the same session.

### 2 · Focal species export

📷 **SCREENSHOT: the Focal species export tab with a species selected and the matched-image table shown**

Pick the species you want a subset of (typically for individual ID work),
and the app matches each TrapTagger record to its local image file by
station and EXIF timestamp, then exports that matched set for the next step.

### 3 · Import ArgusWild

If you're using ArgusWild for individual identification, upload its Standard
Format Export here. This is optional and only relevant if your workflow
includes individual-level ID (useful for species like leopards, where
individuals are identifiable by spot patterns).

---

## Stage 3: Visualize & Export

### Load Data

📷 **SCREENSHOT: the Load Data tab showing all data sources loaded (green status indicators)**

Each visualization and export needs specific data loaded first, which you
do here: your deployment sheet, search effort / gap data, TrapTagger
detections, ArgusWild individual ID data (optional), and GIS layers
(optional, for habitat/block covariates). Load whatever a given export or
chart needs before switching to that tab, and check its subtitle if you're
not sure what it depends on.

### Exports

📷 **SCREENSHOT: the Exports tab showing the grid of download cards**

Ten ready-to-use CSV exports live here, each a single click once its
required data is loaded on the Load Data tab:

| Export | What it contains |
|---|---|
| Camera stations & coordinates | One row per station: location, metadata |
| Sampling effort summary | Trap-nights per station |
| Photo counts by species | Raw detection counts |
| Species detection data | Full detection records, enriched with station metadata |
| Camera operation matrix | Station-by-day operating matrix (1/0/NA), the camtrapR convention |
| Species captures (occupancy format) | A detection history matrix for a chosen species, ready for occupancy modeling |
| Individual ID data | Per-photo individual ID results, joined from ArgusWild |
| Individuals by block/season/age-sex | Summarized counts of unique individuals |
| SECR input data | Capture data formatted for spatial capture-recapture models |
| Selected deployment metadata | Whichever deployment columns you choose to include |

### Effort

📷 **SCREENSHOT: the Effort tab showing the camera operation timeline (Gantt-style chart) and the camera loss map**

Shows when each camera was actually operating (a Gantt-style timeline),
where cameras were lost or had downtime (an interactive map), and a
diagnostic table of camera placement issues worth reviewing before trusting
your effort calculations.

### Species

📷 **SCREENSHOT: the Species tab with a species selected, showing captures-through-time, captures-through-space, and RAI-vs-covariate plots**

Pick a species to see captures through time, captures through space (a map),
and relative abundance index (RAI) plotted against an environmental
covariate of your choice (habitat, block, season, or whatever your
deployment sheet and GIS layers provide).

---

## Stage 4: Analytics

### Activity

📷 **SCREENSHOT: the Activity tab with two species selected, showing the overlaid activity-pattern plot and the overlap coefficient table below it**

Compares when two species (or two groups split by a covariate) are active
during the day, and computes an overlap coefficient (Δ, from 0 = no overlap
to 1 = identical patterns) using the standard method from Ridout & Linkie
(2009). Useful for questions like whether a predator and its prey, or two
competing species, avoid each other in time.

### Diversity

📷 **SCREENSHOT: the Diversity tab showing the summary statistics and the species accumulation curve**

Community-level summaries across your whole survey: observed richness,
Shannon and Simpson diversity indices, and Chao/Jackknife estimators of true
richness (including species never actually detected). The accumulation
curve shows whether more survey effort would likely turn up more species, or
whether the survey has already captured most of what's there.

### Occupancy

📷 **SCREENSHOT: the Occupancy tab after fitting a model, showing the coefficient tables, goodness-of-fit results, and the predicted-occupancy map**

Fits a single-season occupancy model (via the `unmarked` R package) for a
chosen species:

1. Pick a **species** and an **occasion length** (how many days get grouped
   into one sampling occasion. Shorter means more temporal resolution;
   longer means a better chance of actually detecting the species per
   occasion.
2. Choose which covariates affect **occupancy** (ψ) and which affect
   **detection** (p). Block, season, habitat, paired-station status, survey
   effort, and more are available, depending on what data you've loaded.
3. Click **Fit model**. This can take a few seconds, especially with
   goodness-of-fit testing included.
4. Results include coefficient tables for both sub-models, AIC, a
   goodness-of-fit test (MacKenzie & Bailey 2004), and a map of each
   station's predicted occupancy probability.

---

## Saving and restoring your progress

📷 **SCREENSHOT: the session save confirmation / the "Load session" dialog**

At any point, use **Save session** (in the footer bar, visible on every tab)
to download a single file capturing your entire session: every upload,
setting, and decision made so far. Load it back later with **Load session**
to pick up exactly where you left off, without redoing anything. Starting a
new survey from scratch uses **New project**, which clears everything after
a confirmation prompt.

---

## Troubleshooting

### "Missing required column(s)" when I upload my deployment sheet

Your file is missing one of the five columns the app can't function without:
`season`, `block`, `cell_id`, `ct_station`, `ct_id`. Check your column
headers match these exactly (case and spelling matter). A warning about
missing *recommended* columns (like `lat`/`long`) isn't blocking. The app
will still run, just with some features limited.

### Dates look wrong after uploading my deployment sheet (e.g. a strange year, or day/month swapped)

This happens when dates are stored as plain text in your spreadsheet rather
than real date cells, and the app's default assumption about the format
doesn't match your file. Use the **Date format** dropdown on the Survey
setup tab to specify the actual format (e.g. D/M/YYYY if your dates are
day-first). This reprocesses automatically, no re-upload needed.

### A camera shows a "Timestamp mismatch" flag

Usually means the camera's internal clock was wrong (a common field issue:
battery died and the clock reset, or it was never set to the right year in
the first place). Check the flagged camera's images against its expected
deployment window on the Timestamp check card. If it's a simple, consistent
offset (wrong year, a few hours off for timezone), use **Timestamp
correction** to fix it in bulk rather than per-photo.

### Two cameras at the same station are overlapping on a map and I can't tell them apart

The app automatically offsets markers for paired cameras at the same
physical station so they don't sit exactly on top of each other. If they
still look merged, try zooming in further; the offset is scaled to appear
clearly at typical zoom levels but can still look tight at very wide zoom.

### My TrapTagger station names don't seem to match my deployment sheet

TrapTagger's own station naming convention sometimes drops an underscore
that your deployment sheet keeps (e.g. `SiteA01stA` vs `SiteA01st_A`). The
app normalizes station names internally to handle this automatically in
most places, but if you're seeing records that seem to not match up, double
check the raw values in both files for anything unusual beyond just the
underscore (extra whitespace, a typo, a different case).

### ExifTool failed to install automatically

`install_packages.R` tries to install ExifTool for you automatically, but
if that fails (uncommon, but can happen depending on your system), install
it manually from [exiftool.org](https://exiftool.org). The script prints
step-by-step instructions for your operating system if the automatic
install doesn't work. Once it's installed, no need to re-run anything; the
app finds it automatically the next time it needs it.

### An export or chart says something like "no data available" even though I uploaded my files

Each tab's data is loaded independently per session; uploading your
TrapTagger CSV on the Processing page, for instance, doesn't automatically
make it available on Visualize & Export. Check the **Load Data** tab under
Visualize & Export and make sure everything that specific chart or export
needs is actually loaded there too (its subtitle usually says exactly what
it depends on).

### My occupancy model won't fit, or gives a warning about convergence

Occupancy models need enough detections to estimate occupancy and detection
probability separately. If your chosen species has very few detections, try
a longer occasion length (fewer, bigger time windows mean more chances to
detect the species per occasion), or fewer covariates (a simpler model needs
less data to estimate reliably). A model with many covariates and very
little data is the most common cause of convergence trouble.

### The app seems frozen, or the page never loads even after restarting

This usually means something is still running in the R console behind the
scenes (R runs one thing at a time, so one slow step can make the whole app
feel unresponsive until it finishes). Check your R console/RStudio window
for any ongoing process before assuming something crashed. If it's been
stuck for an unusually long time with no R console activity at all, restart
by closing R and re-running `LAUNCH_APP.R`.

### I don't see an error listed here for something I'm running into

Open an [issue](../../issues) on this repository, describing what you did,
what you expected, and what happened instead, ideally with a screenshot.
That turns a one-off problem into something the next user doesn't have to
hit blind, and is likely to end up as a new entry in this section.
