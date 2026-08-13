#' Apply custom quality filters to occurrence records
#'
#' @description
#' Joins the outputs of the VasGBIF import, taxonomic-resolution, and
#' GBIF-issue steps into a single occurrence table, then progressively removes
#' records according to a user-selected set of quality rules.
#'
#' @param occ_import An `"import"` `data.table` returned by [import_records()],
#'   containing at least the columns `issue`, `decimalLatitude`,
#'   `countryCode`, `coordinateUncertaintyInMeters`, `eventDate`, `month`,
#'   `year`, `day`, `identifiedBy`, and `recordedBy`.
#' @param taxa_checked An `"occ_taxa"` object returned by [check_taxon()].
#' @param gbif_issue An `"issue"` object returned by [extract_gbif_issues()].
#' @param filter_countryCode Logical scalar. If `TRUE` (default), removes
#'   records with no usable geographic information: `decimalLatitude` is `NA`
#'   **and** `countryCode` is `NA` or empty. Records with either a coordinate
#'   or a country code are kept.
#' @param filter_coordinateUncertainty Non-negative numeric scalar. Removes
#'   records whose `coordinateUncertaintyInMeters` is strictly greater than the
#'   threshold. Defaults to `10000`. Records with `NA` or empty
#'   `coordinateUncertaintyInMeters` are always kept - they do not
#'   participate in this rule. Pass `NULL`, `NA`, or `''` to disable the
#'   rule.
#' @param filter_date Logical scalar. If `TRUE`, removes records for which all
#'   four date components (`eventDate`, `month`, `year`, `day`) are missing or
#'   empty. Defaults to `FALSE`.
#' @param filter_identifiedBy Logical scalar. If `TRUE`, removes records whose
#'   `identifiedBy` is missing or contains no named identifier (see *Collector
#'   junk detection*). Defaults to `FALSE`.
#' @param filter_recordedBy Logical scalar. If `TRUE`, removes records whose
#'   `recordedBy` is missing or contains no named collector. Defaults to
#'   `FALSE`.
#' @param filter_gbif_issues_max Non-negative numeric scalar. Removes records
#'   flagged with more GBIF issues than the threshold
#'   (`gbif_issues > filter_gbif_issues_max`). Defaults to `5`. Pass `NULL`,
#'   `NA`, or `''` to disable the rule.
#'
#' @details
#' ## Joining the inputs
#'
#' The three inputs are joined by `gbifID`. For memory efficiency the joins
#' are performed **in place** on a single defensive copy of `occ_import`:
#' `copy()` is made once and each join adds columns via `:=`, instead of
#' materialising a fresh full-width table per join. The caller's `occ_import`
#' is never modified. Rows are not deleted during the join or the rules; every
#' criterion accumulates into a logical mask and a single row subset is
#' applied at the end. Peak memory is therefore close to the input plus one
#' working copy, regardless of how many rules are enabled.
#'
#' [check_taxon()] already removes records that fail the `accuracy` threshold,
#' whose `Taxonomic_status` is neither `"Accepted"` nor `"Synonym"`, or that
#' resolve to a genus-level or unranked accepted name, so `occ_taxa_checked`
#' contains only fully resolved records. Rows absent from `occ_taxa_checked`
#' are dropped via the keep mask instead of carrying `NA` taxonomy through the
#' rest of the pipeline. The number removed is recorded in `summary` under the
#' rule name `taxon_resolved`.
#'
#' [extract_gbif_issues()] returns exactly one row per imported record, so the
#' issue join is one-to-one and cannot change the row count. The function
#' verifies this and stops if any record lacks an issue count. The raw `issue`
#' column is removed from `occ_import` and replaced by `gbif_issues`, the
#' per-record issue count computed by [extract_gbif_issues()].
#'
#' ## Filter rules
#'
#' Enabled rules are applied in sequence. By default `countryCode`,
#' `coordinateUncertainty`, and `gbif_issues_max` are enabled; `date`,
#' `identifiedBy`, and `recordedBy` are disabled.
#'
#' * `countryCode`: drop records with `NA` latitude **and** `NA`/empty
#'   `countryCode`.
#' * `coordinateUncertainty`: drop records with
#'   `coordinateUncertaintyInMeters > threshold`; records with `NA` or empty
#'   uncertainty are kept.
#' * `date`: drop records with `eventDate`, `month`, `year`, **and** `day`
#'   all missing.
#' * `identifiedBy` / `recordedBy`: drop records whose value is junk (see
#'   below).
#' * `gbif_issues_max`: drop records with `gbif_issues > threshold`. The
#'   one-to-one issue join guarantees every record carries an issue count, so
#'   no record is exempt from this rule.
#'
#' ## Collector junk detection
#'
#' The `identifiedBy` and `recordedBy` rules are identical in strictness. A
#' value is treated as junk - and the record removed - when it is missing or
#' empty, or when it matches a curated set of "no named person" patterns while
#' containing **no name separator**.
#'
#' The keyword list covers English (`unknown`, `anonymous`, `unnamed`,
#' `unidentified`, `unrecorded`, `incognito`), other languages
#' (`desconocido`, `desconhecido`, `anonimo` and its accented Spanish and
#' Portuguese variants,
#' `sin nombre`, `sem nome`, `inconnu`, `anonyme`, `unbekannt`, `anonym`,
#' and four Chinese terms meaning "unknown", "unnamed", "anonymous" and
#' "no details"), and whole-value patterns such as `s.n.`, `n/a`, `et al.`,
#' and `no collector`.
#'
#' Name separators (`,`, `;`, `&`, `+`, `and`, plus the full-width comma,
#' full-width semicolon, and ideographic enumeration comma used in CJK text)
#' protect values that mix a keyword with a real name, e.g.
#' `"Unknown; Jongmans WJ"` or `"Collector(s): Eric Sundell, unknown"` are
#' kept because a named person is present.
#'
#' Word-boundary matching means the Chinese keywords only match standalone
#' values; a longer phrase that merely begins with one of them (for instance
#' the Chinese for "unknown collector") is not removed. This is deliberately
#' conservative: without boundaries, a real name that happens to contain a
#' keyword could be wrongly dropped.
#'
#' @returns An object of class `"customFiltered"`, implemented as a named list
#'   with two elements:
#'
#' * `occ_filtered`: the filtered `data.table` with all occurrence and joined
#'   columns.
#' * `summary`: a `data.table` with columns `rule`, `dropped`, and `remaining`
#'   giving, for each applied step (the `taxon_resolved` join plus each
#'   enabled rule), how many records were removed and how many remained.
#'
#' A [print()] method for class `"customFiltered"` displays the record counts
#' and the per-rule summary.
#'
#' @seealso
#' * [import_records()], [check_taxon()], [extract_gbif_issues()] for the three
#'   inputs.
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
#' taxa_checked <- check_taxon(occ_import = occ, accuracy = 0.85)
#'
#' filtered <- custom_filter(
#'   occ_import = occ,
#'   taxa_checked = taxa_checked,
#'   gbif_issue = gbif_issue,
#'   filter_date = TRUE,
#'   filter_identifiedBy = TRUE,
#'   filter_recordedBy = TRUE
#' )
#' filtered
#'
#' # Disable the coordinate-uncertainty rule (NULL / NA / '' all work):
#' filtered_loose <- custom_filter(
#'   occ_import = occ,
#'   taxa_checked = taxa_checked,
#'   gbif_issue = gbif_issue,
#'   filter_coordinateUncertainty = NULL
#' )
#' filtered_loose
#'
#' @export
custom_filter <- function(
  occ_import = NA,
  taxa_checked = NA,
  gbif_issue = NA,
  filter_countryCode = TRUE,
  filter_coordinateUncertainty = 10000,
  filter_date = FALSE,
  filter_identifiedBy = FALSE,
  filter_recordedBy = FALSE,
  filter_gbif_issues_max = 5
) {
  t1 <- Sys.time()
  # ---- validate inputs ----
  if (!inherits(occ_import, "import")) {
    stop('`occ_import` must be an "import" data.table from import_records().')
  }
  if (!inherits(taxa_checked, "occ_taxa")) {
    stop('`taxa_checked` must be an "occ_taxa" object from check_taxon().')
  }
  if (!inherits(gbif_issue, "issue")) {
    stop('`gbif_issue` must be an "issue" object from extract_gbif_issues().')
  }

  # ---- validate filter flags ----
  flag_args <- list(
    filter_countryCode = filter_countryCode,
    filter_date = filter_date,
    filter_identifiedBy = filter_identifiedBy,
    filter_recordedBy = filter_recordedBy
  )
  bad_flags <- names(flag_args)[
    !vapply(
      flag_args,
      function(v) is.logical(v) && length(v) == 1L && !is.na(v),
      logical(1)
    )
  ]
  if (length(bad_flags) > 0L) {
    stop('`', bad_flags[1], '` must be a single logical value (TRUE/FALSE).')
  }

  # ---- validate joined inputs ----
  taxa_cols <- c(
    "gbifID",
    "Taxonomic_status",
    "Accepted_name",
    "Accepted_species",
    "Accepted_name_id",
    "Source"
  )
  missing_taxa <- setdiff(taxa_cols, names(taxa_checked$occ_taxa_checked))
  if (length(missing_taxa) > 0L) {
    stop(
      "`taxa_checked$occ_taxa_checked` is missing column(s): ",
      paste(missing_taxa, collapse = ", ")
    )
  }
  issue_cols <- c("gbifID", "issue_count")
  missing_issue <- setdiff(issue_cols, names(gbif_issue$occ_issue))
  if (length(missing_issue) > 0L) {
    stop(
      "`gbif_issue$occ_issue` is missing column(s): ",
      paste(missing_issue, collapse = ", ")
    )
  }

  required_cols <- c(
    "issue",
    "decimalLatitude",
    "countryCode",
    "coordinateUncertaintyInMeters",
    "eventDate",
    "month",
    "year",
    "day",
    "identifiedBy",
    "recordedBy"
  )
  missing_cols <- setdiff(required_cols, names(occ_import))
  if (length(missing_cols) > 0L) {
    stop(
      "`occ_import` is missing required column(s): ",
      paste(missing_cols, collapse = ", ")
    )
  }

  summary <- data.table(
    rule = character(),
    dropped = integer(),
    remaining = integer()
  )

  log_step <- function(summary, rule, before) {
    rbind(
      summary,
      data.table(
        rule = rule,
        dropped = before - sum(keep),
        remaining = sum(keep)
      )
    )
  }

  # A numeric filter is disabled by NULL, NA, or ''
  param_disabled <- function(x) {
    is.null(x) || (length(x) == 1L && (is.na(x) || identical(x, '')))
  }

  # ---- join inputs by gbifID (in place on a defensive copy) ----
  # `occ_import` is copied once and the two joins add columns in place via
  # `:=`, so no full-width table is materialised per join. Rows are only
  # deleted at the end, through the `keep` mask.
  before <- nrow(occ_import)
  occ <- copy(occ_import)
  occ[, issue := NULL]

  # `occ_taxa_checked` holds only records that passed the accuracy and status
  # thresholds; rows absent from it get NA here and are dropped via `keep`
  # (recorded as the taxon_resolved rule).
  occ[
    taxa_checked$occ_taxa_checked,
    on = "gbifID",
    `:=`(
      Taxonomic_status = i.Taxonomic_status,
      Accepted_name = i.Accepted_name,
      Accepted_species = i.Accepted_species,
      Accepted_name_id = i.Accepted_name_id,
      Source = i.Source
    )
  ]
  keep <- !is.na(occ[["Accepted_name"]])
  summary <- log_step(summary, "taxon_resolved", before)

  # `occ_issue` carries one row per imported record, so this join is 1:1 and
  # must not change the row count; enforce that contract rather than trust it
  # (any unmatched row would receive NA).
  occ[
    gbif_issue$occ_issue,
    on = "gbifID",
    gbif_issues := i.issue_count
  ]
  if (anyNA(occ[["gbif_issues"]])) {
    stop(
      "`gbif_issue$occ_issue` does not cover every record in `occ_import`: ",
      sum(is.na(occ[["gbif_issues"]])),
      " record(s) have no issue count.",
      call. = FALSE
    )
  }

  # ---- countryCode ----
  if (filter_countryCode) {
    before <- sum(keep)
    keep <- keep & !(
      is.na(occ[["decimalLatitude"]]) &
        (is.na(occ[["countryCode"]]) | occ[["countryCode"]] == '')
    )
    summary <- log_step(summary, "countryCode", before)
  }

  # ---- coordinateUncertainty ----
  if (!param_disabled(filter_coordinateUncertainty)) {
    if (
      !is.numeric(filter_coordinateUncertainty) ||
        length(filter_coordinateUncertainty) != 1L ||
        filter_coordinateUncertainty < 0
    ) {
      stop(
        '`filter_coordinateUncertainty` must be a single non-negative number, ',
        "or NULL/NA/'' to disable the rule."
      )
    }
    before <- sum(keep)
    uncertainty <- suppressWarnings(
      as.numeric(occ[["coordinateUncertaintyInMeters"]])
    )
    # NA and '' stay: only values strictly above the threshold are removed
    keep <- keep & (is.na(uncertainty) | uncertainty <= filter_coordinateUncertainty)
    summary <- log_step(summary, "coordinateUncertainty", before)
  }

  # ---- Date ----
  if (filter_date) {
    before <- sum(keep)
    keep <- keep & !(
      (is.na(occ[["eventDate"]]) | occ[["eventDate"]] == '') &
        (is.na(occ[["month"]]) | occ[["month"]] == '') &
        (is.na(occ[["year"]]) | occ[["year"]] == '') &
        (is.na(occ[["day"]]) | occ[["day"]] == '')
    )
    summary <- log_step(summary, "date", before)
  }

  # ---- identifiedBy ----
  if (filter_identifiedBy) {
    before <- sum(keep)
    keep <- keep & !is_junk_name(occ[["identifiedBy"]])
    summary <- log_step(summary, "identifiedBy", before)
  }

  # ---- recordedBy ----
  if (filter_recordedBy) {
    before <- sum(keep)
    keep <- keep & !is_junk_name(occ[["recordedBy"]])
    summary <- log_step(summary, "recordedBy", before)
  }

  # ---- gbif_issues_max ----
  if (!param_disabled(filter_gbif_issues_max)) {
    if (
      !is.numeric(filter_gbif_issues_max) ||
        length(filter_gbif_issues_max) != 1L ||
        filter_gbif_issues_max < 0
    ) {
      stop(
        '`filter_gbif_issues_max` must be a single non-negative number, ',
        "or NULL/NA/'' to disable the rule."
      )
    }
    before <- sum(keep)
    # Defensive only: the 1:1 issue join above rules out NA gbif_issues
    keep <- keep & (is.na(occ[["gbif_issues"]]) | occ[["gbif_issues"]] <= filter_gbif_issues_max)
    summary <- log_step(summary, "gbif_issues_max", before)
  }
  # apply the accumulated mask once: a single row subset instead of one per rule
  occ <- occ[keep]

  # keep the occurrence columns in import order, then the joined columns,
  # matching the output column order of the previous merge-based version
  setcolorder(
    occ,
    c(
      "gbifID",
      setdiff(names(occ_import), c("gbifID", "issue")),
      "Taxonomic_status", "Accepted_name", "Accepted_species",
      "Accepted_name_id", "Source",
      "gbif_issues"
    )
  )
  # key and sort by gbifID, matching the merge-based output (merge keys on `by`)
  setkey(occ, gbifID)

  result <- list(
    occ_filtered = occ,
    summary = summary
  )
  class(result) <- "customFiltered"
  used <- Sys.time() - t1
  message(paste('used', used %>% round(1), attributes(used)$units))
  result
}

#' Print a `customFiltered` object
#'
#' Displays a concise summary of the filtering result: the number of records
#' before and after filtering, and the per-rule drop table.
#'
#' @param x An object of class `"customFiltered"` returned by [custom_filter()].
#' @param ... Additional arguments (unused, retained for S3 compatibility).
#'
#' @return Invisibly returns `x`.
#'
#' @export
print.customFiltered <- function(x, ...) {
  n_after <- nrow(x$occ_filtered)
  n_rules <- nrow(x$summary)

  cat("<customFiltered>\n")
  if (n_rules == 0L) {
    cat("No filter rules were applied. Records:", n_after, "\n")
  } else {
    n_before <- x$summary$dropped[1L] + x$summary$remaining[1L]
    cat("Records:", n_before, "->", n_after, "\n\n")
    print(x$summary)
  }
  invisible(x)
}

#' Detect "no named person" values in collector or identifier fields
#'
#' Used by [custom_filter()] to flag junk values in `recordedBy` /
#' `identifiedBy`. A value is considered junk when it is missing or empty, or
#' when it matches a curated keyword / whole-value pattern while containing no
#' name separator.
#'
#' @param x A character vector of collector or identifier values.
#'
#' @return A logical vector, `TRUE` for junk values.
#' @import stringi
#' @keywords internal
#' @noRd
is_junk_name <- function(x) {
  # Non-ASCII keywords and separators are written as \uxxxx escapes so the
  # source stays portable ASCII (R CMD check requirement).
  kw_semantic <- paste0(
    "unknown|anonymous|unnamed|unidentified|unrecorded|incognito|",
    "desconocido|desconhecido|anonimo|an\u00f3nimo|an\u00f4nimo|",
    "sin nombre|sem nome|inconnu|anonyme|unbekannt|anonym|",
    # unknown, unnamed, anonymous, no details
    "\u672a\u77e5|\u65e0\u540d|\u533f\u540d|\u4e0d\u8be6"
  )
  kw_whole <- paste0(
    "^s\\.?n\\.?$|",
    "^n/?a\\.?$|",
    "^(not|no)\\s+(recorded|collector|collectors?)$|",
    "^et\\s*al\\.?$"
  )
  # full-width comma, semicolon and enumeration comma
  sep_pattern <- "[,;]|&|\\band\\b|\\+|\u3001|\uff1b|\uff0c"

  x_trim <- stri_trim_both(x)
  x_low <- stri_trans_tolower(x_trim)

  is_missing <- is.na(x_low) | x_low == ""
  has_keyword <- stri_detect_regex(x_low, paste0("\\b(", kw_semantic, ")\\b"))
  has_whole <- stri_detect_regex(x_low, kw_whole)
  has_separator <- stri_detect_regex(x_low, sep_pattern)

  is_missing | ((has_keyword | has_whole) & !has_separator)
}
