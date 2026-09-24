#' Apply custom quality filters to occurrence records
#'
#' @description
#' Joins the outputs of the VasGBIF import and taxonomic-resolution steps into
#' a single occurrence table, then progressively removes records according to
#' a user-selected set of quality rules.
#'
#' @param occ_import An `"import"` `data.table` returned by [import_records()].
#'   `gbifID` and `issue` are always required; every other column is required
#'   only by the rule that reads it, so a column backing a disabled rule may be
#'   absent. The columns are `decimalLatitude` and `countryCode` for
#'   `filter_countryCode`, `coordinateUncertaintyInMeters` for
#'   `filter_coordinateUncertainty`, `eventDate`, `month`, `year`, and `day`
#'   for `filter_date`, `identifiedBy`, and `recordedBy`.
#' @param taxa_checked An `"occ_taxa"` object returned by [check_taxon()].
#' @param filter_countryCode Logical scalar. If `TRUE` (default), removes
#'   records with no usable geographic information: `decimalLatitude` is `NA`
#'   **and** `countryCode` is `NA` or empty. Records with either a coordinate
#'   or a country code are kept. When enabled, a `filter_countryCode` logical
#'   column is added to `occ_marked`; see *Per-rule verdict columns*.
#' @param filter_coordinateUncertainty Non-negative numeric scalar. Removes
#'   records whose `coordinateUncertaintyInMeters` is strictly greater than the
#'   threshold. Defaults to `10000`. Records with `NA` or empty
#'   `coordinateUncertaintyInMeters` are always kept - they do not
#'   participate in this rule. Pass `NULL`, `NA`, or `''` to disable the
#'   rule. The value is validated when the function is called, before any
#'   work is done. When the rule is enabled, a `filter_coordinateUncertainty`
#'   logical column is added to `occ_marked`.
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
#'   `NA`, or `''` to disable the rule. The value is validated when the
#'   function is called, before any work is done.
#'
#' Each of `filter_date`, `filter_identifiedBy`, `filter_recordedBy`, and
#' `filter_gbif_issues_max` adds a logical column named after the argument to
#' `occ_marked` when it is enabled; see *Per-rule verdict columns*.
#'
#' @details
#' ## Joining the inputs
#'
#' The two inputs are joined by `gbifID`. For memory efficiency the joins are
#' performed **in place** on a single defensive copy of `occ_import`:
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
#' [extract_issues()] is called internally on `occ_import` and returns exactly
#' one row per imported record, so the issue join is one-to-one and cannot
#' change the row count. The function verifies this and stops if any record
#' lacks an issue count. The raw `issue` column is removed from `occ_import`
#' and replaced by `gbif_issues`, the per-record issue count.
#'
#' ## Filter rules
#'
#' Every applied test inspects the full table on its own terms rather than only
#' the records left by the preceding tests, and its verdict is stored as a
#' logical column named after the test. `TRUE` means the record passed that
#' test. By default `countryCode`, `coordinateUncertainty`, and
#' `gbif_issues_max` are enabled; `date`, `identifiedBy`, and `recordedBy` are
#' disabled. Numeric thresholds are validated before any work is done, so an
#' invalid value fails immediately.
#'
#' The always-on `taxon_resolved` test is the first one applied. It is not a
#' selectable rule: [check_taxon()] only retains records whose name resolved, so
#' records absent from `taxa_checked$occ_taxa_checked` receive `NA` `Accepted_name`
#' at the join and fail this test. It always contributes a
#' `filter_taxon_resolved` column.
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
#' ## Per-rule verdict columns
#'
#' Each applied test contributes a logical column named after it:
#' `filter_taxon_resolved` (always) plus `filter_countryCode`,
#' `filter_coordinateUncertainty`, `filter_date`, `filter_identifiedBy`,
#' `filter_recordedBy`, and `filter_gbif_issues_max` for the selected rules.
#' `TRUE` marks a record that passed that test. A disabled rule contributes no
#' column, so the output width depends on which rules were selected. The columns
#' are carried by `occ_marked`, where they identify which tests rejected each
#' excluded record; `occ_filtered` holds only occurrence and joined columns.
#'
#' Because each rule is evaluated independently, one record can fail several
#' tests at once and is then counted by each of them. The `summary` table makes
#' this explicit:
#'
#' * `failed` is the number of records that test rejects on its own terms;
#'   these counts overlap and sum to more than the number of records removed.
#' * `only_failed_here` is the number of records that test rejects and no other
#'   test does; these counts are disjoint but incomplete, since a record failing
#'   several tests is credited to none of them.
#' * `dropped` and `remaining` remain the sequential attribution: each removed
#'   record is credited to the first enabled test that rejected it, so `dropped`
#'   sums exactly to the number of records removed.
#'
#' The split of the output reflects the same distinction. `occ_filtered` holds
#' the records that passed every applied test, with their occurrence and joined
#' columns and no verdict columns; `occ_marked` holds the rest, reduced to
#' `gbifID` and the verdict columns. Because every applied test has a column,
#' each marked record carries at least one `FALSE` and shows exactly which tests
#' rejected it - a record excluded only because its taxon name did not resolve
#' has `FALSE` in `filter_taxon_resolved` alone.
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
#'   with three elements:
#'
#' * `occ_filtered`: the records that passed every applied test, as a
#'   `data.table` with the occurrence and joined columns only - no verdict
#'   columns.
#' * `summary`: a `data.table` with columns `rule`, `dropped`, `remaining`,
#'   `failed`, and `only_failed_here`, giving for each applied step (the
#'   `taxon_resolved` join plus each enabled rule) how many records it removed,
#'   how many remained, and how many it rejects under the independent and
#'   exclusive readings described in *Per-rule verdict columns*.
#' * `occ_marked`: the records excluded by at least one applied test, reduced to
#'   `gbifID` and one verdict column per applied test (see *Per-rule verdict
#'   columns*). Every such record fails at least one of them, so its verdict
#'   columns contain at least one `FALSE`. Together with `occ_filtered`, this
#'   table accounts for every record in `occ_import`.
#'
#' A [print()] method for class `"customFiltered"` displays how many records
#' were kept and excluded, and the per-rule summary.
#'
#' @seealso
#' * [import_records()] and [check_taxon()] for the two inputs.
#' * [extract_issues()] for the issue count behind the `gbif_issues_max` rule.
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
#' taxa_checked <- check_taxon(occ_import = occ, accuracy = 0.85)
#'
#' filtered <- customized_filter(
#'   occ_import = occ,
#'   taxa_checked = taxa_checked,
#'   filter_date = TRUE,
#'   filter_identifiedBy = TRUE,
#'   filter_recordedBy = TRUE
#' )
#' filtered
#' filtered$summary
#'
#' # The kept records carry the occurrence and joined columns only:
#' names(filtered$occ_filtered)
#'
#' # The excluded records carry `gbifID` and one verdict column per applied
#' # test, so each shows exactly which tests rejected it:
#' names(filtered$occ_marked)
#' head(filtered$occ_marked)
#'
#' # Disable the coordinate-uncertainty rule (NULL / NA / '' all work). The
#' # rule contributes no verdict column:
#' filtered_loose <- customized_filter(
#'   occ_import = occ,
#'   taxa_checked = taxa_checked,
#'   filter_coordinateUncertainty = NULL
#' )
#' "filter_coordinateUncertainty" %in% names(filtered_loose$occ_marked)
#'
#' @export
customized_filter <- function(
  occ_import = NA,
  taxa_checked = NA,
  filter_countryCode = TRUE,
  filter_coordinateUncertainty = 10000,
  filter_date = FALSE,
  filter_identifiedBy = FALSE,
  filter_recordedBy = FALSE,
  filter_gbif_issues_max = 5
) {
  t1 <- Sys.time()

  # A numeric filter is disabled by NULL, NA, or ''
  param_disabled <- function(x) {
    is.null(x) || (length(x) == 1L && (is.na(x) || identical(x, '')))
  }

  # ---- validate inputs ----
  if (!inherits(occ_import, "import")) {
    stop('`occ_import` must be an "import" data.table from import_records().')
  }
  if (!inherits(taxa_checked, "occ_taxa")) {
    stop('`taxa_checked` must be an "occ_taxa" object from check_taxon().')
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

  # ---- validate numeric thresholds up front ----
  # Checked here rather than at the point of use, so an invalid threshold fails
  # immediately instead of after the joins and issue extraction have run.
  # NULL, NA, and '' all mean "rule disabled" and are accepted.
  for (nm in c("filter_coordinateUncertainty", "filter_gbif_issues_max")) {
    v <- get(nm, inherits = FALSE)
    if (is.null(v) || (length(v) == 1L && (is.na(v) || identical(v, '')))) {
      next
    }
    if (!is.numeric(v) || length(v) != 1L || v < 0) {
      stop(
        '`',
        nm,
        '` must be a single non-negative number, ',
        "or NULL/NA/'' to disable the rule."
      )
    }
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
  # Columns are required only for the rules that are actually enabled, so a
  # column backing a disabled rule may be absent. `gbifID` and `issue` are
  # always needed: the former keys the joins, the latter feeds
  # `extract_issues()`.
  rule_cols <- c(
    "gbifID",
    "issue",
    if (filter_countryCode) c("decimalLatitude", "countryCode"),
    if (!param_disabled(filter_coordinateUncertainty))
      "coordinateUncertaintyInMeters",
    if (filter_date) c("eventDate", "month", "year", "day"),
    if (filter_identifiedBy) "identifiedBy",
    if (filter_recordedBy) "recordedBy"
  )
  required_cols <- unique(rule_cols)
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
  pass <- !is.na(occ[["Accepted_name"]])
  occ[, filter_taxon_resolved := pass]
  keep <- pass
  summary <- log_step(summary, "taxon_resolved", before)

  # `extract_issues()` carries one row per imported record, so this join is 1:1
  # and must not change the row count; enforce that contract rather than trust
  # it (any unmatched row would receive NA).
  issue_counts <- extract_issues(occ_import)
  occ[
    issue_counts,
    on = "gbifID",
    gbif_issues := i.issue_count
  ]
  if (anyNA(occ[["gbif_issues"]])) {
    stop(
      "No issue count could be computed for ",
      sum(is.na(occ[["gbif_issues"]])),
      " record(s); their `issue` value is NA.",
      call. = FALSE
    )
  }

  # ---- countryCode ----
  # Each rule is evaluated over the full table, its verdict stored in a
  # logical column named after the argument (TRUE = passed). The same verdict
  # is accumulated into `keep`, so the surviving records are unchanged; the
  # column itself is dropped from `occ_filtered` at the end and survives only
  # in `occ_marked`.
  if (filter_countryCode) {
    before <- sum(keep)
    pass <- !(
      is.na(occ[["decimalLatitude"]]) &
        (is.na(occ[["countryCode"]]) | occ[["countryCode"]] == '')
    )
    occ[, filter_countryCode := pass]
    keep <- keep & pass
    summary <- log_step(summary, "countryCode", before)
  }

  # ---- coordinateUncertainty ----
  if (!param_disabled(filter_coordinateUncertainty)) {
    before <- sum(keep)
    uncertainty <- suppressWarnings(
      as.numeric(occ[["coordinateUncertaintyInMeters"]])
    )
    # NA and '' pass: only values strictly above the threshold fail
    pass <- is.na(uncertainty) | uncertainty <= filter_coordinateUncertainty
    occ[, filter_coordinateUncertainty := pass]
    keep <- keep & pass
    summary <- log_step(summary, "coordinateUncertainty", before)
  }

  # ---- Date ----
  if (filter_date) {
    before <- sum(keep)
    pass <- !(
      (is.na(occ[["eventDate"]]) | occ[["eventDate"]] == '') &
        (is.na(occ[["month"]]) | occ[["month"]] == '') &
        (is.na(occ[["year"]]) | occ[["year"]] == '') &
        (is.na(occ[["day"]]) | occ[["day"]] == '')
    )
    occ[, filter_date := pass]
    keep <- keep & pass
    summary <- log_step(summary, "date", before)
  }

  # ---- identifiedBy ----
  if (filter_identifiedBy) {
    before <- sum(keep)
    pass <- !is_junk_name(occ[["identifiedBy"]])
    occ[, filter_identifiedBy := pass]
    keep <- keep & pass
    summary <- log_step(summary, "identifiedBy", before)
  }

  # ---- recordedBy ----
  if (filter_recordedBy) {
    before <- sum(keep)
    pass <- !is_junk_name(occ[["recordedBy"]])
    occ[, filter_recordedBy := pass]
    keep <- keep & pass
    summary <- log_step(summary, "recordedBy", before)
  }

  # ---- gbif_issues_max ----
  if (!param_disabled(filter_gbif_issues_max)) {
    before <- sum(keep)
    # Defensive only: the 1:1 issue join above rules out NA gbif_issues
    pass <- is.na(occ[["gbif_issues"]]) |
      occ[["gbif_issues"]] <= filter_gbif_issues_max
    occ[, filter_gbif_issues_max := pass]
    keep <- keep & pass
    summary <- log_step(summary, "gbif_issues_max", before)
  }
  # ---- independent verdicts ----
  # Rules are evaluated independently now, so one record can fail several tests
  # at once. Neither added column is a partition of the removed records:
  #
  # * `failed` counts the records each test rejects on its own terms, so it
  #   double-counts and sums to more than the number of records removed.
  # * `only_failed_here` counts records rejected by that test and by no other.
  #   These are disjoint but incomplete: a record failing two or more tests is
  #   credited to none of them, so the column sums to less than the number of
  #   records removed (it adds up to the records failing exactly one test).
  #
  # The existing `dropped` column remains the complete, disjoint attribution:
  # it credits each removed record to the first enabled test that rejected it,
  # so it sums exactly to the number of records removed.
  fail_cols <- list()
  for (i in seq_len(nrow(summary))) {
    col <- paste0("filter_", summary$rule[i])
    if (col %in% names(occ)) fail_cols[[summary$rule[i]]] <- !occ[[col]]
  }
  fail_mat <- as.data.table(fail_cols)
  n_fail <- rowSums(fail_mat)
  summary[, failed := as.integer(vapply(fail_cols, sum, numeric(1)))]
  summary[, only_failed_here := as.integer(vapply(
    seq_along(fail_cols),
    function(i) sum(fail_cols[[i]] & n_fail == 1L),
    numeric(1)
  ))]

  # Split once, before any row is lost. `occ_marked` holds every excluded
  # record, reduced to its identifier and the verdict columns of the rules that
  # ran; the failing `F` values are therefore traceable without carrying the
  # whole occurrence table. Every applied test has a column, `taxon_resolved`
  # included, so each marked record shows exactly which tests rejected it.
  verdict_cols <- intersect(paste0("filter_", summary$rule), names(occ))
  occ_marked <- occ[!keep, c("gbifID", verdict_cols), with = FALSE]
  occ <- occ[keep]
  # `occ_filtered` carries only the occurrence and joined columns; the verdicts
  # belong to `occ_marked`.
  occ[, (verdict_cols) := NULL]

  # Column order needs no fixing: the joins and the verdict assignments all
  # append with `:=`, so the occurrence columns keep their import order and the
  # joined, issue, and `filter_*` columns follow in creation order.
  # key and sort by gbifID, matching the merge-based output (merge keys on `by`)
  setkey(occ, gbifID)
  setkey(occ_marked, gbifID)

  result <- list(
    occ_filtered = occ,
    summary = summary,
    occ_marked = occ_marked
  )
  class(result) <- "customFiltered"
  used <- Sys.time() - t1
  message(paste('used', used %>% round(1), attributes(used)$units))
  result
}

#' Print a `customFiltered` object
#'
#' Displays a concise summary of the filtering result: the number of records
#' before and after filtering, how many were excluded, and the per-rule table
#' (`dropped`, `remaining`, `failed`, and `only_failed_here`). The excluded
#' records are available in `x$occ_marked`.
#'
#' @param x An object of class `"customFiltered"` returned by [customized_filter()].
#' @param ... Additional arguments (unused, retained for S3 compatibility).
#'
#' @return Invisibly returns `x`.
#'
#' @export
print.customFiltered <- function(x, ...) {
  n_after <- nrow(x$occ_filtered)
  n_marked <- if (is.data.frame(x$occ_marked)) nrow(x$occ_marked) else 0L
  n_rules <- nrow(x$summary)

  cat("<customFiltered>\n")
  if (n_rules == 0L) {
    cat("No filter rules were applied. Records:", n_after, "\n")
  } else {
    cat(
      "Records: ",
      n_after + n_marked,
      " -> ",
      n_after,
      " (",
      n_marked,
      " excluded)\n\n",
      sep = ""
    )
    print(x$summary)
    cat("\nExcluded records are in `$occ_marked`.\n")
  }
  invisible(x)
}

#' Detect "no named person" values in collector or identifier fields
#'
#' Used by [customized_filter()] to flag junk values in `recordedBy` /
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
