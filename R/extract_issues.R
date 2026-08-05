#' @title Extract GBIF issue flags into logical columns
#' @name extract_gbif_issues
#' @description
#' Parses the pipe-separated `issue` field from a GBIF occurrence `data.table`
#' and expands it into one logical indicator column per issue code defined in
#' [`EnumOccurrenceIssue`]. This is the second step in the VasGBIF import
#' workflow, taking the `data.table` returned by [import_records()] as input.
#'
#' @param occ An `"import"` `data.table` returned by [import_records()],
#'   containing at least the columns `gbifID` and `issue`. The `issue` column
#'   must hold raw pipe-separated GBIF issue codes as present in a GBIF
#'   SIMPLE_CSV download. Defaults to `NA`.
#'
#' @details
#' The set of recognised issue codes is taken from the package dataset
#' [`EnumOccurrenceIssue`]. For each code a logical column is created that is
#' `TRUE` when the code appears anywhere in the record's `issue` string and
#' `FALSE` otherwise. Codes not present in the dataset are ignored.
#'
#' Two further columns are appended to the per-code columns:
#'
#' * `gbifID`: copied from `occ` to allow joining back to the original records.
#' * `issue_count`: the number of issue flags that are `TRUE` for each record.
#'
#' The companion `summary` table ranks the issue codes by how many records
#' they flag, which is useful for spotting data-quality problems at a glance.
#'
#' @returns
#' An object of class `"issue"`, implemented as a named list with two elements:
#'
#' * `occ_issue`: A `data.table` with one logical column per issue code in
#'   [`EnumOccurrenceIssue`], plus `gbifID` for linking to `occ` and
#'   `issue_count` with the total number of flags per record.
#' * `summary`: A `data.table` with columns `issue_keys` and `N`, giving the
#'   number of records flagged with each issue code, ordered by decreasing `N`.
#'
#' @seealso
#' * [import_records()] for the preceding step that produces the `occ` input.
#' * [`EnumOccurrenceIssue`] for the full list of recognised GBIF issue codes.
#' * [print.issue()] for a compact summary of the result.
#'
#' @import data.table
#' @import stringi
#' @importFrom dplyr %>%
#'
#' @examplesIf interactive()
#' gbif_file <- system.file(
#'   "extdata",
#'   "0003386-260721160103020.zip",
#'   package = "VasGBIF"
#' )
#' occ <- import_records(path = gbif_file)
#' gbif_issue <- extract_gbif_issues(occ)
#' head(gbif_issue$summary, 10)
#' gbif_issue$occ_issue[, .(gbifID, issue_count)] |> head()
#'
#' @export
extract_gbif_issues <- function(occ = NA) {
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

  message("Compiling GBIF issues")

  issue_vec <- occ[["issue"]]
  # sapply/vapply collapse to a vector when each result has length one, which
  # would break a single-record input; cbind keeps a matrix of nrow(occ) rows
  # for any input size.
  occ_issue <- lapply(
    issue_keys,
    function(issue_key) stri_detect_fixed(issue_vec, issue_key)
  )
  names(occ_issue) <- issue_keys
  occ_issue <- as.data.table(do.call(cbind, occ_issue))

  summary <- data.table(
    issue_keys = issue_keys,
    N = colSums(occ_issue)
  )[order(-N)]

  occ_issue[, gbifID := occ$gbifID]
  occ_issue[, issue_count := rowSums(.SD), .SDcols = is.logical]

  result <- list(
    occ_issue = occ_issue,
    summary = summary
  )

  class(result) <- 'issue'

  return(result)
}

#' Print an `issue` object
#'
#' Displays a compact summary of a GBIF issue parse: the number of records,
#' the number of recognised issue codes, the issues flagged on the most
#' records, and the distribution of per-record issue counts. The full
#' per-code table is available in the `summary` element; use [head()] or
#' `View()` to inspect it.
#'
#' @param x An object of class `"issue"` returned by [extract_gbif_issues()].
#' @param ... Additional arguments (unused, retained for S3 compatibility).
#'
#' @return Invisibly returns `x`.
#'
#' @export
print.issue <- function(x, ...) {
  occ_issue <- x$occ_issue
  if (!is.data.frame(occ_issue)) {
    cat("<issue> 0 records\n")
    return(invisible(x))
  }

  n_records <- nrow(occ_issue)
  n_codes <- sum(vapply(occ_issue, is.logical, logical(1)))
  cat("<issue> ", n_records, " records | ", n_codes, " issue codes", sep = "")
  cat("\n")

  summary_tbl <- x$summary
  if (is.data.frame(summary_tbl) && all(c("issue_keys", "N") %chin% names(summary_tbl))) {
    top <- as.data.table(summary_tbl)[N > 0][order(-N)][seq_len(min(10, .N))]
    if (nrow(top) > 0) {
      cat("\nTop issues by flagged records (full table in `$summary`):\n")
      print(top)
    }
  }

  if ("issue_count" %chin% names(occ_issue) && n_records > 0) {
    dist <- as.data.table(occ_issue)[, .N, by = issue_count][order(issue_count)]
    cat("\nissue_count distribution:\n")
    print(dist)
  }

  invisible(x)
}
