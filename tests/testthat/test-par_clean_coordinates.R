# ---------------------------------------------------------------------------
# Tests for par_clean_coordinates() and the CoordinateRefined print method.
#
# The function accepts any table with a taxon column and complete coordinate
# columns, so the helpers below build plain occurrence tables rather than a
# customFiltered object. Behavioural tests use small, deterministic
# CoordinateCleaner test sets ("zeros" flags (0, 0), "equal" flags lat == lon)
# and threads = 1 to keep the cluster overhead minimal.
# ---------------------------------------------------------------------------

# --- Helpers ----------------------------------------------------------------

mk_occ <- function(gbifID, lon, lat, species = rep("id1", length(gbifID))) {
  data.table(
    gbifID = gbifID,
    decimalLongitude = lon,
    decimalLatitude = lat,
    Accepted_name_id = species
  )
}

run <- function(occ, ...) {
  suppressMessages(par_clean_coordinates(occ, ...))
}

test_columns <- c("zeros", "equal")

# --- Input validation -------------------------------------------------------

test_that("default (missing) input reports the columns it could not find", {
  expect_error(
    par_clean_coordinates(),
    "Column\\(s\\) not found in `input`"
  )
})

test_that("an object with none of the expected columns reports all of them", {
  expect_error(
    par_clean_coordinates(iris, threads = 1),
    "Column\\(s\\) not found in `input`: Accepted_name_id, decimalLongitude, decimalLatitude"
  )
})

test_that("a whole customFiltered object is rejected with a pointer to its table", {
  cf <- structure(list(occ_filtered = mk_occ("1", 10, 60)), class = "customFiltered")

  expect_error(
    par_clean_coordinates(cf, threads = 1),
    "`input` is a `customFiltered` object, not a table"
  )
  expect_error(
    par_clean_coordinates(cf, threads = 1),
    "filtered\\$occ_filtered"
  )
})

test_that("input may be any table-like object", {
  df <- as.data.frame(mk_occ(c("1", "2"), c(10, 0), c(60, 0)))
  res <- run(df, threads = 1, tests = "zeros")
  expect_s3_class(res, "CoordinateRefined")

  lst <- list(
    gbifID = c("1", "2"),
    decimalLongitude = c(10, 0),
    decimalLatitude = c(60, 0),
    Accepted_name_id = c("id1", "id1")
  )
  expect_s3_class(run(lst, threads = 1, tests = "zeros"), "CoordinateRefined")
})

test_that("required columns are checked and named in the error", {
  for (col in c("decimalLatitude", "decimalLongitude", "Accepted_name_id")) {
    occ <- mk_occ(c("1", "2"), c(10, 20), c(60, 70))
    occ[[col]] <- NULL
    expect_error(
      run(occ, threads = 1, tests = "zeros"),
      paste0("Column\\(s\\) not found in `input`: ", col),
      info = col
    )
  }
})

test_that("column-name arguments must be single non-NA strings", {
  occ <- mk_occ("1", 10, 60)
  for (bad in list(1, NA_character_, c("a", "b"))) {
    expect_error(
      run(occ, species = bad, threads = 1),
      "`species` must be a single column name",
      info = paste(deparse(bad), collapse = "")
    )
  }
})

test_that("the three column names must be distinct", {
  occ <- mk_occ("1", 10, 60)
  expect_error(
    run(occ, species = "decimalLongitude", threads = 1),
    "`species`, `longitude`, and `latitude` must name distinct columns"
  )
})

test_that("threads must be a single positive number", {
  occ <- mk_occ("1", 10, 60)
  for (bad in list(0, -1, "a")) {
    expect_error(
      run(occ, threads = bad),
      "`threads` must be a single positive number",
      info = paste(deparse(bad), collapse = "")
    )
  }
})

test_that("unknown tests error and list the valid ones", {
  expect_error(
    run(mk_occ("1", 10, 60), threads = 1, tests = c("zeros", "bogus")),
    "Unknown test\\(s\\): bogus"
  )
})

test_that("a gbifID column is created when the input has none", {
  occ <- mk_occ(c("a", "b"), c(10, 0), c(60, 0))
  occ[, gbifID := NULL]

  res <- run(occ, threads = 1, tests = "zeros")
  expect_identical(res$CoordinateCleaned$gbifID, "1")
  expect_setequal(res$CoordinateProblematic$gbifID, "2")
  expect_identical(names(res$CoordinateCleaned)[1], "gbifID")
})

# --- Output contract --------------------------------------------------------

test_that("returns a CoordinateRefined object with the expected elements", {
  res <- run(mk_occ(c("1", "2"), c(10, 0), c(60, 0)), threads = 1, tests = test_columns)

  expect_s3_class(res, "CoordinateRefined")
  expect_named(res, c("CoordinateCleaned", "CoordinateProblematic", "runtime"))
  expect_s3_class(res$CoordinateCleaned, "data.table")
  expect_s3_class(res$CoordinateProblematic, "data.table")
  expect_s3_class(res$runtime, "difftime")
})

test_that("CoordinateCleaned keeps the occurrence columns and no verdicts", {
  res <- run(mk_occ(c("1", "2"), c(10, 0), c(60, 0)), threads = 1, tests = "zeros")

  expect_true(all(
    c("gbifID", "decimalLongitude", "decimalLatitude", "Accepted_name_id") %in%
      names(res$CoordinateCleaned)
  ))
  expect_false(".summary" %in% names(res$CoordinateCleaned))
  expect_false(any(startsWith(names(res$CoordinateCleaned), ".")))
})

test_that("CoordinateProblematic carries one verdict column per applied test", {
  res <- run(mk_occ(c("1", "2"), c(10, 0), c(60, 0)), threads = 1, tests = test_columns)

  expect_true(all(c(".zer", ".equ") %in% names(res$CoordinateProblematic)))
  expect_false(any(c(".cap", ".cen", ".gbf", ".inst", ".otl", ".sea") %in%
                     names(res$CoordinateProblematic)))
})

# --- Coordinate splitting ---------------------------------------------------

test_that("passing and failing records are split by CoordinateCleaner", {
  occ <- mk_occ(
    c("1", "2", "3", "4", "5"),
    c(10, 0, 10, NA, 10),
    c(60, 0, 10, 60, NA)
  )
  res <- run(occ, threads = 1, tests = test_columns)

  expect_setequal(res$CoordinateCleaned$gbifID, "1")
  expect_setequal(res$CoordinateProblematic$gbifID, c("2", "3", "4", "5"))
})

test_that("verdict columns distinguish a failed test from a missing coordinate", {
  occ <- mk_occ(
    c("1", "2", "3", "4", "5"),
    c(10, 0, 10, NA, 10),
    c(60, 0, 10, 60, NA)
  )
  res <- run(occ, threads = 1, tests = test_columns)
  p <- res$CoordinateProblematic

  # record 2 fails both tests, record 3 fails only "equal"
  expect_false(p[gbifID == "2", .zer])
  expect_false(p[gbifID == "2", .equ])
  expect_true(p[gbifID == "3", .zer])
  expect_false(p[gbifID == "3", .equ])
  # records 4 and 5 never reached validation, so every verdict is NA
  expect_true(all(is.na(unlist(p[gbifID %in% c("4", "5"), c(".zer", ".equ")]))))
})

test_that("CoordinateProblematic includes records that failed coordinate tests", {
  res <- run(mk_occ(c("1", "2"), c(10, 0), c(60, 0)), threads = 1, tests = "zeros")

  expect_equal(nrow(res$CoordinateProblematic), 1L)
  expect_equal(res$CoordinateProblematic$gbifID, "2")
  expect_true(all(
    c("gbifID", "decimalLongitude", "decimalLatitude", "Accepted_name_id") %in%
      names(res$CoordinateProblematic)
  ))
})

test_that("CoordinateProblematic combines failed tests and missing coordinates", {
  occ <- mk_occ(
    c("1", "2", "3", "4"),
    c(10, 0, NA, 20),
    c(60, 0, 50, NA)
  )
  res <- run(occ, threads = 1, tests = "zeros")

  # 1 passes, 2 fails "zeros", 3 and 4 have missing coordinates
  expect_setequal(res$CoordinateCleaned$gbifID, "1")
  expect_setequal(res$CoordinateProblematic$gbifID, c("2", "3", "4"))
})

test_that("results do not depend on the number of threads", {
  skip_on_cran()
  skip_if(parallel::detectCores() < 2)

  set.seed(7103)
  # two species with a deliberate outlier in the second, so the "outliers" test
  # exercises the per-species distribution that chunking must not split
  occ <- mk_occ(
    gbifID = as.character(1:24),
    lon = c(stats::rnorm(12, 10, 0.5), stats::rnorm(12, 20, 0.5)),
    lat = c(stats::rnorm(12, 60, 0.5), stats::rnorm(12, 50, 0.5)),
    species = rep(c("spA", "spB"), each = 12)
  )
  occ[13, c("decimalLongitude", "decimalLatitude") := .(-40, -20)]

  r1 <- run(occ, threads = 1, tests = "outliers")
  r2 <- run(occ, threads = 2, tests = "outliers")

  expect_setequal(r1$CoordinateProblematic$gbifID, "13")
  expect_identical(r1$CoordinateProblematic, r2$CoordinateProblematic)
  expect_identical(r1$CoordinateCleaned, r2$CoordinateCleaned)
})

# --- Empty input ------------------------------------------------------------

test_that("records without complete coordinates bypass validation", {
  occ <- mk_occ(c("1", "2"), c(NA, 10), c(60, NA))
  res <- run(occ, threads = 1)

  expect_equal(nrow(res$CoordinateCleaned), 0L)
  expect_equal(nrow(res$CoordinateProblematic), 2L)
  expect_setequal(res$CoordinateProblematic$gbifID, c("1", "2"))
  expect_true(all(is.na(res$CoordinateProblematic$.zer)))
})

test_that("empty-coordinate input reports skipping validation", {
  occ <- mk_occ(c("1", "2"), c(NA, 10), c(60, NA))
  expect_message(
    par_clean_coordinates(occ, threads = 1),
    "No records with complete coordinates"
  )
})

test_that("a fully empty input returns empty tables", {
  occ <- mk_occ(character(0), numeric(0), numeric(0))
  res <- run(occ, threads = 1)

  expect_equal(nrow(res$CoordinateCleaned), 0L)
  expect_equal(nrow(res$CoordinateProblematic), 0L)
})

# --- Print method -----------------------------------------------------------

test_that("print.CoordinateRefined shows counts and runtime", {
  res <- run(mk_occ(c("1", "2"), c(10, 0), c(60, 0)), threads = 1, tests = "zeros")

  out <- capture.output(print(res))
  expect_true(any(grepl("<CoordinateRefined> 2 records", out)))
  expect_true(any(grepl("CoordinateCleaned", out)))
  expect_true(any(grepl("CoordinateProblematic", out)))
  expect_true(any(grepl("runtime:", out)))

  expect_invisible(print(res))
})
