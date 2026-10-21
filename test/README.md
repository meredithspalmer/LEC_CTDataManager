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

## Future deployment-sheet schema improvements (field data collection, not app code)

- **Add an explicit, structured field for why a camera/SD card was finally
  removed or collected** (e.g. a dropdown: "Full retrieval" / "SD card
  full" / "Battery dead" / "Camera malfunction" / "Camera lost or stolen"
  / "Knocked down" / "Other \u2014 see notes"), rather than relying on
  free-text `notes_retrieval` alone. The app now surfaces whatever's in
  that free-text field verbatim in the search effort export's
  `deploymentComments` (see Revisit list below), which helps, but a
  structured field would let analyses actually filter/group by retrieval
  reason directly, rather than needing to read prose for every camera.
  Worth folding into whatever comes out of the broader deployment-sheet
  schema rework already flagged elsewhere in this file (multi-visit
  handling).

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
- [x] `3.3` — ArgusWild CSV reader + join to species data

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

- **Addressed #4 from the independent evaluation's prioritized list**: a
  `testthat` suite now exists under `tests/`, covering the ~9 core
  helper functions with the highest actual risk \u2014 either because a real
  bug was found and fixed in them THIS session, or because their logic
  (gap-splitting, interval-merging, NA handling across several related
  fields) is complex enough that a regression could easily slip back in
  silently. Run with `Rscript tests/testthat.R` from the project root
  (needs the `testthat` package \u2014 `install_packages.R` now mentions it
  as an optional, test-only dependency).
  - **Why this structure**: this app is intentionally one file (`app.R`)
    with no separate `R/` package structure, so there's no existing
    package to `library()`-load for testing. `tests/testthat/helper-setup.R`
    sources `app.R` directly instead \u2014 safely, by temporarily replacing
    `shinyApp()` with a no-op for the duration of the source so the file
    loads every function definition without the app actually launching,
    then restores the real `shinyApp()` immediately after.
  - **Covered**: `parse_deployment_datetime()`, `excel_serial_to_date()`,
    `excel_serial_to_time()` (date/time parsing \u2014 the source of a real,
    fixed bug earlier this session); `normalize_station_name()`
    (TrapTagger/deployment-sheet station matching);
    `compute_operational_periods()`, `build_camera_operation_export()`,
    `build_station_operation_periods()` (gap-splitting and the new
    station-level union logic from this session);
    `build_camera_day_matrix()` (including the numeric-cameraID
    regression, another real fixed bug); `collapse_to_independent_events()`
    (including the NA-crash regression, a third real fixed bug);
    `check_coordinate_plausibility()`/`check_date_plausibility()`; and
    `build_enriched_detections()` (the multi-camera `ct_id` logic the
    station-level exports now depend on, plus confirming TrapTagger's own
    `station_folder` is preserved rather than overwritten).
  - **Not covered, worth adding later**: the Shiny reactive/server layer
    itself (would need `shinytest2` or similar, a different kind of test
    than `testthat` alone covers), EXIF/image-file-handling functions
    (need real image fixtures), and the Synology backup API functions
    (need a live or mocked DSM endpoint).

- **Methodological correction, prompted by the user**: "Species captures
  (occupancy format)" and "SECR input data" no longer EXCLUDE records at
  multi-camera (paired) stations \u2014 they're now assigned to the STATION
  as a shared detector instead. The previous behavior (set `ct_id` to
  NA, drop anything that couldn't be pinned to one specific camera) was
  actually wrong for these two exports specifically, not just
  conservative: paired-camera setups are often deliberately there to
  capture BOTH FLANKS of an animal simultaneously for individual ID
  (e.g. leopards), so excluding those records was systematically
  dropping the most valuable data, not an edge case. It's also the
  methodologically correct choice independent of that: occupancy models
  don't care which camera at a station triggered, just whether the
  species was detected there on a given day, and SECR treats two
  co-located detectors as redundant \u2014 never two at the exact same
  point \u2014 so a shared detector at the station was already the standard
  approach for a paired setup, not a workaround for a data limitation.
  - New helper `build_station_operation_periods()`: unions camera-level
    operational windows up to the station level (a station is
    "operating" on a given day if AT LEAST ONE of its cameras was),
    reusing the existing per-camera computation rather than duplicating
    it, then merging overlapping/adjacent intervals per station. Grouped
    by normalized station name throughout (matching the
    `normalize_station_name()` convention already used everywhere else
    in the app for TrapTagger-to-deployment-sheet matching), since
    TrapTagger's own `station_folder` usually drops the underscore the
    deployment sheet keeps.
  - New shared reactive `get_station_operation_periods()`, built on top
    of the existing `get_operation_periods()` so both the re-uploaded-CSV
    and freshly-computed paths get unioned to station level consistently
    rather than duplicating that source-selection logic.
  - **A real bug caught and fixed before it shipped**: SECR's `Detector`
    column was first set to TrapTagger's own raw `station_folder`
    directly \u2014 but "Camera stations & coordinates" (the matching
    trap-location file `secr` also needs) uses the DEPLOYMENT SHEET's
    own `station_folder`, which is often formatted differently (e.g.
    without the underscore the deployment sheet keeps). Using the two
    directly together would have silently failed to match inside
    `secr` itself. Fixed: both exports now relabel through the same
    canonical, deployment-sheet-formatted station name before writing
    the CSV.
  - The exclusion-count warnings added for the independent evaluation's
    #3 item (previous entry below) are repurposed into informational
    notes \u2014 nothing is excluded for this reason anymore, so they now
    simply confirm how many detections of the selected species benefit
    from the station-level combining, rather than warning about data
    loss that no longer happens.
  - `dl_stations` ("Camera stations & coordinates") intentionally stays
    camera-level \u2014 it still serves other purposes (camera operation
    matrix, maps) where per-camera granularity is correct. Its own
    `station_folder` column is still there for building a station-level
    trap-location file from it; card text for SECR now says so
    explicitly.

- **Addressed #3 from the independent evaluation's prioritized list**:
  a visible exclusion-count warning now appears directly on the
  "Species captures (occupancy format)" and "SECR input data" export
  cards, live as the species selection changes \u2014 previously this was
  only logged to the audit log AFTER downloading (and for SECR, not
  even logged there at all). Multi-camera (paired) stations
  have no single camera TrapTagger's own data can unambiguously
  attribute a detection to, so those records are correctly excluded
  from these two specific exports \u2014 but a user had no way to know how
  much of a given species' data was affected until after the fact. Both
  cards now show, before the download even happens, how many
  detections (or individual detections, for SECR) of the currently
  selected species will be excluded for this reason \u2014 says nothing when
  the count is zero, so the warning only appears when it's actually
  relevant. `dl_secr`'s own log message also now reports this count,
  matching the pattern `dl_species_occ` already had.
  - **Remaining items from the independent evaluation**: a `testthat`
    suite for the core helper functions (#4), and the larger
    analysis-layer gaps \u2014 occupancy/SECR model fitting, activity-overlap
    statistics, richness/diversity metrics, REM/REST density estimation,
    full Camtrap DP package export (#5, explicitly framed as a future
    phase rather than an immediate fix) \u2014 are still open.

- **Camera status map: a camera marked "Do not use" on QA/QC wasn't
  showing as red.** Could not fully reproduce or pin down the exact root
  cause from static code review alone \u2014 the save path (QA/QC \u2192
  `rv$camera_decisions`) and the map's lookup both independently checked
  out correct: same `use_status` string ("Do not use"), same
  `site_id`/`ct_id` source (`rv$deployment_data`), matching column names
  throughout. Confirmed via the user's own earlier screenshot that the
  decision WAS saved correctly (site A01A, camera 237, status "Do not
  use" all showing correctly in QA/QC's own table) \u2014 so the save isn't
  the problem, which points at the map's matching logic specifically.
  - The most plausible concrete risk found on review: `%in%` doesn't
    forgive a silent type or whitespace mismatch even when two values
    print identically \u2014 `ct_id` in particular could plausibly be read as
    numeric from certain deployment sheet formats, while
    `rv$camera_decisions` always stores it as character (split from a
    dropdown's text value). Fixed defensively: `site_id`/`ct_id` are now
    trimmed and forced to character on BOTH sides of every comparison on
    this map (the "Do not use" check and the "had a gap" check), closing
    that gap regardless of whether it was the actual cause here.
  - **Root cause confirmed, and it WAS a paired-camera issue**, per the
    user's own follow-up observation: A01A wasn't on the map at all
    (not just the wrong color), while its paired camera A01B was.
    Paired cameras are physically co-located, so deployment sheets
    sometimes only record GPS coordinates on one camera's row at a
    station rather than both \u2014 a camera with missing/zero coordinates
    on its OWN row was being silently dropped from the map entirely,
    even though its paired camera at the exact same physical location
    had perfectly good coordinates recorded right there in the same
    file. Fixed: a camera missing coordinates now borrows them from any
    other camera at the same `station_folder` before the "no
    coordinates" rows get filtered out, rather than requiring every
    individual camera row to carry its own coordinate independently.
    `species_space_map` (Species tab) was never affected by this \u2014 it
    already groups by `station_folder` directly rather than per-camera,
    so it wouldn't lose a station as long as at least one of its camera
    rows had coordinates.
  - **Follow-up bug, found from the user's next screenshot**: fixing the
    dropout surfaced a second, related problem \u2014 paired cameras now
    correctly share coordinates (natively, or via the backfill above),
    which means they're plotted at the EXACT same pixel and completely
    overlap. Whichever marker draws last visually hides every other one
    underneath it entirely \u2014 including a red "do not use" camera hidden
    directly behind a green "no issues" one at the same station, which
    is exactly what the screenshot showed (8 dots, none red, despite a
    confirmed "do not use" decision). Fixed: cameras sharing a station's
    coordinates are now spread into a small, evenly-arranged ring around
    the real point (~9m offset at the equator) so each one reads as a
    visually distinct dot instead of silently stacking on its pair.
  - **Third attempt, after the user reported the camera still wasn't
    appearing on the map AT ALL (not just hidden)**: this meant the
    second fix was targeting the wrong failure entirely for this
    specific case. Two assumptions behind the earlier fixes turned out
    to be unverified: that `station_folder` reliably matches between any
    given pair of cameras (only ever confirmed for a different, specific
    pair from one screenshot, not verified generally), and that the
    block filter couldn't itself be the reason a paired camera goes
    missing. Both addressed this time:
    - **Block filter now expands to the whole station** (via
      `station_folder`) rather than filtering row-by-row \u2014 if a paired
      camera's own row has an inconsistent or missing `block` value
      while its pair's row has the correct one, row-by-row filtering
      would silently drop just that one camera from an otherwise
      fully-matching station.
    - **Coordinate backfill now tries twice**: first by
      `station_folder` as before, then by a normalized `site_id` with
      any trailing camera letter stripped (`"A01A"`/`"A01B"` \u2192
      `"A01"`) as a second attempt, in case `station_folder` itself
      doesn't actually match between a specific pair.
    - **A real, visible diagnostic was added** rather than guessing a
      fourth time blind: the map now shows a warning naming exactly
      which cameras (by `site_id`) have no usable coordinates even after
      both backfill attempts \u2014 deliberately NOT flagging cameras
      legitimately excluded by an active block filter, since that's
      routine, expected behavior and would otherwise make the warning
      noisy and alarming for no reason. If a camera still doesn't appear
      after this build, this diagnostic should say so explicitly and
      name it, which is far more useful for finding the actual cause
      than another screenshot of the map alone.
  - **Fourth attempt: the one-line diagnostic message itself turned out
    to be the problem, not just the underlying logic.** The user
    reported the camera was STILL missing with no diagnostic text at
    all \u2014 which meant the message's own assumption (that a camera
    excluded by the block filter is always routine and not worth
    flagging) was actively hiding the real issue in this case, since
    both the block-filter fix and the primary backfill depend on
    `station_folder` matching between a pair, and that was only ever
    confirmed for a different, specific pair of cameras from one
    screenshot \u2014 never verified in general. Rather than adjust the
    message a third time and risk being wrong in yet another new way,
    replaced it entirely with a real diagnostic TABLE: every camera in
    the deployment sheet, with its own columns for whether it had
    coordinates on its own row, whether it has them now (after checking
    a paired camera), whether it passes the current block filter, and
    whether it's actually shown on the map \u2014 with the underlying
    computation refactored into one shared reactive
    (`camera_placement_status()`) that both the map and this table read
    from, so the two can never disagree with each other the way the map
    and timeline did earlier this session. This replaces guessing which
    single sentence to show with just showing the actual state for
    every camera, which should make the true cause visible directly
    rather than needing a fifth attempt at summarizing it correctly.
  - **Fifth attempt: root cause confirmed directly** from the user's
    timeline screenshot, which showed A01A and A01B both genuinely
    labeled `(SiteA01st_A)` \u2014 `station_folder` DOES match between this
    pair, disproving the hypothesis the third/fourth attempts were built
    around. The map showed only 9 dots for 14 cameras in the deployment
    sheet, pointing at the actual cause: the marker-offset fix (two
    entries up) used a FIXED ~9m ground offset, which is imperceptible
    \u2014 sub-pixel \u2014 once the map is zoomed out to fit an entire survey
    spanning several km, exactly the situation `fitBounds()` produces
    for a multi-station survey. Paired cameras were still visually
    overlapping almost perfectly even after that "fix," just
    fractionally less than before. Fixed properly this time: the offset
    is now a PERCENTAGE of the map's own spatial extent (the overall
    lat/long range across all plotted cameras), not a fixed ground
    distance, so it stays visually meaningful regardless of how far out
    the map is zoomed.

  - **Sixth attempt**: the diagnostic table (previous entry) now confirms
    directly that `camera_placement_status()` is NOT the problem \u2014 every
    single camera, including A01A, correctly shows `on_map = Yes`. The
    bug is specifically in the offset/jitter step that runs after that,
    for separating cameras that end up sharing identical coordinates.
    The user's map screenshot showed only one pair visibly separated out
    of several \u2014 and the survey's own layout (confirmed from the same
    screenshot: stations spread almost entirely north-south, longitude
    nearly constant) explains why: the circular jitter formula puts a
    2-camera pair's offset almost entirely in the LONGITUDE direction,
    but the offset's magnitude was based on the overall span, which was
    dominated by the much larger latitude spread \u2014 so the offset ended
    up far too small relative to the actual (much smaller) longitude
    scale being drawn. Fixed: the offset is now scaled to the
    nearest-neighbor distance between distinct STATIONS (not the
    survey's overall span), which stays meaningful regardless of how
    the stations happen to be arranged, long and narrow or otherwise.
    Also added the actual latitude/longitude to the diagnostic table, so
    if this still isn't resolved, whether paired cameras end up with
    identical or slightly different coordinates is directly visible
    rather than needing to be inferred.
  - **Confirmed working, then tuned for visibility at default zoom**:
    the user's next screenshot showed the red "do not use" camera now
    genuinely separated from its pair for the first time \u2014 the
    nearest-neighbor-based fix was directionally correct \u2014 but only
    visible after zooming in heavily. Since a pair is offset in OPPOSITE
    directions, the total separation between the two cameras is double
    the per-camera offset; at the original 0.15 coefficient that meant
    only 30% of the nearest-station distance total, apparently still too
    tight to read at the fully-zoomed-out default view. Increased to 0.3
    per camera (60% total), substantially more visible while staying
    safely under 100% \u2014 a pair's two cameras still never appear as far
    apart as the actual distance to their nearest neighboring station.
  - **Still not visible at default zoom after doubling the offset \u2014
    found the actual remaining gap**: jitter was keyed on EXACT
    coordinate equality (grouping cameras that shared the identical
    lat/long, down to 6 decimal places). That correctly catches
    coordinates that are identical because one was backfilled from the
    other, but not the case where two cameras at one station each have
    their OWN, genuinely slightly different GPS reading \u2014 a few real
    meters apart, not identical \u2014 which the diagnostic table's new
    lat/long columns made directly checkable. For a pair like that, the
    exact-match check never fires at all, so whatever small, real
    separation they already had stayed completely untouched \u2014 and
    that's still many times smaller than the spacing between actual
    stations, so it read as invisible at the zoomed-out default view no
    matter how large the jitter coefficient was tuned. Fixed properly:
    grouping is now by STATION IDENTITY (`station_folder`) instead of
    coordinate equality, and every camera at a multi-camera station is
    first re-centered to one shared reference point before jittering \u2014
    so the resulting separation is consistent and guaranteed regardless
    of whether the originally recorded coordinates happened to be
    identical, slightly different, or backfilled.

- **Camera operation timeline: "Marked \"Do not use\"" added as a third
  status**, alongside "Continuous" and "Had a recorded gap" \u2014 previously
  a camera correctly appeared in the timeline (confirmed directly from
  the user's screenshot: A01A was there, just not visually flagged) but
  had no way to show its QA/QC exclusion status at all. Same worst-first
  priority and the same color scheme as the camera status map, for
  consistency between the two.

- **Session load now fills forward survey name/deployment phase across
  pages.** `survey_name`/`process_survey_name`/`viz_survey_name` (and the
  three `deployment_phase` equivalents) are fully independent text
  inputs \u2014 confirmed via `get_survey_name()`/`get_deployment_phase()`'s
  own fallback logic, which exists specifically because nothing
  previously kept these in sync. A restored session where the user only
  ever filled in Survey Setup's field left Processing's and Load Data's
  own copies blank, meaning the same value had to be retyped on every
  page. Fixed: on load, if any ONE variant in a group has a saved value,
  it fills in any of the others that are still blank \u2014 never overwrites
  a field that already has its own (possibly deliberately different)
  value.

- **Fixed: Load Data's search effort status misleadingly suggested a
  re-upload was needed, even when it wasn't.** This answers the user's
  question directly: search effort data from Processing WAS already
  auto-importing into Visualize & Export \u2014 `get_operation_periods()`
  (the function every Effort/Species/Activity calculation actually uses)
  already fell back to computing fresh from Processing's own
  `rv$gap_periods` whenever nothing had been explicitly re-uploaded. The
  status indicator just didn't reflect that: it checked the re-uploaded
  variant directly, so it showed nothing loaded \u2014 and the re-upload
  prompt stayed visible \u2014 even while Processing's data was already in
  active use behind the scenes. Fixed to check the same source the real
  calculations use, and to say explicitly which source is actually
  active ("re-uploaded CSV" vs. "auto-computed from Processing's camera
  downtime gaps. No re-upload needed.").

- **Save session footer bar changed to goldenrod** (was the same dark
  green as most other buttons, genuinely hard to spot per the user's
  screenshot). Goldenrod is now reserved for this one bar specifically,
  so it reads as a distinct, persistent affordance rather than blending
  in.

- **"Apply correction" (QA/QC timestamp correction) changed from
  goldenrod to the standard green** \u2014 for internal consistency now that
  goldenrod means something specific elsewhere (the session bar above):
  this is a regular primary action like dozens of others in the app, so
  it should look like one.

- **"Load session" file input now stretches full width**, matching "Save
  session" \u2014 it had an explicit, narrow fixed width (`230px`) that left
  empty space beside it while the button next to it naturally filled the
  card.

- **Re-upload prompts now hide themselves once their data is already
  loaded**, addressing something session save/restore made newly
  visible: landing on a tab after restoring a session (or just loading
  data earlier) left a "Re-upload X (only needed if not already loaded)"
  prompt sitting right under a status message that already said it was
  loaded \u2014 technically accurate per its own label, but redundant and
  easy to misread as still needed. Applied to all 5 instances of this
  pattern (deployment sheet on both Processing and Load Data, TrapTagger,
  ArgusWild, search effort) via one shared helper
  (`sync_optional_upload_visibility()`) rather than duplicating the logic
  five times.
  - A small "Replace this file" link takes the file input's place once
    data is loaded, for anyone who genuinely wants to swap in a
    different file \u2014 the option isn't gone, just not competing for
    attention with a status message that already answered the question.
  - **One real bug caught and fixed during this build, before it ever
    shipped**: the first version tried to `shinyjs::hide()` the file
    input by its own id \u2014 but Shiny's `fileInput()` puts that id on the
    inner, already-invisible `<input type=file>` (replaced visually by
    a separate styled label/button), so hiding it would have done
    nothing visible at all. Fixed by wrapping each file input in its own
    div and targeting that wrapper's id instead.

- **"Save session" now reachable from every tab**, not just Overview.
  Added as a `footer` argument on `page_navbar()` \u2014 bslib renders that on
  every tab automatically, regardless of which one is selected, rather
  than needing to be added to each page individually. Fixed/sticky
  (`position: fixed; bottom: 0`) so it's reachable without scrolling even
  on long pages like Exports; `body` given matching bottom padding so the
  bar doesn't cover the last bit of content on any page.
  - Uses a SEPARATE output id/download handler from Overview's own "Save
    session" button (`dl_session_footer` vs `dl_session`), both backed by
    the same two shared helper functions rather than duplicated logic.
    Two `downloadButton()`s bound to the very same output id would have
    meant two HTML elements sharing one `id` attribute on the same page
    \u2014 technically invalid markup, and not worth the risk when giving each
    its own id/handler pair costs nothing.
  - Deliberately just "Save" in the footer, not "Load"/"New project" too
    \u2014 those are naturally once-at-the-start actions, not "as you go"
    ones, so they stay on Overview only rather than adding footer clutter
    for something rarely needed mid-session.

- **Real session save/restore built**, addressing the #1 finding from
  the independent evaluation (`Independent_Evaluation.md`): the
  "New project"/"Load project" buttons had been stubs the whole time,
  meaning there was no actual way to save a multi-hour session and
  resume it later \u2014 only a re-upload-every-CSV workaround.
  - **Save session**: bundles every meaningful `rv$` field (all
    uploaded/processed data, QA/QC decisions, gap periods, camera
    exclusions, audit log) into one `.rds` file via
    `reactiveValuesToList()`, timestamped and prefixed with the survey
    name. Excludes only the two fields holding transient, in-session-only
    UI state (which folder the custom browser dialog currently has open)
    \u2014 not meaningful project data. Also separately captures the
    survey-name/deployment-phase text inputs, since those live as plain
    Shiny inputs rather than `rv$` fields (confirmed by checking
    `get_survey_name()`/`get_deployment_phase()` directly) and would
    otherwise be silently lost.
  - **Load session**: reads the file immediately on upload but does NOT
    apply it until confirmed in a modal \u2014 loading silently discards
    whatever is already in the current session, so that needed the same
    confirm-before-destroying treatment as Rename. Invalid or unrelated
    `.rds` files are caught and reported clearly rather than crashing.
  - **"New project"** also now actually works (was itself a stub) and
    also requires confirmation, since it's equally destructive.

- **Confirmation dialog added to "Rename images"**, addressing the #2
  finding: it was explicitly labeled irreversible but had zero
  confirmation step, just adjacent static warning text that's easy to
  click past. Pre-checks (deployment sheet loaded, survey folder
  selected) still happen BEFORE the modal appears, so a click that was
  always going to fail doesn't make the user confirm something that was
  never going to happen anyway.

- **Remaining items from the independent evaluation are deferred**,
  per discussion with the user: a visible exclusion-count warning on the
  species-occupancy/SECR export cards, a `testthat` suite for the core
  helper functions, and the larger analysis-layer gaps (occupancy/SECR
  model fitting, activity-overlap statistics, richness/diversity metrics,
  REM/REST density estimation, full Camtrap DP package export) are all
  still open, in the priority order `Independent_Evaluation.md` lays out.

- **Fixed: plotly chart downloads saved as "name.png.png"** \u2014
  `Plotly.downloadImage()`'s `filename` option is documented to be
  WITHOUT an extension, since it appends one itself based on the
  `format` option passed alongside it; every call site was passing a
  name that already ended in `.png`, producing the duplicate. Fixed
  defensively inside `downloadPlotlyAsPng()` itself (strips a trailing
  `.png` before handing the name to Plotly), rather than needing every
  call site to remember this quirk correctly. The map downloads
  (`downloadMapAsPng()`) use a different, direct mechanism with no
  auto-appending involved \u2014 confirmed those were already correct, not
  affected by this bug.

- **Fixed: GIS layer polygon colors clashed with the camera status map's
  own legend colors** \u2014 confirmed directly from the user's screenshot
  (the habitat polygons' green/gold and the legend's green/orange "no
  issues"/"had a gap" were genuinely hard to tell apart on the same map).
  GIS palette changed to blues/purples, deliberately avoiding the
  green/orange/red family the status legend already owns, so the two
  unrelated color-coding schemes can't be confused with each other
  regardless of which habitat/status combination happens to land
  together.

- **Fixed: GIS layer polygons all showed as one undifferentiated shape
  instead of distinctly-colored habitat zones** \u2014 confirmed from the
  user's own screenshot (one visible rectangle, not two). Root cause: the
  coloring loop assigned ONE color per uploaded FILE, not per individual
  polygon FEATURE within it \u2014 but a single GeoJSON/shapefile can (and, in
  the test generator built earlier this session, does) contain multiple
  named polygons in one file (e.g. "Woodland" and "Grassland" both in one
  `habitat_test_layers.geojson`), so they were all getting the exact same
  color and looked like one shape. Fixed: each feature now colored by its
  own name/habitat/type attribute (whichever the uploaded file actually
  has), cycling through the palette independently of which file it came
  from, with each feature's own label shown on hover too (previously
  just the file name).

- **Map PNG downloads switched from `html2canvas` to `leaflet-image`**,
  per the user's report that downloaded maps didn't match what was
  actually zoomed to. This is a known, structural limitation of generic
  DOM-screenshot tools with Leaflet specifically: Leaflet positions its
  tile layer using a CSS transform, which `html2canvas` doesn't reliably
  account for, so the captured tiles and the captured markers can end up
  visibly offset from each other \u2014 not a timing issue a delay would fix.
  `leaflet-image` is purpose-built for this exact problem, reconstructing
  the map's current view directly via Canvas+CORS instead of
  screenshotting the DOM.
  - Requires `preferCanvas = TRUE` on both downloadable maps (Effort's
    camera status map, Species tab's capture map) \u2014 `leaflet-image` can
    only rasterize Canvas-drawn markers/polygons, not Leaflet's default
    SVG ones, so without this the map would export with its background
    tiles but no markers at all.
  - **Known trade-off, stated plainly rather than silently dropped**:
    `leaflet-image` does not capture HTML-based map elements (zoom
    controls, legends) at all, only genuine map content. The dynamic
    title is drawn directly onto the resulting canvas afterward (so that
    context isn't lost), but the color legend itself isn't currently
    reproduced in the downloaded image \u2014 worth revisiting if that turns
    out to matter in practice.
  - **Honesty check**: this is a more involved change (new library, new
    JS logic) than most of this session's fixes, and isn't something
    that could be directly tested here. If maps still don't download
    correctly after this, that's worth reporting back precisely (what
    the image actually shows) rather than assuming the underlying
    diagnosis was wrong.

- **Fixed: "GIS layers" basemap showed "API KEY REQUIRED" instead of a
  map** \u2014 confirmed directly from the user's screenshot. CartoDB changed
  their policy and now requires an API key for their free-tier tiles,
  which wasn't true when that provider was picked. Switched to
  `Esri.WorldGrayCanvas` \u2014 same free, no-authentication tile family as
  the satellite view already used elsewhere in the app, so it's known to
  actually work without a key.

- **Fixed: every "PNG" download button did nothing at all** \u2014 two
  separate, confirmed bugs (not something the user did wrong):
  1. `downloadPlotlyAsPng()` searched the plotly output div for a CHILD
     element with the "js-plotly-plot" class \u2014 but plotly.js adds that
     class directly to the output div itself, not to a nested child, so
     that search always came back empty and the function returned early
     without ever calling the actual download. Fixed: passes the output
     div itself to `Plotly.downloadImage()`.
  2. `downloadMapAsPng()` combined `useCORS: true` with `allowTaint: true`
     \u2014 if a basemap tile fails CORS, `allowTaint` lets it render anyway,
     but that TAINTS the canvas, and a tainted canvas throws a security
     error the moment `toDataURL()` is called. With no `.catch()` on the
     promise, that error vanished completely silently \u2014 exactly "nothing
     happens." Fixed: `allowTaint` removed, and both download functions
     now have a `.catch()` that shows a clear message on failure instead
     of silence.

- **Timeline (Effort tab) is now downloadable as PNG too**, same
  `Plotly.downloadImage()` approach as every other plotly chart.

- **Dynamic titles added to every downloadable figure** (not just a
  filename) \u2014 species/comparison/filter context baked directly into
  each chart via its own `layout(title = ...)`, so the information is
  visible both on-screen and in the downloaded image, not something that
  has to be remembered or re-typed afterward:
  - "Captures through time: {species}", "RAI vs {covariate}: {species}"
  - "Activity pattern: {species1} vs {species2}" or
    "... {species1} by {covariate}"
  - "Camera operation timeline" / "Camera status map", each appending
    "\u2014 Block: {block}" when the block filter is active
  - The two leaflet maps (no native chart-title concept the way plotly
    has) instead get a dynamic title rendered directly above the map
    inside the SAME container `html2canvas` captures \u2014 restructured so
    that capture area excludes the download button itself (which sits
    outside it), rather than screenshotting the button along with the map.

- **Browse scroll-to-top fix, attempt 2** \u2014 the first attempt (last
  session) didn't actually work, per direct user confirmation. Root
  cause of why THAT fix failed: it targeted a guessed CSS class
  (`.btn-file`, the Bootstrap-3-era class Shiny's fileInput() docs
  reference) that this app's Bootstrap 5/bslib setup almost certainly
  doesn't actually use \u2014 so the event handler likely never fired at
  all. Rewritten to target the underlying `<input type="file">` element's
  own events directly instead of guessing at a wrapper class name \u2014 a
  `<label>` associated with a file input natively triggers click/focus on
  the input itself no matter which visible element (button, label, span)
  was actually clicked, so this doesn't depend on knowing the exact
  DOM/class structure. Also now re-asserts the saved scroll position at
  several delays (0/10/50/100/250/500ms) rather than just two, since the
  exact timing of the jump was never confirmed either.

- **Activity tab: covariate-based comparison added, alongside the
  existing 2-species comparison** \u2014 compare Species 1's OWN activity
  pattern across levels of season/habitat/block/month instead (e.g. dry
  vs wet season), rather than only ever two different species. Takes
  over from "Compare with" when set, since showing a 2-species
  comparison AND a covariate split at the same time would get unreadable
  fast. Rebuilt around a generic list of "groups" (hours + label) that
  both plot types (linear, circular) loop over identically, so a species
  comparison and a covariate comparison share the exact same plotting
  code rather than being two separate paths that could quietly drift
  apart from each other. A qualitative 6-color palette cycles if there
  are more groups than colors, since a habitat covariate could plausibly
  have more levels than the old fixed 2-species case ever did.

- **PNG download added to the Activity plot**, same `Plotly.downloadImage()`
  approach already used on the Species tab's two plotly charts.

- **Fixed a real bug: the circular activity plot was being massively
  over-smoothed, washing real peaks out into near-uniform noise** \u2014
  confirmed by the user's own screenshots (linear clearly showing peaks
  around 6-9am and 8-10pm; circular reading as an almost perfect circle).
  Both plots DO pull the exact same underlying independent-event data;
  the circular one just had a real calculation bug on top of it. Root
  cause: `bw = "nrd0"` tells `density()` to compute bandwidth from
  whatever data it's handed \u2014 but it was being handed the TRIPLED/padded
  data (three 24h copies stitched together to handle the midnight
  wraparound), not the real 24h data. Since that padded data spans 72h,
  its own spread is ~3x inflated versus reality, and `nrd0`'s bandwidth
  scales directly with spread \u2014 that inflation alone was enough to wash
  out real peaks. Fixed: bandwidth now computed from the real,
  un-padded data first (`bw.nrd0()`), then applied as a fixed value to
  the padded data, rather than letting `density()` recompute it on the
  inflated version. Also simplified the radial axis (hid the raw
  density-value tick labels, e.g. "0.001, 0.002..." \u2014 not meaningful to
  a general reader, only the relative shape/peaks are) per the
  readability feedback.

- **Effort tab: basemap toggle + PNG download added to the camera status
  map.** "GIS layers" option overlays whatever shapefiles/GeoJSON were
  loaded on Load Data as colored polygons on a plain basemap, falling
  back to the satellite view if none are loaded. Download button uses
  the same `html2canvas` approach already built for the Species tab's
  map.

- **Fixed: `fileInput()`'s "Browse..." button jumping the page to the
  top on click** (TrapTagger/ArgusWild/search-effort uploads, and any
  other file upload in the app). Root cause not fully pinned down (most
  likely the Browse button/label triggering some default,
  form-submission-like browser behavior inside Shiny's own wrapping
  `<form>`) \u2014 fixed pragmatically regardless of the exact cause: scroll
  position is captured right before the click and restored right after,
  on the next tick (and again shortly after, in case the jump itself is
  slightly delayed rather than synchronous).

- **PNG download added to all three Species tab figures.** The two plotly
  charts ("Captures through time," "RAI vs covariate") already had a
  built-in PNG download via their own hover toolbar (the camera icon) \u2014
  not disabled anywhere, just not very discoverable. Added an explicit
  button for each instead, calling that same built-in
  `Plotly.downloadImage()` API directly rather than leaving two figures
  to a hidden hover icon while the map needed a real button regardless.
  - Leaflet has no equivalent built-in image export the way plotly does,
    so "Captures through space" needed something new: `html2canvas`
    (loaded from CDN, pinned to a specific version like every other CDN
    script in this app) screenshots the map's own DOM element
    client-side \u2014 no server-side rendering dependency (e.g. a headless
    browser) needed.
  - **One known limitation, worth knowing about**: `html2canvas`
    screenshotting a Leaflet map's basemap tiles (loaded from Esri's
    tile servers) can run into browser CORS restrictions depending on
    the browser and how those tiles are served \u2014 `useCORS`/`allowTaint`
    are both enabled to give it the best chance, but if the downloaded
    PNG ever comes back with the markers but a blank basemap, that's
    what's happening, and the most reliable fallback is the browser's
    own screenshot tool.

- **Visualize & Export's "Species" and "Activity" tabs built** (both were
  full stubs: empty plots, dropdowns with no choices). All four plots
  reuse `collapse_to_independent_events()` and `get_operation_periods()`
  rather than new, separate logic \u2014 so independence-threshold handling
  and trap-night accounting stay consistent with the Exports tab's own
  "Species detection data" and "Camera operation matrix."
  - **Species tab**: species/covariate dropdowns now populate for real.
    "Captures through time" \u2014 weekly independent-event counts.
    "Captures through space" \u2014 a map, one marker per station, sized by
    event count, joined by NORMALIZED station name (TrapTagger strips
    the underscore our own folder naming keeps \u2014 the same mismatch
    handled throughout Processing). "RAI vs covariate" \u2014 box plot of
    relative abundance index (events per 100 trap-nights) grouped by
    habitat/block/season (whichever columns the deployment sheet
    actually has); trap-nights aggregated up to the STATION level via
    `locationName`, not the camera level, to match TrapTagger's own
    station-level (not camera-level) detections.
  - **Activity tab**: linear (histogram) and circular (polar kernel
    density) activity-pattern plots, with an optional second species
    overlaid for comparison. The circular version pads the hour-of-day
    data by ±24h before smoothing and keeps only the central window \u2014
    avoids a false drop-off right at the midnight boundary that a plain,
    unwrapped density estimate would otherwise show. Uses `nrd0`
    bandwidth (R's own default), not Sheather-Jones, specifically because
    SJ can error outright on a sparse sample \u2014 exactly the kind of small
    dataset a less-common species would produce.
  - Status panels on both tabs' Settings cards confirm species
    availability, or name the missing prerequisite, matching the
    diagnostic pattern already established for the individual-ID
    exports and the Effort tab.

- **Fixed: Effort tab's camera status map could disagree with its own
  timeline** (a camera showing a visible gap in the timeline but not
  colored as "had a gap" on the map) \u2014 confirmed as a real bug, not
  something the user was missing. Root cause: the timeline reads
  `get_operation_periods()`, which prefers a re-uploaded search effort
  CSV if one exists (gaps already "baked in" from whenever it was
  generated); the map's gap check read raw `rv$gap_periods` directly \u2014
  separate state that a CSV re-upload never touches, so it can still be
  empty in the current session even while the timeline is correctly
  showing split bars from the re-uploaded file. Fixed: the map now
  derives "had a gap" from `get_operation_periods()` too (more than one
  row for the same camera), the exact same source and the exact same
  logic the timeline already uses, so the two can no longer disagree.

- **Status boxes ("N records...") on "Individual ID data" and
  "Individuals by block/season" now align to the bottom, directly above
  Download** \u2014 same `mt-auto`-wrapping fix already applied to the cards
  with selectors earlier, extended to these two as well.

- **`success_bar()` color changed** from the same dark olive as `btn-primary`
  download buttons to a distinct medium green (`#3C7A4D`) \u2014 status
  messages like "3 record(s) loaded" were visually indistinguishable
  from actual clickable buttons.

- **Visualize & Export's "Effort" tab built** (was a stub: a `selectInput`
  with no choices and two empty plots). Reuses the same Gantt-chart
  pattern already established for QA/QC's "Timestamp Gantt"
  (`plotly::add_segments()` + `add_markers()` at each end, for visibility
  even when a bar compresses to sub-pixel width) rather than inventing a
  new one.
  - **Block filter** now actually populates from the deployment sheet and
    filters both outputs \u2014 `get_operation_periods()`'s result doesn't
    carry `block` directly (it's a deployment-sheet concept, not part of
    Camtrap DP's Deployments schema the function follows), so it's
    joined back in by `site_id`/`locationID`, the key both sides share.
  - **Timeline** (`effort_timeline_plot`): one row per camera, with a
    visible break wherever there's a recorded gap (since
    `build_camera_operation_export()` already splits a camera's window
    into separate rows around gaps) \u2014 colored by whether a camera had
    any gap at all, so one stands out without reading every bar's hover
    text.
  - **Camera status map** (`camera_loss_map`): one marker per camera,
    color-coded by status, worst case first \u2014 marked "Do not use"
    (QA/QC) beats "had a recorded gap" beats "no issues," so a camera
    with both shows as the more serious/actionable status rather than an
    arbitrary pick between them. Legend included.
  - Added a status panel confirming how many cameras are ready to plot
    (or naming the missing prerequisite), matching the diagnostic pattern
    established for the individual-ID exports earlier.
  - **Not yet built**: Species and Activity tabs are still stubs.

- **Fixed misleading diagnostics on the three individual-ID exports**
  (Individual ID data, Individuals by block/season, SECR input data).
  The user had genuinely loaded ArgusWild data (confirmed: "3 record(s)
  loaded, 2 individual(s)." on Load Data), but SECR's species dropdown
  still said "(upload ArgusWild data first)" \u2014 which sent them looking
  in the wrong place. Root cause: these three exports all need the SAME
  chain (TrapTagger data \u2192 matched to a local file via EXIF \u2192 matched
  to ArgusWild by filename) to produce anything, but the only check that
  existed always blamed ArgusWild specifically, regardless of which of
  the three pieces was actually missing.
  - SECR's species dropdown now checks TrapTagger, then EXIF, then
    ArgusWild, then the actual join result, in that order, and names
    whichever ONE is actually missing \u2014 not always the same guess.
  - Added the identical diagnosis, as a visible status panel (not just
    inferable from an empty downloaded file), to "Individual ID data"
    and "Individuals by block/season" too, which had no visibility into
    this at all before. Shows a clear count ("N record(s) matched...")
    when everything's actually ready.
  - Both download handlers' own guards against a placeholder value
    (previously checking only for the literal string "upload ArgusWild")
    now check for a leading "(" instead, since no real species name
    starts with one \u2014 catches any of the new placeholder variants
    without needing to keep three separate checks in sync by hand.
  - **Process note**: the structural-integrity check used throughout this
    whole project (simple open-paren-count minus close-paren-count
    across the raw file text) produced a false positive on this edit \u2014
    some pre-existing string literal elsewhere in the file apparently has
    an unbalanced raw parenthesis count within itself. Switched to a
    proper R-aware check (ignoring comments and the CONTENTS of string
    literals, not just counting every character in the file) to confirm
    this edit was actually fine; worth using that more rigorous version
    going forward if the simple count ever flags something again.

- **Fixed: deployment metadata's checkboxes vanished entirely** after the
  previous round's CSS multi-column attempt. Root cause: `column-width`
  distributes a container's DIRECT CHILDREN across columns, but that
  wrapper had only one direct child (the entire `checkboxGroupInput()`
  block, label included) \u2014 there was nothing for it to actually split,
  which collapsed the rendering instead of producing the intended
  layout. Replaced with three genuine, separate `checkboxGroupInput()`s
  (one per Bootstrap `column(4)`), with the full column list split into
  consecutive thirds so the reading order stays natural (top-to-bottom
  within a column, then left-to-right across columns) rather than
  interleaved. `dl_metadata` now combines all three selections back into
  one list, reordered to match the deployment sheet's own column order
  (not the arbitrary order they happen to be split/selected in across
  the three groups).

- **Exports tab layout, round 3**:
  - Row spacing increased again (`mb-3` class added to each `fluidRow`
    itself, on top of each card's own `mb-4`) \u2014 the previous round's
    `mb-4`-only change wasn't enough on its own, since there's no gap
    between rows without a margin on the row container itself, not just
    its cards.
  - Selection fields (the independence-threshold number input, both
    species dropdowns) now move to the bottom of their card AS A GROUP
    WITH their download button, not just the button alone \u2014 previously
    only the button had `mt-auto`, so it got pushed to the very bottom
    while its selector stayed stranded mid-card with a growing gap
    between them on cards with less text. Both are now wrapped together
    in one `mt-auto` container, so there's no longer a gap between a
    selector and the button it controls.
  - "Selected deployment metadata" changed from `column(4)` to
    `column(12)` (its own full-width row), since it was the sole card
    in its row with two-thirds of that row sitting empty. Its checkbox
    list now flows through a CSS multi-column layout (`column-width`,
    not a fixed `column-count`, so the number of columns actually
    displayed adapts to available width rather than always forcing a
    fixed number regardless of screen size) instead of a single tall
    column, filling that width properly.

- **Two confirmed, important bugs found from the user's own questions,
  not just a request to change the UI:**
  1. **"SECR input data" had no species filter at all** \u2014 with multiple
     species carrying individual IDs (the user's own example: leopards
     and elephants both do), this silently mixed different species'
     individuals into one capture history, which isn't methodologically
     valid (SECR models are fit per species; mixing them would produce a
     nonsensical or actively misleading result with no warning at all).
     Fixed: added a species dropdown, scoped to species that actually
     HAVE at least one individual ID (not every TrapTagger species, which
     would include ones an export would just come back empty for), and
     the export is now filtered to that selection. Filename and audit
     log both include the selected species.
  2. **"Individuals by block/season/age-sex" was missing `species` from
     its own grouping entirely** \u2014 individuals of different species
     sharing a block/season/sex/life-stage combination were being
     silently merged into one count. Fixed: `species` added to both the
     selection and the `aggregate()` formula; sort order and card text
     updated to match.
  - On whether "Individual ID data" and "Individuals by block/season"
    should be combined: kept separate, deliberately \u2014 they're
    different SHAPES of the same underlying data (per-detection records
    vs. an aggregated summary count), serving different purposes (detailed
    analysis vs. quick demographic overview). Combining them would force
    one of those two uses to lose what it's actually for.

- **Exports tab layout polish**: row spacing increased (`mb-3` \u2192
  `mb-4` on every card) to read more clearly as a grid of distinct rows.
  Download buttons now align to the bottom of every card regardless of
  how much text/inputs sit above them (`d-flex flex-column` on each card,
  `mt-auto` on its download button) \u2014 previously, cards with less
  content had their button sitting mid-card rather than lined up with
  its neighbors.

- **"Individual ID data" export now filtered to matched records only** \u2014
  confirmed this makes sense, per the user's own question: an export
  specifically named for individual-ID data including rows with no
  individual ID at all was just noise mixed into the real individual-level
  data, not a deliberate design choice. Filters to `!is.na(individual_id)`
  before writing. Card text updated from "where matched" (implying mixed
  content) to "matched to an individual ID" (stating the filter directly).

- **Exports tab reordered again** (final layout, this round): row 1 \u2014
  Camera stations, Sampling effort, Photo counts by species; row 2 \u2014
  Species detection data, Camera operation matrix, Species captures
  (still adjacent, per the earlier request); row 3 \u2014 Individual ID
  data, Individuals by block/season, SECR input data; row 4 \u2014 Selected
  deployment metadata alone.

- **All cards in a row now stretch to equal height** (`h-100` on each
  card, relying on Bootstrap's `.row` defaulting to `align-items:
  stretch` already \u2014 no extra class needed on the row itself beyond
  that default).

- **"Species captures" text updated** to the exact wording requested,
  with the EXIF sentence kept in the same paragraph as "Needs:" (not
  pushed to its own line like the other cards' Needs sentences \u2014
  deliberately different here, per direct request).

- **Exports tab reordered and condensed**, per direct request:
  - Every card's "Needs:" sentence now starts on its own line
    (`tags$br()` before it), across all 10 cards, not just the ones
    touched by other changes this turn.
  - "Camera operation matrix" text condensed to the exact wording
    requested, keeping all three hyperlinks (camtrapR's `cameraOperation()`
    reference, camtrapR vignette 3, the unmarked vignette).
  - Reordered into 4 rows (3 cards per row) grouped by what they're for,
    not just alphabetically or by build order: row 1 \u2014 Camera stations,
    Sampling effort, Species detection data (foundational/species-level
    basics); row 2 \u2014 Camera operation matrix, Species captures, Photo
    counts (the two occupancy exports are now adjacent on the same row,
    per direct request, with Photo counts grouped alongside them as the
    third species-level export); row 3 \u2014 Individual ID data, SECR input
    data, Individuals by block/season (all three ArgusWild-dependent,
    individual-level exports now consecutive, previously split apart by
    Photo counts sitting between them); row 4 \u2014 Selected deployment
    metadata alone (the one export that isn't really "analysis output" in
    the same sense as the others).

- **"Effort matrix (occupancy format)" renamed to "Camera operation
  matrix"** \u2014 the user's follow-up question ("doesn't it need a
  species?") revealed the old name itself was the actual source of
  confusion, not a misunderstanding on their part. "Occupancy format"
  implied a complete, ready-to-use occupancy-model input, when this
  export is really `camtrapR`'s species-agnostic `cameraOperation()`
  layer \u2014 the prerequisite trap-effort input shared by every species
  analysis, not a detection history by itself. Renamed to match
  `camtrapR`'s own terminology exactly, with each of the two matrix
  cards ("Camera operation matrix" and "Species captures") now
  explicitly cross-referencing the other and stating plainly that they
  serve different purposes with different 0/NA semantics, rather than
  leaving that relationship to be inferred. Downloaded filename and
  audit log message updated to match
  (`..._camera_operation_matrix_YYYYMMDD.csv`).

- **"Effort matrix": NA and 0 were being conflated \u2014 fixed, per the
  user's direct question, researched and confirmed against two
  authoritative sources rather than assumed:**
  - [camtrapR's `cameraOperation()` reference](https://jniedballa.github.io/camtrapR/reference/cameraOperation.html)
    states explicitly: *"NA: camera(s) not set up, 0: camera(s) not
    operational, 1 (or higher): number of operational camera(s)."* NA and
    0 are documented as meaning two different things, not interchangeable
    \u2014 confirmed again in [camtrapR vignette 3](https://cran.r-project.org/web/packages/camtrapR/vignettes/camtrapr3.pdf)
    (data extraction for occupancy/SECR input): *"If stations were not
    set up, values are NA. Operational stations get value 1. If cameras
    were set up but malfunctioning, it is 0."*
  - [unmarked's own vignette](https://cran.r-project.org/web/packages/unmarked/vignettes/unmarked.html)
    confirms the same principle on the modeling side: NA in a detection
    matrix specifically means a survey didn't happen (e.g. lost/missing
    data), a different concept from 0 (surveyed, nothing detected).
  - Before this fix, `build_camera_day_matrix()` only ever marked a
    camera's specific "on" sub-periods; a gap WITHIN its overall
    deployment window (physically present, just not working that day)
    was indistinguishable from a day truly OUTSIDE that window (not
    there at all) \u2014 both silently defaulted to NA.
  - Fixed, but ONLY for the plain effort matrix: each camera's full
    window (earliest start to latest end, across however many gap-split
    periods it has) is now marked 0 first, then its specific "on"
    sub-periods are overlaid as 1 \u2014 leaving any gap within that window
    sitting at 0, exactly matching camtrapR's convention.
  - **Deliberately NOT applied to "Species captures" (occupancy
    format)**: there, a gap day correctly stays NA rather than becoming
    0, since a malfunctioning camera couldn't have detected the species
    even if present \u2014 collapsing that into "surveyed, not detected"
    would bias detection-probability estimates. The two exports now
    have different, each-individually-correct semantics, both stated
    directly in their own UI card text along with the citations above,
    rather than readers needing to infer it or take it on faith.

- **Fixed: "Effort matrix" cells were always `0` or `NA`, never `1`** \u2014
  confirmed directly against the user's actual downloaded CSV (only `0`
  and `NA` present, no `1` anywhere, across all 129 columns). Root cause:
  `build_camera_day_matrix()` always marked an operational day `0` first,
  then only ever upgraded specific days to `1` via a second loop that
  runs over supplied detections \u2014 correct for the species occupancy
  matrix (0 = operating but not detected, 1 = operating and detected),
  but the plain effort matrix never supplies any detections at all, so
  that upgrade loop never ran and every operational day stayed frozen at
  0 forever. There was no code path that could ever produce a 1 for it.
  Fixed: the plain-matrix case (no detections given) now marks
  operational days `1` directly, since there's no detected/not-detected
  distinction to make in that case; the species-occupancy case (detections
  given) keeps the 0-then-upgrade scheme exactly as before. Also fixed
  the function's own doc comment, which had actually described the
  correct intended behavior all along \u2014 the code just didn't match it.

- **"Effort summary" now shows which station each camera belongs to.**
  Confirmed the underlying data was already correct \u2014 each row was
  already one individual camera's own operational-days total (both
  `cameraID` and `locationID` are per-camera, e.g. "A01A" and "A01B" are
  different `locationID` values even though they're paired at the same
  station), never merged with its pair. The gap was visibility: with no
  station column in the output, there was no way to SEE that two rows
  were a pair just by looking at the CSV. Added `locationName` (the
  shared station, e.g. "SiteA01st_A") to the output so that's now visible
  directly, sorted by station.

- **Fixed: "Effort matrix" (and, by the same shared code path, "Species
  occupancy") failing with "subscript out of bounds."** Root cause: a
  camera ID like "237" looks purely numeric to a spreadsheet reader, so
  `ct_id` can come through as a numeric column rather than character. R
  indexes a named matrix POSITIONALLY when given a numeric subscript, not
  by name \u2014 so an un-coerced numeric camera ID silently became "row
  number 237" instead of "the row named 237," which is far beyond how
  many rows the matrix actually has (one per unique camera, likely a
  dozen or so). The second loop in `build_camera_day_matrix()` (marking
  detections) already explicitly coerced to character and was safe; the
  first loop (marking operational days, which runs regardless of whether
  there are any detections) didn't, and is what actually broke. Fixed by
  coercing `cameraID` to character once at the top of the function, so
  every downstream use (both loops, plus the matrix's own dimnames) is
  guaranteed consistent and name-based rather than one of them being
  incidentally safe and the other not. Searched the rest of the file for
  the same risk pattern (`ct_id`/`cameraID` indexing a named structure
  without explicit coercion) and found no other instances.

- **Fixed: "Effort summary" export failing with "no rows to aggregate"**,
  confirmed to NOT be a data problem (Processing's own "Download search
  effort (CSV)" calls the same underlying `build_camera_operation_export()`
  directly on the same `rv$deployment_data` and works, proving the dates
  in the user's actual data were valid all along). Root cause:
  `get_operation_periods()` can return data from two different sources
  depending on the session \u2014 freshly computed (where
  `deploymentStart`/`deploymentEnd` are plain ISO 8601 text, "...T...Z")
  or a re-uploaded search effort CSV via `read_search_effort_csv()`
  (which already converts those same fields to `POSIXct`). The export
  handlers assumed text either way and called `as.character()` on
  whatever came back \u2014 but `as.character()` on an already-`POSIXct`
  value uses R's own default print format ("YYYY-MM-DD HH:MM:SS", no
  "T", no "Z"), which then silently fails to re-parse against the ISO
  format string and turns every date into a missing value. With every
  row's duration missing, `aggregate()` has nothing left after dropping
  NA rows, hence the exact error message.
  - Added a shared `parse_deployment_datetime()` helper that checks
    `inherits(x, "POSIXct")` and handles each representation explicitly,
    instead of assuming one. Used in `dl_effort_summary`, `dl_secr`, and
    inside `build_camera_day_matrix()` (which also feeds `dl_effort_matrix`
    and `dl_species_occ`) \u2014 the last of these had been using a `substr()`
    approach that happened to tolerate both formats by coincidence (both
    share the same "YYYY-MM-DD" date prefix regardless of what follows),
    but is now made explicit and guaranteed correct rather than
    incidentally safe.

- **Fixed: 7 of the 9 remaining Exports-tab downloads were serving an
  HTML error page instead of a CSV.** Root cause confirmed via careful
  code review (no R interpreter available in this environment to run and
  reproduce directly, so this was traced by hand, line by line):
  - **Two confirmed bugs**, both the same class \u2014 a raw `!=`/`==`
    comparison that silently returns `NA` (not `TRUE`/`FALSE`) when
    either side is `NA`, then feeding that `NA` into an `if()`, which R
    treats as a hard error ("missing value where TRUE/FALSE needed"),
    not a soft failure. This is exactly what turns a CSV download into
    Shiny's default HTML error page.
    1. `collapse_to_independent_events()` (powers "Species detection
       data"): `df$species[i] != last_species` errors the moment any
       TrapTagger record has a missing/blank species. Fixed with
       `!identical(...)`, which is NA-safe by construction (correctly
       treats two `NA`s as equal and an `NA` next to a real value as
       different, always returning `TRUE`/`FALSE`).
    2. "Species occupancy" export: `sum(enriched$species == species_sel
       & ...)` silently becomes `NA` under the same condition, then
       `if (n_multi_cam_dropped > 0)` crashes the same way. Fixed with
       `na.rm = TRUE`.
  - **Every remaining export handler now wrapped in `tryCatch()`** (`dl_*`
    content functions, all 10, including "Camera stations" which already
    worked) as a defensive safety net on top of the two confirmed fixes
    above \u2014 given the inability to run R directly in this environment to
    exhaustively verify every code path against the user's actual data,
    this guarantees any FUTURE uncaught error in an export becomes a
    one-row CSV stating what failed (plus a notification and an audit
    log entry with the exact R error message), rather than a silent,
    undiagnosable HTML page. If any export still fails after this build,
    the resulting CSV's error message is the fastest way to pinpoint
    exactly what's still wrong, rather than guessing again blind.

- **TODO: deployment sheet needs an explicit, structured field for why a
  camera/SD card was finally removed or collected** (e.g. a dropdown:
  "Full retrieval" / "SD card full" / "Battery dead" / "Camera
  malfunction" / "Camera lost or stolen" / "Knocked down" / "Other \u2014
  see notes"), rather than relying on free-text `notes_retrieval` alone.
  This is a field data-collection change, not app code \u2014 see "Future
  deployment-sheet schema improvements" above for the full writeup.
  Worth folding into the broader deployment-sheet schema rework already
  flagged elsewhere in this file (multi-visit handling).

- **Search effort export now surfaces deployment/retrieval notes** (e.g.
  "SD card full") from the deployment sheet, rather than only recording
  gap-derived comments. Reused the same `notes_deployment`/
  `notes_retrieval` columns the existing "Camera health flags" feature
  already draws on \u2014 surfaced verbatim in `deploymentComments` rather
  than keyword-matched against specific phrases like "SD card full",
  since field notes vary too much in wording for narrow matching to be
  reliable. Attached to the period each note actually explains:
  deployment notes on the first operational period (explains a late
  start), retrieval notes on the last (explains why it ended when it
  did) \u2014 not duplicated onto every split period, which would have
  misleadingly suggested a note explains a gap it has nothing to do
  with.

- **Real bug fixed in "Camera stations & coordinates" export: `n_cameras`
  always showed 1**, even for genuinely paired stations. Nothing to do
  with TrapTagger (this export pulls directly from the deployment sheet,
  never touches TrapTagger data) \u2014 `site_id` is already unique per
  camera location (e.g. "A01A"/"A01B" are different `site_id` values), so
  counting rows per `site_id` always returned 1 regardless of how many
  cameras share a station. Fixed to count distinct `site_id` values per
  `station_folder` instead (the actual station-level grouping \u2014 both
  "A01A" and "A01B" share `station_folder` "SiteA01st_A"). Confirmed
  against the real test data: A01A/A01B (same station) now correctly
  show `n_cameras` = 2; A04A/A04B (different stations despite similar
  names) correctly stay at 1.

- **Audited every "primary action bar" button app-wide for size
  consistency**, not just the two named in the request. Searched every
  `btn-primary`/`btn-outline-primary` button and classified each as
  either a standalone "final action" (the one button that completes a
  card's workflow, e.g. "Run image audit," "Download search effort") or
  a deliberately small, paired button (e.g. "New project"/"Load project"
  sitting side by side, or "Detect gaps"/"Add gap period manually").
  - Found exactly **one** genuine discrepancy: "Run cross-check"
    (Processing \u2192 Import TrapTagger) had `btn-sm` while every other
    standalone final-action button in the app doesn't \u2014 including
    "Download search effort" directly above it in the same card group,
    which is almost certainly what caught the user's eye. Fixed: removed
    `btn-sm`, now matches its peers exactly.
  - Everything else checked out as intentional, not inconsistent: small
    paired buttons are consistently sized against their own pair (not
    against solo final-action buttons, which is a different visual
    category by design), and "Extract EXIF data" sits in a narrower
    `column(3)` alongside a summary in `column(9)` rather than full card
    width \u2014 a deliberate side-by-side layout, not a button-size bug, so
    left as-is rather than restructured.

- **Full app-wide em-dash sweep** (not just one section this time, per
  direct request) \u2014 scanned the entire file systematically rather than
  spot-checking. Found 204 total lines with em-dashes; scoped the fix to
  the ~130 that are actual user-facing text (UI labels, subtitles,
  notifications, warnings, audit log messages) and left the ~124 that are
  internal code comments (`#`, `//`, `/* */`) alone, since those are
  invisible to anyone using the app \u2014 **flagged this scoping choice to
  the user explicitly rather than assuming it**, and it's still open
  whether they want comments swept too.
  - Two status-VALUE strings (not just prose) needed careful, consistent,
    find-everywhere replacement since they're compared for equality
    elsewhere in the code, not just displayed: `"Empty \u2014 needs
    review"` \u2192 `"Empty, needs review"` (6 occurrences, all fixed
    together) and the Focal species preview table's `"\u2014 not found"`
    placeholder (the exact one from the user's own screenshot) \u2192
    `"Not found"` (2 occurrences, both the value-assignment and the
    matching `styleEqual()` call, which would have silently stopped
    highlighting those rows if only one had been changed).
  - One standalone em-dash used as a table "no value" placeholder
    (TrapTagger cross-check table) \u2192 `"N/A"`.
  - Remaining ~49 lines (notifications, info panels, subtitles, warning
    messages) reworded individually with commas/semicolons/colons
    depending on what read best for each sentence, not a single
    blanket find-replace.
  - Verified after every batch: structural integrity (balanced
    braces/parens), full UI input/output ID cross-check (same expected
    list of not-yet-built stub tabs, no new orphans), and no
    `reactiveValues()` duplicates \u2014 confirms none of this bulk text
    surgery broke anything functional.
  - Final confirmed count: **zero** em-dashes remain in any user-facing
    text anywhere in the app.

- **Main page text: em-dashes removed, checked against the SOP.** Found
  and fixed 5 em-dashes on the Overview page (intro paragraph, table row
  labels, one parenthetical) \u2014 replaced with plain commas/semicolons/
  periods rather than re-wording around them. Also caught that
  `BUILD_LABEL` itself (now displayed directly on the page's "Version"
  line, since last session's change) still used an em-dash as its own
  separator \u2014 fixed, and switched to a comma there going forward so
  future build-label bumps don't quietly reintroduce the exact thing just
  removed.
  - Checked the page's step descriptions against the TrapTagger Images
    Processing SOP (the only SOP shared in this project, focused on
    folder structure/upload prep) \u2014 Steps 1 and 2's descriptions match
    both the SOP and what's actually built. Flagged, per direct
    confirmation, that Step 3's description (detection maps, activity
    patterns, RAI plots) describes functionality not yet built (only data
    exports are real so far) \u2014 **left as intentional roadmap/aspirational
    language**, not changed, per the user's explicit choice.

- **"What you'll need" table was genuinely out of date** — checked
  directly against the actual code rather than assumed accurate, and it
  was missing real capability added earlier this session:
  - Row 2 (Process) didn't mention its own deployment-sheet re-upload
    (`process_deployment_csv`) or that ArgusWild data is used there too
    (Import ArgusWild), not just on Visualize.
  - Row 3 (Visualize) only mentioned ArgusWild + GIS, missing that its
    "Load Data" tab can independently accept the deployment sheet, EXIF/
    timestamp data, TrapTagger data, and the search effort CSV as well —
    the whole point of that tab being able to work without Ingest/Process
    done first. Column header changed from "Inputs required" to "Inputs"
    since most of row 3's items are optional depending on which export is
    wanted, not uniformly required.

- **Main page (Overview) redesigned**: all 5 sections rebuilt as stacked,
  full-width cards (was a 7/5 two-column split) in the requested order:
  What this app does \u2192 What you'll need \u2192 Getting started \u2192 Session
  \u2192 Contact & support.
  - Step numbering fixed to start at 1 in both "What this app does" (was
    2-3-4) and "What you'll need" (was 2-3-4, now 1-2-3) \u2014 these
    referenced the page's nav_panel position, not the pipeline's own step
    count, which was confusing since this page itself isn't one of the
    numbered pipeline steps.
  - "What you'll need" table also corrected to reflect GIS layers now
    living on Visualize & Export's Load Data tab, not Ingest (per the
    earlier move this session) \u2014 moved from the Ingest row to the
    Visualize row, marked optional.
  - Contact & support filled in: Meredith S. Palmer,
    mspalmer.zool@gmail.com (as a clickable mailto: link), Leopard
    Ecology & Conservation. "Version" now shows the live `BUILD_LABEL`
    instead of a hardcoded "0.1 (skeleton)" that would otherwise drift out
    of date with every future build.

- **Search effort export: two confirmed answers, one real fix.**
  - Confirmed (by reading the code directly): start/stop dates come from
    the deployment sheet's setup/retrieval dates, NOT first/last photo
    timestamps. **Tabled per the user's request** \u2014 whether to narrow
    this using actual photo evidence when a camera started late or died
    early is an open question, flagged here rather than decided
    unilaterally, since it's a real methodological choice affecting
    downstream effort/occupancy calculations.
  - Confirmed AND fixed a real gap: cameras marked "Do not use" (QA/QC,
    "Cameras to exclude") were NOT being excluded from the search effort
    export \u2014 `build_camera_operation_export()` never referenced
    `rv$camera_decisions` at all. Fixed: takes `camera_decisions` as a
    parameter now and drops excluded cameras entirely before computing
    anything for them (their downtime isn't "search effort" if the
    camera's own data was already excluded as unreliable). UI text on
    Processing's "Camera downtime gaps" card updated to state both facts
    plainly rather than leaving them undocumented.

- **Visualize & Export's "Exports" tab fully built** (was 10 stub
  downloadButtons producing empty CSVs; all now produce real data):
  - **`build_enriched_detections()`**: the key bridge this whole tab
    relies on. TrapTagger's own export carries NO local filename (only a
    remote `image_url`) \u2014 the only way to link its species/station/
    timestamp records back to ArgusWild's `individual_id` (keyed by local
    filename) is the same EXIF-based station+timestamp match Processing's
    "Focal species export" already does (`match_traptagger_to_local_images()`),
    generalized here to ALL TrapTagger records at once rather than one
    selected species. Also recovers block/season/cell_id from the
    deployment sheet by normalized station name, since TrapTagger's
    export doesn't carry those either.
  - **Camera-level vs station-level precision, stated honestly rather than
    guessed**: TrapTagger doesn't track which camera at a multi-camera
    station took a given photo. A station with exactly one camera gets
    an unambiguous `ct_id`; a station with more than one is left `NA`
    rather than silently guessing, and camera-level exports (species
    occupancy matrix, SECR input) exclude those records \u2014 the exact
    count excluded is written to the audit log on each download, not
    silently dropped.
  - **`collapse_to_independent_events()`**: standard camera-trap
    independent-event logic \u2014 consecutive detections of the same
    species at the same station within a configurable threshold (new
    "Independence threshold" input on the export card itself, since this
    tab is meant to work independently of the Species visualization tab)
    collapse into one event.
  - **`build_camera_day_matrix()`**: shared by both the plain effort
    matrix and the per-species occupancy matrix \u2014 camera \u00d7 day, 1 =
    operating (and, for occupancy, detected), 0 = operating not detected,
    `NA` = not deployed yet / already retrieved, matching the standard
    camtrapR-style convention.
  - **SECR export is the capture-history file only** (Session/ID/Occasion/
    Detector), not the full secr input (which also needs a trap-location
    file) \u2014 stated in both the UI and the audit log message, meant to
    be paired with "Camera stations & coordinates."
  - Each export card's subtitle now states exactly what data it needs
    loaded (deployment sheet / TrapTagger / ArgusWild / EXIF) rather than
    a generic description, so a missing prerequisite is discoverable
    before clicking Download, not just an empty resulting file.
  - **Not yet built**: the Effort/Species/Activity tabs' interactive
    plots and maps are still stubs \u2014 this turn was Exports only.

- **Manual edit capability added to Import ArgusWild's "Individual ID
  summary" table** — Individual ID/Sex/Life stage cells (highlighted) are
  now directly editable in place, for filling in or correcting a value
  ArgusWild left blank or got wrong, without needing to re-upload a
  modified CSV.
  - `join_arguswild_to_species_data()` now always includes individual_id/
    sex/life_stage columns in its output, even if the uploaded ArgusWild
    CSV didn't supply sex/life_stage at all — otherwise there'd be no
    column for the user to fill in by hand.
  - Since `argus_joined()` is a computed reactive (would otherwise
    discard any edit the next time anything it depends on changes), edits
    are captured via DT's `cell_edit` event and stored separately in a new
    `rv$argus_manual_edits` field, keyed by `local_filename`, then merged
    back on top of the ArgusWild-derived values inside `argus_joined()`
    itself — same general pattern as `rv$camera_decisions` storing manual
    use/do-not-use decisions separately from computed audit data.
    Clearing a cell (empty string) removes that field's manual override
    rather than storing an empty value that would incorrectly overwrite
    a real one later.
  - Added a shared `ARGUS_ID_TABLE_COLS` constant so the join function's
    output order and the editable table's column-index math (DT reports
    edits by 0-based column index) can't drift out of sync with each
    other independently.
  - **Caught two more accidental duplicate `reactiveValues()` entries**
    while making unrelated edits earlier in this same session
    (`arguswild_data`, `gis_layers` had each briefly ended up listed
    twice) — fixed and reconfirmed via direct inspection that the full
    list has no duplicates.

- **GIS layer upload moved from Ingest to Visualize & Export's Load Data
  tab**, and actually built (was a UI-only stub before, never wired to
  anything). Reads shapefiles/GeoJSON via `sf::st_read()`. Handles a real
  Shiny gotcha: multi-file uploads give each file a random temp name that
  doesn't match its original filename, but a shapefile's `.shp`/`.dbf`/
  `.shx`/`.prj` components need to share a base name in the same directory
  to find each other — fixed by copying each upload into a fresh temp
  directory under its ORIGINAL filename first. Does a real spatial join
  (`sf::st_within()`) counting cameras per polygon feature, labeled by
  whichever of `name`/`habitat`/`type`/`label` column the layer happens to
  have. `generate_gis_test_layers.R` generates two fake habitat polygons
  ("Woodland"/"Grassland") from the real station coordinates, deliberately
  split unevenly (5 vs 9 cameras) rather than evenly, per the user's
  request for "different numbers of cameras."

- **QA/QC exposition added** on "Export corrected data" (Ingest), pulled
  directly from the actual TrapTagger SOP content established earlier in
  this project (not guessed): explains that TrapTagger reads each image's
  timestamp from its own EXIF metadata at upload time, never from this
  CSV — so an uncorrected camera clock will still show the wrong date in
  TrapTagger even after downloading this file, since this app never
  writes corrections back into the image files themselves. Also states
  directly that "Do not use" cameras should be excluded from the
  TrapTagger upload entirely, and explains why the app's own Cross-check
  and "Match to local images" already compare against each image's RAW
  timestamp rather than the corrected one (that's genuinely what
  TrapTagger saw).

- **Search effort export redesigned around Camtrap DP**
  (https://camtrap-dp.tdwg.org/data/#deployments) — the real, open,
  TDWG/GBIF-backed camera trap data standard, confirmed via its actual
  published schema rather than invented. Its key property is exactly what
  was asked for: `deploymentID` is unique per OPERATIONAL PERIOD, not per
  camera — a camera that goes offline and comes back on now produces two
  separate rows, with the gap simply absent from either, rather than one
  row silently spanning across it.
  - `compute_operational_periods()`: real interval-subtraction logic —
    given a camera's full deployment window and a set of (possibly
    overlapping) recorded gaps, merges overlapping gaps first, then
    returns the resulting "on" sub-periods. A camera with no gaps still
    returns its one full-window row unchanged.
  - `build_camera_operation_export()` populates Camtrap DP's actual
    column names (`deploymentID`, `locationID`, `locationName`,
    `latitude`, `longitude`, `deploymentStart`/`deploymentEnd` as ISO
    8601, `cameraID`, `deploymentComments`) — only the fields this app
    actually has data for; the standard's other optional deployment-level
    fields (cameraModel, cameraHeight, etc.) are left out rather than
    populated with guesses.
  - The re-upload side (Visualize & Export's Load Data tab) now stores
    into a NEW, separate `rv$camera_operation_periods` field — this is a
    genuinely different data shape (one row per operational period) than
    `rv$gap_periods` (one row per gap), so conflating them would have
    been wrong; `rv$gap_periods` itself is untouched and still drives the
    interactive "Camera downtime gaps" UI on Processing exactly as before.
  - **Caught and fixed two genuine accidental duplicate-field bugs** in
    `reactiveValues()` while making this change (both `arguswild_data` and
    `gis_layers` had ended up listed twice, apparently leftover from
    earlier edits) — confirmed via direct inspection that no duplicates
    remain anywhere in the list.
  - **Not yet built**: the camera on/off matrix for occupancy modeling
    the user mentioned as the ultimate goal — this search effort export
    is the input that would feed it, but the matrix-building step itself
    is a separate, later piece of work (Visualize & Export's "Effort" tab
    is still a stub).

- **Three requests addressed**:
  1. **All 13 download buttons made visually prominent** — found a real
     inconsistency: one download button was already solid `btn-primary`
     (the app's dark green theme color), but the other 12 used outline
     styles with `btn-sm` (white background, small text). All now use
     solid `btn-primary` consistently, without the `btn-sm` size
     reduction — reusing the app's existing theme color rather than
     introducing a new one, per the user's own "or whatever you
     recommend" invitation.
  2. **New `success_bar()` helper** — matches the visual language of
     Shiny's own built-in "Upload complete" bar (full-width, dark
     background, centered white text), for confirming success after a
     BUTTON-triggered action (like "Extract EXIF data"), which has no
     native equivalent indicator the way file uploads do. Applied to all
     five status indicators on Visualize & Export's Load Data tab
     (deployment, EXIF, TrapTagger, ArgusWild, search effort) for
     consistency, not just the EXIF one specifically asked about.
     **Also moved** the EXIF status indicator to directly below the
     "Extract EXIF data" button (it was above the folder input/button
     before, out of the way of where the user's eyes actually are right
     after clicking) — matching where the built-in upload bar appears
     relative to its file input.
  3. **Confirmed ArgusWild uploads are genuinely optional** — verified by
     reviewing the code directly, not assumed: nothing in Processing or
     Visualize & Export's Load Data tab requires `rv$arguswild_data` to
     be non-null for anything else to function. Both cards are already
     labeled "(optional)". Noting for when the remaining Visualize &
     Export tabs (Exports/Effort/Species/Activity, still stubs) get
     built: "Individual ID data"/"SECR input data" exports are the only
     features that should ever depend on ArgusWild data, and should
     gracefully degrade (clear message, not an error) if it's absent —
     everything else (effort, species detection, activity patterns) is
     species-level, not individual-level, and must work regardless.

- **New "Load Data" tab added as the first tab of Visualize & Export** —
  confirmed with the user first: ArgusWild import's purpose is genuinely
  to feed Visualize & Export's downstream analysis, but rather than move
  it there and lose the QA value of catching unmatched records early
  (while the person who understands the file structure is still actively
  working), it's **kept on Processing** and a **separate** "Load Data"
  tab was built here instead — matching the "start fresh, don't need
  Ingest/Processing done in the same session" philosophy already used
  elsewhere, since whoever does final analysis may be a different person
  entirely (an analyst, not the field tech).
  - Four cards: Deployment sheet, EXIF/corrected timestamp data (needed
    for effort calculations), TrapTagger classification data, ArgusWild
    individual ID data (optional). Each reuses the EXACT SAME helper
    functions Processing's own uploads use (`process_deployment_file()`,
    `run_exif_extraction()`, `read_traptagger_csv()`,
    `read_arguswild_csv()`), writing into the same `rv$` fields — so
    anything already loaded from earlier in the session (Ingest,
    Processing) shows up here immediately as already-loaded, and nothing
    needs re-loading twice.
  - `get_survey_name()`/`get_deployment_phase()` extended to a three-way
    fallback (this page's own entry \u2192 Processing's \u2192 Survey
    Setup's), rather than duplicating that fallback logic a third time.
  - **RESOLVED — the gap noted below has been closed.** Gap periods now
    have a full export/import round-trip: "Download search effort (CSV)"
    on Processing's Camera downtime gaps card exports `rv$gap_periods`
    (site_id, ct_id, gap_start, gap_end, reason, source), and a matching
    "Search effort / gap periods" card on Visualize & Export's Load Data
    tab reads it back via `read_search_effort_csv()`, replacing
    `rv$gap_periods` outright on upload (same behavior as re-uploading
    TrapTagger/ArgusWild data — a deliberate action, not merged). Someone
    starting fresh at Visualize & Export can now load every piece of data
    that page needs independently, including gap periods.

- **Focal species export rebuilt as stacked full-width sections**, per
  direct feedback — was a two-column layout (5/7 split) where the
  preview table sat permanently visible before matching ever ran, making
  every record look "not found" until the user noticed they needed to
  scroll down and run "Match to local images" first. New order: Select
  focal species → Match to local images → Focal species preview (now
  reads correctly, since it's encountered after the matching step in
  reading order) → Export (moved to the very bottom, as requested).

- **Fixed: Import ArgusWild's summary rendered completely blank, with no
  error message at all**, when a species wasn't currently selected (or
  TrapTagger data wasn't loaded) on "Focal species export." Root cause: a
  Shiny gotcha — `focal_species_matched()` uses `req()` internally, and a
  failed `req()` throws a SILENT error that propagates up through any
  reactive that calls it, making dependent UI outputs render as nothing at
  all rather than an error. `argus_joined()` was calling it unconditionally.
  Fixed by checking the actual prerequisites explicitly
  (`focal_species_ready()`) before ever calling `focal_species_matched()`,
  with a clear, actionable message ("Select a focal species on...") shown
  instead of silent blankness.

- **Page 3.3 (Import ArgusWild) built.** Grounded in real, documented
  schema rather than guessed: ArgusWild is built on the Wildbook/WBIA
  platform (confirmed via Tech4Conservation's own GitHub), and its
  "Standard Format Export" mirrors Wildbook's documented Bulk Import
  schema (wildbook.docs.wildme.org/data/bulk-import-beta.html).
  `read_arguswild_csv()` maps the real column names
  (`MarkedIndividual.individualID`, `Encounter.mediaAsset0`,
  `Encounter.genus`/`specificEpithet`, date fields, `locationID`, `sex`,
  `lifeStage`) — only `individual_id` and `media_asset` are required,
  everything else is optional.
  - **The join** (`join_arguswild_to_species_data()`) matches ArgusWild's
    `Encounter.mediaAsset0` against `basename(matched_local_path)` from
    Page 3.2's `focal_species_matched()` reactive — reused directly
    rather than duplicated, since our own focal-species export copies
    images with their original renamed filename unchanged, so this
    should match exactly for any successfully identified image.
  - **This creates an implicit dependency worth knowing about**: the
    join is always against whichever species is CURRENTLY selected on
    "Focal species export," and needs "Match to local images" to have
    been run there first (not just uploaded/selected) — the summary
    panel here explains this and flags a mismatch count if the numbers
    don't look right, rather than failing silently.
  - Individual ID summary table shows station/species/timestamp/local
    file alongside individual ID/sex/life stage, with unmatched records
    clearly marked "no match" (colored) rather than silently dropped.

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
