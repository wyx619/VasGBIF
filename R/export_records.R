#' @title Export refined records to compressed CSV files
#'
#' @description Writes the output of [refine_records()] to disk as gzip-compressed
#' CSV files. Three files are exported: all usable records, the native subset,
#' and records that failed coordinate validation.
#'
#' @param refined_records A `refined` object returned by [refine_records()].
#' @param export_path Directory where the compressed CSV files should be written.
#'
#' @returns Called for its side effect of writing files to `export_path`. Returns
#'   `NULL` invisibly.
#'
#' @details
#' The following files are written:
#'
#' - `usable_refined_records.csv.gz`: all records with validated coordinates
#'   and assigned native status
#' - `native_refined_records.csv.gz`: the subset classified as native
#' - `CoordinateProblematic_records.csv.gz`: records that failed one or more
#'   CoordinateCleaner tests
#'
#' Files are written with `fwrite(encoding = "UTF-8")`. `export_path` is
#' validated before writing: if it exists as a file (not a directory) or is
#' `NA`, the function stops with an error; if it does not exist, a warning is
#' emitted and the directory is created automatically.
#'
#' @import data.table
#' @seealso [refine_records()]
#' @export
export_records <- function(refined_records = NA, export_path = NA) {
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

  all_records <- refined_records$all_records
  native_records <- all_records[native_status == "native", ]
  CoordinateProblematic <- refined_records$CoordinateProblematic

  tryCatch(
    {
      message("Exporting records")
      fwrite(
        all_records,
        file = file.path(export_path, 'usable_refined_records.csv.gz'),
        encoding = "UTF-8"
      )
      fwrite(
        native_records,
        file = file.path(export_path, 'native_refined_records.csv.gz'),
        encoding = "UTF-8"
      )
      fwrite(
        CoordinateProblematic,
        file = file.path(export_path, 'CoordinateProblematic_records.csv.gz'),
        encoding = "UTF-8"
      )
      message("Exported")
    },
    error = function(e) {
      stop("File export failed: ", e$message)
    }
  )
}
