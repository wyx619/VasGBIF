# ---------------------------------------------------------------------------
# Tests for extract_issues(), an internal helper that customized_filter() calls.
#
# It counts, for every record, how many of the issue codes listed in the
# bundled EnumOccurrenceIssue dataset appear in the raw pipe-separated `issue`
# column, and returns a two-column data.table: gbifID + issue_count. The
# expectations below therefore follow that dataset; if it changes, revisit them.
# ---------------------------------------------------------------------------

# --- Helpers ----------------------------------------------------------------

mk_import <- function(gbifID, issue) {
  out <- data.table(gbifID = gbifID, issue = issue)
  class(out) <- c("import", "data.table", "data.frame")
  out
}

codes <- EnumOccurrenceIssue$constant

# Every code is searched for in every record, so a code spelled inside another
# code is counted as well as the longer one. Split the codes by whether they
# contain another code, and build the simple expectations from the plain ones.
contains_other <- vapply(
  codes,
  function(code) any(stri_detect_fixed(code, setdiff(codes, code))),
  logical(1)
)
plain <- codes[!contains_other]
nested <- codes[contains_other]
stopifnot(length(plain) >= 3)
code_a <- plain[1]
code_b <- plain[2]
code_c <- plain[3]

# --- Input validation -------------------------------------------------------

test_that("default (missing) input errors with a clear message", {
  expect_error(extract_issues(), 'must be an "import" object')
})

test_that("occ must be an import object", {
  expect_error(extract_issues(occ = iris), 'must be an "import" object')
})

test_that("occ must carry the required columns", {
  for (col in c("gbifID", "issue")) {
    occ <- mk_import("1", "")
    occ[[col]] <- NULL
    expect_error(extract_issues(occ), "missing required column", info = col)
  }
})

test_that("an empty occ errors", {
  occ <- mk_import(character(0), character(0))
  expect_error(extract_issues(occ), "contains no records")
})

# --- Output contract --------------------------------------------------------

test_that("returns a two-column data.table of gbifID and issue_count", {
  occ <- mk_import(c("1", "2"), c(code_a, ""))
  res <- extract_issues(occ)

  expect_s3_class(res, "data.table")
  expect_named(res, c("gbifID", "issue_count"))
  expect_equal(nrow(res), nrow(occ))
  expect_true(is.numeric(res$issue_count))
})

test_that("gbifID is copied verbatim and in the original order", {
  ids <- c("999", "abc", "0001")
  res <- extract_issues(mk_import(ids, c("", "", "")))

  expect_identical(res$gbifID, ids)
})

test_that("a single record yields a single row", {
  res <- extract_issues(mk_import("1", code_a))

  expect_equal(nrow(res), 1L)
  expect_identical(res$gbifID, "1")
  expect_equal(res$issue_count, 1)
})

# --- Counting ---------------------------------------------------------------

test_that("issue codes are counted in pipe-separated strings", {
  occ <- mk_import(
    c("1", "2", "3"),
    c(code_a, paste(code_a, code_b, sep = "|"), "")
  )
  res <- extract_issues(occ)

  expect_equal(res$issue_count, c(1, 2, 0))
})

test_that("the count is the number of distinct codes flagged, not their length", {
  occ <- mk_import(
    c("1", "2", "3"),
    c(code_a, paste(code_a, code_b, code_c, sep = "|"), "")
  )
  res <- extract_issues(occ)

  expect_equal(res$issue_count, c(1, 3, 0))
})

test_that("every recognised code is detected in a record of its own", {
  res <- extract_issues(mk_import(as.character(seq_along(codes)), codes))

  expect_identical(res$gbifID, as.character(seq_along(codes)))
  expect_equal(res$issue_count, 1 + as.numeric(contains_other))
})

test_that("a code spelled inside another code is counted alongside it", {
  skip_if(length(nested) == 0, "no issue code contains another")

  # Pinned deliberately: this inflates issue_count for the affected records,
  # which matters because customized_filter() compares it to
  # filter_gbif_issues_max. If the matching is ever tightened to exact codes,
  # this test and the "substring" wording in the documentation must change too.
  inner <- codes[stri_detect_fixed(nested[1], codes) & codes != nested[1]]
  occ <- mk_import("1", nested[1])

  expect_gt(length(inner), 0L)
  expect_equal(extract_issues(occ)$issue_count, 1 + length(inner))
})

test_that("codes outside EnumOccurrenceIssue are ignored", {
  occ <- mk_import(c("1", "2"), c("BOGUS_ISSUE_CODE", tolower(code_a)))
  res <- extract_issues(occ)

  expect_equal(res$issue_count, c(0, 0))
})

test_that("a code embedded in extra text still counts", {
  # Matching is deliberately literal and partial, so a flag carrying text
  # around it is still recognised.
  occ <- mk_import("1", paste0("prefix_", code_a, "_suffix"))
  expect_equal(extract_issues(occ)$issue_count, 1)
})

test_that("a large input keeps one row per record", {
  n <- 5000L
  occ <- mk_import(
    as.character(seq_len(n)),
    rep(c(code_a, paste(code_a, code_b, sep = "|"), ""), length.out = n)
  )
  res <- extract_issues(occ)

  expect_equal(nrow(res), n)
  expect_equal(sum(res$issue_count), sum(rep(c(1, 2, 0), length.out = n)))
})

# --- Package surface --------------------------------------------------------

test_that("extract_issues stays internal and the issue print method is gone", {
  expect_false("extract_issues" %in% getNamespaceExports("VasGBIF"))
  expect_false(exists("print.issue", envir = asNamespace("VasGBIF")))
})

test_that("no 'issue' class is produced any more", {
  res <- extract_issues(mk_import("1", code_a))
  expect_false(inherits(res, "issue"))
})
