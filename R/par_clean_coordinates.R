#' @title Validate coordinates of filtered occurrence records
#' @name par_clean_coordinates
#'
#' @description Validates the coordinates of occurrence records with
#'   CoordinateCleaner and splits them into coordinate-clean and problematic
#'   tables. Any table with a taxon column and complete coordinate columns is
#'   accepted, so the function does not depend on the output of
#'   [customized_filter()].
#'
#' [CoordinateCleaner::clean_coordinates] checks run in parallel to flag
#' common spatial issues such as centroids, capitals, and marine records.
#'
#' Records that pass all requested tests are returned in `CoordinateCleaned`;
#' records that fail one or more tests, along with records lacking coordinates,
#' are returned in `CoordinateProblematic`. The latter carries one logical
#' column per test applied, so a flagged record can be traced to the specific
#' test(s) it failed. Native-status classification is a separate step:
#' [detect_native_coord()] classifies the records with validated coordinates,
#' and [detect_native_country()] the coordinate-less records (extracted from
#' `CoordinateProblematic`).
#'
#' @param input A table of occurrence records, with
#'   coordinates that are complete, i.e. neither longitude nor latitude may be
#'   `NA`; records missing either are returned in `CoordinateProblematic`
#'   without being validated. Typically `filtered$occ_filtered`, the table
#'   returned by [customized_filter()]. If the table has no `gbifID` column,
#'   one is created as a character sequence number over the input rows.
#' @param species Name of the column giving the taxon each record belongs to,
#'   used to group records for the `outliers` test. Defaults to
#'   `"Accepted_name_id"`, the column produced by [customized_filter()].
#' @param longitude,latitude Names of the longitude and latitude columns.
#'   Default to `"decimalLongitude"` and `"decimalLatitude"`, the names
#'   produced by [customized_filter()].
#' @param threads Number of threads to use for coordinate validation, passed to
#'   [set_threads()]. Use an integer `>= 1` for an absolute count, or a value
#'   between `0` and `1` for a proportion of available cores. The default is
#'   `4`.
#' @param tests Character vector of CoordinateCleaner validation tests to
#'   apply. Choose one or more of `"capitals"`, `"centroids"`, `"equal"`,
#'   `"gbif"`, `"institutions"`, `"outliers"`, `"seas"`, and `"zeros"`. The
#'   default uses all tests. Each test adds its own verdict column to
#'   `CoordinateProblematic`; see *Verdict columns*.
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
#' The `seas` test is evaluated against the bundled `WorldLandMap` land
#' polygons buffered by 5 km. The buffer absorbs records that a coarse
#' coastline places just offshore, which would otherwise be reported as sea
#' records; it is applied because the map is a low-resolution outline, not
#' because those records are expected to be at sea.
#'
#' ## Parallel processing
#'
#' Records with complete coordinates are chunked across the requested number of
#' workers and validated with `foreach` and `doParallel`. The worker count is
#' capped to the number of species and of records, so no worker is left idle.
#'
#' Chunks are built from species, not from consecutive rows: every record of a
#' species is kept in one chunk, and whole species are assigned to the chunk
#' that currently holds the fewest records, which keeps chunk sizes close to
#' equal. Records of a species must not be split across workers because the
#' `outliers` test judges each record against the distribution of its own
#' species, so splitting them would change which records are flagged.
#'
#' ## Verdict columns
#'
#' `CoordinateProblematic` gains one logical column per test listed in `tests`,
#' named after the corresponding CoordinateCleaner flag (`.cap` for `capitals`,
#' `.cen` for `centroids`, `.equ` for `equal`, `.gbf` for `gbif`, `.inst` for
#' `institutions`, `.otl` for `outliers`, `.sea` for `seas`, and `.zer` for
#' `zeros`). `TRUE` means the record passed that test, `FALSE` means it failed
#' it, and records that never reached validation keep `NA` throughout, which is
#' how coordinate-less records can be told apart from flagged ones. These
#' columns are appended after the occurrence columns. `CoordinateCleaned` holds
#' records that passed every test and keeps the occurrence columns only.
#'
#' ## Empty input
#'
#' If no records have complete coordinates, validation is skipped. An empty
#' `CoordinateCleaned` table is returned, while records lacking coordinates are
#' placed in `CoordinateProblematic`, with every verdict column set to `NA`.
#'
#' @returns A `CoordinateRefined` object (list) with three elements:
#'
#' - `CoordinateCleaned`: a `data.table` of records that passed all requested
#'   coordinate tests (complete data with valid coordinates)
#' - `CoordinateProblematic`: a `data.table` containing (1) records that failed
#'   one or more coordinate tests, and (2) records lacking complete coordinates
#'   (missing latitude or longitude). The two kinds of record are told apart by
#'   the verdict columns described in *Verdict columns*: they are all `NA` for
#'   the coordinate-less records and for the other records at least one is
#'   `FALSE`, the columns for the remaining tests being `TRUE`
#' - `runtime`: the elapsed execution time
#'
#' Use [detect_native_coord()] to classify the records with validated
#' coordinates, and [detect_native_country()] for the coordinate-less records
#' from `CoordinateProblematic`.
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
#' @seealso [CoordinateCleaner::clean_coordinates()], [customized_filter()],
#'   [detect_native_coord()], [detect_native_country()], [export_records()],
#'   [print.CoordinateRefined()], [set_threads()]
#' @examplesIf interactive() && exists("filtered")
#' cleaned_coordinates <- par_clean_coordinates(filtered$occ_filtered, threads = 4)
#'
#' cleaned_coordinates
#' # the test each flagged record failed
#' cleaned_coordinates$CoordinateProblematic[.otl == FALSE]
#'
#' # the column names can be mapped explicitly instead
#' par_clean_coordinates(
#'   filtered$occ_filtered,
#'   species = "Accepted_name_id",
#'   longitude = "decimalLongitude",
#'   latitude = "decimalLatitude"
#' )
#' @export
par_clean_coordinates <- function(
  input = NA,
  species = "Accepted_name_id",
  longitude = "decimalLongitude",
  latitude = "decimalLatitude",
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

  # A `customFiltered` object is a list of tables, so it reaches
  # `as.data.table()` and fails there with an opaque coercion error. Catch it
  # first and name the table this function actually wants.
  if (inherits(input, "customFiltered")) {
    stop(
      "`input` is a `customFiltered` object, not a table. Pass the table it ",
      "contains, for example `par_clean_coordinates(filtered$occ_filtered)`.",
      call. = FALSE
    )
  }

  # copied because `:=` below would otherwise modify the caller's data.table
  records <- data.table::copy(data.table::as.data.table(input))
  if (!"gbifID" %in% names(records)) {
    records[, gbifID := as.character(seq_len(.N))]
    data.table::setcolorder(records, "gbifID")
  }

  # ---- validate the column names ----
  for (arg in c("species", "longitude", "latitude")) {
    col <- get(arg)
    if (!is.character(col) || length(col) != 1L || is.na(col)) {
      stop("`", arg, "` must be a single column name.")
    }
  }
  missing_cols <- setdiff(c(species, longitude, latitude), names(records))
  if (length(missing_cols) > 0L) {
    stop(
      "Column(s) not found in `input`: ",
      paste(missing_cols, collapse = ", ")
    )
  }
  if (anyDuplicated(c(species, longitude, latitude))) {
    stop("`species`, `longitude`, and `latitude` must name distinct columns.")
  }
  threads_num <- suppressWarnings(as.numeric(threads))
  if (length(threads_num) != 1L || is.na(threads_num) || threads_num <= 0) {
    stop("`threads` must be a single positive number; see set_threads().")
  }
  # resolved here, so an invalid `threads` fails before any chunking
  threads <- set_threads(threads_num)

  # ---- validate tests ----
  # single source of truth for the test names and the verdict column each test
  # writes into the `clean_coordinates()` result
  test_flag <- c(
    capitals = ".cap",
    centroids = ".cen",
    equal = ".equ",
    gbif = ".gbf",
    institutions = ".inst",
    outliers = ".otl",
    seas = ".sea",
    zeros = ".zer"
  )
  bad_tests <- setdiff(tests, names(test_flag))
  if (length(bad_tests) > 0L) {
    stop(
      "Unknown test(s): ",
      paste(bad_tests, collapse = ", "),
      ". Valid tests are: ",
      paste(names(test_flag), collapse = ", ")
    )
  }
  tests <- unique(tests)
  flag_cols <- unname(test_flag[tests])

  # verdict columns for records that never reached validation: present, but NA
  blank_flags <- function(x) {
    x <- data.table::copy(x)
    if (length(flag_cols) > 0L) {
      x[, (flag_cols) := NA]
    }
    x
  }

  complete_coord <- !is.na(records[[longitude]]) & !is.na(records[[latitude]])
  filtered <- records[complete_coord]
  no_coord <- records[!complete_coord]

  message("Validating coordinates")

  # ---- empty data guard ----
  if (nrow(filtered) == 0L) {
    message("No records with complete coordinates; skipping validation.")
    used <- Sys.time() - start
    message(paste('used', used %>% round(1), attributes(used)$units))
    cleaned_coordinates <- list(
      CoordinateCleaned = data.table(),
      CoordinateProblematic = blank_flags(no_coord),
      runtime = used
    )
    class(cleaned_coordinates) <- 'CoordinateRefined'
    return(cleaned_coordinates)
  }

  # cap workers to what can actually be used (avoid idle cluster nodes)
  worker_count <- max(
    1L,
    min(threads, uniqueN(filtered[[species]]), nrow(filtered))
  )

  # chunk by species, never by row: the outlier test judges each record against
  # the distribution of its own species, so a species must not be split across
  # workers. Greedy balancing keeps the chunks near equal in size.
  species_n <- filtered[, .N, by = c(species)][order(-N)]
  load <- numeric(worker_count)
  species_bin <- integer(nrow(species_n))
  for (i in seq_len(nrow(species_n))) {
    bin <- which.min(load)
    species_bin[i] <- bin
    load[bin] <- load[bin] + species_n$N[i]
  }
  row_bin <- species_bin[match(filtered[[species]], species_n[[species]])]

  # only the four columns the validation needs are shipped to the workers
  chunk_cols <- c("gbifID", longitude, latitude, species)
  chunks_list <- lapply(
    split(filtered, row_bin),
    function(x) x[, chunk_cols, with = FALSE]
  )

  WorldLandMap <- WorldLandMap

  coord <- function(data) {
    suppressWarnings(CoordinateCleaner::clean_coordinates(
      # clean_coordinates() is written for data.frame input. Handed a
      # data.table it resolves the species/lon/lat columns differently inside
      # the outlier test and silently flags far fewer records, in a way that
      # also depends on how the records are chunked.
      as.data.frame(data),
      lon = longitude,
      lat = latitude,
      species = species,
      tests = tests,
      seas_ref = WorldLandMap,
      # a 5 km buffer absorbs coordinates that the coarse coastline pushes just
      # offshore; without it such records are reported as sea records
      seas_buffer = 5000,
      value = "spatialvalid",
      verbose = FALSE
    ))
  }

  cl <- parallel::makeCluster(worker_count)
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
    .errorhandling = "stop",
    .packages = c("CoordinateCleaner", "dplyr"),
    .inorder = FALSE
  ) %dopar%
    {
      coord(data)
    }

  CoordinateFlagged <- rbindlist(CoordinateFlagged, fill = TRUE)

  # guard against a chunk silently going missing, which would drop its records
  if (anyNA(match(filtered$gbifID, CoordinateFlagged$gbifID))) {
    stop("Validation results are incomplete: some records were never returned.")
  }

  # per-test verdicts, carried over as `TRUE` = passed and `FALSE` = failed;
  # records that never reached validation keep `NA`
  failed_ids <- CoordinateFlagged[.summary == FALSE, gbifID]
  verdicts <- CoordinateFlagged[, c("gbifID", flag_cols), with = FALSE]

  CoordinateProblematic <- merge(
    filtered[gbifID %chin% failed_ids],
    verdicts,
    by = "gbifID",
    sort = FALSE,
    allow.cartesian = TRUE
  ) %>%
    rbind(blank_flags(no_coord), fill = TRUE)

  CoordinateCleaned <- filtered[
    gbifID %chin% CoordinateFlagged[.summary == TRUE, gbifID]
  ]

  used <- Sys.time() - start
  message(paste('used', used %>% round(1), attributes(used)$units))
  rm(chunks_list, CoordinateFlagged, verdicts, failed_ids)
  cleaned_coordinates <- list(
    CoordinateCleaned = CoordinateCleaned,
    CoordinateProblematic = CoordinateProblematic,
    runtime = used
  )
  class(cleaned_coordinates) <- 'CoordinateRefined'
  return(cleaned_coordinates)
}

#' Print a `CoordinateRefined` object
#'
#' Displays a compact summary of a coordinate-refinement result: the number of
#' records in each output table and the elapsed runtime. The records themselves
#' are not shown; use [head()] or `View()` to inspect them.
#'
#' @param x An object of class `"CoordinateRefined"` returned by
#'   [par_clean_coordinates()].
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
