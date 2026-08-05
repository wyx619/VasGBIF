#' @title Export refined records to compressed CSV files
#'
#' @description Writes the results of [refine_coordinates()] and
#'   [detect_native_status()] to disk as gzip-compressed CSV files. Three files
#'   are exported: all refined records joined with their native status, the
#'   native subset, and records that failed coordinate validation.
#'
#' @param refined_coordinates A `CoordinateRefined` object returned by
#'   [refine_coordinates()].
#' @param native_detected A `nativeDetected` object returned by
#'   [detect_native_status()].
#' @param export_path Directory where the compressed CSV files should be written.
#'
#' @returns Called for its side effect of writing files to `export_path`. Returns
#'   `NULL` invisibly.
#'
#' @details
#' The following files are written:
#'
#' - `all_records.csv.gz`: all refined records — those with validated
#'   coordinates and those without — joined with their native status by `gbifID`
#' - `native_records.csv.gz`: the subset classified as `"native"`
#' - `CoordinateProblematic_records.csv.gz`: records that failed one or more
#'   CoordinateCleaner tests
#'
#' Files are written with `fwrite(encoding = "UTF-8")`. `export_path` is
#' validated before writing: if it is not a single character path or exists as
#' a file (not a directory), the function stops with an error; if it does not
#' exist, a warning is emitted and the directory is created automatically.
#'
#' The data inputs are validated first: `refined_coordinates` must be a
#' `CoordinateRefined` object whose `CoordinateCleaned` and `Coordinateless`
#' tables share identical columns and contain `gbifID`; `native_detected` must
#' be a `nativeDetected` object with `gbifID` and `native_status`.
#'
#' @import data.table
#' @importFrom dplyr %>% filter
#' @seealso [refine_coordinates()], [detect_native_status()]
#' @export
export_records <- function(
  refined_coordinates = NA,
  native_detected = NA,
  export_path = NA
) {
  # ---- validate inputs ----
  if (!inherits(refined_coordinates, "CoordinateRefined")) {
    stop(
      '`refined_coordinates` must be a "CoordinateRefined" object from refine_coordinates().'
    )
  }
  if (!inherits(native_detected, "nativeDetected")) {
    stop(
      '`native_detected` must be a "nativeDetected" object from detect_native_status().'
    )
  }

  cleaned <- refined_coordinates$CoordinateCleaned
  coordinateless <- refined_coordinates$Coordinateless
  problematic <- refined_coordinates$CoordinateProblematic

  if (!is.data.frame(cleaned)) {
    stop("`refined_coordinates$CoordinateCleaned` must be a data.frame.")
  }
  if (!is.data.frame(coordinateless)) {
    stop("`refined_coordinates$Coordinateless` must be a data.frame.")
  }
  if (!is.data.frame(problematic)) {
    stop("`refined_coordinates$CoordinateProblematic` must be a data.frame.")
  }

  for (nm in c("CoordinateCleaned", "Coordinateless")) {
    missing_cols <- setdiff("gbifID", names(refined_coordinates[[nm]]))
    if (length(missing_cols) > 0L) {
      stop(
        "`refined_coordinates$",
        nm,
        "` is missing required column(s): ",
        paste(missing_cols, collapse = ", ")
      )
    }
  }

  # CoordinateCleaned and Coordinateless are rbind-ed, so columns must match
  if (!identical(sort(names(cleaned)), sort(names(coordinateless)))) {
    stop(
      "`refined_coordinates$CoordinateCleaned` and `$Coordinateless` must have identical columns."
    )
  }

  missing_status_cols <- setdiff(
    c("gbifID", "native_status"),
    names(native_detected)
  )
  if (length(missing_status_cols) > 0L) {
    stop(
      "`native_detected` is missing required column(s): ",
      paste(missing_status_cols, collapse = ", ")
    )
  }

  # ---- validate export path ----
  if (
    !is.character(export_path) || length(export_path) != 1 || is.na(export_path)
  ) {
    stop("export_path must be a single directory path, not NA")
  }

  if (dir.exists(export_path)) {
    # directory already exists — proceed
  } else if (file.exists(export_path)) {
    stop("export_path exists but is a file, not a directory: ", export_path)
  } else {
    warning("export_path does not exist, creating: ", export_path)
    dir.create(export_path, recursive = TRUE)
  }

  all_records <- cleaned %>%
    rbind(coordinateless) %>%
    merge(native_detected, by = 'gbifID')

  message(paste(all_records[, .N], 'records finally left'))

  native_records <- all_records[native_status == "native", ]

  message(paste(native_records[, .N], 'of them are native'))

  tryCatch(
    {
      message("Exporting records")
      fwrite(
        all_records,
        file = file.path(export_path, 'all_records.csv.gz'),
        encoding = "UTF-8"
      )
      fwrite(
        native_records,
        file = file.path(export_path, 'native_records.csv.gz'),
        encoding = "UTF-8"
      )
      fwrite(
        problematic,
        file = file.path(export_path, 'CoordinateProblematic_records.csv.gz'),
        encoding = "UTF-8"
      )
      message("Done")
    },
    error = function(e) {
      stop("File export failed: ", e$message)
    }
  )
}
