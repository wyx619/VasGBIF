#' @title Validate coordinates, restore metadata, and detect native status
#' @name refine_records
#'
#' @description Validates spatial information, restores metadata for usable vouchers, and
#' classifies records by geographic distribution status.
#'
#' The function combines three steps:
#'
#' 1. Restores missing metadata from duplicate records via [restore_duplicates()].
#' 2. Runs [CoordinateCleaner::clean_coordinates] checks in parallel to flag common spatial issues such as centroids,
#'    capitals, institutions, and marine records.
#' 3. Assigns native status by matching validated coordinates to WGSRPD Level 3 areas and WCVP
#'    distribution data via [detect_native_status()].
#'
#' @param voucher A `vouchers` object returned by [set_vouchers()].
#' @param threads Number of threads to use for coordinate validation. Use an integer `>= 1` for an
#'   absolute count, or a value between `0` and `1` for a proportion of available cores. The
#'   default is `4`.
#' @param tests Character vector of CoordinateCleaner validation tests to apply. Choose one or
#'   more of `"capitals"`, `"centroids"`, `"equal"`, `"gbif"`, `"institutions"`,
#'   `"outliers"`, `"seas"`, and `"zeros"`. The default uses all tests.
#'
#' @details
#' ## Metadata restoration
#'
#' [restore_duplicates()] fills missing metadata fields in usable voucher records using values from
#' duplicate records that share the same collection event key. Restored fields include `eventDate`,
#' `year`, `month`, `day`, `identifiedBy`, `countryCode`, `stateProvince`, and `locality`.
#' Candidate values longer than 10,000 characters are skipped.
#'
#' ## Coordinate validation
#'
#' Coordinate validation is performed with CoordinateCleaner. Available tests are:
#'
#' - `capitals`: records at country capital coordinates
#' - `centroids`: records at country or province centroids
#' - `equal`: records with identical latitude and longitude values
#' - `gbif`: records matching known GBIF geospatial issues
#' - `institutions`: records at known herbarium or museum coordinates
#' - `outliers`: geographic outliers within a species range
#' - `seas`: records located in marine areas for terrestrial species
#' - `zeros`: records at coordinates `(0, 0)`
#'
#' ## Native status detection
#'
#' Delegated to [detect_native_status()]. Records that pass coordinate validation are matched
#' against WCVP distribution data via WGSRPD Level 3 polygons using a two-stage priority-based
#' classification. The result is a `native_status` label for each record: `"native"`,
#' `"introduced"`, `"extinct"`, `"location_doubtful"`, or `"unknown"`.
#'
#' @returns A `refined` object (list) with three elements:
#'
#' - `all_records`: a `data.table` of records with validated coordinates, restored metadata, and
#'   native status classification
#' - `CoordinateProblematic`: a `data.table` of records that failed one or more CoordinateCleaner
#'   tests
#' - `runtime`: the elapsed execution time
#'
#' Use [export_records()] to write results to compressed CSV files.
#'
#' @references
#'
#' - Zizka, A., Silvestro, D., Andermann, T., Azevedo, J., Duarte Ritter, C., Edler, D., Farooq,
#'   H., Herdean, A., Ariza, M., Scharn, R., Svantesson, S., Wengstrom, N., Vitecek, S., &
#'   Antonelli, A. (2019). CoordinateCleaner: Standardized cleaning of occurrence records from
#'   biological collection databases. *Methods in Ecology and Evolution*, 10(5), 744-751.
#'   \doi{10.1111/2041-210X.13152}
#' - Govaerts, R., Nic Lughadha, E., Black, N. et al. The World Checklist of Vascular Plants, a
#'   continuously updated resource for exploring global plant diversity. *Scientific Data*, 8, 215
#'   (2021). \doi{10.1038/s41597-021-00997-6}
#'
#' @import data.table
#' @importFrom dplyr %>%
#' @import foreach
#' @import doParallel
#' @import rnaturalearthdata
#' @importFrom utils head
#' @import stringi
#' @seealso [`clean_coordinates()`][CoordinateCleaner::clean_coordinates], [export_records()]
#' @examplesIf interactive() && exists("voucher")
#'
#' refined_records <- refine_records(
#'   voucher = voucher,
#'   threads = 4,
#'   tests = c(
#'     "capitals", "centroids", "equal", "gbif",
#'     "institutions", "outliers", "seas", "zeros"
#'   )
#' )
#' @export
refine_records <- function(
  voucher = NA,
  threads = 4,
  tests = c(
    "capitals",
    "centroids",
    "equal",
    "gbif",
    "institutions",
    "outliers",
    "seas",
    "zeros"
  )
) {
  start <- Sys.time()

  voucher <- restore_duplicates(voucher$occ_digital_voucher[
    VasGBIF_dataset_result != 'unsable'
  ])

  voucher[
    is.na(VasGBIF_wcvp_taxon_name),
    `:=`(
      VasGBIF_wcvp_taxon_rank = wcvp_taxon_rank,
      VasGBIF_wcvp_taxon_status = wcvp_taxon_status,
      VasGBIF_wcvp_family = wcvp_family,
      VasGBIF_wcvp_taxon_name = wcvp_taxon_name,
      VasGBIF_wcvp_taxon_authors = wcvp_taxon_authors,
      VasGBIF_wcvp_reviewed = wcvp_reviewed
    )
  ]

  # iso2to3 <- CoordinateCleaner::countryref %>%
  #   select(iso3, iso2) %>%
  #   unique() %>%
  #   setDT()
  # voucher <- merge(
  #   voucher,
  #   iso2to3,
  #   by.x = 'countryCode',
  #   by.y = 'iso2',
  #   all.x = T
  # )
  voucher[, gbifID := as.character(gbifID)]
  message("Validating coordinates")

  threads <- threads %>% as.numeric() %>% set_threads()
  chunks_list <- voucher[, .(
    gbifID,
    VasGBIF_decimalLongitude,
    VasGBIF_decimalLatitude,
    VasGBIF_wcvp_plant_name_id,
    countryCode,
    VasGBIF_wcvp_taxon_name
  )] %>%
    split(., ceiling(seq_len(nrow(.)) / (nrow(.) / threads)))

  WorldLandMap <- WorldLandMap

  coord <- function(data) {
    suppressWarnings(CoordinateCleaner::clean_coordinates(
      data,
      lon = "VasGBIF_decimalLongitude",
      lat = "VasGBIF_decimalLatitude",
      species = "VasGBIF_wcvp_plant_name_id",
      tests = tests,
      seas_ref = WorldLandMap,
      value = "spatialvalid",
      verbose = FALSE
    ))
  }

  cl <- parallel::makeCluster(threads)

  registerDoParallel(cl)

  CoordinateFlagged <- foreach(
    data = chunks_list,
    .multicombine = T,
    .errorhandling = "pass",
    .packages = c("CoordinateCleaner", "rnaturalearthdata", "dplyr"),
    .inorder = F
  ) %dopar%
    {
      coord(data)
    }

  CoordinateFlagged <- rbindlist(CoordinateFlagged, fill = T)

  CoordinateProblematic <- CoordinateFlagged[.summary == F]

  CoordinateCleaned <- CoordinateFlagged[
    .summary == T,
    .(
      gbifID,
      VasGBIF_decimalLongitude,
      VasGBIF_decimalLatitude,
      VasGBIF_wcvp_taxon_name
    )
  ]

  parallel::stopCluster(cl)
  rm(chunks_list, CoordinateFlagged)

  native_detected <- detect_native_status(CoordinateCleaned)

  results <- merge(voucher, native_detected, by = "gbifID")

  end <- Sys.time()
  used <- end - start
  message(paste('used', used %>% round(1), attributes(used)$units))

  refined_records <- list(
    all_records = results,
    CoordinateProblematic = CoordinateProblematic,
    runtime = end - start
  )
  class(refined_records) <- 'refined'
  return(refined_records)
}
