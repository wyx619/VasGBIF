#' Import GBIF occurrence records
#'
#' Reads a GBIF occurrence download and returns a `data.table` of the fields
#' required by the 'VasGBIF' workflow.
#'
#' Two kinds of input are accepted, chosen by the file extension:
#'
#' * A ZIP archive in 'SIMPLE_CSV' or Darwin Core Archive ('DWCA') format. The
#'   occurrence data file is extracted and read from there.
#' * An already extracted occurrence table in any other file, e.g. `.csv`,
#'   `.txt` or `.tsv`. The extension is not used to infer the format: the file
#'   must be tab-separated regardless.
#'
#' In both cases the first column must be named `gbifID`; anything else stops
#' with an error. This also catches comma-separated files, whose header then
#' arrives as a single column.
#'
#' @param path Character scalar. Path to a GBIF occurrence download: either a
#'   'SIMPLE_CSV' or 'DWCA' ZIP archive, or an extracted tab-separated
#'   occurrence table. An archive must contain a tab-separated occurrence data
#'   file, named `occurrence.txt` when the archive contains more than one
#'   member (as in a Darwin Core Archive).
#' @param tempdir Character scalar or `NULL`. Directory into which the ZIP
#'   archive is extracted. Ignored when `path` is not a ZIP file.
#'
#'   * `NULL` (default): a unique subdirectory is created inside the system
#'     temporary directory via [base::tempfile()], and it is deleted on exit
#'     unless `remove_tempfile = FALSE`.
#'   * A user-supplied path: if the directory does not exist it is created
#'     (recursively). If it already exists and contains files, a warning is
#'     issued because those files may be overwritten. The directory is never
#'     deleted; on exit only the extracted occurrence file is unlinked, and
#'     even that is skipped when `remove_tempfile = FALSE`.
#' @param remove_tempfile Logical scalar. Controls whether the files this call
#'   produced are deleted when the function exits (including after an error).
#'   Defaults to `TRUE`.
#'
#'   * With `tempdir = NULL`, the extraction directory is created by this call
#'     and holds nothing else, so the directory is removed whole.
#'   * With a user-supplied `tempdir`, only the extracted occurrence file is
#'     unlinked. The directory itself and every unrelated file in it are left
#'     untouched.
#'   * `FALSE` keeps the extracted file in `ex_path` and reports its location.
#'
#' @details
#' An archive is extracted into a dedicated directory rather than next to the
#' ZIP file, so a ZIP stored in `inst/extdata` is never modified.
#'
#' The function performs the following steps:
#'
#' * Validates that `path` is a non-empty single character string.
#' * Resolves the file to read. For a `.zip` path the archive members are
#'   listed: a 'SIMPLE_CSV' download holds a single data file which is
#'   extracted by name, while a 'DWCA' holds several members (typically
#'   `meta.xml`, `occurrence.txt`, and extension files) and its
#'   `occurrence.txt` core file is assumed. For any other path the file itself
#'   is read directly.
#' * Reads the header of the resolved file with
#'   [data.table::fread()] using `nrows = 0`, and requires its first column to
#'   be named `gbifID`. Only the header is parsed, so this check is nearly free
#'   and rejects unusable files before the full read.
#' * Reads the tab-separated, UTF-8 occurrence file with
#'   [data.table::fread()], selecting only the GBIF fields used by VasGBIF.
#' * Coerces `gbifID` to character.
#'
#'
#' @returns
#' A `data.table` of class `"import"` containing the selected occurrence
#' fields with Darwin Core / GBIF column names. The `gbifID` column is always
#' character.
#'
#' @seealso
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
#' # An already extracted occurrence table is read directly. The extension is
#' # irrelevant; the file must be tab-separated and start with a `gbifID`
#' # column.
#' # occ <- import_records(path = "~/downloads/occurrence.txt")
#'
#' # Extract into a directory of your own; the extracted file is removed on
#' # exit, but the directory and its other contents are kept.
#' # occ <- import_records(path = gbif_file, tempdir = "~/gbif_extracted")
#'
#' # Keep the extracted file as well.
#' # occ <- import_records(
#' #   path = gbif_file, tempdir = "~/gbif_extracted", remove_tempfile = FALSE
#' # )
#'
#' @references
#' GBIF.org (23 July 2026) GBIF Occurrence Download
#' \doi{10.15468/dl.nt5exp}
#'
#' @export
import_records <- function(path = '', tempdir = NULL, remove_tempfile = TRUE) {
  t1 <- Sys.time()
  if (!is.character(path) || length(path) != 1L) {
    stop('`path` must be a single character string.')
  }
  if (path == '') {
    stop(
      '`path` is empty. Provide the path to a GBIF SIMPLE_CSV or DWCA zip, ',
      'or to an already extracted occurrence table.'
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

  if (tolower(tools::file_ext(path)) == "zip") {
    # ---- ZIP branch: extract the occurrence file, then read it ----
    archive_files <- utils::unzip(path, list = TRUE)$Name
    if (length(archive_files) != 1L) {
      archive_files <- 'occurrence.txt'
    }

    # Resolve extraction directory. `auto_dir` marks a directory this call
    # created itself, which is the only case where removing the directory as a
    # whole is safe.
    if (is.null(tempdir)) {
      ex_path <- base::tempfile("VasGBIF-")
      dir.create(ex_path)
      auto_dir <- TRUE
    } else {
      if (!is.character(tempdir) || length(tempdir) != 1L) {
        stop('`tempdir` must be a single character string.')
      }
      ex_path <- tempdir
      auto_dir <- FALSE
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
    }

    # Cleanup removes only what this call produced. A user-supplied `tempdir`
    # may hold unrelated files, so at most the extracted members are unlinked
    # there; an auto-created directory contains nothing else and is removed
    # whole.
    if (!isFALSE(remove_tempfile)) {
      on.exit(
        if (auto_dir) {
          unlink(ex_path, recursive = TRUE, force = TRUE)
        } else {
          unlink(file.path(ex_path, archive_files), force = TRUE)
        },
        add = TRUE
      )
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

    data_file <- file.path(ex_path, archive_files)
  } else {
    # ---- plain-file branch: an already extracted occurrence table ----
    data_file <- path
  }

  # A GBIF occurrence table always starts with `gbifID`. Only the header and
  # its first column are needed (`nrows = 0`, `select = 1L`), so the check is
  # nearly free and rejects files that are not GBIF downloads - including
  # comma-separated ones, whose header then arrives as a single column -
  # before the full file is parsed.
  header <- fread(
    data_file,
    sep = '\t',
    encoding = 'UTF-8',
    quote = "",
    nrows = 0L,
    select = 1L,
    showProgress = FALSE
  )
  first_col <- names(header)[1L]
  if (length(first_col) == 0L || is.na(first_col) || first_col != "gbifID") {
    stop(
      '`path` does not look like a GBIF occurrence table: the first column is ',
      if (length(first_col) == 0L || is.na(first_col)) 'absent' else
        paste0('"', first_col, '"'),
      ', expected "gbifID". The file must be tab-separated.',
      call. = FALSE
    )
  }

  message("Loading records")
  occ <- fread(
    data_file,
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
