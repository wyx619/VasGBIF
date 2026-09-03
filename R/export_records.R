#' @title Export classified records to compressed CSV files
#'
#' @description Writes the results of [detect_native_coord()] to disk as
#'   gzip-compressed CSV files. Two files are exported: all classified records
#'   and the native subset.
#'
#' @param native_detected_coord A `nativeDetected` object returned by
#'   [detect_native_coord()], containing records with validated coordinates.
#' @param export_path Directory where the compressed CSV files should be written.
#'
#' @returns Called for its side effect of writing files to `export_path`. Returns
#'   `NULL` invisibly.
#'
#' @details
#' The following files are written:
#'
#' - `all_records.csv.gz`: every classified record with validated coordinates,
#'   with all its columns and its native status
#' - `native_records.csv.gz`: the subset classified as `"native"`
#'
#' `native_detected_coord` already carries every column of the input records, so
#' no join is performed here: `all_records.csv.gz` is written straight from it.
#'
#' `native_detected_coord` must carry coordinates for every record: it is the
#' spatial output of [detect_native_coord()], which only classifies records
#' with validated coordinates. The function stops if `decimalLongitude` or
#' `decimalLatitude` is missing for any record - the output of
#' [detect_native_country()] would be rejected this way. Records without
#' coordinates are classified separately by [detect_native_country()]; to
#' export both sets together, bind the two results before calling this
#' function.
#'
#' Files are written with `fwrite(encoding = "UTF-8")`. `export_path` is
#' validated before writing: if it is not a single character path or exists as
#' a file (not a directory), the function stops with an error; if it does not
#' exist, a warning is emitted and the directory is created automatically.
#'
#' @import data.table
#' @seealso [detect_native_coord()], [detect_native_country()],
#'   [clean_coordinates()]
#' @export
export_records <- function(
  native_detected_coord = NA,
  export_path = NA
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
    "decimalLongitude",
    "decimalLatitude"
  )
  missing_cols <- setdiff(required_cols, names(native_detected_coord))
  if (length(missing_cols) > 0L) {
    stop(
      "`native_detected_coord` is missing required column(s): ",
      paste(missing_cols, collapse = ", ")
    )
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

  # ---- validate export path ----
  if (
    !is.character(export_path) || length(export_path) != 1 || is.na(export_path)
  ) {
    stop("export_path must be a single directory path, not NA")
  }

  if (dir.exists(export_path)) {
    # directory already exists - proceed
  } else if (file.exists(export_path)) {
    stop("export_path exists but is a file, not a directory: ", export_path)
  } else {
    warning("export_path does not exist, creating: ", export_path)
    dir.create(export_path, recursive = TRUE)
  }

  # `detect_native_coord()` returns the record columns alongside the status,
  # so this is the export table as-is -- no join, no column selection.
  all_records <- native_detected_coord

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
      message("Done")
    },
    error = function(e) {
      stop("File export failed: ", e$message)
    }
  )
}
