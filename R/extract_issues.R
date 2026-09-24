#' @title Count GBIF issue flags per record
#' @name extract_issues
#' @description
#' Counts, for every occurrence record, how many of the issue codes defined in
#' [`EnumOccurrenceIssue`] are flagged in the record's `issue` field. This is
#' the second step in the VasGBIF import workflow, taking the `data.table`
#' returned by [import_records()] as input.
#'
#' The function is internal: [customized_filter()] calls it directly, so users
#' never invoke it themselves.
#'
#' @param occ An `"import"` `data.table` returned by [import_records()],
#'   containing at least the columns `gbifID` and `issue`. The `issue` column
#'   must hold raw GBIF issue codes as present in a GBIF SIMPLE_CSV download.
#'   Defaults to `NA`.
#'
#' @details
#' The set of recognised issue codes is taken from the package dataset
#' [`EnumOccurrenceIssue`]. Each code is searched for in the record's `issue`
#' string, and `issue_count` is how many of them are found. Codes not present
#' in the dataset are ignored.
#'
#' @returns
#' A `data.table` with one row per record in `occ` and two columns:
#'
#' * `gbifID`: copied from `occ` to allow joining back to the original records.
#' * `issue_count`: the number of issue codes flagged for that record.
#'
#' @seealso
#' * [import_records()] for the preceding step that produces the `occ` input.
#' * [customized_filter()] for the consumer of the issue count.
#' * [`EnumOccurrenceIssue`] for the full list of recognised GBIF issue codes.
#'
#' @import data.table
#' @import stringi
#' @keywords internal
#'
#' @examplesIf interactive()
#' gbif_file <- system.file(
#'   "extdata",
#'   "0003386-260721160103020.zip",
#'   package = "VasGBIF"
#' )
#' occ <- import_records(path = gbif_file)
#' head(extract_issues(occ))
#'
extract_issues <- function(occ = NA) {
  if (!inherits(occ, "import")) {
    stop(
      "`occ` must be an \"import\" object returned by `import_records()`.",
      call. = FALSE
    )
  }

  missing_cols <- setdiff(c("gbifID", "issue"), names(occ))
  if (length(missing_cols) > 0) {
    stop(
      "`occ` is missing required column(s): ",
      paste(missing_cols, collapse = ", "),
      ".",
      call. = FALSE
    )
  }

  if (nrow(occ) == 0) {
    stop("`occ` contains no records.", call. = FALSE)
  }

  EnumOccurrenceIssue <- EnumOccurrenceIssue
  issue_keys <- EnumOccurrenceIssue[, constant]

  #message("Compiling GBIF issues")

  issue_vec <- occ[["issue"]]
  # sapply/vapply collapse to a vector when each result has length one, which
  # would break a single-record input; cbind keeps a matrix of nrow(occ) rows
  # for any input size.
  issue_flags <- lapply(
    issue_keys,
    function(issue_key) stri_detect_fixed(issue_vec, issue_key)
  )
  names(issue_flags) <- issue_keys
  issue_flags <- as.data.table(do.call(cbind, issue_flags))

  data.table(
    gbifID = occ[["gbifID"]],
    issue_count = rowSums(issue_flags)
  )
}
