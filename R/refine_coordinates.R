#' @title Validate coordinates of filtered occurrence records
#' @name refine_coordinates
#'
#' @description Validates the coordinates of filtered occurrence records with
#'   CoordinateCleaner and splits them into coordinate-clean and problematic
#'   tables.
#'
#' [CoordinateCleaner::clean_coordinates] checks run in parallel to flag
#' common spatial issues such as centroids, capitals, and marine records.
#'
#' Records that pass all requested tests are returned in `CoordinateCleaned`;
#' records that fail one or more tests are returned in `CoordinateProblematic`.
#' Native-status classification is a separate step: [detect_native_coord()]
#' classifies the records with validated coordinates, and
#' [detect_native_country()] the coordinate-less records (taken directly from
#' `custom_filtered`).
#'
#' @param custom_filtered A `customFiltered` object returned by
#'   [custom_filter()].
#' @param threads Number of threads to use for coordinate validation, passed to
#'   [set_threads()]. Use an integer `>= 1` for an absolute count, or a value
#'   between `0` and `1` for a proportion of available cores. The default is
#'   `4`.
#' @param tests Character vector of CoordinateCleaner validation tests to
#'   apply. Choose one or more of `"capitals"`, `"centroids"`, `"equal"`,
#'   `"gbif"`, `"institutions"`, `"outliers"`, `"seas"`, and `"zeros"`. The
#'   default uses all tests.
#'
#' @details
#' ## Coordinate validation
#'
#' Coordinate validation is performed with CoordinateCleaner. Available tests
#' are:
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
#' ## Parallel processing
#'
#' Records with complete coordinates are chunked across the requested number of
#' workers and validated with `foreach` and `doParallel`. The worker count is
#' capped to the number of records to avoid idle cluster nodes.
#'
#' ## Empty input
#'
#' If no records have complete coordinates, validation is skipped and empty
#' `CoordinateCleaned` and `CoordinateProblematic` tables are returned.
#'
#' @returns A `CoordinateRefined` object (list) with three elements:
#'
#' - `CoordinateCleaned`: a `data.table` of records that passed all requested
#'   coordinate tests
#' - `CoordinateProblematic`: a `data.table` of records that failed one or more
#'   tests, retaining the CoordinateCleaner flag columns (e.g. `.summary`) so
#'   the failing tests can be inspected
#' - `runtime`: the elapsed execution time
#'
#' Use [detect_native_coord()] to classify the records with validated
#' coordinates, and [detect_native_country()] for the coordinate-less records.
#'
#' @references
#'
#' - Zizka, A., Silvestro, D., Andermann, T., Azevedo, J., Duarte Ritter, C., Edler, D., Farooq,
#'   H., Herdean, A., Ariza, M., Scharn, R., Svantesson, S., Wengstrom, N., Vitecek, S., &
#'   Antonelli, A. (2019). CoordinateCleaner: Standardized cleaning of occurrence records from
#'   biological collection databases. *Methods in Ecology and Evolution*, 10(5), 744-751.
#'   \doi{10.1111/2041-210X.13152}
#'
#' @import data.table
#' @importFrom dplyr %>%
#' @import foreach
#' @import doParallel
#' @import rnaturalearthdata
#' @seealso [`clean_coordinates()`][CoordinateCleaner::clean_coordinates],
#'   [custom_filter()], [detect_native_coord()], [detect_native_country()],
#'   [export_records()], [print.CoordinateRefined()], [set_threads()]
#' @examplesIf interactive() && exists("filtered")
#' refined_coordinates(custom_filtered = filtered, threads = 4)
#' @export
refine_coordinates <- function(
  custom_filtered = NA,
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

  # ---- validate inputs ----
  if (!inherits(custom_filtered, "customFiltered")) {
    stop(
      '`custom_filtered` must be a "customFiltered" object from custom_filter().'
    )
  }
  required_cols <- c(
    "gbifID",
    "decimalLatitude",
    "decimalLongitude",
    "Accepted_name_id"
  )
  missing_cols <- setdiff(required_cols, names(custom_filtered$occ_filtered))
  if (length(missing_cols) > 0L) {
    stop(
      "`custom_filtered$occ_filtered` is missing required column(s): ",
      paste(missing_cols, collapse = ", ")
    )
  }

  # ---- validate tests ----
  valid_tests <- c(
    "capitals",
    "centroids",
    "equal",
    "gbif",
    "institutions",
    "outliers",
    "seas",
    "zeros"
  )
  bad_tests <- setdiff(tests, valid_tests)
  if (length(bad_tests) > 0L) {
    stop(
      "Unknown test(s): ",
      paste(bad_tests, collapse = ", "),
      ". Valid tests are: ",
      paste(valid_tests, collapse = ", ")
    )
  }

  filtered <- custom_filtered$occ_filtered[
    !is.na(decimalLatitude) & !is.na(decimalLongitude)
  ] %>%
    as.data.table()

  message("Validating coordinates")

  threads <- threads %>% as.numeric() %>% set_threads()

  # ---- empty data guard ----
  if (nrow(filtered) == 0L) {
    message("No records with complete coordinates; skipping validation.")
    used <- Sys.time() - start
    message(paste('used', used %>% round(1), attributes(used)$units))
    refined_coordinates <- list(
      CoordinateCleaned = filtered,
      CoordinateProblematic = data.table(),
      runtime = used
    )
    class(refined_coordinates) <- 'CoordinateRefined'
    return(refined_coordinates)
  }

  # cap workers to available records (avoid idle cluster nodes)
  n_workers <- max(1L, min(threads, nrow(filtered)))

  chunks_list <- filtered[, .(
    gbifID,
    decimalLongitude,
    decimalLatitude,
    Accepted_name_id
  )] %>%
    split(., ceiling(seq_len(nrow(.)) / (nrow(.) / n_workers)))

  WorldLandMap <- WorldLandMap

  coord <- function(data) {
    suppressWarnings(CoordinateCleaner::clean_coordinates(
      data,
      lon = "decimalLongitude",
      lat = "decimalLatitude",
      species = "Accepted_name_id",
      tests = tests,
      seas_ref = WorldLandMap,
      value = "spatialvalid",
      verbose = FALSE
    ))
  }

  cl <- parallel::makeCluster(n_workers)
  # always release the cluster, even on error
  on.exit(
    {
      parallel::stopCluster(cl)
      foreach::registerDoSEQ()
    },
    add = TRUE
  )

  registerDoParallel(cl)

  CoordinateFlagged <- foreach(
    data = chunks_list,
    .multicombine = TRUE,
    .errorhandling = "remove",
    .packages = c("CoordinateCleaner", "rnaturalearthdata", "dplyr"),
    .inorder = FALSE
  ) %dopar%
    {
      coord(data)
    }

  CoordinateFlagged <- rbindlist(CoordinateFlagged, fill = TRUE)

  CoordinateProblematic <- CoordinateFlagged[.summary == FALSE]

  CoordinateCleaned <- CoordinateFlagged[.summary == TRUE, gbifID]

  rm(chunks_list, CoordinateFlagged)

  results <- filtered[gbifID %chin% CoordinateCleaned]

  used <- Sys.time() - start
  message(paste('used', used %>% round(1), attributes(used)$units))

  refined_coordinates <- list(
    CoordinateCleaned = results,
    CoordinateProblematic = CoordinateProblematic,
    runtime = used
  )
  class(refined_coordinates) <- 'CoordinateRefined'
  return(refined_coordinates)
}

#' Print a `CoordinateRefined` object
#'
#' Displays a compact summary of a coordinate-refinement result: the number of
#' records in each output table and the elapsed runtime. The records themselves
#' are not shown; use [head()] or `View()` to inspect them.
#'
#' @param x An object of class `"CoordinateRefined"` returned by
#'   [refine_coordinates()].
#' @param ... Additional arguments (unused, retained for S3 compatibility).
#'
#' @return Invisibly returns `x`.
#'
#' @export
print.CoordinateRefined <- function(x, ...) {
  count_rows <- function(nm) {
    if (is.data.frame(x[[nm]])) nrow(x[[nm]]) else 0L
  }

  counts <- data.table(
    table = c("CoordinateCleaned", "CoordinateProblematic"),
    n = vapply(
      c("CoordinateCleaned", "CoordinateProblematic"),
      count_rows,
      integer(1)
    )
  )

  cat("<CoordinateRefined> ", sum(counts$n), " records", sep = "")
  cat("\n\n")
  print(counts)
  if (!is.null(x$runtime)) {
    cat("\nruntime: ", format(x$runtime), "\n", sep = "")
  }

  invisible(x)
}
