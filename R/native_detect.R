#' @title Detect native status from WGSRPD distributions
#'
#' @description Assigns a native status classification to each occurrence record
#' by matching validated coordinates to WCVP distribution data via WGSRPD
#' Level 3 polygons.
#'
#' Native status is determined in two stages, working one taxon at a time.
#'
#' **Stage 1 — classify WGSRPD areas.** The internal `Distributions` dataset
#' links each WGSRPD Level 3 area code to WCVP flags (`introduced`, `extinct`,
#' `location_doubtful`). These flags are resolved into a single status label
#' with the following priority:
#'
#' 1. If `location_doubtful == 1`, the area is classified as
#'    `"location_doubtful"` regardless of other flags.
#' 2. Otherwise, if `introduced == 1`, the area is `"introduced"`.
#' 3. Otherwise, if `extinct == 1`, the area is `"extinct"`.
#' 4. If all three flags are `0`, the area is `"native"`.
#' 5. Any remaining case defaults to `"unknown"`.
#'
#' **Stage 2 — spatial intersection.** For each taxon, the validated
#' occurrence points are overlaid on the WGSRPD Level 3 polygon map (via
#' [terra::extract()]) to assign an area code to each record. That area code
#' is then looked up in the classified distribution table. Records falling
#' outside any documented area, or whose taxon has no entry in
#' `Distributions`, are labelled `"unknown"`.
#'
#' @param CoordinateCleaned A `data.table` of records that passed coordinate
#'   validation, containing at minimum `gbifID`,
#'   `VasGBIF_decimalLongitude`, `VasGBIF_decimalLatitude`, and
#'   `VasGBIF_wcvp_taxon_name`.
#'
#' @returns A `data.table` with columns:
#'
#' - `gbifID`: the record identifier
#' - `LEVEL3_COD`: the assigned WGSRPD Level 3 area code, or `NA` if the
#'   taxon has no distribution data
#' - `native_status`: one of `"native"`, `"introduced"`, `"extinct"`,
#'   `"location_doubtful"`, or `"unknown"`
#'
#' @import data.table
#' @importFrom dplyr %>%
#' @importFrom terra vect merge extract
#' @keywords internal
detect_native_status <- function(CoordinateCleaned) {
  species <- CoordinateCleaned[, unique(VasGBIF_wcvp_taxon_name)]
  Distributions <- Distributions
  local <- Distributions[
    taxon_name %chin% CoordinateCleaned$VasGBIF_wcvp_taxon_name,
  ]

  local[,
    native_status := fcase(
      location_doubtful == 1                                  , "location_doubtful" ,
      introduced == 1                                         , "introduced"        ,
      extinct == 1                                            , "extinct"           ,
      introduced == 0 & extinct == 0 & location_doubtful == 0 , "native"            ,
      default = "unknown"
    )
  ][, c("introduced", "extinct", "location_doubtful") := NULL]

  WGSRPD3map <- terra::vect(WGSRPD3)

  local_status <- function(taxon = NA_character_, CoordinateCleaned = "") {
    species_df <- local[taxon_name == taxon, .(area_code_l3, native_status)]

    if (nrow(species_df) == 0) {
      return(data.table(
        LEVEL3_COD = NA_character_,
        native_status = "unknown",
        gbifID = CoordinateCleaned[
          VasGBIF_wcvp_taxon_name == taxon,
          gbifID
        ]
      ))
    }

    occurrence_points <- CoordinateCleaned[
      VasGBIF_wcvp_taxon_name == taxon,
      .(gbifID, VasGBIF_decimalLongitude, VasGBIF_decimalLatitude)
    ] %>%
      terra::vect(
        geom = c("VasGBIF_decimalLongitude", "VasGBIF_decimalLatitude"),
        crs = "EPSG:4326"
      )

    distribution <- terra::merge(
      WGSRPD3map,
      species_df,
      by.x = "LEVEL3_COD",
      by.y = "area_code_l3"
    ) %>%
      .[, c("LEVEL3_COD", "native_status")]

    extracted_data <- terra::extract(distribution, occurrence_points) %>%
      setDT() %>%
      unique(by = "id.y")

    extracted_data[, .(
      gbifID = CoordinateCleaned[VasGBIF_wcvp_taxon_name == taxon, gbifID],
      LEVEL3_COD = LEVEL3_COD,
      native_status = fifelse(
        is.na(native_status),
        "unknown",
        native_status
      )
    )]
  }

  result <- list()

  message("Extracting WGSRPD information")

  for (i in seq_along(species)) {
    result[[i]] <- local_status(
      taxon = species[i],
      CoordinateCleaned = CoordinateCleaned
    )
    if (i %% 1000 == 0 | i == length(species)) {
      message(paste("Extracting", i, "/", length(species)))
    }
  }

  result <- result %>% rbindlist(fill = T) %>% unique()
  return(result)
}
