#' Import GBIF occurrence records
#'
#' Imports occurrence records from a GBIF ZIP download and prepares the result
#' for subsequent VasGBIF processing. The function reads the occurrence data
#' file in the archive, retains the fields required by the package, expands GBIF
#' issue codes into record-level logical indicators, and creates an issue-count
#' summary.
#'
#' @param path Character scalar giving the path to a GBIF ZIP file. The archive
#'   must contain exactly one tab-separated occurrence data file.
#' @param remove_tempfile Logical scalar. If `TRUE`, the temporary extraction
#'   directory is removed when the function exits, including after an error. If
#'   `FALSE`, the extracted directory is retained and its path is reported.
#'   Defaults to `TRUE`.
#'
#' @details
#'
#' The input archive is extracted into a temporary directory rather than next
#' to the ZIP file. This also prevents a ZIP stored in a package's
#' `inst/extdata` directory from being modified during import.
#'
#' The function performs the following steps:
#'
#' * Checks that `path` is a character path with a `.zip` extension.
#' * Checks that the archive contains exactly one member and extracts that
#'   member to a unique temporary directory.
#' * Reads the tab-separated, UTF-8 occurrence file with
#'   [data.table::fread()] and selects the GBIF fields used by the VasGBIF
#'   workflow.
#' * Coerces `gbifID` to character.
#' * Parses the pipe-separated `issue` field. For each issue code in
#'   [`EnumOccurrenceIssue`], it creates a logical column indicating whether
#'   that issue occurs in each record, then counts the flagged records by issue
#'   code.
#'
#' The function does not filter records by basis of record, taxon, geography,
#' or issue status. It also does not correct or remove records flagged by GBIF;
#' it only imports the selected fields and creates diagnostic indicators.
#'
#' The `occ_issue` component uses the `gbifID` column to link issue indicators
#' back to `occ`. The available issue columns are determined by the package
#' dataset [`EnumOccurrenceIssue`]; they can therefore change if that dataset
#' is updated.
#'
#' When `remove_tempfile = FALSE`, the function leaves the extracted file in a
#' system temporary directory. The caller is responsible for removing the
#' retained directory after inspecting it.
#'
#' @returns
#' An object of class `import`, implemented as a list with four elements:
#'
#' * `occ`: A `data.table` containing the selected occurrence fields. Its
#'   columns retain the Darwin Core/GBIF field names.
#' * `occ_issue`: A `data.table` containing one logical column for each issue
#'   code in [`EnumOccurrenceIssue`], plus `gbifID` for linking the indicators
#'   to `occ`.
#' * `summary`: A `data.table` with columns `issue_keys` and `N`, giving the
#'   number of records associated with each issue; rows are ordered by
#'   decreasing `N`.
#' * `runtime`: The elapsed time reported for the import operation.
#'
#' @seealso
#' * [`unzip()`][utils::unzip] for listing or extracting ZIP archives.
#' * [`data.table::fread()`][data.table::fread] for delimited-file import.
#'
#' @import data.table
#' @import stringi
#' @importFrom dplyr %>%
#' @importFrom utils head
#'
#' @examplesIf interactive()
#' gbif_file <- system.file(
#'   "extdata",
#'   "0003386-260721160103020.zip",
#'   package = "VasGBIF"
#' )
#' occ_import <- import_records(path = gbif_file)
#' head(occ_import$summary, 5)
#'
#' # Or choose another GBIF ZIP file interactively.
#' # occ_import <- import_records(path = file.choose())
#'
#' @references
#' GBIF.org (23 July 2026) GBIF Occurrence Download
#' \doi{10.15468/dl.nt5exp}
#'
#' @export
import_records <- function(path = '', remove_tempfile = TRUE) {
  start <- Sys.time()

  if (!is.character(path)) {
    stop('set path to the downloaded SIMPLE_CSV zip!')
  }
  if (is.character(path)) {
    if (path == '') stop('require path to the downloaded SIMPLE_CSV zip!')
  }

  fields <- c(
    "gbifID",
    "occurrenceID",
    "family",
    "taxonRank",
    "scientificName",
    "verbatimScientificName",
    "countryCode",
    "locality",
    "stateProvince",
    "occurrenceStatus",
    "decimalLatitude",
    "decimalLongitude",
    "eventDate",
    "day",
    "month",
    "year",
    "basisOfRecord",
    "institutionCode",
    "collectionCode",
    "catalogNumber",
    "recordNumber",
    "identifiedBy",
    "dateIdentified",
    "recordedBy",
    "typeStatus",
    "mediaType",
    "issue",
    "coordinateUncertaintyInMeters"
  )

  if (tolower(tools::file_ext(path)) != "zip") {
    stop('should be the SIMPLE_CSV zip from GBIF!')
  }

  archive_files <- utils::unzip(path, list = TRUE)$Name
  if (length(archive_files) != 1L) {
    archive_files <- 'occurrence.txt'
  }

  ex_path <- tempfile("VasGBIF-")
  dir.create(ex_path)
  if (isTRUE(remove_tempfile)) {
    on.exit(unlink(ex_path, recursive = TRUE, force = TRUE), add = TRUE)
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
  path_occ <- file.path(ex_path, archive_files)

  message("Loading records")
  occ <- fread(
    path_occ,
    sep = '\t',
    encoding = 'UTF-8',
    select = fields,
    quote = "",
    showProgress = FALSE
  )
  occ[, gbifID := as.character(gbifID)]

  if (!isTRUE(remove_tempfile)) {
    message("Preserved extracted files in ", ex_path)
  }

  # extract_gbif_issue

  EnumOccurrenceIssue <- EnumOccurrenceIssue
  issue_keys <- EnumOccurrenceIssue[, constant]

  message("Compiling GBIF issues")

  fix <- function(issue) stri_detect_fixed(occ[, issue], issue)
  occ_issue <- sapply(issue_keys, fix) %>% as.data.table()

  summary <- data.table(
    issue_keys = issue_keys,
    N = colSums(occ_issue)
  )[order(-N)]

  occ_issue[, gbifID := occ$gbifID]

  end <- Sys.time()
  used <- end - start

  message(paste('used', used %>% round(1), attributes(used)$units))

  occ_import <- list(
    occ = occ,
    occ_issue = occ_issue,
    summary = summary,
    runtime = used
  )
  class(occ_import) <- "import"
  return(occ_import)
}
