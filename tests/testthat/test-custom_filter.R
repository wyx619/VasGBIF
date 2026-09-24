# ---------------------------------------------------------------------------
# Tests for customized_filter() and the customFiltered print method.
#
# The function joins import_records() and check_taxon() output, then applies a
# user-selected set of quality rules. Issue counts are no longer supplied by the
# caller: extract_issues() is called internally on the raw `issue` field, so the
# helpers here build a realistic pipe-separated `issue` column rather than a
# pre-computed count.
# ---------------------------------------------------------------------------

# --- Helpers ----------------------------------------------------------------

mk_occ_import <- function(
  gbifID,
  issue = rep("", length(gbifID)),
  decimalLatitude = rep(10, length(gbifID)),
  countryCode = rep("NO", length(gbifID)),
  coordinateUncertaintyInMeters = rep(500, length(gbifID)),
  eventDate = rep("2020-01-01", length(gbifID)),
  month = rep("01", length(gbifID)),
  year = rep("2020", length(gbifID)),
  day = rep("01", length(gbifID)),
  identifiedBy = rep("Jongmans WJ", length(gbifID)),
  recordedBy = rep("Collector A", length(gbifID))
) {
  out <- data.table(
    gbifID = gbifID,
    issue = issue,
    decimalLatitude = decimalLatitude,
    countryCode = countryCode,
    coordinateUncertaintyInMeters = coordinateUncertaintyInMeters,
    eventDate = eventDate,
    month = month,
    year = year,
    day = day,
    identifiedBy = identifiedBy,
    recordedBy = recordedBy
  )
  class(out) <- c("import", class(out))
  out
}

mk_taxa <- function(gbifID) {
  n <- length(gbifID)
  checked <- data.table(
    gbifID = gbifID,
    Taxonomic_status = rep("Accepted", n),
    Accepted_name = rep("Species A", n),
    Accepted_species = rep("Species A", n),
    Accepted_name_id = rep("id-A", n),
    Source = rep("wcvp", n)
  )
  out <- list(occ_taxa_checked = checked)
  class(out) <- "occ_taxa"
  out
}

codes <- EnumOccurrenceIssue$constant

# Every code is searched for in the record, so a code spelled inside another
# code is counted as well as the longer one. The plain codes contain no other
# code and therefore let a group size be translated directly into a count.
plain <- codes[!vapply(
  codes,
  function(code) any(stri_detect_fixed(code, setdiff(codes, code))),
  logical(1)
)]

issue_string <- function(codes) paste(codes, collapse = "|")

# Expected gbif_issues for a record carrying the given codes, following the
# documented substring semantics rather than assuming one per code.
count_of <- function(codes) {
  sum(stri_detect_fixed(issue_string(codes), EnumOccurrenceIssue$constant))
}

# Disable every filter rule (keeps only the taxon_resolved join step).
filter_off <- list(
  filter_countryCode = FALSE,
  filter_coordinateUncertainty = NULL,
  filter_date = FALSE,
  filter_identifiedBy = FALSE,
  filter_recordedBy = FALSE,
  filter_gbif_issues_max = NULL
)

run <- function(occ, taxa, ...) {
  suppressMessages(customized_filter(occ_import = occ, taxa_checked = taxa, ...))
}

run_off <- function(occ, taxa) {
  suppressMessages(do.call(
    customized_filter,
    c(list(occ_import = occ, taxa_checked = taxa), filter_off)
  ))
}

# --- Input validation -------------------------------------------------------

test_that("default (missing) inputs error with a clear message", {
  expect_error(customized_filter(), '`occ_import` must be an "import" data.table')
})

test_that("each input must have its expected class", {
  occ <- mk_occ_import("1")
  taxa <- mk_taxa("1")

  expect_error(
    customized_filter(occ_import = iris, taxa_checked = taxa),
    '`occ_import` must be an "import" data.table'
  )
  expect_error(
    customized_filter(occ_import = occ, taxa_checked = iris),
    '`taxa_checked` must be an "occ_taxa" object'
  )
})

test_that("filter flags must be single non-NA logicals", {
  occ <- mk_occ_import("1")
  taxa <- mk_taxa("1")
  for (bad in list(NA, 1, c(TRUE, FALSE), "TRUE")) {
    expect_error(
      customized_filter(occ_import = occ, taxa_checked = taxa,
                        filter_countryCode = bad),
      '`filter_countryCode` must be a single logical value',
      info = paste(deparse(bad), collapse = "")
    )
  }
})

test_that("numeric filters must be non-negative scalars or disabled", {
  occ <- mk_occ_import("1")
  taxa <- mk_taxa("1")
  for (bad in list(-1, "100", c(100, 200))) {
    expect_error(
      customized_filter(occ_import = occ, taxa_checked = taxa,
                        filter_coordinateUncertainty = bad),
      "`filter_coordinateUncertainty` must be a single non-negative number",
      info = paste(deparse(bad), collapse = "")
    )
    expect_error(
      customized_filter(occ_import = occ, taxa_checked = taxa,
                        filter_gbif_issues_max = bad),
      "`filter_gbif_issues_max` must be a single non-negative number",
      info = paste(deparse(bad), collapse = "")
    )
  }
})

test_that("occ_import must carry the columns the enabled rules read", {
  taxa <- mk_taxa("1")

  # read by the default rules
  for (col in c("issue", "decimalLatitude", "countryCode",
                "coordinateUncertaintyInMeters")) {
    occ <- mk_occ_import("1")
    occ[[col]] <- NULL
    expect_error(
      run(occ, taxa),
      paste0("missing required column\\(s\\): ", col),
      info = col
    )
  }

  # read only by rules that are off by default
  for (col in c("eventDate", "month", "year", "day", "identifiedBy", "recordedBy")) {
    occ <- mk_occ_import("1")
    occ[[col]] <- NULL
    expect_error(run(occ, taxa), NA, info = col)
  }
})

test_that("a column becomes required only once its rule is enabled", {
  taxa <- mk_taxa("1")

  occ <- mk_occ_import("1")
  occ[["identifiedBy"]] <- NULL
  expect_error(
    run(occ, taxa, filter_identifiedBy = TRUE),
    "missing required column\\(s\\): identifiedBy"
  )

  occ <- mk_occ_import("1")
  occ[["coordinateUncertaintyInMeters"]] <- NULL
  expect_no_error(run(occ, taxa, filter_coordinateUncertainty = NULL))
  expect_error(
    run(occ, taxa),
    "missing required column\\(s\\): coordinateUncertaintyInMeters"
  )
})

test_that("taxa_checked must carry its columns", {
  occ <- mk_occ_import("1")
  for (col in c(
    "gbifID", "Taxonomic_status", "Accepted_name", "Accepted_species",
    "Accepted_name_id", "Source"
  )) {
    taxa <- mk_taxa("1")
    taxa$occ_taxa_checked[[col]] <- NULL
    expect_error(
      run(occ, taxa),
      paste0("missing column\\(s\\): ", col),
      info = col
    )
  }
})

# --- Joining the inputs -----------------------------------------------------

test_that("the taxon join drops unresolved records and logs taxon_resolved", {
  occ <- mk_occ_import(c("1", "2"))
  taxa <- mk_taxa("1") # "2" is unresolved
  res <- run_off(occ, taxa)

  expect_setequal(res$occ_filtered$gbifID, "1")
  expect_identical(res$summary$rule, "taxon_resolved")
  expect_equal(res$summary$dropped, 1L)
  expect_equal(res$summary$remaining, 1L)
  # the verdict is recorded on the excluded side only
  expect_false(any(startsWith(names(res$occ_filtered), "filter_")))
  expect_false(res$occ_marked[gbifID == "2", filter_taxon_resolved])
})

test_that("the issue count is computed internally from the raw issue field", {
  occ <- mk_occ_import(c("1", "2"), issue = c(issue_string(plain[1:3]), ""))
  res <- run_off(occ, mk_taxa(c("1", "2")))

  expect_equal(res$occ_filtered[gbifID == "1", gbif_issues], count_of(plain[1:3]))
  expect_equal(res$occ_filtered[gbifID == "2", gbif_issues], 0)
  # the raw pipe-separated field does not survive into the output
  expect_false("issue" %in% names(res$occ_filtered))
})

test_that("a larger issue string is counted without truncation", {
  group <- plain[1:12]
  occ <- mk_occ_import("1", issue = issue_string(group))
  res <- run_off(occ, mk_taxa("1"))

  expect_equal(count_of(group), 12)
  expect_equal(res$occ_filtered$gbif_issues, count_of(group))
})

test_that("a record whose issue field is NA is reported rather than silently kept", {
  occ <- mk_occ_import(c("1", "2"), issue = c("", NA))
  expect_error(
    run(occ, mk_taxa(c("1", "2"))),
    "No issue count could be computed for"
  )
})

# --- Filter rules -----------------------------------------------------------

test_that("countryCode rule drops records with neither coordinate nor country code", {
  occ <- mk_occ_import(
    gbifID = c("1", "2", "3", "4"),
    decimalLatitude = c(10, NA, 10, NA),
    countryCode = c("NO", NA, NA, "NO")
  )
  res <- run(occ, mk_taxa(c("1", "2", "3", "4")),
             filter_coordinateUncertainty = NULL, filter_gbif_issues_max = NULL)

  expect_setequal(res$occ_filtered$gbifID, c("1", "3", "4"))
  expect_identical(res$summary[rule == "countryCode", dropped], 1L)
  expect_identical(res$summary[rule == "countryCode", failed], 1L)
})

test_that("coordinateUncertainty drops values strictly above the threshold", {
  occ <- mk_occ_import(
    gbifID = c("1", "2", "3", "4"),
    coordinateUncertaintyInMeters = c(500, 50000, NA, "")
  )
  res <- run(occ, mk_taxa(c("1", "2", "3", "4")),
             filter_countryCode = FALSE, filter_gbif_issues_max = NULL)

  # NA and '' uncertainty stay; only 50000 > 10000 is removed
  expect_setequal(res$occ_filtered$gbifID, c("1", "3", "4"))
  expect_identical(res$summary[rule == "coordinateUncertainty", dropped], 1L)
})

test_that("coordinateUncertainty rule can be disabled with NULL, NA or ''", {
  occ <- mk_occ_import(c("1", "2"), coordinateUncertaintyInMeters = c(500, 50000))
  taxa <- mk_taxa(c("1", "2"))
  for (off in list(NULL, NA, "")) {
    res <- run(occ, taxa, filter_countryCode = FALSE,
               filter_coordinateUncertainty = off, filter_gbif_issues_max = NULL)
    expect_setequal(res$occ_filtered$gbifID, c("1", "2"))
    expect_false("coordinateUncertainty" %in% res$summary$rule)
  }
})

test_that("date rule drops records with all four date components missing", {
  occ <- mk_occ_import(
    gbifID = c("1", "2", "3"),
    eventDate = c("2020-01-01", NA, NA),
    month = c("01", NA, "05"),
    year = c("2020", NA, NA),
    day = c("01", NA, NA)
  )
  res <- run(occ, mk_taxa(c("1", "2", "3")),
             filter_countryCode = FALSE, filter_coordinateUncertainty = NULL,
             filter_date = TRUE, filter_gbif_issues_max = NULL)

  # row 2 has no date at all; row 3 keeps its month
  expect_setequal(res$occ_filtered$gbifID, c("1", "3"))
  expect_identical(res$summary[rule == "date", dropped], 1L)
})

test_that("identifiedBy and recordedBy rules flag junk but keep mixed names", {
  occ <- mk_occ_import(
    gbifID = c("1", "2", "3", "4", "5", "6"),
    identifiedBy = c(
      "unknown", "Unknown; Jongmans WJ", "\u672a\u77e5", "Jongmans WJ", NA, "Jongmans WJ"
    ),
    recordedBy = c(
      "s.n.", "Collector(s): Eric Sundell, unknown", "Botanist X",
      "Botanist Y", "Botanist Z", "no collector"
    )
  )
  res <- run(occ, mk_taxa(c("1", "2", "3", "4", "5", "6")),
             filter_countryCode = FALSE, filter_coordinateUncertainty = NULL,
             filter_identifiedBy = TRUE, filter_recordedBy = TRUE,
             filter_gbif_issues_max = NULL)

  # junk identifiedBy (1, 3, 5), junk recordedBy (1, 6); both fields must be clean
  expect_setequal(res$occ_filtered$gbifID, c("2", "4"))
  expect_identical(res$summary[rule == "identifiedBy", dropped], 3L)
  expect_identical(res$summary[rule == "recordedBy", dropped], 1L)
})

test_that("gbif_issues_max drops records above the threshold", {
  occ <- mk_occ_import(
    gbifID = c("1", "2", "3"),
    issue = c("", issue_string(plain[1:3]), issue_string(plain[1:12]))
  )
  res <- run(occ, mk_taxa(c("1", "2", "3")),
             filter_countryCode = FALSE, filter_coordinateUncertainty = NULL,
             filter_gbif_issues_max = 5)

  expect_setequal(res$occ_filtered$gbifID, c("1", "2"))
  expect_identical(res$summary[rule == "gbif_issues_max", dropped], 1L)
  expect_identical(res$summary[rule == "gbif_issues_max", failed], 1L)
})

test_that("gbif_issues_max rule can be disabled", {
  occ <- mk_occ_import(c("1", "2"), issue = c("", issue_string(plain[1:12])))
  res <- run(occ, mk_taxa(c("1", "2")),
             filter_countryCode = FALSE, filter_coordinateUncertainty = NULL,
             filter_gbif_issues_max = NULL)

  expect_setequal(res$occ_filtered$gbifID, c("1", "2"))
  expect_false("gbif_issues_max" %in% res$summary$rule)
})

# --- Output contract --------------------------------------------------------

test_that("returns a customFiltered object with occ_filtered, summary and occ_marked", {
  occ <- mk_occ_import(c("1", "2"))
  res <- run(occ, mk_taxa(c("1", "2")))

  expect_s3_class(res, "customFiltered")
  expect_named(res, c("occ_filtered", "summary", "occ_marked"))
  expect_s3_class(res$occ_filtered, "data.table")
  expect_s3_class(res$occ_marked, "data.table")
  expect_named(
    res$summary,
    c("rule", "dropped", "remaining", "failed", "only_failed_here")
  )
  expect_identical(
    res$summary$rule,
    c("taxon_resolved", "countryCode", "coordinateUncertainty", "gbif_issues_max")
  )
  expect_true(all(res$summary$dropped >= 0L))
  expect_true(all(diff(res$summary$remaining) <= 0L))
})

test_that("occ_filtered drops the verdict columns, occ_marked carries all of them", {
  occ <- mk_occ_import(c("1", "2"), decimalLatitude = c(10, NA), countryCode = c("NO", NA))
  res <- run(occ, mk_taxa(c("1", "2")))

  expect_false(any(startsWith(names(res$occ_filtered), "filter_")))
  expect_identical(names(res$occ_marked)[1], "gbifID")
  expect_setequal(
    setdiff(names(res$occ_marked), "gbifID"),
    paste0("filter_", res$summary$rule)
  )
  # the excluded record shows which test rejected it
  expect_false(res$occ_marked[gbifID == "2", filter_countryCode])
  expect_true(res$occ_marked[gbifID == "2", filter_taxon_resolved])
})

test_that("every marked record fails at least one applied test", {
  occ <- mk_occ_import(c("1", "2", "3"), decimalLatitude = c(10, NA, 10),
                       countryCode = c("NO", NA, NA))
  res <- run(occ, mk_taxa(c("1", "2", "3")))

  verdicts <- res$occ_marked[, setdiff(names(res$occ_marked), "gbifID"), with = FALSE]
  expect_gt(nrow(verdicts), 0L)
  expect_true(all(rowSums(!verdicts) >= 1))
})

test_that("occ_filtered and occ_marked together account for every input record", {
  occ <- mk_occ_import(c("1", "2", "3"), decimalLatitude = c(10, NA, 10),
                       countryCode = c("NO", NA, NA))
  res <- run(occ, mk_taxa(c("1", "2", "3")))

  expect_equal(nrow(res$occ_filtered) + nrow(res$occ_marked), nrow(occ))
  expect_setequal(c(res$occ_filtered$gbifID, res$occ_marked$gbifID), occ$gbifID)
  expect_length(intersect(res$occ_filtered$gbifID, res$occ_marked$gbifID), 0L)
})

test_that("the caller's occ_import is never modified", {
  occ <- mk_occ_import(c("1", "2"), issue = c(issue_string(plain[1:3]), ""))
  snapshot <- data.table::copy(occ)

  invisible(run(occ, mk_taxa(c("1", "2"))))

  expect_identical(occ, snapshot)
  expect_true("issue" %in% names(occ))
})

test_that("failed overlaps across rules while only_failed_here stays disjoint", {
  occ <- mk_occ_import(
    gbifID = c("1", "2", "3"),
    decimalLatitude = c(NA, 10, 10),
    countryCode = c(NA, "NO", "NO"),
    coordinateUncertaintyInMeters = c(50000, 50000, 500)
  )
  res <- run(occ, mk_taxa(c("1", "2", "3")),
             filter_countryCode = TRUE, filter_coordinateUncertainty = 10000,
             filter_gbif_issues_max = NULL)

  # record 1 fails both rules, record 2 fails only coordinateUncertainty
  expect_identical(res$summary[rule == "countryCode", failed], 1L)
  expect_identical(res$summary[rule == "coordinateUncertainty", failed], 2L)
  expect_identical(res$summary[rule == "countryCode", only_failed_here], 0L)
  expect_identical(res$summary[rule == "coordinateUncertainty", only_failed_here], 1L)

  # dropped credits each removed record once, to the first rule that rejected it
  expect_equal(sum(res$summary$dropped), nrow(res$occ_marked))
})

# --- Print method -----------------------------------------------------------

test_that("print.customFiltered shows record counts and the per-rule table", {
  occ <- mk_occ_import(c("1", "2"), decimalLatitude = c(10, NA), countryCode = c("NO", NA))
  res <- run(occ, mk_taxa(c("1", "2")))

  out <- capture.output(print(res))
  expect_true(any(grepl("<customFiltered>", out)))
  expect_true(any(grepl("Records: 2 -> 1 \\(1 excluded\\)", out)))
  expect_true(any(grepl("countryCode", out)))
  expect_true(any(grepl("only_failed_here", out)))
  expect_invisible(print(res))
})

test_that("print.customFiltered handles a summary with no rules", {
  x <- structure(
    list(
      occ_filtered = data.table(gbifID = "1"),
      summary = data.table(
        rule = character(),
        dropped = integer(),
        remaining = integer(),
        failed = integer(),
        only_failed_here = integer()
      )
    ),
    class = "customFiltered"
  )
  out <- capture.output(print(x))
  expect_true(any(grepl("No filter rules were applied", out)))
})
