# ---------------------------------------------------------------------------
# Tests for detect_native_country().
#
# The function classifies coordinateless records against the package's
# bundled `Distributions` and `Level3maping` snapshots, so the fixtures use
# real taxa and country codes (e.g. "Alnus glutinosa" is native in NOR, which
# is the sole Level 3 area for ISO code "NO"). If the bundled data changes,
# the expected values below must be revisited.
# ---------------------------------------------------------------------------

# --- Helpers ----------------------------------------------------------------

mk_cleaned_coordinates <- function(CoordinateProblematic) {
  out <- list(
    CoordinateCleaned = data.table(),
    CoordinateProblematic = CoordinateProblematic,
    runtime = as.difftime(0, units = "secs")
  )
  class(out) <- "CoordinateRefined"
  out
}

# A minimal occ_filtered carrying the columns detect_native_country() needs.
# Coordinates default to NA so rows are treated as coordinateless.
mk_occ <- function(gbifID, name, cc, lon = NA_real_, lat = NA_real_) {
  data.table(
    gbifID = gbifID,
    Accepted_name = name,
    countryCode = cc,
    decimalLongitude = lon,
    decimalLatitude = lat
  )
}

# --- Input validation -------------------------------------------------------

test_that("default (missing) input errors with a clear message", {
  expect_error(
    detect_native_country(),
    '`cleaned_coordinates` must be a "CoordinateRefined" object'
  )
})

test_that("cleaned_coordinates must be a CoordinateRefined object", {
  expect_error(
    detect_native_country(cleaned_coordinates = iris),
    '`cleaned_coordinates` must be a "CoordinateRefined" object'
  )
})

test_that("CoordinateProblematic must carry the required columns", {
  for (col in c("gbifID", "Accepted_name", "countryCode", "decimalLongitude", "decimalLatitude")) {
    occ <- mk_occ("1", "Alnus glutinosa", "NO")
    occ[[col]] <- NULL
    expect_error(
      detect_native_country(cleaned_coordinates = mk_cleaned_coordinates(occ)),
      paste0("missing required column\\(s\\): ", col),
      info = col
    )
  }
})

test_that("an already-classified input is rejected", {
  occ <- mk_occ("1", "Alnus glutinosa", "NO")
  occ[, native_status := "native"]

  expect_error(
    detect_native_country(cleaned_coordinates = mk_cleaned_coordinates(occ)),
    "already contains the classification column"
  )
})

# --- Output contract --------------------------------------------------------

test_that("all records from CoordinateProblematic are classified", {
  occ <- rbind(
    mk_occ("1", "Alnus glutinosa", "NO", NA_real_, NA_real_), # no coords
    mk_occ("2", "Alnus glutinosa", "NO", NA_real_, 60),       # missing lon
    mk_occ("3", "Alnus glutinosa", "NO", 10, NA_real_),       # missing lat
    mk_occ("4", "Alnus glutinosa", "NO", 10, 60)              # complete (failed validation)
  )
  result <- suppressMessages(detect_native_country(
    cleaned_coordinates = mk_cleaned_coordinates(occ)
  ))

  expect_setequal(result$gbifID, c("1", "2", "3", "4"))
  expect_s3_class(result, "nativeDetected")
  expect_identical(key(result), "gbifID")
  expect_named(
    result,
    c(
      "gbifID",
      "Accepted_name",
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
  expect_false(any(result$buffered))
})

test_that("record columns are returned unchanged", {
  occ <- mk_occ(c("1", "2"), "Alnus glutinosa", c("NO", "DE"))
  result <- suppressMessages(detect_native_country(
    cleaned_coordinates = mk_cleaned_coordinates(occ)
  ))

  setkey(occ, gbifID)
  expect_equal(
    result[, names(occ), with = FALSE],
    occ,
    ignore_attr = "class"
  )
})

# --- Country-code classification --------------------------------------------

test_that("a record without coordinates resolves from its country code", {
  result <- suppressMessages(detect_native_country(cleaned_coordinates = mk_cleaned_coordinates(
    mk_occ("1", "Alnus glutinosa", "NO")
  )))

  expect_equal(result$native_status, "native")
  expect_equal(result$native_status_source, "country_code")
  expect_equal(result$LEVEL3_COD, "NOR")
})

test_that("an introduced taxon resolves as introduced from its country code", {
  # Acorus calamus is introduced in Norway (NOR, introduced = 1).
  result <- suppressMessages(detect_native_country(cleaned_coordinates = mk_cleaned_coordinates(
    mk_occ("1", "Acorus calamus", "NO")
  )))

  expect_equal(result$native_status, "introduced")
  expect_equal(result$native_status_source, "country_code")
  expect_equal(result$LEVEL3_COD, "NOR")
})

test_that("a multi-area country is adjudicated by status preference", {
  # ISO code "CN" maps to eight Level 3 areas; "Abutilon guineense" is native
  # in CHC (China South-Central) and introduced in CHH (Hainan). Native wins
  # and the native area is reported.
  result <- suppressMessages(detect_native_country(cleaned_coordinates = mk_cleaned_coordinates(
    mk_occ("1", "Abutilon guineense", "CN")
  )))

  expect_equal(result$native_status, "native")
  expect_equal(result$native_status_source, "country_code")
  expect_equal(result$LEVEL3_COD, "CHC")
})

test_that("a hybrid recorded with ASCII 'x' matches the U+00D7 name", {
  # "× Bolboschoenoplectus" is native in CHN (China North-Central), one of the
  # Level 3 areas mapped from ISO code "CN".
  result <- suppressMessages(detect_native_country(cleaned_coordinates = mk_cleaned_coordinates(
    mk_occ("1", "x Bolboschoenoplectus", "CN")
  )))

  expect_equal(result$native_status, "native")
  expect_equal(result$native_status_source, "country_code")
  expect_equal(result$LEVEL3_COD, "CHN")
})

test_that("a mapped country with no distribution hit is country_code_no_entry", {
  result <- suppressMessages(detect_native_country(cleaned_coordinates = mk_cleaned_coordinates(
    mk_occ("1", "Test absentia ficta", "NO")
  )))

  expect_equal(result$native_status, "unknown")
  expect_equal(result$native_status_source, "country_code_no_entry")
  expect_true(is.na(result$LEVEL3_COD))
})

test_that("no usable country code leaves a record unmatched", {
  occ <- mk_occ(c("1", "2"), "Alnus glutinosa", c(NA_character_, ""))
  result <- suppressMessages(detect_native_country(
    cleaned_coordinates = mk_cleaned_coordinates(occ)
  ))

  expect_true(all(result$native_status == "unknown"))
  expect_true(all(result$native_status_source == "unmatched"))
  expect_true(all(is.na(result$LEVEL3_COD)))
})

test_that("a country code unknown to Level3maping leaves a record unmatched", {
  # "ZZ" appears in no Level 3 area; the code is non-missing but unmapped.
  result <- suppressMessages(detect_native_country(cleaned_coordinates = mk_cleaned_coordinates(
    mk_occ("1", "Alnus glutinosa", "ZZ")
  )))

  expect_equal(result$native_status, "unknown")
  expect_equal(result$native_status_source, "unmatched")
  expect_true(is.na(result$LEVEL3_COD))
})

# --- Empty input ------------------------------------------------------------

test_that("empty countryCode records are excluded from classification", {
  occ <- rbind(
    mk_occ("1", "Alnus glutinosa", "", 10, 60),        # empty countryCode
    mk_occ("2", "Alnus glutinosa", NA_character_, 10, 60) # NA countryCode
  )
  result <- suppressMessages(detect_native_country(
    cleaned_coordinates = mk_cleaned_coordinates(occ)
  ))

  expect_equal(nrow(result), 0L)
  expect_s3_class(result, "nativeDetected")
})

test_that("an empty occ_filtered returns an empty nativeDetected", {
  occ <- mk_occ(character(), character(), character())
  result <- suppressMessages(detect_native_country(
    cleaned_coordinates = mk_cleaned_coordinates(occ[0])
  ))

  expect_equal(nrow(result), 0L)
  expect_s3_class(result, "nativeDetected")
})
