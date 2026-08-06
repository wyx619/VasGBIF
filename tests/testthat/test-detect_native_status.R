# ---------------------------------------------------------------------------
# Tests for detect_native_status() and the nativeDetected print method.
#
# The function no longer accepts injectable `distributions`/`wgsrpd3` tables:
# it classifies against the package's bundled `Distributions`, `WGSRPD3` and
# `Level3maping` snapshots. The fixtures below therefore use real taxa and
# coordinates from that snapshot (e.g. "Alnus glutinosa" is native in NOR).
# If the bundled data changes, the expected values below must be revisited.
# ---------------------------------------------------------------------------

# --- Helpers ----------------------------------------------------------------

# A minimal CoordinateCleaned with the columns detect_native_status() needs.
mk_clean <- function(gbifID, name, species = name, lon, lat, cc = NA_character_) {
  data.table(
    gbifID = gbifID,
    Accepted_name = name,
    Accepted_species = species,
    countryCode = cc,
    decimalLongitude = lon,
    decimalLatitude = lat
  )
}

# A minimal Coordinateless row.
mk_without <- function(gbifID, name, species = name, cc = NA_character_) {
  data.table(
    gbifID = gbifID,
    countryCode = cc,
    Accepted_name = name,
    Accepted_species = species
  )
}

# --- Output contract --------------------------------------------------------

test_that("output is a nativeDetected data.table keyed by gbifID", {
  result <- suppressMessages(detect_native_status(list(
    CoordinateCleaned = mk_clean("1", "Alnus glutinosa", lon = 10, lat = 60),
    Coordinateless = NULL
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
      "Accepted_species",
      "countryCode",
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
  clean <- mk_clean("1", "Alnus glutinosa", lon = 10, lat = 60, cc = "NO")
  without <- mk_without("2", "Alnus glutinosa", cc = "NO")

  result <- suppressMessages(detect_native_status(list(
    CoordinateCleaned = clean,
    Coordinateless = without
  )))

  input <- rbindlist(list(clean, without), use.names = TRUE, fill = TRUE)
  setkey(input, gbifID)
  expect_equal(
    result[, names(input), with = FALSE],
    input,
    ignore_attr = "class"
  )
})

test_that("an already-classified input is rejected", {
  clean <- mk_clean("1", "Alnus glutinosa", lon = 10, lat = 60)
  clean[, native_status := "native"]

  expect_error(
    detect_native_status(list(
      CoordinateCleaned = clean,
      Coordinateless = NULL
    )),
    "already contains the classification column"
  )
})

test_that("one row per input record across both tables", {
  clean <- rbind(
    mk_clean("1", "Alnus glutinosa", lon = 10, lat = 60),
    mk_clean("2", "Alnus glutinosa", lon = 10, lat = 60)
  )
  without <- rbind(
    mk_without("3", "Alnus glutinosa", cc = "NO"),
    mk_without("4", "Alnus glutinosa", cc = "NO")
  )
  result <- suppressMessages(detect_native_status(list(
    CoordinateCleaned = clean,
    Coordinateless = without
  )))

  expect_equal(nrow(result), 4L)
  expect_false(anyDuplicated(result$gbifID) > 0)
  # The output is keyed by gbifID, hence sorted by it.
  expect_true(!is.unsorted(result$gbifID))
})

# --- Spatial stage ----------------------------------------------------------

test_that("a point in a documented area resolves from its accepted name", {
  result <- suppressMessages(detect_native_status(list(
    CoordinateCleaned = mk_clean("1", "Alnus glutinosa", lon = 10, lat = 60),
    Coordinateless = NULL
  )))

  expect_equal(result$LEVEL3_COD, "NOR")
  expect_equal(result$native_status, "native")
  expect_equal(result$native_status_source, "accepted_name")
  expect_false(result$buffered)
})

test_that("a taxon absent from Distributions is unknown and unmatched", {
  result <- suppressMessages(detect_native_status(list(
    CoordinateCleaned = mk_clean("1", "Test absentia ficta", lon = 10, lat = 60),
    Coordinateless = NULL
  )))

  expect_equal(result$native_status, "unknown")
  expect_equal(result$native_status_source, "unmatched")
  expect_true(is.na(result$LEVEL3_COD))
  expect_false(result$buffered)
})

# --- Buffer pass ------------------------------------------------------------

test_that("buffer_km = 0 leaves an outside point unknown", {
  # (6.5, 58) is seaward of the NOR polygon; with no buffer and no country
  # code the record cannot be resolved at all.
  result <- suppressMessages(detect_native_status(list(
    CoordinateCleaned = mk_clean("1", "Alnus glutinosa", lon = 6.5, lat = 58),
    Coordinateless = NULL
  ), buffer_km = 0))

  expect_equal(result$native_status, "unknown")
  expect_equal(result$native_status_source, "unmatched")
})

test_that("a buffer wide enough to reach the polygon resolves and is flagged", {
  result <- suppressMessages(detect_native_status(list(
    CoordinateCleaned = mk_clean("1", "Alnus glutinosa", lon = 6.5, lat = 58),
    Coordinateless = NULL
  ), buffer_km = 25))

  expect_equal(result$native_status, "native")
  expect_equal(result$LEVEL3_COD, "NOR")
  expect_equal(result$native_status_source, "accepted_name")
  expect_true(result$buffered)
})

test_that("an exact hit is never displaced by a buffered candidate", {
  # (10, 60) is inside NOR; running a 25 km buffer must not turn the exact
  # hit into a buffered one.
  result <- suppressMessages(detect_native_status(list(
    CoordinateCleaned = mk_clean("1", "Alnus glutinosa", lon = 10, lat = 60),
    Coordinateless = NULL
  ), buffer_km = 25))

  expect_equal(result$native_status_source, "accepted_name")
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
  dist <- list(CoordinateCleaned = clean, Coordinateless = NULL)

  small <- suppressMessages(detect_native_status(dist, buffer_km = 25, buffer_chunk_size = 2))
  large <- suppressMessages(detect_native_status(dist, buffer_km = 25, buffer_chunk_size = 1000))

  expect_equal(small, large)
  expect_true(all(small$buffered))
  expect_equal(nrow(small), 7L)
})

# --- species_fallback -------------------------------------------------------

test_that("species_fallback = FALSE leaves an infraspecific taxon unmatched", {
  result <- suppressMessages(detect_native_status(list(
    CoordinateCleaned = mk_clean(
      "1", "Alnus glutinosa subsp. ficticia",
      species = "Alnus glutinosa", lon = 10, lat = 60
    ),
    Coordinateless = NULL
  ), species_fallback = FALSE))

  expect_equal(result$native_status, "unknown")
  expect_equal(result$native_status_source, "unmatched")
})

test_that("species_fallback = TRUE inherits the parent species status", {
  result <- suppressMessages(detect_native_status(list(
    CoordinateCleaned = mk_clean(
      "1", "Alnus glutinosa subsp. ficticia",
      species = "Alnus glutinosa", lon = 10, lat = 60
    ),
    Coordinateless = NULL
  ), species_fallback = TRUE))

  expect_equal(result$native_status, "native")
  expect_equal(result$native_status_source, "accepted_species")
})

test_that("an accepted-name match outranks a parent species match", {
  # Ajuga chamaepitys subsp. chamaepitys is introduced in POL while the
  # species is native there; the more precise name must win even though
  # native is the preferred status.
  result <- suppressMessages(detect_native_status(list(
    CoordinateCleaned = mk_clean(
      "1", "Ajuga chamaepitys subsp. chamaepitys",
      species = "Ajuga chamaepitys", lon = 19.4, lat = 52.1, cc = "PL"
    ),
    Coordinateless = NULL
  ), species_fallback = TRUE))

  expect_equal(result$native_status, "introduced")
  expect_equal(result$native_status_source, "accepted_name")
  expect_equal(result$LEVEL3_COD, "POL")
})

test_that("species_fallback = TRUE requires an Accepted_species column", {
  clean <- mk_clean("1", "Alnus glutinosa", lon = 10, lat = 60)
  clean[, Accepted_species := NULL]
  expect_error(
    suppressMessages(detect_native_status(list(
      CoordinateCleaned = clean,
      Coordinateless = NULL
    ), species_fallback = TRUE)),
    "Accepted_species"
  )
})

# --- Hybrid name normalisation ----------------------------------------------

test_that("a hybrid recorded with ASCII 'x' matches the U+00D7 name", {
  result <- suppressMessages(detect_native_status(list(
    CoordinateCleaned = mk_clean("1", "Alnus x pubescens", lon = 10, lat = 60),
    Coordinateless = NULL
  )))

  expect_equal(result$native_status, "native")
  expect_equal(result$native_status_source, "accepted_name")
  expect_equal(result$LEVEL3_COD, "NOR")
})

# --- Country-code stage -----------------------------------------------------

test_that("a record without coordinates resolves from its country code", {
  result <- suppressMessages(detect_native_status(list(
    CoordinateCleaned = mk_clean("x", "Alnus glutinosa", lon = 10, lat = 60),
    Coordinateless = mk_without("1", "Alnus glutinosa", cc = "NO")
  )))

  row <- result[gbifID == "1"]
  expect_equal(row$native_status, "native")
  expect_equal(row$native_status_source, "country_code")
  expect_equal(row$LEVEL3_COD, "NOR")
})

test_that("a spatial miss is retried by country code", {
  # (6.5, 58) misses every polygon, but the country code NO maps to NOR
  # where the taxon is native.
  result <- suppressMessages(detect_native_status(list(
    CoordinateCleaned = mk_clean("1", "Alnus glutinosa", lon = 6.5, lat = 58, cc = "NO"),
    Coordinateless = NULL
  ), buffer_km = 0))

  expect_equal(result$native_status, "native")
  expect_equal(result$native_status_source, "country_code_after_spatial_miss")
  expect_equal(result$LEVEL3_COD, "NOR")
})

test_that("a mapped country with no distribution hit is country_code_miss", {
  result <- suppressMessages(detect_native_status(list(
    CoordinateCleaned = mk_clean("x", "Alnus glutinosa", lon = 10, lat = 60),
    Coordinateless = mk_without("1", "Test absentia ficta", cc = "NO")
  )))

  row <- result[gbifID == "1"]
  expect_equal(row$native_status, "unknown")
  expect_equal(row$native_status_source, "country_code_miss")
})

test_that("no usable country code leaves a record unmatched", {
  result <- suppressMessages(detect_native_status(list(
    CoordinateCleaned = mk_clean("x", "Alnus glutinosa", lon = 10, lat = 60),
    Coordinateless = mk_without("1", "Alnus glutinosa", cc = NA_character_)
  )))

  row <- result[gbifID == "1"]
  expect_equal(row$native_status, "unknown")
  expect_equal(row$native_status_source, "unmatched")
})

test_that("a missing countryCode column is treated as no country code", {
  clean <- mk_clean("1", "Alnus glutinosa", lon = 10, lat = 60)
  clean[, countryCode := NULL]
  without <- mk_without("2", "Alnus glutinosa", cc = "NO")
  without[, countryCode := NULL]

  result <- suppressMessages(detect_native_status(list(
    CoordinateCleaned = clean,
    Coordinateless = without
  )))

  # The spatial hit still resolves; the coordinateless row has no code.
  expect_equal(result[gbifID == "1"]$native_status_source, "accepted_name")
  expect_equal(result[gbifID == "2"]$native_status, "unknown")
  expect_equal(result[gbifID == "2"]$native_status_source, "unmatched")
})

# --- Empty inputs -----------------------------------------------------------

test_that("empty CoordinateCleaned and Coordinateless are handled", {
  clean <- mk_clean(character(), character(), lon = numeric(), lat = numeric())
  without <- mk_without(character(), character())

  result <- suppressMessages(detect_native_status(list(
    CoordinateCleaned = clean[0],
    Coordinateless = NULL
  )))
  expect_equal(nrow(result), 0L)

  result2 <- suppressMessages(detect_native_status(list(
    CoordinateCleaned = clean[0],
    Coordinateless = without[0]
  )))
  expect_equal(nrow(result2), 0L)
})

# --- Parameter validation ---------------------------------------------------

test_that("invalid parameters are rejected", {
  clean <- mk_clean("1", "Alnus glutinosa", lon = 10, lat = 60)
  dist <- list(CoordinateCleaned = clean, Coordinateless = NULL)

  expect_error(detect_native_status(dist, species_fallback = NA), "TRUE or FALSE")
  expect_error(detect_native_status(dist, species_fallback = "yes"), "TRUE or FALSE")
  expect_error(detect_native_status(dist, buffer_km = -1), "non-negative")
  expect_error(detect_native_status(dist, buffer_km = c(1, 2)), "non-negative")
  expect_error(detect_native_status(dist, buffer_km = NA_real_), "non-negative")
  expect_error(detect_native_status(dist, buffer_chunk_size = 0), "positive")
  expect_error(detect_native_status(dist, buffer_chunk_size = "big"), "positive")
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
  result <- suppressMessages(detect_native_status(list(
    CoordinateCleaned = rbind(
      mk_clean("1", "Alnus glutinosa", lon = 10, lat = 60),
      mk_clean("2", "Alnus glutinosa", lon = 6.5, lat = 58)
    ),
    Coordinateless = NULL
  ), buffer_km = 25))

  out <- capture.output(print(result))
  expect_true(any(grepl("<nativeDetected> 2 records", out)))
  expect_true(any(grepl("native_status:", out)))
  expect_true(any(grepl("native_status_source:", out)))
  expect_true(any(grepl("native", out)))
  expect_true(any(grepl("accepted_name", out)))
})

test_that("print handles an empty result", {
  clean <- mk_clean(character(), character(), lon = numeric(), lat = numeric())
  result <- suppressMessages(detect_native_status(list(
    CoordinateCleaned = clean[0],
    Coordinateless = NULL
  )))

  expect_no_error(capture.output(print(result)))
})

test_that("print falls back to data.table for a degraded subset", {
  result <- suppressMessages(detect_native_status(list(
    CoordinateCleaned = mk_clean("1", "Alnus glutinosa", lon = 10, lat = 60),
    Coordinateless = NULL
  )))

  sub <- result[, .(gbifID)]
  expect_no_error(capture.output(print(sub)))
  # The subset keeps its class but prints as a plain data.table.
  expect_s3_class(sub, "nativeDetected")
})
