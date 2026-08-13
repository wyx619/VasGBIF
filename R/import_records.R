#' Import GBIF occurrence records
#'
#' Reads a GBIF occurrence download in 'SIMPLE_CSV' or Darwin Core Archive
#' ('DWCA') format from a ZIP file, extracts the occurrence data file, and
#' returns a `data.table` of the fields required by the 'VasGBIF' workflow.
#' The returned table is the direct input to [extract_gbif_issues()].
#'
#' @param path Character scalar. Path to a GBIF occurrence ZIP download in
#'   'SIMPLE_CSV' or 'DWCA' format. The archive must contain a tab-separated
#'   occurrence data file, named `occurrence.txt` when the archive contains
#'   more than one member (as in a Darwin Core Archive).
#' @param tempdir Character scalar or `NULL`. Directory into which the ZIP
#'   archive is extracted.
#'
#'   * `NULL` (default): a unique subdirectory is created inside the system
#'     temporary directory via [base::tempfile()], and it is deleted on exit
#'     unless `remove_tempfile = FALSE`.
#'   * A user-supplied path: if the directory does not exist it is created
#'     (recursively). If it already exists and contains files, a warning is
#'     issued because those files may be overwritten. The directory is
#'     **not** deleted on exit by default; set `remove_tempfile = TRUE` to
#'     override.
#' @param remove_tempfile Logical scalar or `NULL`. Controls whether the
#'   extraction directory is deleted when the function exits (including after
#'   an error).
#'
#'   * `NULL` (default): behaves as `TRUE` when `tempdir = NULL` (auto
#'     directory is cleaned up), and as `FALSE` when the user supplies a
#'     `tempdir` (the directory is kept).
#'   * `TRUE` or `FALSE`: override the default in either direction.
#'
#' @details
#' The archive is extracted into a dedicated directory rather than next to the
#' ZIP file, so a ZIP stored in `inst/extdata` is never modified.
#'
#' The function performs the following steps:
#'
#' * Validates that `path` is a non-empty character string with a `.zip`
#'   extension.
#' * Lists the archive members; a 'SIMPLE_CSV' download holds a single data
#'   file which is extracted by name, while a 'DWCA' holds several members
#'   (typically `meta.xml`, `occurrence.txt`, and extension files) and its
#'   `occurrence.txt` core file is assumed.
#' * Reads the tab-separated, UTF-8 occurrence file with
#'   [data.table::fread()], selecting only the GBIF fields used by VasGBIF.
#' * Coerces `gbifID` to character.
#'
#' No records are filtered, corrected, or removed at this stage. All diagnostic
#' fields - including the raw `issue` column - are preserved so that
#' [extract_gbif_issues()] can parse them in the next step.
#'
#' @returns
#' A `data.table` of class `"import"` containing the selected occurrence
#' fields with Darwin Core / GBIF column names. The `gbifID` column is always
#' character. The `issue` column contains raw pipe-separated GBIF issue codes
#' and is consumed by [extract_gbif_issues()].
#'
#' @seealso
#' * [extract_gbif_issues()] for the next step: parsing the `issue` column into
#'   logical indicator columns.
#' * [print.import()] for a one-line record count.
#' * [data.table::fread()] for delimited-file import.
#' * [`unzip()`][utils::unzip] for ZIP archive handling.
#' * [GBIF download formats](https://techdocs.gbif.org/en/data-use/download-formats)
#'   for the difference between 'SIMPLE_CSV' and 'DWCA' downloads.
#'
#' @import data.table
#' @importFrom dplyr %>%
#' @importFrom utils unzip
#' @importFrom tools file_ext
#'
#' @examplesIf interactive()
#' gbif_file <- system.file(
#'   "extdata",
#'   "0003386-260721160103020.zip",
#'   package = "VasGBIF"
#' )
#' occ <- import_records(path = gbif_file)
#' occ_import <- extract_gbif_issues(occ)
#' head(occ_import$summary, 5)
#'
#' # Extract to a specific directory and keep it afterwards.
#' # occ <- import_records(path = gbif_file, tempdir = "~/gbif_extracted")
#'
#' @references
#' GBIF.org (23 July 2026) GBIF Occurrence Download
#' \doi{10.15468/dl.nt5exp}
#'
#' @export
import_records <- function(path = '', tempdir = NULL, remove_tempfile = NULL) {
  t1 <- Sys.time()
  if (!is.character(path) || length(path) != 1L) {
    stop('`path` must be a single character string.')
  }
  if (path == '') {
    stop('`path` is empty. Provide the path to a GBIF SIMPLE_CSV or DWCA zip.')
  }
  if (tolower(tools::file_ext(path)) != "zip") {
    stop(
      '`path` must point to a .zip file from a GBIF SIMPLE_CSV or DWCA download.'
    )
  }

  fields <- c(
    "gbifID",
    "order",
    "family",
    "species",
    "taxonRank",
    "scientificName",
    "verbatimScientificName",
    "countryCode",
    "locality",
    "occurrenceStatus",
    "decimalLatitude",
    "decimalLongitude",
    "coordinateUncertaintyInMeters",
    "elevation",
    "eventDate",
    "day",
    "month",
    "year",
    "basisOfRecord",
    "institutionCode",
    "collectionCode",
    "identifiedBy",
    "recordedBy",
    "issue"
  )

  archive_files <- utils::unzip(path, list = TRUE)$Name
  if (length(archive_files) != 1L) {
    archive_files <- 'occurrence.txt'
  }

  # Resolve extraction directory and cleanup behaviour
  if (is.null(tempdir)) {
    ex_path <- base::tempfile("VasGBIF-")
    dir.create(ex_path)
    if (is.null(remove_tempfile)) remove_tempfile <- TRUE
  } else {
    if (!is.character(tempdir) || length(tempdir) != 1L) {
      stop('`tempdir` must be a single character string.')
    }
    ex_path <- tempdir
    if (!dir.exists(ex_path)) {
      message("Creating directory: ", ex_path)
      dir.create(ex_path, recursive = TRUE, showWarnings = FALSE)
    } else {
      n_existing <- length(list.files(ex_path))
      if (n_existing > 0L) {
        warning(
          "Directory '",
          ex_path,
          "' already contains ",
          n_existing,
          " file(s); existing files with the same name will be overwritten.",
          call. = FALSE
        )
      }
    }
    if (is.null(remove_tempfile)) remove_tempfile <- FALSE
  }

  if (isTRUE(remove_tempfile)) {
    on.exit(unlink(ex_path, recursive = TRUE, force = TRUE), add = TRUE)
  } else {
    message("Extracted files will be preserved in: ", ex_path)
  }

  message("Decompressing")
  utils::unzip(
    path,
    files = archive_files,
    exdir = ex_path,
    list = FALSE,
    overwrite = TRUE,
    junkpaths = FALSE,
    unzip = "internal",
    setTimes = FALSE
  )

  message("Loading records")
  occ <- fread(
    file.path(ex_path, archive_files),
    sep = '\t',
    encoding = 'UTF-8',
    select = fields,
    quote = "",
    showProgress = FALSE
  )
  occ[, gbifID := as.character(gbifID)]

  class(occ) <- c('import', class(occ))
  used <- Sys.time() - t1
  message(paste('used', used %>% round(1), attributes(used)$units))
  occ
}

#' Print an `import` object
#'
#' Displays a one-line summary of an imported GBIF download: the number of
#' occurrence records.
#'
#' @param x An object of class `"import"` returned by [import_records()].
#' @param ... Additional arguments (unused, retained for S3 compatibility).
#'
#' @return Invisibly returns `x`.
#'
#' @export
print.import <- function(x, ...) {
  n_records <- if (is.data.frame(x)) nrow(x) else 0L
  cat("<import> ", n_records, " records\n", sep = "")
  invisible(x)
}
