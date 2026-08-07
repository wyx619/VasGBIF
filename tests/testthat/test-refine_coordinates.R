# ---------------------------------------------------------------------------
# Tests for refine_coordinates() and the CoordinateRefined print method.
#
# Behavioural tests use small, deterministic CoordinateCleaner test sets
# ("zeros" flags (0, 0), "equal" flags lat == lon) and threads = 1 to keep
# the cluster overhead minimal.
# ---------------------------------------------------------------------------

# --- Helpers ----------------------------------------------------------------

mk_custom_filtered <- function(occ_filtered) {
  out <- list(occ_filtered = occ_filtered)
  class(out) <- "customFiltered"
  out
}

mk_occ <- function(gbifID, lon, lat, species = rep("id1", length(gbifID))) {
  data.table(
    gbifID = gbifID,
    decimalLongitude = lon,
    decimalLatitude = lat,
    Accepted_name_id = species
  )
}

# --- Input validation -------------------------------------------------------

test_that("default (missing) inputs error with a clear message", {
  expect_error(
    refine_coordinates(),
    '`custom_filtered` must be a "customFiltered" object'
  )
})

test_that("custom_filtered must be a customFiltered object", {
  expect_error(
    refine_coordinates(custom_filtered = iris),
    '`custom_filtered` must be a "customFiltered" object'
  )
})

test_that("occ_filtered must carry the required columns", {
  for (col in c("gbifID", "decimalLatitude", "decimalLongitude", "Accepted_name_id")) {
    occ <- mk_occ(c("1", "2"), c(10, 20), c(60, 70))
    occ[[col]] <- NULL
    expect_error(
      refine_coordinates(custom_filtered = mk_custom_filtered(occ)),
      paste0("missing required column\\(s\\): ", col),
      info = col
    )
  }
})

test_that("unknown tests error", {
  cf <- mk_custom_filtered(mk_occ("1", 10, 60))
  expect_error(
    refine_coordinates(custom_filtered = cf, tests = c("zeros", "bogus")),
    "Unknown test\\(s\\): bogus"
  )
})

# --- Output contract --------------------------------------------------------

test_that("returns a CoordinateRefined object with the expected elements", {
  cf <- mk_custom_filtered(mk_occ(c("1", "2"), c(10, 0), c(60, 0)))
  res <- suppressMessages(refine_coordinates(
    custom_filtered = cf,
    threads = 1,
    tests = c("zeros", "equal")
  ))

  expect_s3_class(res, "CoordinateRefined")
  expect_named(
    res,
    c("CoordinateCleaned", "CoordinateProblematic", "runtime")
  )
  expect_s3_class(res$CoordinateCleaned, "data.table")
  expect_s3_class(res$CoordinateProblematic, "data.table")
  expect_s3_class(res$runtime, "difftime")
})

# --- Coordinate splitting ---------------------------------------------------

test_that("passing and failing records are split by CoordinateCleaner", {
  occ <- mk_occ(
    c("1", "2", "3", "4", "5"),
    c(10, 0, 10, NA, 10),
    c(60, 0, 10, 60, NA)
  )
  res <- suppressMessages(refine_coordinates(
    custom_filtered = mk_custom_filtered(occ),
    threads = 1,
    tests = c("zeros", "equal")
  ))

  expect_setequal(res$CoordinateCleaned$gbifID, "1")
  expect_setequal(res$CoordinateProblematic$gbifID, c("2", "3"))
})

test_that("CoordinateCleaned keeps the original columns only", {
  occ <- mk_occ(c("1", "2"), c(10, 0), c(60, 0))
  res <- suppressMessages(refine_coordinates(
    custom_filtered = mk_custom_filtered(occ),
    threads = 1,
    tests = "zeros"
  ))
  expect_true(all(
    c("gbifID", "decimalLongitude", "decimalLatitude", "Accepted_name_id") %in%
      names(res$CoordinateCleaned)
  ))
  expect_false(".summary" %in% names(res$CoordinateCleaned))
})

test_that("CoordinateProblematic retains the CoordinateCleaner flag columns", {
  occ <- mk_occ(c("1", "2"), c(10, 0), c(60, 0))
  res <- suppressMessages(refine_coordinates(
    custom_filtered = mk_custom_filtered(occ),
    threads = 1,
    tests = "zeros"
  ))
  expect_true(".summary" %in% names(res$CoordinateProblematic))
  expect_true(".zer" %in% names(res$CoordinateProblematic))
  expect_true(all(res$CoordinateProblematic$.summary == FALSE))
})

# --- Empty input ------------------------------------------------------------

test_that("records without complete coordinates bypass validation", {
  occ <- mk_occ(c("1", "2"), c(NA, 10), c(60, NA))
  res <- suppressMessages(refine_coordinates(
    custom_filtered = mk_custom_filtered(occ),
    threads = 1
  ))

  expect_equal(nrow(res$CoordinateCleaned), 0L)
  expect_equal(nrow(res$CoordinateProblematic), 0L)
})

test_that("empty-coordinate input reports skipping validation", {
  occ <- mk_occ(c("1", "2"), c(NA, 10), c(60, NA))
  expect_message(
    refine_coordinates(custom_filtered = mk_custom_filtered(occ), threads = 1),
    "No records with complete coordinates"
  )
})

test_that("a fully empty occ_filtered returns empty tables", {
  occ <- mk_occ(character(0), numeric(0), numeric(0))
  res <- suppressMessages(refine_coordinates(
    custom_filtered = mk_custom_filtered(occ),
    threads = 1
  ))

  expect_equal(nrow(res$CoordinateCleaned), 0L)
  expect_equal(nrow(res$CoordinateProblematic), 0L)
})

# --- Print method -----------------------------------------------------------

test_that("print.CoordinateRefined shows counts and runtime", {
  cf <- mk_custom_filtered(mk_occ(c("1", "2"), c(10, 0), c(60, 0)))
  res <- suppressMessages(refine_coordinates(
    custom_filtered = cf,
    threads = 1,
    tests = "zeros"
  ))

  out <- capture.output(print(res))
  expect_true(any(grepl("<CoordinateRefined> 2 records", out)))
  expect_true(any(grepl("CoordinateCleaned", out)))
  expect_true(any(grepl("CoordinateProblematic", out)))
  expect_true(any(grepl("runtime:", out)))

  expect_invisible(print(res))
})
