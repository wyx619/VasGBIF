#' Visualize refined records on interactive maps
#'
#' Renders refined occurrence records on interactive maps for spatial
#' exploration and quality assessment. Records are deduplicated with geohashes
#' and color-coded by their native status.
#'
#' The function works in four steps:
#'
#' * **Record selection:** Reads the classified records from
#'   [detect_native_status()], keeping those whose `native_status` is not
#'   `"unknown"`.
#' * **Geohash deduplication:** Encodes coordinates at the requested precision
#'   and retains one representative record per species, geohash cell, and native
#'   status.
#' * **Interactive visualization:** Builds a multi-layer map with records
#'   color-coded by `native_status`.
#' * **Basemap selection:** Provides OpenStreetMap, Esri World Imagery, and
#'   Stadia Stamen Watercolor basemaps.
#'
#' @param native_detected A `nativeDetected` object returned by
#'   [detect_native_status()].
#' @param precision Positive integer controlling the spatial resolution of
#'   geohash-based deduplication. Higher values produce finer-grained cells. For
#'   reference, precision values of 4, 3, and 2 represent approximately 20 km,
#'   156 km, and 1,250 km resolution, respectively. Defaults to `3`.
#' @param cex Numeric value controlling the point size of occurrence records on
#'   the map. Defaults to `3`.
#'
#' @details
#' ## Record selection
#'
#' Both the classification and the coordinates are read from `native_detected`,
#' which carries every column of the input records. Records with
#' `native_status = "unknown"` are excluded, as are records with missing
#' longitude or latitude — which removes the coordinateless records that
#' [detect_native_status()] classified through their country code.
#'
#' ## Geohash deduplication
#'
#' Geohash encoding converts latitude-longitude pairs into alphanumeric strings
#' representing grid cells of varying sizes. The function groups records by
#' species name, geohash cell, and native status, then retains the first record
#' from each group. This reduces visual overplotting while preserving the broad
#' spatial distribution pattern, which is useful for densely sampled regions.
#'
#' ## Map layers and interactivity
#'
#' The generated map includes:
#'
#' * A color-coded legend based on `native_status` categories.
#' * Popups displaying record attributes such as GBIF ID, GBIF issues, and
#'   taxon name.
#' * Toggleable basemap layers for different visualization contexts.
#' * Point transparency set to `alpha.regions = 0.6` to improve density
#'   perception.
#'
#' @returns
#' A `mapview` interactive map object displaying refined occurrence records
#' color-coded by `native_status`. The map contains a native-status legend,
#' three switchable basemap layers, and clickable popups with record metadata.
#'
#' @seealso
#' [detect_native_status()] for the object consumed by this function;
#' [`gh_encode()`][geohashTools::gh_encode] for geohash encoding and
#' [`mapView()`][mapview::mapView] for interactive map construction.
#'
#' @import data.table
#' @import geohashTools
#' @import mapview
#' @importFrom dplyr %>% filter mutate select slice ungroup group_by
#'
#' @examplesIf interactive() && exists("native_detected")
#' map_records(
#'   native_detected = native_detected,
#'   precision = 3,
#'   cex = 3
#' )
#'
#' @export
map_records <- function(
  native_detected = NA,
  precision = 3,
  cex = 3
) {
  # ---- validate inputs ----
  if (!inherits(native_detected, "nativeDetected")) {
    stop(
      '`native_detected` must be a "nativeDetected" object from detect_native_status().'
    )
  }

  required_cols <- c(
    "gbifID",
    "native_status",
    "native_status_source",
    "gbif_issues",
    "Accepted_name",
    "scientificName",
    "Taxonomic_status",
    "order",
    "family",
    "basisOfRecord",
    "decimalLatitude",
    "decimalLongitude"
  )
  missing_cols <- setdiff(required_cols, names(native_detected))
  if (length(missing_cols) > 0L) {
    stop(
      "`native_detected` is missing required column(s): ",
      paste(missing_cols, collapse = ", ")
    )
  }

  if (
    !is.numeric(precision) ||
      length(precision) != 1L ||
      is.na(precision) ||
      precision < 1 ||
      precision != floor(precision)
  ) {
    stop("`precision` must be a single positive integer.")
  }
  if (!is.numeric(cex) || length(cex) != 1L || is.na(cex) || cex <= 0) {
    stop("`cex` must be a single positive number.")
  }

  # `native_detected` carries every column of the input records, but a popup
  # listing all of them is unreadable, so only the informative ones are kept.
  all_records <- native_detected[
    native_status != 'unknown',
    .(
      gbifID,
      native_status,
      native_status_source,
      gbif_issues,
      Accepted_name,
      scientificName,
      Taxonomic_status,
      order,
      family,
      basisOfRecord,
      decimalLatitude,
      decimalLongitude
    )
  ]
  # Drop the `nativeDetected` class: what follows is a display subset, not a
  # classification result, and the print method would misreport it.
  setattr(all_records, "class", c("data.table", "data.frame"))

  dedup_by_geohash <- function(data, precision) {
    # 4 for 20 km, 3 for 156 km, 2 for 1250 km
    data <- data %>%
      filter(
        !is.na(decimalLatitude),
        !is.na(decimalLongitude)
      ) %>%
      mutate(
        geohash = gh_encode(
          decimalLatitude,
          decimalLongitude,
          precision
        )
      ) %>%
      group_by(Accepted_name, geohash, native_status) %>%
      slice(1) %>%
      ungroup() %>%
      select(-geohash)
    return(data)
  }

  simpled <- dedup_by_geohash(all_records, precision) %>% setDT()

  simpled_vect <- terra::vect(
    simpled,
    geom = c("decimalLongitude", "decimalLatitude"),
    crs = "EPSG:4326"
  )
  map <- mapView(
    x = simpled_vect,
    zcol = "native_status",
    legend = TRUE,
    layer.name = "native_status",
    popup = T,
    cex = cex,
    alpha.regions = 0.6,
    map.types = c(
      "OpenStreetMap",
      "Esri.WorldImagery",
      "Stadia.StamenWatercolor"
    ),
    alpha = 0.3
  )

  message("Done")
  return(map)
}
