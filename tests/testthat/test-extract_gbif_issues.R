# ---------------------------------------------------------------------------
# Tests for extract_gbif_issues() and the issue print method.
#
# The function expands the raw pipe-separated `issue` column against the
# bundled EnumOccurrenceIssue dataset, so expected column sets and codes are
# derived from that dataset. If the dataset changes, the expectations below
# must be revisited.
# ---------------------------------------------------------------------------

# --- Helpers ----------------------------------------------------------------

mk_import <- function(gbifID, issue) {
  out <- data.table(gbifID = gbifID, issue = issue)
  class(out) <- c("import", "data.table", "data.frame")
  out
}

# Two distinct issue codes that are not substrings of one another, taken from
# the bundled dataset so the tests stay in sync with it.
code_a <- EnumOccurrenceIssue$constant[1]
code_b <- EnumOccurrenceIssue$constant[2]

# --- Input validation -------------------------------------------------------

test_that("default (missing) inputs error with a clear message", {
  expect_error(extract_gbif_issues(), "must be an \"import\" object")
})

test_that("occ must be an import object", {
  expect_error(extract_gbif_issues(occ = iris), "must be an \"import\" object")
})

test_that("occ must carry the required columns", {
  for (col in c("gbifID", "issue")) {
    occ <- mk_import("1", "")
    occ[[col]] <- NULL
    expect_error(
      extract_gbif_issues(occ),
      "missing required column",
      info = col
    )
  }
})

test_that("an empty occ errors", {
  occ <- mk_import(character(0), character(0))
  expect_error(extract_gbif_issues(occ), "contains no records")
})

# --- Output contract --------------------------------------------------------

test_that("returns an issue object with occ_issue and summary", {
  occ <- mk_import(c("1", "2"), c(code_a, ""))
  res <- suppressMessages(extract_gbif_issues(occ))

  expect_s3_class(res, "issue")
  expect_named(res, c("occ_issue", "summary"))
  expect_s3_class(res$occ_issue, "data.table")
  expect_s3_class(res$summary, "data.table")
})

test_that("occ_issue has one logical column per issue code plus gbifID and issue_count", {
  occ <- mk_import(c("1", "2"), c(code_a, ""))
  res <- suppressMessages(extract_gbif_issues(occ))

  codes <- EnumOccurrenceIssue$constant
  expect_equal(ncol(res$occ_issue), length(codes) + 2L)
  expect_setequal(names(res$occ_issue), c(codes, "gbifID", "issue_count"))
  expect_true(all(vapply(res$occ_issue[, ..codes], is.logical, logical(1))))
  expect_identical(res$occ_issue$gbifID, c("1", "2"))
})

# --- Detection --------------------------------------------------------------

test_that("issue codes are detected in pipe-separated strings", {
  occ <- mk_import(
    c("1", "2", "3"),
    c(code_a, paste(code_a, code_b, sep = "|"), "")
  )
  res <- suppressMessages(extract_gbif_issues(occ))

  expect_true(res$occ_issue[[code_a]][1])
  expect_false(res$occ_issue[[code_b]][1])
  expect_true(res$occ_issue[[code_a]][2])
  expect_true(res$occ_issue[[code_b]][2])
  expect_false(res$occ_issue[[code_a]][3])
  expect_false(res$occ_issue[[code_b]][3])
  expect_equal(res$occ_issue$issue_count, c(1, 2, 0))
})

test_that("a single record still yields one row per issue code", {
  occ <- mk_import("1", code_a)
  res <- suppressMessages(extract_gbif_issues(occ))

  expect_equal(nrow(res$occ_issue), 1L)
  expect_equal(ncol(res$occ_issue), nrow(EnumOccurrenceIssue) + 2L)
  expect_true(res$occ_issue[[code_a]])
})

test_that("codes outside EnumOccurrenceIssue are ignored", {
  occ <- mk_import("1", "BOGUS_ISSUE_CODE")
  res <- suppressMessages(extract_gbif_issues(occ))

  expect_false("BOGUS_ISSUE_CODE" %chin% names(res$occ_issue))
  expect_equal(res$occ_issue$issue_count, 0)
})

# --- Summary ----------------------------------------------------------------

test_that("summary ranks codes by the number of flagged records", {
  occ <- mk_import(
    c("1", "2", "3"),
    c(code_a, code_a, code_b)
  )
  res <- suppressMessages(extract_gbif_issues(occ))

  expect_setequal(res$summary$issue_keys, EnumOccurrenceIssue$constant)
  expect_true(!is.unsorted(-res$summary$N))
  expect_equal(res$summary[issue_keys == code_a, N], 2)
  expect_equal(res$summary[issue_keys == code_b, N], 1)
})

# --- Print method -----------------------------------------------------------

test_that("print shows record counts, top issues, and issue_count distribution", {
  occ <- mk_import(
    c("1", "2", "3"),
    c(code_a, paste(code_a, code_b, sep = "|"), "")
  )
  res <- suppressMessages(extract_gbif_issues(occ))

  out <- capture.output(print(res))
  expect_true(any(grepl(
    paste0("<issue> 3 records | ", nrow(EnumOccurrenceIssue), " issue codes"),
    out
  )))
  expect_true(any(grepl("Top issues by flagged records", out)))
  expect_true(any(grepl(code_a, out)))
  expect_true(any(grepl("issue_count distribution:", out)))

  expect_invisible(print(res))
})

test_that("print handles missing elements", {
  x <- structure(list(), class = "issue")
  expect_no_error(out <- capture.output(print(x)))
  expect_true(any(grepl("<issue> 0 records", out)))
})

test_that("print handles a summary without the expected columns", {
  x <- list(
    occ_issue = data.table(gbifID = "1", issue_count = 1),
    summary = data.table(foo = 1)
  )
  class(x) <- "issue"
  out <- capture.output(print(x))
  expect_true(any(grepl("<issue> 1 records | 0 issue codes", out)))
  expect_false(any(grepl("Top issues", out)))
})
