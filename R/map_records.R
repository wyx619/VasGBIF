#' Visualize refined records on interactive maps
#'
#' Renders refined occurrence records on interactive maps for spatial
#' exploration and quality assessment. Records are deduplicated with geohashes
#' and color-coded by their native status.
#'
#' The function works in four steps:
#'
#' * **Record selection:** Reads the classified records from
#'   [detect_native_coord()], keeping those whose `native_status` is not
#'   `"unknown"`, optionally restricted to a single species named by `species`.
#' * **Geohash deduplication:** Encodes coordinates at the requested precision
#'   and retains one representative record per species, geohash cell, and native
#'   status.
#' * **Interactive visualization:** Builds a multi-layer map with records
#'   color-coded by `native_status`.
#' * **Basemap selection:** Provides OpenStreetMap, Esri World Imagery, and
#'   Stadia Stamen Watercolor basemaps.
#'
#' @param native_detected_coord A `nativeDetected` object returned by
#'   [detect_native_coord()], containing records with validated coordinates.
#' @param species Either `"all"` (the default) to map every species, or a single
#'   species name to restrict the map to that species. The name is matched
#'   exactly against the `Accepted_name` column, so `"Saxifraga hirculus"` maps
#'   the records of that species. Records whose `native_status` is `"unknown"`
#'   are excluded either way.
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
#' Both the classification and the coordinates are read from
#' `native_detected_coord`, which carries every column of the input records.
#' Records with `native_status = "unknown"` are excluded. When `species` names a
#' species rather than `"all"`, the selection is narrowed further to the records
#' whose `Accepted_name` equals that name; the comparison is exact, so the
#' spelling must match the column value. A name that selects nothing is an
#' error, because an empty map is read as "this species has no native records".
#' Records with missing longitude or latitude are excluded as a guard;
#' [detect_native_coord()] only classifies records with validated coordinates,
#' so none are expected, and inputs that carry missing coordinates (such as the
#' output of [detect_native_country()]) are rejected outright.
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
#' [detect_native_coord()] for the object consumed by this function;
#' [`gh_encode()`][geohashTools::gh_encode] for geohash encoding and
#' [`mapView()`][mapview::mapView] for interactive map construction.
#'
#' @import data.table
#' @import geohashTools
#' @import mapview
#' @importFrom dplyr %>% filter mutate select slice ungroup group_by
#'
#' @examplesIf interactive() && exists("native_detected_coord")
#' # Every species in the classification
#' map_records(
#'   native_detected_coord = native_detected_coord,
#'   precision = 3,
#'   cex = 3
#' )
#'
#' # A single species
#' map_records(
#'   native_detected_coord = native_detected_coord,
#'   species = "Saxifraga hirculus"
#' )
#'
#' @export
map_records <- function(
  native_detected_coord = NA,
  species = "all",
  precision = 3,
  cex = 3
) {
  # ---- validate inputs ----
  if (!inherits(native_detected_coord, "nativeDetected")) {
    stop(
      '`native_detected_coord` must be a "nativeDetected" object from detect_native_coord().'
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
  missing_cols <- setdiff(required_cols, names(native_detected_coord))
  if (length(missing_cols) > 0L) {
    stop(
      "`native_detected_coord` is missing required column(s): ",
      paste(missing_cols, collapse = ", ")
    )
  }

  if (!is.character(species) || length(species) != 1L || is.na(species)) {
    stop('`species` must be a single species name, or "all".', call. = FALSE)
  }

  # The spatial stage classifies records with validated coordinates only, so a
  # `native_detected_coord` carrying missing coordinates is a misuse (e.g. the
  # output of `detect_native_country()`), not a legitimate input.
  n_missing_coord <- sum(
    is.na(native_detected_coord$decimalLongitude) |
      is.na(native_detected_coord$decimalLatitude)
  )
  if (n_missing_coord > 0L) {
    stop(
      "`native_detected_coord` contains ",
      n_missing_coord,
      " record(s) with missing coordinates; it must be the output of ",
      "`detect_native_coord()`, which carries coordinates for every record.",
      call. = FALSE
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

  # The row selection is built as an explicit logical vector rather than as a
  # condition inside `[.data.table`: `input` carries its own `species` column,
  # so a bare `species` in `i` would resolve to that column and the comparison
  # would silently use the wrong values.
  keep <- native_detected_coord[["native_status"]] != "unknown"
  if (species != "all") {
    keep <- keep & native_detected_coord[["Accepted_name"]] == species
  }
  # `native_status` may hold `NA`, which makes `keep` hold `NA`; those rows are
  # dropped by the subset below, so they are not counted here either.
  n_selected <- sum(keep, na.rm = TRUE)

  # Silently drawing nothing for a name that matches no record would be read as
  # "this species has no native records", so refuse it and point at the likely
  # cause instead.
  if (species != "all" && n_selected == 0L) {
    stop(
      "No record of `species` = \"",
      species,
      "\" is left after excluding `native_status == \"unknown\"`. The name ",
      "must match `Accepted_name` exactly; the classification holds ",
      uniqueN(native_detected_coord[["Accepted_name"]]),
      " distinct name(s).",
      call. = FALSE
    )
  }

  # `native_detected_coord` carries every column of the input records, but a
  # popup listing all of them is unreadable, so only the informative ones are
  # kept.
  all_records <- native_detected_coord[
    keep,
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

