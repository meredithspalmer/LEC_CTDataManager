# Generate Test Data

Scripts that build a complete, realistic synthetic camera-trap survey, so
you can try every feature of CT Data Manager without needing your own real
field data.

## What's in this folder

| File | What it does |
|---|---|
| `Deployment_Data_Sample.xlsx` | A real (sample) deployment/retrieval sheet from Leopard Ecology & Conservation's own field surveys. The template every script below is built around. |
| `generate_full_test_data.R` | **Start here.** Generates a full set of real, EXIF-stamped synthetic images that exercise Image Audit, Rename, and QA/QC in one run. |
| `generate_traptagger_test_data.R` | Generates a synthetic TrapTagger species-classification export, matched to the actual images `generate_full_test_data.R` creates. |
| `generate_arguswild_test_data.R` | Generates a synthetic ArgusWild individual-ID export, for trying the individual-ID / SECR features. |
| `generate_gis_test_layers.R` | Generates a sample GIS habitat layer (GeoJSON), for trying habitat covariates on the Species and Occupancy tabs. |

Each script after the first is optional and adds data for a later stage of
the pipeline. You don't need all of them, only the ones for the features
you want to try.

## Quick start

1. **Launch the app** and go to **Ingest & QA/QC → 1 · Survey setup**.
   Upload `Deployment_Data_Sample.xlsx`, type a survey name and deployment
   phase (anything you like, e.g. `LEC_2023_S1_Dry` and
   `First_deployment`), and click **Create folder structure**.
2. **Open `generate_full_test_data.R`** in RStudio and edit the four
   variables near the top so they match exactly what you just entered in
   the app (survey name, deployment phase, output location, and the path
   to `Deployment_Data_Sample.xlsx`). Run the whole script. It's slower
   than a simple file-copy, since it writes real EXIF data into each
   image, expect a few minutes for a full survey.
3. **Back in the app**, walk the pipeline in order:
   - **Image audit** → point it at your survey folder, run the audit.
   - **Rename images** → preview, then commit.
   - **QA/QC** → extract EXIF, check timestamps, check paired stations,
     check coordinates.
4. **Optional, for Processing / Visualize & Export / Analytics**: run
   `generate_traptagger_test_data.R` (edit its own path variables the same
   way first), then upload the CSV it produces on the Processing page.
5. **Optional, for individual-ID work**: run
   `generate_arguswild_test_data.R` and upload its output on
   **Processing → 3 · Import ArgusWild**.
6. **Optional, for habitat covariates**: run `generate_gis_test_layers.R`
   and upload its output on **Visualize & Export → Load Data**.

## A few things to expect, on purpose

`generate_full_test_data.R` deliberately builds a handful of specific test
scenarios into the data, so these aren't bugs if you see them:

- **One camera comes back completely empty**, and another is marked empty
  with a documented reason, testing Image Audit's empty-folder handling.
- **One camera shows a "Timestamp mismatch"**, and one pair of co-located
  cameras shows a paired-station mismatch, testing QA/QC's timestamp
  correction tools.
- **A few cameras use sub-folders** (mimicking how Reconyx, Cuddeback, and
  generic cameras organize their SD cards), testing Rename's
  sub-folder-consolidation logic.
- **Every camera starts with generic filenames** (`IMG_0001.jpg`-style, as
  a real SD card would produce), so running **Rename images** is a
  genuinely necessary step for every camera, not just the sub-folder ones.

Everything else in the sample data (deployment/retrieval notes, lat/long,
clock-drift columns) comes straight from the real deployment sheet, so the
rest of the app's checks reflect realistic field data as-is.

## Troubleshooting

- **"Can't find [folder]"**: `generate_full_test_data.R` doesn't create your
  survey's top-level folder itself, it expects you already clicked
  **Create folder structure** in the app first, with the exact same
  survey name, deployment phase, and output location entered at the top
  of the script.
- **Dates look wrong after uploading the sample sheet**: shouldn't happen
  with this file specifically (its dates are real Excel date cells, not
  text), but if you substitute your own deployment sheet later and see
  this, see the date-format picker on the Survey setup tab.
- **Species data doesn't match your images**: make sure
  `generate_traptagger_test_data.R`'s own path variables point at the
  exact same survey folder `generate_full_test_data.R` used, both scripts
  need to agree on where the data lives.
