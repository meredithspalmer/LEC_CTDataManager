# =============================================================================
# generate_gis_test_layers.R
#
# Generates two fake habitat polygons (GeoJSON) for testing the GIS layer
# upload on Visualize & Export's Load Data tab — a "Woodland" zone and a
# "Grassland" zone, split so a DIFFERENT number of real test stations
# falls in each (5 vs 9), based on the actual station coordinates in
# Deployment_Data_Sample.xlsx:
#
#   A01st_A -23.15843797  (2 cameras)  \
#   A02st_A -23.19904997  (1 camera )   > Woodland (5 cameras total)
#   A03st_A -23.24147698  (2 cameras)  /
#   ------------------------- boundary at lat -23.27 -------------------------
#   A04st_A -23.30122604  (1 camera )  \
#   A04st_B -23.32049503  (1 camera )   \
#   A05st_A -23.35783000  (2 cameras)    \
#   A06st_A -23.39138196  (1 camera )     > Grassland (9 cameras total)
#   A07st_A -23.43511000  (1 camera )    /
#   A08st_A -23.48098000  (1 camera )   /
#   A09st_A -23.52835000  (2 cameras)  /
#
# These are simple bounding-box rectangles, not realistic habitat
# boundaries — good enough to test the spatial join (which polygon does
# each camera fall inside) without needing real GIS data.
#
# HOW TO USE:
# 1. Run this script. It writes habitat_test_layers.geojson to the
#    working directory.
# 2. Upload that file on Visualize & Export -> Load Data -> GIS layers.
# 3. Confirm the camera-count table shows: Woodland = 5, Grassland = 9.
# =============================================================================

suppressWarnings(suppressMessages({
  library(sf)
}))

OUTPUT_FILE <- "~/Desktop/Work/Consultancies/Leopard Ecology & Conservation/App/Sample Data/habitat_test_layers.geojson"

# Longitude range with a buffer around all stations' actual longitudes
# (23.925 to 23.943), latitude range split at -23.27.
lon_min <- 23.85
lon_max <- 24.05
lat_boundary <- -23.27
lat_top    <- -23.05   # north of A01st_A
lat_bottom <- -23.65   # south of A09st_A

make_box <- function(lon_min, lon_max, lat_min, lat_max) {
  sf::st_polygon(list(rbind(
    c(lon_min, lat_min), c(lon_max, lat_min),
    c(lon_max, lat_max), c(lon_min, lat_max),
    c(lon_min, lat_min)
  )))
}

woodland  <- make_box(lon_min, lon_max, lat_boundary, lat_top)
grassland <- make_box(lon_min, lon_max, lat_bottom, lat_boundary)

layers <- sf::st_sf(
  name = c("Woodland", "Grassland"),
  habitat_type = c("Woodland", "Grassland"),
  geometry = sf::st_sfc(woodland, grassland, crs = 4326)
)

sf::st_write(layers, OUTPUT_FILE, delete_dsn = TRUE, quiet = TRUE)

cat("Done. Wrote 2 habitat polygon(s) to", OUTPUT_FILE, "\n\n")
cat("Expected camera counts when uploaded and joined against the deployment sheet:\n")
cat("  Woodland  (lat", lat_boundary, "to", lat_top, "): 5 cameras (A01st_A, A02st_A, A03st_A)\n")
cat("  Grassland (lat", lat_bottom, "to", lat_boundary, "): 9 cameras (A04st_A, A04st_B, A05st_A, A06st_A, A07st_A, A08st_A, A09st_A)\n")
