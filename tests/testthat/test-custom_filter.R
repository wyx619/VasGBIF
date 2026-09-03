# ---------------------------------------------------------------------------
# Tests for customized_filter() and the customFiltered print method.
# ---------------------------------------------------------------------------

# --- Helpers ----------------------------------------------------------------

mk_occ_import <- function(
  gbifID,
  issue = rep(0L, length(gbifID)),
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

mk_issue <- function(gbifID, issue_count = rep(0L, length(gbifID))) {
  out <- list(occ_issue = data.table(gbifID = gbifID, issue_count = issue_count))
  class(out) <- "issue"
  out
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

# --- Input validation -------------------------------------------------------

test_that("default (missing) inputs error with a clear message", {
  expect_error(
    customized_filter(),
    '`occ_import` must be an "import" data.table'
  )
})

test_that("each input must have its expected class", {
  occ <- mk_occ_import("1")
  taxa <- mk_taxa("1")
  issue <- mk_issue("1")
  expect_error(
    customized_filter(occ_import = iris, taxa_checked = taxa, gbif_issue = issue),
    '`occ_import` must be an "import" data.table'
  )
  expect_error(
    customized_filter(occ_import = occ, taxa_checked = iris, gbif_issue = issue),
    '`taxa_checked` must be an "occ_taxa" object'
  )
  expect_error(
    customized_filter(occ_import = occ, taxa_checked = taxa, gbif_issue = iris),
    '`gbif_issue` must be an "issue" object'
  )
})

test_that("filter flags must be single non-NA logicals", {
  occ <- mk_occ_import("1")
  taxa <- mk_taxa("1")
  issue <- mk_issue("1")
  for (bad in list(NA, 1, c(TRUE, FALSE), "TRUE")) {
    expect_error(
      customized_filter(occ_import = occ, taxa_checked = taxa, gbif_issue = issue,
                    filter_countryCode = bad),
      '`filter_countryCode` must be a single logical value',
      info = paste(deparse(bad), collapse = "")
    )
  }
})

test_that("occ_import must carry the required columns", {
  taxa <- mk_taxa("1")
  issue <- mk_issue("1")
  for (col in c(
    "issue", "decimalLatitude", "countryCode", "coordinateUncertaintyInMeters",
    "eventDate", "month", "year", "day", "identifiedBy", "recordedBy"
  )) {
    occ <- mk_occ_import("1")
    occ[[col]] <- NULL
    expect_error(
      customized_filter(occ_import = occ, taxa_checked = taxa, gbif_issue = issue),
      paste0("missing required column\\(s\\): ", col),
      info = col
    )
  }
})

test_that("taxa_checked and gbif_issue must carry their columns", {
  occ <- mk_occ_import("1")
  for (col in c(
    "gbifID", "Taxonomic_status", "Accepted_name", "Accepted_species",
    "Accepted_name_id", "Source"
  )) {
    taxa <- mk_taxa("1")
    taxa$occ_taxa_checked[[col]] <- NULL
    expect_error(
      customized_filter(occ_import = occ, taxa_checked = taxa, gbif_issue = mk_issue("1")),
      paste0("missing column\\(s\\): ", col),
      info = col
    )
  }
  for (col in c("gbifID", "issue_count")) {
    issue <- mk_issue("1")
    issue$occ_issue[[col]] <- NULL
    expect_error(
      customized_filter(occ_import = occ, taxa_checked = mk_taxa("1"), gbif_issue = issue),
      paste0("missing column\\(s\\): ", col),
      info = col
    )
  }
})

test_that("numeric filters must be non-negative scalars or disabled", {
  occ <- mk_occ_import("1")
  taxa <- mk_taxa("1")
  issue <- mk_issue("1")
  for (bad in list(-1, "100", c(100, 200))) {
    expect_error(
      customized_filter(occ_import = occ, taxa_checked = taxa, gbif_issue = issue,
                    filter_coordinateUncertainty = bad),
      "`filter_coordinateUncertainty` must be a single non-negative number",
      info = paste(deparse(bad), collapse = "")
    )
    expect_error(
      customized_filter(occ_import = occ, taxa_checked = taxa, gbif_issue = issue,
                    filter_gbif_issues_max = bad),
      "`filter_gbif_issues_max` must be a single non-negative number",
      info = paste(deparse(bad), collapse = "")
    )
  }
})

# --- Joining the inputs -----------------------------------------------------

test_that("inner taxon join drops unresolved records and logs taxon_resolved", {
  occ <- mk_occ_import(c("1", "2"))
  taxa <- mk_taxa("1") # "2" unresolved
  issue <- mk_issue(c("1", "2"))
  res <- do.call(customized_filter, c(
    list(occ_import = occ, taxa_checked = taxa, gbif_issue = issue),
    filter_off
  ))

  expect_setequal(res$occ_filtered$gbifID, "1")
  expect_identical(res$summary$rule, "taxon_resolved")
  expect_equal(res$summary$dropped, 1L)
  expect_equal(res$summary$remaining, 1L)
})

test_that("issue join must cover every record", {
  occ <- mk_occ_import(c("1", "2"))
  taxa <- mk_taxa(c("1", "2"))
  issue <- mk_issue("1") # missing "2"
  expect_error(
    customized_filter(occ_import = occ, taxa_checked = taxa, gbif_issue = issue),
    "does not cover every record"
  )
})

test_that("issue count is joined as gbif_issues and the raw issue column is dropped", {
  occ <- mk_occ_import(c("1", "2"), issue = c(3L, 1L))
  taxa <- mk_taxa(c("1", "2"))
  issue <- mk_issue(c("1", "2"), issue_count = c(3L, 1L))
  res <- do.call(customized_filter, c(
    list(occ_import = occ, taxa_checked = taxa, gbif_issue = issue),
    filter_off
  ))

  expect_true("gbif_issues" %in% names(res$occ_filtered))
  expect_false("issue" %in% names(res$occ_filtered))
  expect_identical(res$occ_filtered[gbifID == "1", gbif_issues], 3L)
})

# --- Filter rules -----------------------------------------------------------

test_that("countryCode rule drops records with neither coordinate nor country code", {
  occ <- mk_occ_import(
    gbifID = c("1", "2", "3", "4"),
    decimalLatitude = c(10, NA, 10, NA),
    countryCode = c("NO", NA, NA, "NO")
  )
  res <- customized_filter(
    occ_import = occ,
    taxa_checked = mk_taxa(c("1", "2", "3", "4")),
    gbif_issue = mk_issue(c("1", "2", "3", "4"))
  )

  expect_setequal(res$occ_filtered$gbifID, c("1", "3", "4"))
  expect_identical(res$summary[rule == "countryCode", dropped], 1L)
})

test_that("coordinateUncertainty drops values strictly above the threshold", {
  occ <- mk_occ_import(
    gbifID = c("1", "2", "3", "4"),
    coordinateUncertaintyInMeters = c(500, 50000, NA, "")
  )
  res <- customized_filter(
    occ_import = occ,
    taxa_checked = mk_taxa(c("1", "2", "3", "4")),
    gbif_issue = mk_issue(c("1", "2", "3", "4")),
    filter_countryCode = FALSE
  )

  # NA and '' uncertainty stay; only 50000 > 10000 is removed
  expect_setequal(res$occ_filtered$gbifID, c("1", "3", "4"))
})

test_that("coordinateUncertainty rule can be disabled with NULL, NA or ''", {
  occ <- mk_occ_import(c("1", "2"), coordinateUncertaintyInMeters = c(500, 50000))
  taxa <- mk_taxa(c("1", "2"))
  issue <- mk_issue(c("1", "2"))
  for (off in list(NULL, NA, "")) {
    res <- customized_filter(
      occ_import = occ, taxa_checked = taxa, gbif_issue = issue,
      filter_countryCode = FALSE, filter_coordinateUncertainty = off
    )
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
  res <- customized_filter(
    occ_import = occ,
    taxa_checked = mk_taxa(c("1", "2", "3")),
    gbif_issue = mk_issue(c("1", "2", "3")),
    filter_countryCode = FALSE,
    filter_coordinateUncertainty = NULL,
    filter_date = TRUE
  )

  # row 2 has no date at all; row 3 keeps its month
  expect_setequal(res$occ_filtered$gbifID, c("1", "3"))
})

test_that("identifiedBy and recordedBy rules flag junk but keep mixed names", {
  occ <- mk_occ_import(
    gbifID = c("1", "2", "3", "4", "5", "6"),
    identifiedBy = c(
      "unknown", "Unknown; Jongmans WJ", "未知", "Jongmans WJ", NA, "Jongmans WJ"
    ),
    recordedBy = c(
      "s.n.", "Collector(s): Eric Sundell, unknown", "Botanist X",
      "Botanist Y", "Botanist Z", "no collector"
    )
  )
  res <- customized_filter(
    occ_import = occ,
    taxa_checked = mk_taxa(c("1", "2", "3", "4", "5", "6")),
    gbif_issue = mk_issue(c("1", "2", "3", "4", "5", "6")),
    filter_countryCode = FALSE,
    filter_coordinateUncertainty = NULL,
    filter_identifiedBy = TRUE,
    filter_recordedBy = TRUE
  )

  # junk idBy (1, 3, 5), junk recBy (1, 6); both fields must be clean
  expect_setequal(res$occ_filtered$gbifID, c("2", "4"))
})

test_that("gbif_issues_max drops records above the threshold", {
  occ <- mk_occ_import(c("1", "2", "3"))
  issue <- mk_issue(c("1", "2", "3"), issue_count = c(0L, 3L, 12L))
  res <- customized_filter(
    occ_import = occ,
    taxa_checked = mk_taxa(c("1", "2", "3")),
    gbif_issue = issue,
    filter_countryCode = FALSE,
    filter_coordinateUncertainty = NULL,
    filter_gbif_issues_max = 5
  )

  expect_setequal(res$occ_filtered$gbifID, c("1", "2"))
})

test_that("gbif_issues_max rule can be disabled", {
  occ <- mk_occ_import(c("1", "2"))
  issue <- mk_issue(c("1", "2"), issue_count = c(0L, 12L))
  res <- customized_filter(
    occ_import = occ,
    taxa_checked = mk_taxa(c("1", "2")),
    gbif_issue = issue,
    filter_countryCode = FALSE,
    filter_coordinateUncertainty = NULL,
    filter_gbif_issues_max = NULL
  )

  expect_setequal(res$occ_filtered$gbifID, c("1", "2"))
  expect_false("gbif_issues_max" %in% res$summary$rule)
})

# --- Output contract --------------------------------------------------------

test_that("returns a customFiltered object with occ_filtered and summary", {
  occ <- mk_occ_import(c("1", "2"))
  res <- customized_filter(
    occ_import = occ,
    taxa_checked = mk_taxa(c("1", "2")),
    gbif_issue = mk_issue(c("1", "2"))
  )

  expect_s3_class(res, "customFiltered")
  expect_named(res, c("occ_filtered", "summary"))
  expect_s3_class(res$occ_filtered, "data.table")
  expect_named(res$summary, c("rule", "dropped", "remaining"))
  expect_identical(
    res$summary$rule,
    c("taxon_resolved", "countryCode", "coordinateUncertainty", "gbif_issues_max")
  )
  expect_true(all(res$summary$dropped >= 0L))
  expect_true(all(diff(res$summary$remaining) <= 0L))
})

# --- Print method -----------------------------------------------------------

test_that("print.customFiltered shows record counts and the per-rule table", {
  occ <- mk_occ_import(c("1", "2"), decimalLatitude = c(10, NA), countryCode = c("NO", NA))
  res <- customized_filter(
    occ_import = occ,
    taxa_checked = mk_taxa(c("1", "2")),
    gbif_issue = mk_issue(c("1", "2"))
  )

  out <- capture.output(print(res))
  expect_true(any(grepl("<customFiltered>", out)))
  expect_true(any(grepl("Records: 2 -> 1", out)))
  expect_true(any(grepl("countryCode", out)))
  expect_invisible(print(res))
})

test_that("print.customFiltered handles a summary with no rules", {
  x <- structure(
    list(
      occ_filtered = data.table(gbifID = "1"),
      summary = data.table(
        rule = character(),
        dropped = integer(),
        remaining = integer()
      )
    ),
    class = "customFiltered"
  )
  out <- capture.output(print(x))
  expect_true(any(grepl("No filter rules were applied", out)))
})
