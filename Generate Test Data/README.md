# Camera Trap Data Manager — Developer Notes

**Status:** UI skeleton — all pages and panels built, no backend logic yet.

---

## File structure

```
CamTrapManager/
├── app.R                         ← Main Shiny app (UI + server)
├── install_packages.R            ← Run once to install all dependencies
├── LAUNCH_APP.R                  ← Double-click launcher for field users
├── generate_full_test_data.R     ← ★ Recommended: one script, tests the whole workflow
├── generate_test_data.R          ← Superseded — dummy images for Image Audit only
├── generate_rename_test_data.R   ← Superseded — sub-folders for Rename only
├── generate_qaqc_test_data.R     ← Superseded — real EXIF images for QA/QC only
└── README.md                     ← This file
```

**Use `generate_full_test_data.R`** — it replaces the three page-specific
scripts below it with one dataset that flows through Image Audit → Rename →
QA/QC in a single run (real EXIF-stamped JPEGs throughout, including inside
sub-folders, rather than page-specific zero-byte dummy files). The three
older scripts are kept for reference but shouldn't be needed going forward.

## For field technicians (zero-setup)

1. Install R from https://cran.r-project.org (one time)
2. Open `install_packages.R` in RStudio → click **Source** (one time)
3. Double-click `LAUNCH_APP.R` to open the app

---

## Design notes

Visual identity is grounded in field-survey/ledger work rather than generic
SaaS styling — limestone-grey background, deep bushveld green, dry-grass
amber for flags. Humanist sans (Public Sans) for UI text; monospace (IBM
Plex Mono) reserved for data values (camera IDs, coordinates, file paths).
Numbered step markers are used only where content is a genuine sequence
(the pipeline itself, and the sub-steps within Ingest).

## Known pitfalls (for future reference)

- **Never wrap a `req()`-containing reactive in a generic `tryCatch`.**
  `req()` signals "not ready yet" to Shiny using a special condition class
  that Shiny's own internals are designed to catch and handle by quietly
  pausing that output/observer. A plain `tryCatch(..., error = function(e) ...)`
  intercepts that same condition and converts it into an ordinary return
  value instead, which can produce strange, hard-to-diagnose behavior once
  combined with `outputOptions(..., suspendWhenHidden = FALSE)` (used for
  `conditionalPanel` server-side conditions) — since that setting forces the
  output to evaluate immediately at session start, before any button is
  clicked. If a reactive depends on data that might not exist yet, check
  `is.null()` explicitly and return an empty/default value instead of using
  `req()` inside anything that's also wrapped in `tryCatch`.
- If the app seems to hang completely (R console shows no prompt, page never
  loads even in a fresh incognito window), that's a real R-level hang, not a
  network/browser/cache issue — since R is single-threaded, one blocking
  reactive can freeze the entire app for every user. Bisect by adding
  `cat("[CHECKPOINT] ...")` lines throughout `server()` and checking which
  one printed last before the freeze.

---

## Build plan

### Page 2 — Ingest & QA/QC
- [x] `2.1` — Deployment file reader (.csv/.xlsx) + column validation + folder structure generator
- [x] `2.2` — Image audit (directory walk, count files, flag empty folders, camera count check, mark-empty workflow)
- [x] `2.3` — Backup: Synology server (real File Station API) + local folder-to-folder, both with progress bar and file/folder verification
- [x] `2.4` — Image renaming (sub-folder consolidation, sequential numbering, leading zeros, camera-brand-agnostic)
- [x] `2.5` — EXIF extraction (`exiftoolr`)
- [x] `2.5` — Timestamp QA (vs deployment sheet, with tolerance)
- [x] `2.5` — Coordinate map (leaflet, hover labels)
- [x] `2.5` — Paired station check (A/B suffix detection)
- [x] `2.5` — Batch timestamp correction
- [x] `2.5` — Camera health flags

### Page 3 — Process
- [x] `3.1` — TrapTagger CSV reader + format detection
- [x] `3.1` — Knocked-over camera flag detection
- [x] `3.1` — Multi-visit site handling
- [x] `3.1` — Manual gap period UI
- [x] `3.2` — Focal species filter + CSV export
- [x] `3.2` — Image copy to ArgusWild folder
- [ ] `3.3` — ArgusWild CSV reader + join to species data

### Page 4 — Visualize & Export
- [ ] All 10 CSV download handlers
- [ ] Effort timeline (plotly gantt)
- [ ] Camera loss map (leaflet)
- [ ] Species time series
- [ ] Species detection map (circles scaled by count)
- [ ] RAI vs covariate plot
- [ ] Activity pattern plot (overlap kernel density)
- [ ] SECR output formatter

---

## Revisit list

- **Root cause found for the ongoing "focal species matching still doesn't
  work" mystery**: `generate_traptagger_test_data.R`'s output path,
  `OUTPUT_FILE <- "traptagger_test_export.csv"`, was a RELATIVE path —
  meaning it wrote wherever R's working directory happened to be at
  runtime, which silently differs between sessions/launch methods
  (RStudio project directory, terminal's current folder, etc.). Two runs
  from two different working directories produce two different files
  with the identical filename in different places — exactly what caused
  the confusion here: console output proved the rewritten script ran
  correctly (444 records, 7 stations, A04st_A/A05st_A correctly skipped),
  but the app's upload summary showed "2168 records · 9 stations · 40
  Knocked Down" — the exact signature of the FIRST, fully-synthetic
  version of this script from an earlier run, sitting somewhere else on
  disk under the same filename and uploaded by mistake.
  Fixed: `OUTPUT_FILE` now writes inside `survey_path` itself
  (`BASE_DIR/SURVEY_NAME/traptagger_test_export.csv`) — an explicit,
  predictable, survey-specific location, not dependent on the working
  directory at all. Updated the "HOW TO USE" instructions to point at
  this exact location and warn about older copies with the same filename
  potentially still existing elsewhere from previous runs.

- **Three UI text requests on Processing** — Survey name/Deployment
  phase inputs there now match Survey Setup's exact label/subtitle/
  placeholder style (`tags$label` + subtitle text, not a generic
  placeholder sentence); "Match to local images"'s info panel simplified
  to "Point to your survey's top-level folder — the same one used in
  Image Audit," matching the concise style used elsewhere for folder
  inputs, rather than the longer explanation of session-independence.

- **Root cause found for "local file not found" on every record**:
  `generate_traptagger_test_data.R` generated its own independently-
  randomized timestamps for "match" stations, assuming they'd coincide
  with whatever timestamps `generate_full_test_data.R` separately, also
  randomly, assigned to the real local images. They never could — two
  independent random processes don't produce matching values by
  themselves. Rewrote the script to read the REAL EXIF timestamp of each
  actual local test image (never inventing new ones for "match"
  stations), guaranteeing genuine matches by construction. Reuses
  `generate_full_test_data.R`'s deployment-reading code verbatim (not
  re-derived) so `site_id`/`camera_folder` compute identically regardless
  of the exact deployment sheet's column set.
  - **Found and fixed a second, deeper issue while doing this**:
    `generate_full_test_data.R` assigns its own special test roles
    (mismatch, empty variants, reconyx, cuddeback, single_subfolder,
    multi_visit) to the first 9 rows of the deployment sheet,
    deterministically, regardless of which station they belong to.
    Traced through the actual row order: this lands on A01, A02, A03,
    A04st_A and A05st_A, each getting at least one camera in a
    non-standard state (shifted timestamps, empty, or deleted) — meaning
    several of the originally-chosen "clean match" stations could never
    have actually produced a clean match. Rebuilt the role assignment
    using only A06/A07/A08/A09 (traced and confirmed entirely "normal")
    for the guaranteed match/knockdown outcomes; A02 and A03 (naturally
    empty anyway) now serve the discrepancy/missing roles that don't need
    real images; A01, A04st_A and A05st_A are deliberately left out of
    the test plan rather than given a misleading guaranteed-outcome
    label — real data and folder handling for reconyx/cuddeback/single-
    subfolder/multi-visit layouts all still work correctly there, just
    without a single promised outcome.
  - Reused `find_suffixed_sibling_folders()`'s logic (read-only
    reimplementation, since this script can't call into app.R directly)
    so multi-visit a/b folders resolve the same way the app itself does.

- **Survey name and deployment phase can now be entered directly on
  Processing** — closing the last gap in "start fresh at Processing
  without visiting Ingest first." `run_exif_extraction()` (needed by
  "Match to local images") and filename construction both need
  `deployment_phase`/`survey_name`, previously only available from Survey
  Setup's own inputs. Checked every Processing handler individually:
  `detect_knockdown_gaps()` and `cross_check_traptagger()` turned out to
  need neither at all (they work directly off `deployment_df`'s
  persistent columns), so only two places actually needed a fix.
  - Survey Setup's `survey_name`/`deployment_phase` inputs can't simply
    be duplicated with the same widget ID on Processing (two DOM elements
    sharing one ID breaks Shiny's reactivity) — so Processing got its own
    separate `process_survey_name`/`process_deployment_phase` inputs on
    the Deployment sheet card instead.
  - Added `get_survey_name()`/`get_deployment_phase()` helpers: the
    single place that decides which value wins — Processing's own entry
    if filled in, otherwise falling back to Survey Setup's — rather than
    duplicating that fallback logic at every call site. `build_export_
    prefix()` and "Match to local images" both now go through these.

- **Focal species export no longer requires having just come from
  Ingest/QA-QC in the same session.** Its matching step needed
  `rv$exif_data`, previously only populated by QA/QC's own "Extract EXIF
  data" button (Page 2.5) — meaning someone starting fresh at Processing
  would hit a dead end. Per direct feedback, chose to re-extract during
  the export step itself (Page 3.2) rather than coupling it to TrapTagger
  import (Page 3.1), since gap detection and the cross-check there don't
  need image data at all — adding a folder input there just for this
  later purpose would have been misplaced.
  - New **"Match to local images"** card/button on Page 3.2, with its own
    "Survey image folder" input (same custom browser as everywhere else).
    If `rv$exif_data` is already loaded (e.g. from QA/QC earlier this
    session), it's reused as-is — no redundant re-extraction. If not,
    clicking the button runs `run_exif_extraction()` on demand, same
    underlying function QA/QC uses, just triggered from a different entry
    point with its own validation (deployment sheet + folder + deployment
    phase all needed, same as QA/QC's own version).
  - This is a genuinely separate step from "Export for ArgusWild" (not
    folded into it) so the match preview works standalone, before
    committing to any file copying.
  - Updated error/caption messages on this page to point to "Match to
    local images" instead of assuming the person visited QA/QC.

- **Focal species export built** (Page 3.2). The real design challenge:
  TrapTagger's CSV only has a remote "Image URL" (an ID, not a local path
  or original filename), so there's no direct link back to the local
  image file — confirmed with the user before building, along with the
  export folder organization.
  - `match_traptagger_to_local_images()` matches each TrapTagger record
    to a local image by station (normalized, same underscore mismatch as
    the cross-check) + EXACT EXIF timestamp — both `read_traptagger_csv()`
    and `extract_exif_datetimes()` parse as UTC consistently, so a
    genuine match lines up exactly; a 2-second tolerance is kept only as
    a rounding safety margin, not because bigger drift is expected.
    Matches on raw `datetime`, never `datetime_corrected` — TrapTagger
    saw the image's original EXIF timestamp at upload time, before any
    in-app corrections existed.
    Requires QA/QC's EXIF extraction to have been run first
    (`rv$exif_data`) — the export button errors clearly if it hasn't.
  - Focal species dropdown populates from `rv$traptagger_data$species`
    (excluding "None"/"Knocked Down", which aren't real species).
  - Preview table shows the match status per record (which local file, or
    "not found") before exporting, so mismatches are visible before
    committing to a copy.
  - **Export organizes images into sub-folders by species** (confirmed
    with the user) — copying preserves the original renamed filename
    unchanged, so station/site/camera info stays fully readable from the
    filename regardless of which species sub-folder it landed in.
    Unmatched records are skipped (counted, not silently dropped) rather
    than erroring the whole export.
  - CSV export includes the matched local path as a column, alongside
    the original TrapTagger fields, filename following the same
    `{survey}_{phase}_focal_species_{date}.csv` pattern as other
    downloads on this page.

- **App renamed**: "CamTrap Manager" → "Camera Trap Data Manager" (full
  name, used on the Overview page and in body text), "CT Data Manager"
  (navbar/brand link specifically, per direct request). Tagline changed
  to "Camera trap data processing pipeline for Leopard Ecology &
  Conservation" (was "...for wildlife monitoring · Botswana Wildlife
  Ecology Program" — also updated a stale comment referencing the old
  organization name elsewhere in the file).
- **Multi-visit handling removed from the Processing page** (per direct
  feedback) — the dedicated "Survey image folder" input, "Detect"
  button, and results table are gone, along with the now-unused
  `detect_multi_visit_cameras()` function and its reactive field.
  **The underlying recognition logic is untouched** — Image Audit,
  Rename, and QA/QC's EXIF extraction still correctly recognize and
  handle a/b multi-visit folders via `resolve_camera_folder_path()`
  and the shared `find_suffixed_sibling_folders()` helper; only the
  standalone detection/browsing UI was removed. Added a matching note to
  the Rename page instead, next to the existing sub-folder-handling note,
  explaining that renaming consolidates the a/b folders. Updated the
  "Create folder structure" note (Survey Setup) to point at Rename
  instead of the now-removed Processing feature.

- **Regression fixed: the multi-visit fix broke "Mark as empty."** When
  fixing `run_image_audit()` for multi-visit cameras, the audit table's
  `path` column was changed to always report `resolved$expected_path`
  (the plain, unsuffixed name) — correct for "Folder missing" rows (where
  it's the same thing anyway), but wrong for already-marked-empty folders
  like `A03A_261empty`, whose REAL path on disk has the "empty" suffix.
  This made "Mark as empty & save reason" try to operate on a path
  (`A03A_261`) that was never real, always failing with "That folder no
  longer exists" — even right after a fresh audit run. `path` now
  reverts to the actual resolved path (`p[1]`) as before; still correct
  for "Folder missing" (identical to `expected_path` in that case, since
  that's what `resolve_camera_folder_path()` returns when nothing is
  found) and for multi-visit rows (which never feed into the
  mark-as-empty flow anyway, since they have real images).

- **Multi-visit handling built** — detects the SOP's SD-card-swap
  convention (a camera swapped mid-deployment without full retrieval
  gets two sibling folders with a trailing letter suffix, e.g.
  "F01C_LEC134a"/"F01C_LEC134b", instead of one plain folder). This isn't
  recorded anywhere in the deployment sheet (no interim-visit date, no
  second SD_ID), so detection works from the folder structure alone —
  `detect_multi_visit_cameras()` checks whether each expected camera
  folder has letter-suffixed siblings instead of (or alongside) the plain
  name. New "Survey image folder" input + "Detect" button on the
  Multi-visit handling card, reusing the same custom folder browser as
  everywhere else. Added a `multi_visit` test role to
  `generate_full_test_data.R` (splits into "...a"/"...b" folders instead
  of the plain one) so this is actually exercisable.
  - **Added a note to "Create folder structure"** (Survey Setup) flagging
    that the technician has to manually add the a/b suffix on retrieval if
    a swap happens — the app has no way to anticipate this ahead of time.
  - **TODO (flagged by the user directly, revisit when deployment data
    generation is reworked)**: this currently detects from the folder
    structure only, since the deployment sheet doesn't capture
    interim-visit information at all. Once the deployment sheet schema is
    reworked, consider capturing this explicitly there (e.g. an
    interim-visit date, or a second SD_ID) so it can be cross-checked
    against the folder structure instead of relying on folder structure
    alone.
  - **RESOLVED — the gap noted below has been fixed.** `resolve_camera_
    folder_path()` (shared by Image Audit, Rename, and QA/QC's EXIF
    extraction) now recognizes letter-suffixed a/b siblings, not just the
    plain name or its "empty" variant. It returns multiple source paths
    plus a stable `expected_path` (the plain name) for consolidation.
    Specifically:
    - `audit_one_folder()` sums image/file counts across both `a`/`b`
      folders; Image Audit shows a distinct **"OK (multi-visit)"** status
      (colored the same as "OK", not flagged) instead of "Folder missing".
    - `find_unexpected_camera_folders()` no longer flags `a`/`b` folders
      as unexpected.
    - `list_camera_images_ordered()` and `plan_camera_rename()` now accept
      multiple source folders — **Rename correctly consolidates both
      `a`/`b` batches into one plain-named folder** (created if it doesn't
      exist yet, source folders removed once emptied by the same
      mechanism sub-folder consolidation already uses), preserving
      chronological order since "a" sorts before "b".
    - `run_exif_extraction()` (QA/QC) now pulls EXIF data from both
      folders too.
    - Extracted a shared `find_suffixed_sibling_folders()` helper so this
      detection logic isn't duplicated between `resolve_camera_folder_
      path()` and `detect_multi_visit_cameras()`.
    - **Added a workflow-ordering note to the Multi-visit handling card
      itself**: detection should run BEFORE Rename, since Rename
      consolidates and removes the a/b folders — nothing is lost either
      way (images consolidate correctly regardless of order), but the
      *record* of which cameras had a swap is lost if checked afterward.
    - Updated `generate_full_test_data.R`'s walkthrough instructions to
      match the corrected behavior.

- **Processing page (Import TrapTagger) rebuilt as stacked, full-width
  sections** for readability, per direct feedback — was a two-column
  layout (5/7 split), now every section is its own full-width card,
  stacked top to bottom: Deployment sheet → TrapTagger classification
  export → Camera downtime gaps → Cross-check against deployment sheet →
  Multi-visit handling → Classification summary (moved to the very
  bottom, as requested). TrapTagger upload and Camera downtime gaps were
  previously bundled into one card — split into two separate full-width
  cards, matching "each section is its own block." No IDs changed, only
  layout — confirmed via the same input/output cross-check used
  throughout this project.

- **TrapTagger cross-check: all rows flagged — two separate causes, only
  one was a bug.**
  1. **Not a bug**: the sample deployment sheet uses placeholder dates
     (`2025-05-07` etc.), while `sample_traptagger_export.csv` is a real
     2023 survey extract — two unrelated datasets, so a year-level
     mismatch is expected here and will resolve once cross-checked
     against a deployment sheet with real, matching dates.
  2. **Real bug, found while checking #1**: `cross_check_traptagger()`
     grouped on the exact (station, setup_datetime, retrieved_datetime)
     combination, so a station with two co-located cameras that have
     even slightly different setup/retrieved dates in the deployment
     sheet (confirmed in the real sample data — station A01st_A's two
     cameras are retrieved 4 days apart) produced two confusing duplicate
     rows for the same station instead of one properly-aggregated row.
     Fixed: now aggregates to one row per station using the min setup and
     max retrieved date across all its cameras — the station's actual
     deployment window, not any one camera's.

- **Four requests addressed**:
  1. **Fixed `info_panel()`/`warn_panel()` text overflow** — the Rename
     settings box (and any other panel with a long unbroken example
     string, like a filename) was overflowing its card. Root cause: a
     Bootstrap flex container (`d-flex align-items-center`) doesn't let
     its text child wrap by default (`min-width: auto` on flex items is a
     well-known CSS gotcha), and even with that fixed, a long token with
     no spaces (like an example filename) won't break on its own. Fixed
     both: `align-items-start` + explicit `min-width: 0` and
     `overflow-wrap: break-word` on the text span, `flex-shrink: 0` on the
     icon so it doesn't get squeezed.
  2. **Corrected CSV now has an explicit `station_folder` column**
     ("SiteA01st_A") — it wasn't captured anywhere before, only
     `cell_id`/`site_id`/`ct_id`, none of which represent the station
     level. Added to `run_exif_extraction()`'s output (it already had
     access to this via `get_camera_folder_table()`, just wasn't keeping
     it) and threaded through `build_corrected_export()`.
  3. **Corrected CSV and classification summary filenames now both
     include survey name AND deployment phase** — the corrected CSV
     previously only had survey name; added deployment phase there too so
     both downloads are actually consistent, not just superficially
     similar. Added a shared `build_export_prefix()` helper
     (`{survey}_{phase}`, or just `{survey}` / `"camtrap"` as fallbacks)
     used by all three download handlers, so this stays consistent by
     construction rather than needing to be kept in sync by hand.
  4. **Classification summary is now two separate downloads**, not one
     with a checkbox: "Download by species" (total records per species,
     collapsed across all stations) and "Download by station × species"
     (the existing breakdown). Two distinct, always-available buttons
     rather than a checkbox + conditional zip bundling — simpler, and the
     user can already get both just by clicking both buttons. Distinct
     filenames (`_by_species_` vs `_by_station_species_`) so downloading
     both never overwrites either one.

- **`station_folder` mismatch with TrapTagger — resolved by normalizing
  the comparison, not by changing our folder naming.** `ct_station_id`'s
  raw value contains an underscore ("A05st_A"), so our
  `station_folder` is `"SiteA05st_A"`. TrapTagger's real "Site Name" has
  no underscore ("SiteA05stA" — confirmed against a real export; its
  site-detection regex, `Site[A-Z][0-9]+st[A-Z]`, has none either). An
  earlier version of this fix stripped the underscore from our own folder
  naming to match TrapTagger — reverted per direct feedback, since that
  would require renaming every folder already created and moves our
  naming away from the deployment sheet's own notation. **Final
  approach**: folder naming keeps the underscore everywhere (unchanged),
  and a new `normalize_station_name()` helper strips it ONLY when
  comparing against TrapTagger data, in `detect_knockdown_gaps()` and
  `cross_check_traptagger()`. Both sides normalize to the same form for
  matching purposes; neither side's actual naming changes.

- **Removed the "No deployment sheet loaded" warning** on the Processing
  page's re-upload card — per direct feedback, most users will already
  have it loaded from Ingest in the same session, so warning by default
  was more alarming than useful. Shows nothing when not loaded (rather
  than a warning), and the green success confirmation when it is. The
  upload field's own label ("Re-upload deployment sheet — only needed if
  not already loaded") stays, since that's the actually-useful guidance.

- **Three Processing-page requests addressed**:
  1. **"Process" tab renamed to "Processing"** (navbar and the Overview
     page's own reference to it, for consistency).
  2. **Deployment sheet can now be re-uploaded directly on the Processing
     page**, without redoing all of Ingest — a new card at the top with a
     status line (loaded or not) and a file upload, reusing the exact same
     `process_deployment_file()` logic Survey Setup uses (auto-detect
     format only; no format picker here, since this is for re-loading a
     file that's already been successfully processed once — if dates come
     through wrong, Survey Setup's fuller validation panel is the right
     place). **Answering the "which data should this be?" question
     directly: the deployment sheet, not the corrected per-image CSV** —
     gap detection and the cross-check both need per-camera metadata
     (setup/retrieval dates, station groupings) that only the deployment
     sheet provides; the corrected CSV is a different shape (one row per
     photo) and isn't usable for either of these purposes.
  3. **Classification summary is now downloadable as a CSV** — not just
     the inline top-10 species shown in the UI, but a full per-station ×
     per-species long-format breakdown (station_folder, species,
     n_records), ready to pivot for further analysis. Includes "None" and
     "Knocked Down" rows as-is rather than arbitrarily excluding them.

- **Page 3.1 (Import TrapTagger) built**: reader, gap periods (manual +
  auto-detect), and a new cross-check section — none of this existed
  before this round, so documenting the design decisions in full:
  - **Real TrapTagger export structure confirmed** (from an actual client
    download, not assumed): exactly 7 columns — Site Name, Latitude,
    Longitude, Timestamp, Species, Sighting Count, Image URL. "Site Name"
    (e.g. "SiteA01stA") is TrapTagger's own **station-level** identifier —
    matches our `station_folder` exactly, NOT an individual CT_Loc, since
    TrapTagger's "Folder" camera-identifier mode can't distinguish which
    camera in a double-camera station produced a given image. This is a
    real, structural limitation of the data, not a simplification on our
    part — flagged clearly wherever it matters.
  - **How TrapTagger registers a knockdown, discovered directly from the
    real data**: there's no separate "gap" field — a knockdown period is
    registered by tagging the affected images' `Species` as
    `"Knocked Down"`. `detect_knockdown_gaps()` finds the min/max timestamp
    of those tags per station. Confirmed against a real example in the
    client's own full export (`SiteD03stA`, 43 images, ~3.5 day gap).
  - **`station_folder` is now a persistent column** on `rv$deployment_data`
    (computed in `add_derived_columns()`), not just a local variable inside
    `get_camera_folder_table()` — it doesn't depend on `deployment_phase`
    (unlike `block_deploy`), so it's available immediately after upload,
    which the new TrapTagger functions need for matching against "Site
    Name". `get_camera_folder_table()` still recomputes it locally too
    (harmless redundancy, left alone for safety).
  - **Because TrapTagger data is station-level, an auto-detected gap
    applies to EVERY camera at that station** (one row per camera,
    conservatively — no way to tell which specific camera was actually
    knocked down from this data). A **manual** gap, by contrast, targets
    one specific camera directly, since it's based on the field team's own
    observation of exactly which physical unit was affected. Both share
    the same `rv$gap_periods` table (`site_id, ct_id, gap_start, gap_end,
    reason, source`), distinguished by the `source` column ("Manual" vs
    "Auto (TrapTagger)").
  - Re-running "Detect gaps from TrapTagger" replaces previously
    auto-detected gaps (matched by site_id+ct_id) rather than duplicating
    them; manual gaps are left untouched.
  - **`cross_check_traptagger()`** compares TrapTagger's own observed
    activity range per station (excluding "Knocked Down" tagged rows, since
    those represent downtime, not real activity) against the deployment
    sheet's setup/retrieval window — same concept as the QA/QC timestamp
    check, but cross-checking TrapTagger's pipeline against ours instead of
    raw EXIF against the deployment sheet. A station with zero non-
    knockdown records is flagged as "not found" — either never uploaded, or
    the camera never captured anything usable.
  - **`sample_traptagger_export.csv`** (in the outputs folder) — a real
    6,363-row extract covering all 10 of our test stations, taken directly
    from the client's actual full export (not fabricated). One realistic
    "Knocked Down" gap was injected into `SiteA05stA` (2023-06-15 →
    2023-06-18) by relabeling real existing rows — chosen because none of
    our 10 test sites had a genuine one in the source file, but the
    mechanism itself is authentic.
  - **Explicitly NOT done yet**: gap periods are captured and displayed,
    but **not yet subtracted from effort/trap-night calculations** — that
    consumption happens on Page 4, which isn't built. Adding a hard
    requirement to the revisit list below so this doesn't get silently
    forgotten when that page is eventually built.
  - **Multi-visit handling** (sites checked multiple times, or camera
    device changes) remains a stub — out of scope for this round, not
    addressed.

- **MUST when Page 4 (effort calculations) is built**: subtract each
  recorded gap period (`rv$gap_periods`) from that camera's effective
  trap-days. This was the explicit reason for capturing gaps now rather
  than treating them as documentation-only.

- **Timestamp correction "camera" scope future-proofed against CT_ID
  reuse**: it previously matched on `CT_ID` alone — if the same physical
  camera unit is ever redeployed under a different site/season (plausible
  for reusable hardware, though not the case in the specific bug reported
  that prompted this), the correction would apply to every row sharing
  that ID, not just the intended one. Fixed to match on a composite
  `site_id|ct_id` value instead. The dropdown now sends this composite
  value directly, with a disambiguating label (e.g. `103 (A09_A)`) only
  when a CT_ID genuinely repeats — the common one-row-per-camera case
  stays a plain, uncluttered label. **This was NOT the cause of the
  originally-reported bug** (confirmed CT_ID 103 appears exactly once in
  that deployment sheet) — that investigation is still open; see below.

- **Open investigation: "+1 Year" on a single camera produced a
  multi-year shift.** Ruled out so far: (1) wrong input value — the audit
  log confirmed exactly `1yr 0mo 0day 0min` was submitted; (2) CT_ID
  collision across multiple rows — confirmed CT_ID 103 appears exactly
  once. Next diagnostic step: get the exact "Photos actually span" dates
  for camera 103 from the Timestamp Check flagged list, both BEFORE and
  AFTER applying the correction — this will show whether the span's
  *length* changed (which would point to stale/duplicate images in that
  camera's folder) or only its *position* shifted by more than one year
  (which would point to a real bug in `apply_timestamp_correction()` or
  `summarize_exif_by_camera()` not yet found by code review alone).

- **All remaining folder pickers converted to the custom browser**
  (Backup source ×2, Backup destination, ArgusWild export folder — the
  last one is UI-only since the export feature itself isn't built yet).
  Generalized `open_folder_browser()` made this a small change per picker.
  Removed all remaining `shinyDirButton`/`shinyDirChoose`/`parseDirPath`
  usage, and the now-fully-dead `build_dir_roots()`/`dir_roots` (the
  `shinyFiles`-specific "roots" list has no equivalent need in the custom
  browser, since it navigates real paths directly).
  **Caught and fixed a real regression while doing this**: the custom
  browser's breadcrumb couldn't reach the filesystem root, meaning
  sibling top-level folders (like `/Volumes`, where macOS mounts network
  shares and external drives — exactly what `build_dir_roots()` used to
  handle) were unreachable once browsing started from Home. Added a
  clickable root ("/") breadcrumb segment on Mac/Linux. **Known remaining
  gap**: on Windows, the browser can't switch to a different drive letter
  than the one currently being browsed — paste the full path (e.g.
  `D:\...`) into the text field directly as a workaround.

- **Rename filename didn't reflect the actual (corrected) folder
  structure**: `plan_camera_rename()` still used `block_season`
  (Block+Season) and never included the station folder at all — left over
  from before the TrapTagger-compatible 5-level hierarchy was built,
  creating a real inconsistency between the folder path and the filename.
  Fixed: the filename now mirrors the folder structure exactly —
  `SurveyName_{Block_Phase}_{Site+StationID}_{CT_Loc}_{CT_ID}_imgNNNN.ext`
  (e.g. `..._NW_First_deployment_SiteA01st_A_A01A_237_img0001.jpg`) — so a
  filename alone is fully traceable back to its folder path. Cell ID is
  still the one thing left out, since the station name already encodes it.
  Updated both callers (`preview_image_rename()`, `run_image_rename()`) and
  the Rename preview table, which now also shows a "Station" column
  alongside the (also-corrected) "Block" column, matching what's actually
  baked into the new filename.

- **Two more requests addressed**:
  1. **"Choose output location" now uses the same custom folder browser**
     as "Select image folder" — paste-path text field + a "Browse…" button
     opening the same click-to-navigate modal (full-row-clickable folders,
     breadcrumb navigation), instead of the old `shinyFiles` tree widget.
     Generalized the browser mechanism to support this: added
     `open_folder_browser(target_input, current_value, title)` and a
     `rv$browse_target_input` field, so "Select this folder" writes back
     to whichever text input opened the modal. Removed the now-unused
     `shinyDirChoose`/`selected_output_dir` wiring entirely. This same
     generalized mechanism is ready to reuse for the other remaining
     `shinyFiles` pickers in the app (Backup, GIS/TrapTagger export) if the
     same complaint comes up there.
  2. **Missing folders now show their expected path** — but per direct
     follow-up feedback, NOT as a column in the main results table (too
     cluttered); instead listed under "Camera count check," below the
     table, right where the "N camera folder(s) not found on disk" warning
     already lives — matching how "unexpected folders" are already listed
     there. Uses the same underlying data (`resolve_camera_folder_path()`
     already returns the expected path even when nothing was found), just
     surfaced in a different, better place.

- **Image Audit "100% Folder missing" diagnosed**: root cause was the user
  selecting the "output location" (the folder chosen during folder
  creation, e.g. `.../Sample Folders`) rather than the survey's OWN folder
  one level inside it (`.../Sample Folders/LEC_2023_S1_Dry`) — an easy mix-
  up since both are chosen via the same folder-browsing flow, just at
  different steps. Confirmed via Deployment phase re-entry (correct) and
  the exact `image_dir_path` value (one level too shallow). Rather than
  leaving this as a one-off explanation, added a proactive check to
  `audit_summary_ui`: if 100% of expected folders come back "Folder
  missing," a specific warning now names the likely cause and suggests the
  exact fix (browse one level deeper to the survey's own folder), instead
  of just showing a wall of "missing" rows with no diagnostic help.

Open design/UX and technical questions raised during development — not
blocking, tracked here so they aren't lost.

- **Camera use/do-not-use decisions now reach a real export**: the QA/QC
  page's "Download corrected CSV" button includes the use/do-not-use
  status and note as columns, joined from `rv$camera_decisions`. Page 4's
  full export (combining this with species classifications, effort, etc.)
  is still a stub — when building it, make sure it incorporates the same
  use/do-not-use + note data rather than treating it as a QA/QC-only
  artifact.

- **UX/UI polish pass**: Current build is functional-first. Once the backend
  is working end to end, worth a dedicated pass on: information density on
  dense pages (Ingest/QA-QC in particular), mobile/tablet responsiveness if
  technicians ever use this on anything other than a laptop, accessibility
  (keyboard focus states, color contrast for the amber/warning color against
  white cards), and empty-state messaging (what a brand-new user sees before
  any data is loaded).

- **Confirmed deployment/retrieval sheet schema** (from `Deployment_Data_Sample.xlsx`):
  - Deployment: `Season`, `Block`, `N_Cam_Per_Station`, `Cell_ID`, `CT_Station`, `CT_ID`,
    `CT Type`, `SD_ID`, `Real Lat`, `Real Long`, `Survey Season`, `Date Setup`, `Time Setup`,
    `Height (cm)`, `Bearing`, `Habitat`, `Attachment`, `Lock`, `Lock_Type`, `Notes_Deployment`
  - Retrieval: `Date_retrieved`, `Time_Retrieved`, `Date_Retrieved_CT`, `Time_Retrieved_CT`,
    `Date_Last_Image`, `Time_Last_Image`, `Notes_Retrieval`
  - Folder hierarchy: `Survey Name / Block_Season / Cell_ID / Site (Cell_ID_CT_Station) / Camera (CT_ID)`
  - The sample file has 287 blank padding rows after 14 real records, and 2 blank-header
    trailing columns — both handled automatically as Excel export artifacts.
  - `Notes_Retrieval` contains inconsistent free text (e.g. "No data found", "SD Full") —
    not auto-parsed yet; carried through as-is.

- **TrapTagger export format**: Need a real example of the TrapTagger
  classification CSV to build the importer — specifically how species,
  datetime, camera/site, and knocked-over-camera flags are represented.

- **Backup — two destination types, built via three iterations**:
  1. First built as plain folder-to-folder copy only (works for USB drives,
     mapped network drives, synced cloud folders) — no credentials needed,
     simplest possible approach.
  2. Learned the real backup server is a Synology NAS ("Swiss Server" /
     Garai_Server, reached via WireGuard VPN to `192.168.13.119`), and
     initially assumed it would be mounted as a normal network drive
     (Windows: map `\\192.168.13.119\`; Mac: `smb://192.168.13.119`) — same
     folder-copy logic would then just work. Also hit (and fixed) folder
     pickers being unable to browse to any mounted-outside-Home location
     (`build_dir_roots()` — still used, adds drive letters on Windows,
     `/Volumes` on Mac, `/media`+`/mnt` on Linux — fixes this for every
     picker in the app, not just backup) and switched backup's path entry
     to plain text fields (paste a path from Finder/Explorer) since the
     interactive picker still wasn't reliable enough for this specific case.
  3. **Turned out the actual access method is different**: the user connects
     via the Synology **DSM web interface** (`https://192.168.13.119:5001/`
     — File Station), not a mounted drive at all. This meant no local
     filesystem path exists for the server side, so backup now has two
     genuinely different modes, selected via a radio button:
     - **Swiss/Khutse server**: real Synology File Station API calls
       (`syno_login`, `syno_folder_exists`, `syno_create_folder`,
       `syno_upload_file`, `syno_list_files_recursive` — see "Synology DSM
       File Station API" helpers) using username/password entered directly
       in the app (never saved/persisted). SSL verification is disabled for
       these calls since it's an internal VPN-only address with a
       self-signed cert, not a publicly-exposed service. A "Test connection"
       button checks login + finds the CameraTraps folder before committing
       to a full backup.
     - **Local folder / USB / cloud-sync folder**: the original plain
       folder-to-folder copy, for anything that genuinely does appear as a
       normal drive.
     Both modes still find-or-create `BackupCTData` and a survey-named
     subfolder inside it. For the server mode specifically, `SYNO_CAMERATRAPS_PATH`
     (`/Research/LEC_Field_Research/CameraTraps`) is checked but never
     auto-created if missing — that path should already exist on the real
     server, so a missing path there almost certainly means the server
     address/login is wrong, and silently creating stray folders on a shared
     team server would be worse than erroring clearly.
  - Not yet implemented for the server API path: recreating the exact same
    survey subfolder *structure* (block/cell/site) during upload — currently
    every file goes into per-directory remote folders created on the fly by
    walking each file's relative path, which should produce the same nested
    structure, but hasn't yet been tested against a real deployment sheet's
    full folder tree (only tested against the mock `generate_test_data.R`
    structure). Worth a dedicated real-server test pass.

- **Server backup made resumable AND session-timeout-resilient, after two
  real failures during testing**: first hit `Could not create folder 'X' ...
  on the server`, partway through a real backup, with earlier folders
  already successfully created.
  1. First fix attempt: made folder creation self-healing (re-check
     existence if `CreateFolder` reports failure, in case of a stale check
     over the VPN). This also made backups resumable — `run_server_backup()`
     lists what's already on the server before uploading and skips anything
     already present, so re-running after a partial failure only sends
     what's missing.
  2. The error recurred with the same folder even after that fix, now
     surfaced with an actual Synology error code (400) thanks to improved
     error capturing. Code 400 in Synology's common error list means
     **"no such account or incorrect password"** — since this happened
     mid-backup rather than at login, the real cause is a **session
     timeout**: a large backup makes many sequential requests (one per file,
     one per folder check) over a VPN tunnel that's documented as the
     bottleneck for this server, easily outlasting DSM's session lifetime.
     Fixed properly with a mutable session object (`syno_new_session`,
     `syno_refresh`, `syno_retry`) threaded through folder creation and file
     upload: any call that fails is retried once after silently
     re-authenticating, so a backup keeps going through a session timeout
     instead of aborting partway through with an opaque auth error.

- **Session/project save-load**: Deliberately NOT building automatic
  session persistence for now — progress lives in the browser session only.
  If this becomes a real pain point once the app is in daily field use
  (e.g. technicians needing to pause a multi-day survey partway through),
  revisit with a proper design (naming, explicit save points, where files
  live) rather than bolting on an automatic background save.

- **Independence threshold default**: Set to 30 minutes as a placeholder
  for the species-event definition on Page 4. Confirm with the ecologist
  what's standard for this survey design.

- **"Run image audit" (and 4 other buttons) did nothing with no error**:
  `req(rv$deployment_data)` as the first line of several button handlers
  meant that if deployment data wasn't loaded (e.g. a fresh session where
  the CSV wasn't re-uploaded yet — sessions aren't persisted, by design),
  the button click silently did nothing at all, with zero feedback. Fixed
  in all five affected handlers (`btn_create_folders`, `btn_audit_images`,
  `btn_mark_empty`, `btn_preview_rename`, `btn_run_rename`) by replacing the
  silent `req()` with an explicit check + `showNotification()`, consistent
  with every other validation in the app. General lesson: `req()` is right
  for gating a *reactive output* that should just stay blank until data
  exists, but wrong for gating an *action button's* response — a button
  click should always produce visible feedback, even when the answer is
  "you need to do X first."

- **Images inside sub-folders (100RECNX, DCIM, etc.) weren't actually being
  renamed** — only loose images sitting directly in the camera folder were.
  Root cause: `list.dirs(path, recursive = FALSE)` in R always includes
  `path` itself in its result, even though `recursive = FALSE` sounds like
  it should return only the immediate children — a well-known R quirk.
  Left unfiltered, this meant the camera folder was silently treated as one
  of its own "sub-folders" in ways that interfered with correctly reaching
  the real ones. Fixed with a new shared helper, `list_real_subfolders()`,
  that explicitly excludes the path itself (compared via `normalizePath()`,
  since `list.dirs()`'s returned paths aren't always textually identical to
  the input even when they refer to the same folder). Used consistently in
  both `list_camera_images_ordered()` and `plan_camera_rename()` — this
  exact quirk is worth checking for in any other spot that calls
  `list.dirs()` with `recursive = FALSE` in the future.

- **Rename preview now shows Block and Site**, not just Camera/old
  name/new name — added directly to `preview_image_rename()`'s output
  columns, per direct feedback that Camera alone wasn't enough context to
  make sense of a large preview table.

- **QA/QC (Page 2.5) design decisions**:
  - EXIF extraction reuses the survey folder from Image Audit
    (`rv$image_audit_base_dir`), same as Rename — one exiftool call per
    camera (batching all its images together) rather than per-image, since
    exiftool's own startup cost dominates for small individual calls.
  - Timestamp/paired-station checks compare against whichever datetime
    column is present — `datetime_corrected` if a batch correction has been
    applied, otherwise the raw extracted `datetime` — so every downstream
    check reflects a correction immediately without needing to re-extract.
  - Batch timestamp correction needed a "which one?" picker that wasn't in
    the original UI scaffold (only the scope *type* — all/block/cell/camera
    — was there, not which specific value); added a dynamically-populated
    `ts_correction_scope_value` selector.
  - Coordinate outlier detection is intentionally light-touch: only flags
    missing/(0,0) coordinates and points statistically far from the rest of
    the survey (robust median+MAD distance, with a ~11km floor so a tightly
    clustered real survey doesn't get spuriously flagged) — the map itself,
    with hover labels, is still the primary tool for visually spotting
    subtler coordinate mistakes, per the original brief.
  - Camera health flags combine three signals: clock drift >24h between
    actual retrieval time and the camera's own internal clock at retrieval,
    any non-empty deployment/retrieval notes, and an Image Audit status of
    missing/empty — deliberately not attempting to detect "only blank
    images" via image content analysis, which would need real pixel data
    (not meaningful against the zero-byte dummy test files this app has
    been tested with so far) and is a reasonable follow-up once real camera
    images are available to test against.

- **Added `BUILD_LABEL`** (top of `app.R`, shown on Page 1 and the navbar
  footer on every page) after several rounds of test results that looked
  suspiciously identical across supposedly-different app/script versions —
  this project hit the exact same stale-file confusion earlier during the
  Synology backup work, and it's worth eliminating the guesswork
  permanently rather than re-diagnosing it each time. **When handing over a
  new `app.R`, always bump `BUILD_LABEL`.**

- **Timestamp check now skips cameras marked empty**: `check_timestamps()`
  now accepts the Image Audit results and excludes any camera with status
  "Empty (documented)" or "Empty (marked, no reason file)" from flagging
  entirely — a documented/known-empty folder having no EXIF data is
  expected, not a problem worth surfacing alongside genuine mismatches.
  These show a distinct "Marked empty (skipped)" status internally but
  don't count toward the flagged total or appear in the flagged list.

- **Two real bugs found from actual console output (not stale files after
  all)**:
  1. **Test cases silently skipped**: four camera folders (237, 133, 204,
     261) had been renamed to `_empty` variants way back during Image
     Audit testing, and the QA/QC test script only checked the plain
     folder name — so it reported them "not found" and skipped them
     entirely. This meant all three deliberately-injected test cases (the
     mismatch camera, the empty camera, and one half of the paired-station
     test) landed on missing folders, while the 10 unaffected "normal"
     cameras succeeded fine — explaining why nothing ever got flagged.
     Fixed with `resolve_and_restore_camera_dir()`, which checks both the
     plain and `_empty` names and restores the folder to its plain name if
     only the `_empty` variant exists.
  2. **Paired-station detection didn't actually check for a real pair**:
     it only checked "does this cell have 2 camera rows," not whether they
     have different station letters. The real data has a cell (`A01`)
     with two cameras that are both labeled station "A" (a backup camera,
     not a paired deployment) — which was getting incorrectly treated as
     an A/B pair instead of the real one (`A04_A`/`A04_B`). This is a real
     bug in the app's `check_paired_stations()`, not just the test script
     — fixed in both places by requiring the two rows to have genuinely
     different station letters, not just any two rows sharing a cell.
  Also confirmed from this same console output: the dates in the chart
  were never actually wrong — the real deployment file genuinely has 2025
  dates, and "Parsed setup dates successfully for 14/14 cameras" showed
  parsing was working correctly all along. My earlier assumption that
  "LEC_2023" in the survey name meant the data should be from 2023 was
  simply incorrect.

- **Coordinate map still showing default view with no markers, even after
  the numeric-coercion fix, and no error logged**: root cause was
  architectural, not data-related. The map was built as a base
  `renderLeaflet()` (static tiles + default view) plus a separate
  `observe()` block that added markers afterward via `leafletProxy()`. This
  is a known Shiny/leaflet gotcha: if that `observe()` block fires (e.g.
  right when the deployment sheet is uploaded on the Survey Setup page)
  before the QA/QC tab has ever been opened, the underlying map widget
  doesn't exist in the page's DOM yet, so the proxy call silently has
  nothing to apply itself to — no error, since the call itself is valid,
  it just updates a widget that isn't there yet. By the time the tab is
  actually opened, the base map renders fresh with no markers, and nothing
  re-triggers the marker-adding logic since its only dependency (the
  deployment data) already changed once, earlier. Fixed by merging
  everything into a single `renderLeaflet()` that builds tiles, markers,
  and the zoom-to-fit bounds all at once, computed fresh every time the
  widget actually renders — eliminating this entire class of bug rather
  than working around one instance of it.

- **Coordinate check rendering nothing**: `lat`/`long` (mapped from "Real
  Lat"/"Real Long") were never explicitly coerced to numeric anywhere —
  the column mapping itself was already correct, but if Excel/CSV returns
  these as text (stray spaces, a formatting quirk, etc.), leaflet silently
  plots nothing at all with no error, exactly matching the reported
  symptom (base map renders fine, zero markers, "no issues found" because
  the outlier-detection logic never got valid numbers to check either).
  Fixed with explicit `as.numeric()` coercion in `add_derived_columns()`,
  plus a new `check_coordinate_plausibility()` — mirroring the date
  plausibility check — that warns if any value failed to parse as a
  number at all, or if a coordinate falls outside the valid range (-90/90
  latitude, -180/180 longitude), shown in the same validation panel as the
  date warnings.

- **Audit log panel was never actually visible, this whole time** — a real,
  longstanding bug, not something that broke recently. `audit_log_ui` was
  defined as a component early in the project but never actually attached
  anywhere in the `ui <- page_navbar(...)` tree, so it silently never
  rendered at all, on any page, in any build. Every time it was referenced
  as a diagnostic tool in this README or in conversation, it was
  describing something the user could never actually see. Fixed by
  wrapping the final `ui` assignment in `tagList(page_navbar(...),
  audit_log_ui)`. **Lesson: defining a UI component as an R variable does
  not mean it's part of the rendered page — it must be explicitly included
  somewhere in the top-level `ui` object.**

- **Folder hierarchy rebuilt for TrapTagger compatibility**, based directly
  on the client's "Trap Tagger Images Processing SOP":
  - New structure: `SurveyName / {Block}_{DeploymentPhase} / Cell_ID /
    Site{CT_Station_ID} / {CT_Loc}_{CT_ID}` — five levels, not four.
  - **"Deployment phase"** is a new manually-typed field on Survey Setup
    (lives under Survey name) — it's not derivable from the deployment
    sheet (no such column exists), so the user types it directly (e.g.
    `First_deployment`). Used to build the block-level folder name (e.g.
    `NW_First_deployment`).
  - The **"Site" folder is the STATION** (`Site` + `CT_Station_ID`, e.g.
    `SiteA01stA`), not the individual camera location as the previous
    (also-corrected-this-project) model assumed. A double-camera
    station's two `CT Loc`s are sibling folders *inside* this Site
    folder. This isn't optional politeness — TrapTagger's own upload tool
    uses a regex (`Site[A-Z][0-9]+st[A-Z]`) to find this exact folder
    pattern when auto-detecting sites during upload; without it,
    TrapTagger's site/camera auto-detection won't work.
  - The **camera folder itself is now `{CT_Loc}_{CT_ID}`** (e.g.
    `A01A_237`), not just the bare CT_ID as before — matches the SOP's
    camera-folder-naming rule exactly.
  - `build_folder_paths()`, `render_folder_tree()`, and
    `get_camera_folder_table()` — the three functions that construct
    every folder path in the app — were rewritten, and `deployment_phase`
    was threaded through every function that calls them (`run_image_audit`,
    `preview_image_rename`, `run_image_rename`, `run_exif_extraction`) and
    all 7 server call sites, each now validating it's entered before
    proceeding.
  - **Fixed the "empty" folder suffix to match the SOP exactly**: the app
    used `_empty` (with underscore) everywhere; the SOP's own example is
    `F01C_LEC152empty` (no underscore). Fixed in
    `resolve_camera_folder_path()`, the "Mark as empty" button handler, and
    `find_unexpected_camera_folders()`.
  - **Not yet implemented**: the SOP's SD-card-swap suffix convention
    (`F01C_LEC134a`, `F01C_LEC134b` for sequential SD cards in the same
    camera during one deployment) has no support anywhere in the app yet —
    flagged as a gap, not silently assumed to work.
  - **All three test-data generator scripts updated to match**:
    `generate_test_data.R` and `generate_rename_test_data.R` discover
    camera folders generically (leaf directories, whatever the actual
    depth), so they only needed the "empty" suffix convention fixed (no
    underscore, matching the SOP). `generate_qaqc_test_data.R` computes
    folder paths itself and needed a real structural fix: added a
    `DEPLOYMENT_PHASE` variable (must match what's typed into the app
    exactly) and new `block_deploy`/`station_folder`/`camera_folder`
    derived columns feeding into the corrected 5-level path.

- **Major correction: Cell/Station/Location naming model** (based on the
  client's actual field data model, confirmed directly against a real
  ~300-row deployment sheet):
  - **Cell ID** (`A07`) = the 5×5km grid. **CT station ID** (`A07st_A`) = a
    station within a cell (max 2 per cell: `st_A`, `st_B`). **CT Loc**
    (`A07A`, `A07B`, `A07C`) = the true per-camera physical location — a
    station can have 1 (single camera) or 2 (co-located double-camera
    pair) CT Locs.
  - `site_id` (used throughout — folders, EXIF matching, QA/QC) now comes
    directly from `CT Loc`, not a synthesized `Cell_ID + "_" + station
    letter`. The old formula collapsed both cameras of a double-camera
    station into the same `site_id`, which was the root cause of the
    `A01_A` "two different cameras, one site" oddity investigated earlier
    in this project — that was misdiagnosed at the time as a stray
    duplicate/backup camera; it was actually the real, intended
    co-located pair.
  - `check_paired_stations()` rebuilt to group by **CT station ID**
    (falling back to cell+block if a file lacks that column), pairing
    stations with exactly 2 distinct CT Locs — not "2 rows in the same
    cell with different station letters," which incorrectly missed true
    pairs and could incorrectly flag two unrelated single-camera stations
    in the same cell as a pair.
  - New `check_station_camera_count()`: cross-checks `N_Cam_Per_Station`'s
    claim against the actual number of CT Locs recorded for that station,
    surfaced in the Paired station check panel. Added because the real
    file has genuine inconsistencies here (e.g. a station labeled "1
    camera" with 2 locations recorded) — worth surfacing rather than
    silently trusting a label that can be wrong.
  - Column matching is now **case- and whitespace-insensitive**
    (`normalize_header()`), and covers the real file's actual headers
    directly (e.g. "CT station" not "CT_Station", "lock" not "Lock",
    "Note Retrieved/Issues" not "Notes_Retrieval", "Date on CT at
    retrieval" not "Date_Retrieved_CT") alongside the original template
    spelling — discovered these mismatches by inspecting a real uploaded
    file directly rather than assuming the original sample schema was
    representative. A canonical list of recommended header names (using
    underscores, e.g. `CT_Station_ID`, `Real_Lat`) was worked out with the
    client for future files, though exact spelling doesn't matter given
    the normalized matching.
  - `generate_qaqc_test_data.R` updated to match: normalized header
    matching, `ct_loc`-based `site_id`, and the corrected
    station-ID-based pairing logic — it was testing the WRONG pairing
    definition before this fix.
  - Survey Setup's preview table and deployment-summary log now reflect
    `ct_loc` (the true site count, not the undercounted station-letter
    combination).

- **Image Audit's folder picker replaced entirely**: the previous fix (a
  paste-path text field alongside the existing `shinyFiles` browse button)
  missed the actual request — the user wanted the *clicking experience*
  itself improved, not just an alternative. `shinyFiles`' tree widget has
  very limited customization hooks (no way to make the folder *name*
  clickable instead of just the tiny expand arrow, no way to remove the
  unclickable file-contents pane). Replaced it with a custom modal folder
  browser: every folder name is a full-width clickable row (hover-
  highlighted), a breadcrumb at the top lets you jump back up several
  levels in one click rather than collapsing one level at a time, and
  nothing but folders are ever shown. Built with `jsonlite::toJSON()` for
  safe path-to-JS-string embedding (already a transitive dependency via
  `shiny` itself, added explicitly to `install_packages.R` for clarity).
  The paste-path text field is kept too, as a fast option for anyone who
  already has the path copied. This same pattern could be extracted and
  reused for the other folder pickers in the app (Backup, output
  location, GIS/TrapTagger export) if the same complaint comes up there.

- **Auto-detect date parsing was too naive**: it silently fell back to
  R's own `as.Date()` default (ISO "%Y-%m-%d"), which produces nonsense
  for other common formats rather than erroring (confirmed directly from
  a user's real file: "5/7/25" → year 5, exactly matching the plausibility
  warning). Fixed by having Auto-detect actually try several common
  candidate formats (ISO, M/D/Y and D/M/Y with both 2- and 4-digit years)
  and use whichever parses the most values into a plausible year — much
  more likely to get manually-entered field data right without the user
  needing to select a format explicitly. **Known limitation, stated
  honestly**: when every date in a column happens to have day ≤ 12 (so
  M/D and D/M are both structurally valid for every row), this heuristic
  can't distinguish them with certainty and defaults to M/D/Y as a
  reasonable convention — if the actual data uses D/M ordering, explicitly
  selecting that format from the dropdown is still the reliable option.

- **Brand title click didn't actually navigate**: the previous fix used a
  raw JS `Shiny.setInputValue('main_nav', 'page_intro')` call, but
  `page_navbar`'s tab switching is driven by Bootstrap's own tab
  framework — poking the underlying Shiny input value directly doesn't
  trigger the actual visual pane switch. Fixed by making the title a real
  `actionLink` and handling it server-side with `updateNavbarPage()`,
  which is the supported, correct mechanism for programmatically switching
  a `page_navbar` tab.
- **"Check timestamps" button now matches "Extract EXIF data"** in size
  and color (`btn-primary`, full size) — it was a small outline button
  before and easy to miss.
- **Corrected CSV filename simplified** to `{survey}_corrected_{date}.csv`
  (dropped the redundant "timestamps" segment).

- **Five more requests addressed**:
  1. **"Export corrected data" moved below "Coordinate check"** on the QA/QC
     page, per direct request.
  2. **Corrected CSV filename now uses date only**, not date+time.
  3. **Survey Setup preview now shows parsed date/time columns**
     (`setup_date`, `setup_time`, `retrieved_date`, `retrieved_time`) so a
     parsing problem is visible immediately after upload, not only later
     during QA/QC.
  4. **Fixed mixed 2-digit/4-digit year dates within the same column**
     (e.g. "5/12/26" alongside "5/12/2026", both genuinely occurring in
     manually-entered data) — R's `%y`/`%Y` format specifiers are each
     strict about width, so a single chosen format could parse one but not
     the other. `excel_serial_to_date()` now automatically retries any
     value that fails to parse with the alternate year width, regardless
     of which format the user selected. Also relabeled the date-format
     dropdown options (e.g. "M/D/YYYY" instead of "MM/DD/YYYY") to make
     clear 1-2 digit month/day values were always handled fine — the
     actual bug was specifically the year width, not digit-padding.
  5. **Rename preview now shows each photo's EXIF timestamp**, so
     chronological order can be visually verified before committing to an
     irreversible rename. Extracted a shared `extract_exif_datetimes()`
     helper (previously duplicated logic inside `run_exif_extraction()`
     alone) so both features share one implementation. Added a note near
     the preview button that this makes the preview take a bit longer for
     large surveys, since it now reads real EXIF data rather than just
     planning filenames.
  6. **Removed the separate "Overview" nav tab** — the page still exists
     and is reachable, but its own tab button is now hidden (CSS-hidden,
     not removed from the underlying tabset) and clicking the "CamTrap
     Manager" title in the navbar switches to it instead, via a small
     inline script setting the `main_nav` input directly.

- **Five QA/QC polish items**:
  1. **Coordinate map marker color** changed from amber (`#B8862E`) to the
     app's dark green (`#1F2E24`) — the amber was hard to read against tan
     satellite imagery.
  2. **Removed "only blank images"** from Camera health flags' subtitle —
     the app can't actually detect blank image *content* yet (no image
     pixel analysis), only presence/absence and folder status, so this
     claim was inaccurate.
  3. **"Cameras to exclude" and "Timestamp correction" now start at the
     same vertical height** — previously both were columns inside one
     shared card with a single top-level title, but only "Cameras to
     exclude" had its own `section_header()` inside its column, pushing
     its actual content down relative to the other column. Split into two
     separate cards side by side, each with its own header at the same
     starting position.
  4. **± Years/Months/Days/Minutes no longer respond to mouse-wheel
     scrolling** — a well-known browser quirk where hovering a
     `type="number"` field and scrolling silently changes its value. Added
     a small global script that blurs any number input on wheel, app-wide,
     so scrolling the page never accidentally changes a correction offset.
  5. **New: "Download corrected CSV"** on the QA/QC page — one row per
     photo, with `datetime_original` and `datetime_corrected` side by side
     (nothing is ever overwritten) plus each camera's Use/Do-not-use status
     and note joined in from "Cameras to exclude" (defaulting to "Use" for
     any camera without a saved decision). This satisfies the revisit-list
     item about getting the use/exclude decision into an actual exported
     file — this IS that export, at least for the QA/QC timestamp data (a
     more complete Page 4 export, combining this with species
     classifications etc., is still a separate future step).

- **Correction now always refreshes diagnostics**: previously, applying a
  correction only auto-refreshed the timestamp/paired-station checks if
  "Check timestamps" had already been clicked at least once beforehand —
  if a correction was applied first (without running the check yet), the
  diagnostics stayed empty until manually re-checked. Removed that
  condition; applying any correction now always recomputes and displays
  both checks immediately, regardless of what's been clicked before.

- **Test data design flaw found via direct user testing**: the "mismatch"
  test camera used a fixed absolute 5-day photo window (2019-01-15 to
  2019-01-20), completely unrelated to the real deployment's ~67-day
  expected window. Applying the exact correct shift moved the *start* into
  alignment, but the *end* remained off by ~62 days — not a bug in the
  correction feature, but a fundamental property of the test data: a
  uniform time-shift can only **translate** a range, never **stretch** a
  5-day span into a 67-day one, so this test case could never be fully
  resolved by any correction, however correct. Fixed by shifting each
  camera's **real** setup/retrieval dates by a whole number of years
  (calendar-aware, via `POSIXlt` — the same mechanism the app's own
  "± Years" field uses) rather than using a fixed short absolute window —
  this preserves the camera's true deployment duration, so applying the
  exact inverse "+N Years" correction in the app now fully resolves both
  the start and end of the mismatch, properly testing that the correction
  feature actually works end-to-end rather than just moving things closer.

- **QA/QC page reordered**: Timestamp check → Paired station check →
  Camera health flags → Timestamp correction → Coordinate check, per
  direct request. All sections are now full-width (rather than paired
  two-up) since the request was specifically about strict top-to-bottom
  ordering, which a 2-column layout can't cleanly express.

- **New: "Cameras to exclude" decision tool**, added inside the Timestamp
  correction card (since that's the natural point a technician gives up
  trying to fix a camera's clock) — pick a camera, mark it "Use" or "Do not
  use," optionally add a note, and it's saved to a running table
  (`rv$camera_decisions`). **Not yet wired into any actual export** — Page
  4's real CSV export is still a stub. Revisit list item added: when that
  export is built, it must include the use/do-not-use status and note as
  columns in the final camera-trap datasheet, which is the whole point of
  capturing this during QA/QC rather than just noting it externally.

- **Four QA/QC usability fixes**:
  1. **Chart hover re-added, but customized** — after removing hover text
     entirely per earlier feedback, it turned out that was too aggressive:
     without it, individual bars couldn't be identified at all when the
     y-axis got dense. Re-added hover, but showing only camera ID + exact
     date range — not the flag name (that stays exclusively in the list
     below, avoiding the original redundancy complaint).
  2. **Chart height increased** (280px → 550px) so more camera rows fit
     without cramping/overlapping labels.
  3. **Camera health flags moved above Timestamp correction** in the page
     layout, per direct request.
  4. **Camera health flags now includes documented-empty cameras, with
     their actual reason text** — previously only `image_audit` statuses
     indicating an *undocumented* problem (missing/needs-review/no-reason)
     were included; a properly documented empty folder (reason recorded via
     the Image Audit "mark as empty" workflow) was invisible here even
     though it's exactly the kind of thing a reviewer needs to see (a
     leopard survey has real technicians recording real reasons — camera
     stolen, SD corrupted, etc. — losing that context defeats the purpose
     of recording it). Added `read_empty_reason_file()`, which reads the
     actual `EMPTY_REASON.txt` content from the folder and shows it as the
     flag reason, rather than just a generic status string.

- **Timestamp correction data model, clarified and fixed**: `datetime` (raw
  EXIF value) is never modified under any code path. `datetime_corrected`
  is created the first time "Apply correction" is clicked, initialized as
  an exact copy of `datetime` for every image — so every camera already
  has a side-by-side original/corrected pair, even ones that never needed
  correcting (no manual duplication needed). Originally, a second
  correction click computed its offset from the current
  `datetime_corrected` value, meaning repeated corrections would compound
  rather than replace — fixed so every correction is now computed fresh
  from the untouched raw `datetime`, always replacing rather than
  stacking, per direct confirmation this is the desired behavior.
  **Revisit later**: this pairing currently only lives in-memory
  (`rv$exif_data`) for the current browser session — once Page 4's actual
  CSV export is built (still a stub), make sure the exported camera-trap
  datasheet includes BOTH `datetime` and `datetime_corrected` columns
  side-by-side, so this record persists beyond the session rather than
  just being visible in-app.

- **Root cause of "0005-07-25" found**: a deployment sheet date like "5/7/25"
  is genuinely ambiguous (May 7 vs July 5), and when a date cell comes
  through as plain TEXT rather than a real Excel date value (common with
  inconsistent manual data entry — the client explicitly noted the source
  files aren't yet standardized), R's default date parser assumes ISO
  format ("%Y-%m-%d") and can silently misparse it into nonsense (reading
  "5" as a 4-digit year) rather than erroring. Fixed two ways:
  1. Added a **date/time format picker** next to the deployment file upload
     (MM/DD/YYYY, DD/MM/YYYY, YYYY-MM-DD, etc.) — this only affects TEXT
     date/time values; real Excel date cells are unambiguous either way and
     parse the same regardless of this setting. Changing the dropdown
     reprocesses the already-uploaded file automatically — no need to
     re-upload.
  2. Added `check_date_plausibility()` — after parsing, checks whether any
     resulting year falls outside a sane range (2000-2100) and surfaces a
     clear warning naming which column and pointing at the format picker,
     rather than letting a nonsense date like year 5 propagate silently
     into every downstream QA/QC check.
  Both the format setting and the plausibility check are general — they
  apply to every date/time column read from the deployment sheet, not just
  the one that surfaced this bug.

- **Two bugs found from first real QA/QC test screenshot**:
  1. **Gantt chart had a confusing diagonal line connecting unrelated
     cameras.** The `plot_ly()` call setting up the chart accidentally
     defined a bogus, malformed initial trace (mapping `x`/`xend` as plain
     scatter-mode aesthetics, which isn't meaningful) that was left in
     alongside the actual `add_segments()` trace that draws the real bars.
     Fixed by removing the leftover initial trace — the chart now has just
     the one correct trace.
  2. **`generate_qaqc_test_data.R`'s fallback window was based on
     `Sys.Date()`**, which drifts every time the script is run on a
     different day. Real symptom seen: nearly every camera showed
     "Timestamp mismatch" against 2025 dates despite the survey being named
     `LEC_2023_S1_Dry`, and the Gantt chart showed two disconnected date
     clusters — consistent with the script having been run more than once
     on different days, each time falling back to a different "last 30
     days from today" window for cameras whose real deployment dates failed
     to parse. Fixed by anchoring the fallback to the deployment sheet's own
     median real date instead of today's date (so it's now deterministic
     across repeated runs), and by adding clear diagnostic printing whenever
     a real date fails to parse or a camera ends up using the fallback —
     this should make it obvious immediately if date-parsing is failing,
     rather than only visible later as a confusing pattern in the app.

- **Image renaming design decisions**: reuses the survey folder already
  selected in Image Audit (`rv$image_audit_base_dir`) rather than adding a
  separate folder picker — enforces running Audit before Rename, which
  matches the natural pipeline order and avoids yet another folder-browse
  step. Leading zeros are always at least 4 digits (e.g. `img0001`), growing
  further only if a camera's actual count exceeds that (e.g. 12000 images →
  5 digits) — changed from an earlier version that used the literal minimum
  digit count needed (so small counts had no padding at all), based on
  direct feedback. The filename convention is
  `SurveyName_Block_Site_Camera_imgNNNN.ext` — `Cell_ID` is deliberately
  **not** included, since `Site` already encodes it (`site_id` = `cell_id`
  + station letter, e.g. `A01_A`), so including both was redundant; the
  physical folder *hierarchy* still has a separate Cell_ID level, since
  that's useful for browsing regardless of filename redundancy — only the
  flat filename was simplified. Sub-folder deletion is deliberately
  conservative: a sub-folder is only deleted once it's completely empty
  after moving its images out; if unexpected leftover files remain (e.g. a
  camera's own metadata file), the sub-folder is left in place and flagged
  in the results table rather than force-deleted, so nothing unexpected is
  silently destroyed.
