#' Visualize refined records on interactive maps
#'
#' Renders refined occurrence records on interactive maps for spatial
#' exploration and quality assessment. Records are deduplicated with geohashes
#' and color-coded by their native status.
#'
#' The workflow has four stages:
#'
#' * **Record aggregation:** Combines native and non-native refined records that
#'   passed spatial validation (`VasGBIF_useful_for_spatial_analysis = TRUE`).
#' * **Geohash deduplication:** Encodes coordinates at the requested precision
#'   and retains one representative record per species, geohash cell, and native
#'   status.
#' * **Interactive visualization:** Builds a multi-layer map with records
#'   color-coded by `native_status`.
#' * **Basemap selection:** Provides OpenStreetMap, Esri World Imagery, and
#'   Stadia Stamen Watercolor basemaps.
#'
#' @param refined_records A `refined` object returned by [refine_records()].
#' @param precision Positive integer controlling the spatial resolution of
#'   geohash-based deduplication. Higher values produce finer-grained cells. For
#'   reference, precision values of 4, 3, and 2 represent approximately 20 km,
#'   156 km, and 1,250 km resolution, respectively. Defaults to `3`.
#' @param cex Numeric value controlling the point size of occurrence records on
#'   the map. Defaults to `3`.
#'
#' @details
#' ## Geohash deduplication
#'
#' Geohash encoding converts latitude-longitude pairs into alphanumeric strings
#' representing grid cells of varying sizes. The function groups records by
#' species name, geohash cell, and native status, then retains the first record
#' from each group. This reduces visual overplotting while preserving the
#' broad spatial distribution pattern, which is useful for densely sampled
#' regions.
#'
#' ## Map layers and interactivity
#'
#' The generated map includes:
#'
#' * A color-coded legend based on `native_status` categories.
#' * Popups displaying record attributes such as GBIF ID, collection key, and
#'   taxon name.
#' * Toggleable basemap layers for different visualization contexts.
#' * Point transparency set to `alpha.regions = 0.6` to improve density
#'   perception.
#'
#' ## Record selection
#'
#' Records are included only when `VasGBIF_useful_for_spatial_analysis = TRUE`.
#' For non-native records, `native_status` must also differ from `"unknown"`.
#' Records with missing longitude or latitude are removed before geohash
#' deduplication.
#'
#' @returns
#' A `mapview` interactive map object displaying refined occurrence records
#' color-coded by `native_status`. The map contains a native-status legend,
#' three switchable basemap layers, and clickable popups with record metadata.
#'
#' @seealso
#' [`gh_encode()`][geohashTools::gh_encode] for geohash encoding and
#' [`mapView()`][mapview::mapView] for interactive map construction.
#'
#' @import data.table
#' @import geohashTools
#' @import mapview
#' @importFrom dplyr %>% filter mutate select slice ungroup group_by
#'
#' @examplesIf interactive() && exists("refined_records")
#' map_records(refined_records = refined_records, precision = 3, cex = 3)
#'
#' @export
map_records <- function(refined_records = NA, precision = 3, cex = 3) {
  all_records <- refined_records$all_records[
    VasGBIF_useful_for_spatial_analysis == T & native_status != 'unknown',
    .(
      gbifID,
      collection_key,
      VasGBIF_wcvp_family,
      VasGBIF_decimalLatitude,
      VasGBIF_decimalLongitude,
      VasGBIF_wcvp_taxon_status,
      VasGBIF_wcvp_taxon_name,
      LEVEL3_COD,
      native_status
    )
  ]

  dedup_by_geohash <- function(data, precision) {
    # 4 for 20 km, 3 for 156 km, 2 for 1250 km
    data <- data %>%
      filter(
        !is.na(VasGBIF_decimalLatitude),
        !is.na(VasGBIF_decimalLongitude)
      ) %>%
      mutate(
        geohash = gh_encode(
          VasGBIF_decimalLatitude,
          VasGBIF_decimalLongitude,
          precision
        )
      ) %>%
      group_by(VasGBIF_wcvp_taxon_name, geohash, native_status) %>%
      slice(1) %>%
      ungroup() %>%
      select(-geohash)
    return(data)
  }

  dedup <- dedup_by_geohash(all_records, precision) %>% setDT()

  dedup_vect <- terra::vect(
    dedup,
    geom = c("VasGBIF_decimalLongitude", "VasGBIF_decimalLatitude"),
    crs = "EPSG:4326"
  )
  map <- mapView(
    x = dedup_vect,
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

  message("Finished!")
  return(map)
}
