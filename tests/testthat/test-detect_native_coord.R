# ---------------------------------------------------------------------------
# Tests for detect_native_coord() and the nativeDetected print method.
#
# The function classifies against the package's bundled `Distributions` and
# `WGSRPD3` snapshots, so the fixtures below use real taxa and coordinates
# from that snapshot (e.g. "Alnus glutinosa" is native in NOR). If the
# bundled data changes, the expected values below must be revisited.
# ---------------------------------------------------------------------------

# --- Helpers ----------------------------------------------------------------

# A minimal CoordinateCleaned with the columns detect_native_coord() needs.
mk_clean <- function(gbifID, name, lon, lat) {
  data.table(
    gbifID = gbifID,
    Accepted_name = name,
    decimalLongitude = lon,
    decimalLatitude = lat
  )
}

# --- Input validation -------------------------------------------------------

test_that("default (missing) input errors with a clear message", {
  expect_error(
    detect_native_coord(),
    "must be a `CoordinateRefined` object"
  )
})

test_that("refined_coordinates must carry a CoordinateCleaned table", {
  expect_error(
    detect_native_coord(refined_coordinates = list()),
    "CoordinateCleaned"
  )
})

test_that("CoordinateCleaned must carry the required columns", {
  for (col in c("gbifID", "Accepted_name", "decimalLongitude", "decimalLatitude")) {
    clean <- mk_clean("1", "Alnus glutinosa", 10, 60)
    clean[[col]] <- NULL
    expect_error(
      detect_native_coord(refined_coordinates = list(CoordinateCleaned = clean)),
      paste0("missing required column\\(s\\): ", col),
      info = col
    )
  }
})

# --- Output contract --------------------------------------------------------

test_that("output is a nativeDetected data.table keyed by gbifID", {
  result <- suppressMessages(detect_native_coord(refined_coordinates = list(
    CoordinateCleaned = mk_clean("1", "Alnus glutinosa", 10, 60)
  )))

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
      "native_status_source",
      "buffered"
    )
  )
  expect_type(result$buffered, "logical")
  expect_false(anyNA(result$buffered))
})

test_that("record columns are returned unchanged", {
  clean <- mk_clean("1", "Alnus glutinosa", 10, 60)

  result <- suppressMessages(detect_native_coord(refined_coordinates = list(
    CoordinateCleaned = clean
  )))

  setkey(clean, gbifID)
  expect_equal(
    result[, names(clean), with = FALSE],
    clean,
    ignore_attr = "class"
  )
})

test_that("an already-classified input is rejected", {
  clean <- mk_clean("1", "Alnus glutinosa", 10, 60)
  clean[, native_status := "native"]

  expect_error(
    detect_native_coord(refined_coordinates = list(CoordinateCleaned = clean)),
    "already contains the classification column"
  )
})

test_that("one row per input record", {
  clean <- rbind(
    mk_clean("1", "Alnus glutinosa", 10, 60),
    mk_clean("2", "Alnus glutinosa", 10, 60)
  )
  result <- suppressMessages(detect_native_coord(refined_coordinates = list(
    CoordinateCleaned = clean
  )))

  expect_equal(nrow(result), 2L)
  expect_false(anyDuplicated(result$gbifID) > 0)
  # The output is keyed by gbifID, hence sorted by it.
  expect_true(!is.unsorted(result$gbifID))
})

# --- Spatial classification -------------------------------------------------

test_that("a point in a documented area resolves from its accepted name", {
  result <- suppressMessages(detect_native_coord(refined_coordinates = list(
    CoordinateCleaned = mk_clean("1", "Alnus glutinosa", 10, 60)
  )))

  expect_equal(result$LEVEL3_COD, "NOR")
  expect_equal(result$native_status, "native")
  expect_equal(result$native_status_source, "spatial")
  expect_false(result$buffered)
})

test_that("a taxon absent from Distributions is unknown and unmatched", {
  result <- suppressMessages(detect_native_coord(refined_coordinates = list(
    CoordinateCleaned = mk_clean("1", "Test absentia ficta", 10, 60)
  )))

  expect_equal(result$native_status, "unknown")
  expect_equal(result$native_status_source, "unmatched")
  expect_true(is.na(result$LEVEL3_COD))
  expect_false(result$buffered)
})

# --- Buffer pass ------------------------------------------------------------

test_that("buffer_km = 0 leaves an outside point unknown", {
  # (6.5, 58) is seaward of the NOR polygon; with no buffer the record cannot
  # be resolved at all.
  result <- suppressMessages(detect_native_coord(refined_coordinates = list(
    CoordinateCleaned = mk_clean("1", "Alnus glutinosa", 6.5, 58)
  ), buffer_km = 0))

  expect_equal(result$native_status, "unknown")
  expect_equal(result$native_status_source, "unmatched")
})

test_that("a buffer wide enough to reach the polygon resolves and is flagged", {
  result <- suppressMessages(detect_native_coord(refined_coordinates = list(
    CoordinateCleaned = mk_clean("1", "Alnus glutinosa", 6.5, 58)
  ), buffer_km = 25))

  expect_equal(result$native_status, "native")
  expect_equal(result$LEVEL3_COD, "NOR")
  expect_equal(result$native_status_source, "spatial_buffered")
  expect_true(result$buffered)
})

test_that("an exact hit is never displaced by a buffered candidate", {
  # (10, 60) is inside NOR; running a 25 km buffer must not turn the exact
  # hit into a buffered one.
  result <- suppressMessages(detect_native_coord(refined_coordinates = list(
    CoordinateCleaned = mk_clean("1", "Alnus glutinosa", 10, 60)
  ), buffer_km = 25))

  expect_equal(result$native_status_source, "spatial")
  expect_false(result$buffered)
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
  dist <- list(CoordinateCleaned = clean)

  small <- suppressMessages(detect_native_coord(dist, buffer_km = 25, buffer_chunk_size = 2))
  large <- suppressMessages(detect_native_coord(dist, buffer_km = 25, buffer_chunk_size = 1000))

  expect_equal(small, large)
  expect_true(all(small$buffered))
  expect_equal(nrow(small), 7L)
})

# --- Hybrid name normalisation ----------------------------------------------

test_that("a hybrid recorded with ASCII 'x' matches the U+00D7 name", {
  result <- suppressMessages(detect_native_coord(refined_coordinates = list(
    CoordinateCleaned = mk_clean("1", "Alnus x pubescens", 10, 60)
  )))

  expect_equal(result$native_status, "native")
  expect_equal(result$native_status_source, "spatial")
  expect_equal(result$LEVEL3_COD, "NOR")
})

# --- Empty input ------------------------------------------------------------

test_that("empty CoordinateCleaned is handled", {
  clean <- mk_clean(character(), character(), numeric(), numeric())

  result <- suppressMessages(detect_native_coord(refined_coordinates = list(
    CoordinateCleaned = clean[0]
  )))
  expect_equal(nrow(result), 0L)
  expect_s3_class(result, "nativeDetected")
})

# --- Parameter validation ---------------------------------------------------

test_that("invalid parameters are rejected", {
  dist <- list(CoordinateCleaned = mk_clean("1", "Alnus glutinosa", 10, 60))

  expect_error(detect_native_coord(dist, buffer_km = -1), "non-negative")
  expect_error(detect_native_coord(dist, buffer_km = c(1, 2)), "non-negative")
  expect_error(detect_native_coord(dist, buffer_km = NA_real_), "non-negative")
  expect_error(detect_native_coord(dist, buffer_chunk_size = 0), "positive")
  expect_error(detect_native_coord(dist, buffer_chunk_size = "big"), "positive")
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
  result <- suppressMessages(detect_native_coord(refined_coordinates = list(
    CoordinateCleaned = rbind(
      mk_clean("1", "Alnus glutinosa", 10, 60),
      mk_clean("2", "Alnus glutinosa", 6.5, 58)
    )
  ), buffer_km = 25))

  out <- capture.output(print(result))
  expect_true(any(grepl("<nativeDetected> 2 records", out)))
  expect_true(any(grepl("native_status:", out)))
  expect_true(any(grepl("native_status_source:", out)))
  expect_true(any(grepl("native", out)))
  expect_true(any(grepl("spatial", out)))
})

test_that("print handles an empty result", {
  clean <- mk_clean(character(), character(), numeric(), numeric())
  result <- suppressMessages(detect_native_coord(refined_coordinates = list(
    CoordinateCleaned = clean[0]
  )))

  expect_no_error(capture.output(print(result)))
})

test_that("print falls back to data.table for a degraded subset", {
  result <- suppressMessages(detect_native_coord(refined_coordinates = list(
    CoordinateCleaned = mk_clean("1", "Alnus glutinosa", 10, 60)
  )))

  sub <- result[, .(gbifID)]
  expect_no_error(capture.output(print(sub)))
  # The subset keeps its class but prints as a plain data.table.
  expect_s3_class(sub, "nativeDetected")
})
