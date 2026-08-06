#' @title Export classified records to compressed CSV files
#'
#' @description Writes the results of [detect_native_status()] to disk as
#'   gzip-compressed CSV files. Two files are exported: all classified records
#'   and the native subset.
#'
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
#' - `all_records.csv.gz`: every classified record — those with validated
#'   coordinates and those without — with all its columns and its native status
#' - `native_records.csv.gz`: the subset classified as `"native"`
#'
#' `native_detected` already carries every column of the input records, so no
#' join is performed here: `all_records.csv.gz` is written straight from it.
#' Records that failed coordinate validation are never classified and therefore
#' do not appear in the output; use [refine_coordinates()] to inspect them.
#'
#' Files are written with `fwrite(encoding = "UTF-8")`. `export_path` is
#' validated before writing: if it is not a single character path or exists as
#' a file (not a directory), the function stops with an error; if it does not
#' exist, a warning is emitted and the directory is created automatically.
#'
#' @import data.table
#' @seealso [detect_native_status()], [refine_coordinates()]
#' @export
export_records <- function(
  native_detected = NA,
  export_path = NA
) {
  # ---- validate inputs ----
  if (!inherits(native_detected, "nativeDetected")) {
    stop(
      '`native_detected` must be a "nativeDetected" object from detect_native_status().'
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

  # `detect_native_status()` returns the record columns alongside the status,
  # so this is the export table as-is -- no join, no column selection.
  all_records <- native_detected

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
