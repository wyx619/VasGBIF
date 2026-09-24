# ---------------------------------------------------------------------------
# Tests for detect_native_coord() and the nativeDetected print method.
#
# The function takes any table with species and coordinate columns, so the
# helpers below build plain occurrence tables rather than a CoordinateRefined
# object. It classifies against the package's bundled `Distributions` and
# `WGSRPD3` snapshots, so the fixtures use real taxa and coordinates from that
# snapshot (e.g. "Alnus glutinosa" is native in NOR). If the bundled data
# changes, the expected values below must be revisited.
# ---------------------------------------------------------------------------

# --- Helpers ----------------------------------------------------------------

# A minimal occurrence table with the columns detect_native_coord() needs.
mk_clean <- function(gbifID, name, lon, lat) {
  data.table(
    gbifID = gbifID,
    Accepted_name = name,
    decimalLongitude = lon,
    decimalLatitude = lat
  )
}

run <- function(input, ...) {
  suppressMessages(detect_native_coord(input, ...))
}

# --- Input validation -------------------------------------------------------

test_that("default (missing) input reports the columns it could not find", {
  expect_error(
    detect_native_coord(),
    "`input` is missing required column\\(s\\): Accepted_name, decimalLongitude, decimalLatitude"
  )
})

test_that("an object with none of the expected columns reports all of them", {
  expect_error(
    detect_native_coord(iris),
    "`input` is missing required column\\(s\\): Accepted_name, decimalLongitude, decimalLatitude"
  )
})

test_that("required columns are checked and named in the error", {
  for (col in c("Accepted_name", "decimalLongitude", "decimalLatitude")) {
    clean <- mk_clean("1", "Alnus glutinosa", 10, 60)
    clean[[col]] <- NULL
    expect_error(
      detect_native_coord(clean),
      paste0("`input` is missing required column\\(s\\): ", col),
      info = col
    )
  }
})

test_that("column-name arguments must be single non-NA strings", {
  clean <- mk_clean("1", "Alnus glutinosa", 10, 60)
  for (bad in list(1, NA_character_, c("a", "b"))) {
    expect_error(
      detect_native_coord(clean, species = bad),
      "`species` must be a single column name",
      info = paste(deparse(bad), collapse = "")
    )
  }
})

test_that("the three column names must be distinct", {
  clean <- mk_clean("1", "Alnus glutinosa", 10, 60)
  expect_error(
    detect_native_coord(clean, species = "decimalLongitude"),
    "must name three distinct columns"
  )
})

test_that("input may be any table-like object", {
  expect_s3_class(
    run(as.data.frame(mk_clean("1", "Alnus glutinosa", 10, 60))),
    "nativeDetected"
  )
  expect_s3_class(
    run(list(
      gbifID = "1", Accepted_name = "Alnus glutinosa",
      decimalLongitude = 10, decimalLatitude = 60
    )),
    "nativeDetected"
  )
})

test_that("a gbifID column is created when the input has none", {
  occ <- data.table(
    Accepted_name = c("Alnus glutinosa", "Alnus glutinosa"),
    decimalLongitude = c(10, 10),
    decimalLatitude = c(60, 60)
  )
  result <- run(occ)

  expect_identical(result$gbifID, c("1", "2"))
  expect_identical(names(result)[1], "gbifID")
})

test_that("an already-classified input is rejected", {
  clean <- mk_clean("1", "Alnus glutinosa", 10, 60)
  clean[, native_status := "native"]

  expect_error(
    detect_native_coord(clean),
    "already contains the classification column\\(s\\): native_status"
  )
})

test_that("records with a missing coordinate are rejected by name of the alternative", {
  clean <- mk_clean(c("1", "2"), c("Alnus glutinosa", "Alnus glutinosa"), c(NA, 10), c(60, 60))
  expect_error(
    detect_native_coord(clean),
    "1 record\\(s\\) with a missing coordinate"
  )
  expect_error(
    detect_native_coord(clean),
    "detect_native_country\\(\\)"
  )
})

test_that("a table with a column named `species` does not shadow the argument", {
  # The default `species` argument is "Accepted_name", while the table also
  # carries a column literally named `species`. Resolution must follow
  # `Accepted_name`; when it followed the column, both rows were classified as
  # the wrong taxon.
  occ <- mk_clean(
    c("1", "2"),
    c("Alnus glutinosa", "Test absentia ficta"),
    c(10, 10),
    c(60, 60)
  )
  occ[, species := "Pinus sylvestris"]

  result <- run(occ)

  expect_equal(result[gbifID == "1", native_status], "native")
  expect_equal(result[gbifID == "2", native_status], "unknown")
})

# --- Output contract --------------------------------------------------------

test_that("output is a nativeDetected data.table keyed by gbifID", {
  result <- run(mk_clean("1", "Alnus glutinosa", 10, 60))

  expect_s3_class(result, "nativeDetected")
  expect_s3_class(result, "data.table")
  expect_identical(key(result), "gbifID")
  # The record columns are carried through, with the classification columns
  # appended; `merge()` puts the join key first.
  expect_named(
    result,
    c(
      "gbifID",
      "Accepted_name",
      "decimalLongitude",
      "decimalLatitude",
      "LEVEL3_COD",
      "native_status",
      "native_status_source"
    )
  )
  expect_false("buffered" %in% names(result))
})

test_that("record columns are returned unchanged", {
  clean <- mk_clean("1", "Alnus glutinosa", 10, 60)
  result <- run(clean)

  setkey(clean, gbifID)
  expect_equal(
    result[, names(clean), with = FALSE],
    clean,
    ignore_attr = "class"
  )
})

test_that("one row per input record", {
  clean <- rbind(
    mk_clean("1", "Alnus glutinosa", 10, 60),
    mk_clean("2", "Alnus glutinosa", 10, 60)
  )
  result <- run(clean)

  expect_equal(nrow(result), 2L)
  expect_false(anyDuplicated(result$gbifID) > 0)
  # The output is keyed by gbifID, hence sorted by it.
  expect_true(!is.unsorted(result$gbifID))
})

# --- Spatial classification -------------------------------------------------

test_that("a point in a documented area resolves from its accepted name", {
  result <- run(mk_clean("1", "Alnus glutinosa", 10, 60))

  expect_equal(result$LEVEL3_COD, "NOR")
  expect_equal(result$native_status, "native")
  expect_equal(result$native_status_source, "exact")
})

test_that("a taxon absent from Distributions is unknown and unmatched", {
  result <- run(mk_clean("1", "Test absentia ficta", 10, 60))

  expect_equal(result$native_status, "unknown")
  expect_equal(result$native_status_source, "unmatched")
  expect_true(is.na(result$LEVEL3_COD))
})

# --- Buffer pass ------------------------------------------------------------

test_that("buffer_km = 0 leaves an outside point unknown", {
  # (6.5, 58) is seaward of the NOR polygon; with no buffer the record cannot
  # be resolved at all.
  result <- run(mk_clean("1", "Alnus glutinosa", 6.5, 58), buffer_km = 0)

  expect_equal(result$native_status, "unknown")
  expect_equal(result$native_status_source, "unmatched")
})

test_that("a buffer wide enough to reach the polygon resolves and is flagged", {
  result <- run(mk_clean("1", "Alnus glutinosa", 6.5, 58), buffer_km = 25)

  expect_equal(result$native_status, "native")
  expect_equal(result$LEVEL3_COD, "NOR")
  expect_equal(result$native_status_source, "buffered")
})

test_that("an exact hit is never displaced by a buffered candidate", {
  # (10, 60) is inside NOR; running a 25 km buffer must not turn the exact
  # hit into a buffered one.
  result <- run(mk_clean("1", "Alnus glutinosa", 10, 60), buffer_km = 25)

  expect_equal(result$native_status_source, "exact")
})

test_that("buffer results do not depend on buffer_chunk_size", {
  pts <- data.frame(
    lon = c(6.5, 6.75, 7.25, 7.5, 7.75, 8.25, 8.5),
    lat = rep(58, 7)
  )
  clean <- mk_clean(
    gbifID = as.character(1:7),
    name = "Alnus glutinosa",
    lon = pts$lon,
    lat = pts$lat
  )

  small <- run(clean, buffer_km = 25, buffer_chunk_size = 2)
  large <- run(clean, buffer_km = 25, buffer_chunk_size = 1000)

  expect_equal(small, large)
  expect_true(all(small$native_status_source == "buffered"))
  expect_equal(nrow(small), 7L)
})

# --- Hybrid name normalisation ----------------------------------------------

test_that("a hybrid recorded with ASCII 'x' matches the U+00D7 name", {
  result <- run(mk_clean("1", "Alnus x pubescens", 10, 60))

  expect_equal(result$native_status, "native")
  expect_equal(result$native_status_source, "exact")
  expect_equal(result$LEVEL3_COD, "NOR")
})

# --- Empty input ------------------------------------------------------------

test_that("an empty input is handled", {
  clean <- mk_clean(character(), character(), numeric(), numeric())
  result <- run(clean)

  expect_equal(nrow(result), 0L)
  expect_s3_class(result, "nativeDetected")
})

# --- Parameter validation ---------------------------------------------------

test_that("invalid parameters are rejected", {
  clean <- mk_clean("1", "Alnus glutinosa", 10, 60)

  expect_error(detect_native_coord(clean, buffer_km = -1), "non-negative")
  expect_error(detect_native_coord(clean, buffer_km = c(1, 2)), "non-negative")
  expect_error(detect_native_coord(clean, buffer_km = NA_real_), "non-negative")
  expect_error(detect_native_coord(clean, buffer_chunk_size = 0), "positive")
  expect_error(detect_native_coord(clean, buffer_chunk_size = "big"), "positive")
})

# --- canonical_taxon_name() -------------------------------------------------

test_that("canonical_taxon_name normalises hybrid markers and whitespace", {
  expect_equal(canonical_taxon_name("Saxifraga \u00d7 urbium"), "Saxifraga x urbium")
  expect_equal(canonical_taxon_name("Saxifraga \u00d7urbium"), "Saxifraga x urbium")
  expect_equal(canonical_taxon_name("Saxifraga   urbium"), "Saxifraga urbium")
  expect_equal(canonical_taxon_name("  Saxifraga urbium  "), "Saxifraga urbium")
  # The marker is preserved, not dropped, so hybrids stay distinct.
  expect_false(
    identical(canonical_taxon_name("Saxifraga \u00d7 geum"), "Saxifraga geum")
  )
})

# --- print.nativeDetected() -------------------------------------------------

test_that("print shows a compact status summary", {
  result <- run(
    rbind(
      mk_clean("1", "Alnus glutinosa", 10, 60),
      mk_clean("2", "Alnus glutinosa", 6.5, 58)
    ),
    buffer_km = 25
  )

  out <- capture.output(print(result))
  expect_true(any(grepl("<nativeDetected> 2 records", out)))
  expect_true(any(grepl("native_status:", out)))
  expect_true(any(grepl("native_status_source:", out)))
  expect_true(any(grepl("native", out)))
  expect_true(any(grepl("exact", out)))
})

test_that("print handles an empty result", {
  clean <- mk_clean(character(), character(), numeric(), numeric())
  result <- run(clean)

  expect_no_error(capture.output(print(result)))
})

test_that("print falls back to data.table for a degraded subset", {
  result <- run(mk_clean("1", "Alnus glutinosa", 10, 60))

  sub <- result[, .(gbifID)]
  expect_no_error(capture.output(print(sub)))
  # The subset keeps its class but prints as a plain data.table.
  expect_s3_class(sub, "nativeDetected")
})
