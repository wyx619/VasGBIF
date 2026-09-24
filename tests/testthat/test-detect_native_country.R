# ---------------------------------------------------------------------------
# Tests for detect_native_country().
#
# The function takes any table with species and country-code columns, so the
# helpers below build plain occurrence tables rather than a CoordinateRefined
# object. It classifies against the package's bundled `Distributions` and
# `Level3maping` snapshots, so the fixtures use real taxa and country codes
# (e.g. "Alnus glutinosa" is native in NOR, which is the sole Level 3 area for
# ISO code "NO"). If the bundled data changes, the expected values below must
# be revisited.
# ---------------------------------------------------------------------------

# --- Helpers ----------------------------------------------------------------

# A minimal occurrence table with the columns detect_native_country() needs.
# Coordinates default to NA: this stage uses no geometry, so they are optional.
mk_occ <- function(gbifID, name, cc, lon = NA_real_, lat = NA_real_) {
  data.table(
    gbifID = gbifID,
    Accepted_name = name,
    countryCode = cc,
    decimalLongitude = lon,
    decimalLatitude = lat
  )
}

run <- function(input, ...) {
  suppressMessages(detect_native_country(input, ...))
}

# --- Input validation -------------------------------------------------------

test_that("default (missing) input reports the columns it could not find", {
  expect_error(
    detect_native_country(),
    "`input` is missing required column\\(s\\): Accepted_name, countryCode"
  )
})

test_that("an object with none of the expected columns reports all of them", {
  expect_error(
    detect_native_country(iris),
    "`input` is missing required column\\(s\\): Accepted_name, countryCode"
  )
})

test_that("only the species and country columns are required", {
  # No geometry is used, so the coordinate columns are optional; so is gbifID,
  # which is generated when absent.
  occ <- data.table(Accepted_name = "Alnus glutinosa", countryCode = "NO")
  expect_s3_class(run(occ), "nativeDetected")

  for (col in c("Accepted_name", "countryCode")) {
    occ <- mk_occ("1", "Alnus glutinosa", "NO")
    occ[[col]] <- NULL
    expect_error(
      detect_native_country(occ),
      paste0("`input` is missing required column\\(s\\): ", col),
      info = col
    )
  }
})

test_that("column-name arguments must be single non-NA strings", {
  occ <- mk_occ("1", "Alnus glutinosa", "NO")
  for (bad in list(1, NA_character_, c("a", "b"))) {
    expect_error(
      detect_native_country(occ, species = bad),
      "`species` must be a single column name",
      info = paste(deparse(bad), collapse = "")
    )
  }
})

test_that("the two column names must be distinct", {
  occ <- mk_occ("1", "Alnus glutinosa", "NO")
  expect_error(
    detect_native_country(occ, species = "countryCode"),
    "must name two distinct columns"
  )
})

test_that("input may be any table-like object", {
  expect_s3_class(
    run(as.data.frame(mk_occ("1", "Alnus glutinosa", "NO"))),
    "nativeDetected"
  )
  expect_s3_class(
    run(list(gbifID = "1", Accepted_name = "Alnus glutinosa", countryCode = "NO")),
    "nativeDetected"
  )
})

test_that("a gbifID column is created when the input has none", {
  occ <- mk_occ(c("x", "y"), "Alnus glutinosa", c("NO", "NO"))
  occ[, gbifID := NULL]

  result <- run(occ)
  expect_identical(result$gbifID, c("1", "2"))
  expect_identical(names(result)[1], "gbifID")
})

test_that("an already-classified input is rejected", {
  occ <- mk_occ("1", "Alnus glutinosa", "NO")
  occ[, native_status := "native"]

  expect_error(
    detect_native_country(occ),
    "already contains the classification column\\(s\\): native_status"
  )
})

test_that("a table with a column named `species` does not shadow the argument", {
  # The default `species` argument is "Accepted_name", while the table also
  # carries a column literally named `species`. Resolution must follow
  # `Accepted_name`; a lookup that followed the column would classify both rows
  # from the wrong name.
  occ <- mk_occ(
    c("1", "2"),
    c("Alnus glutinosa", "Test absentia ficta"),
    c("NO", "NO")
  )
  occ[, species := "Acorus calamus"]

  result <- run(occ)
  expect_equal(result[gbifID == "1", native_status], "native")
  expect_equal(result[gbifID == "2", native_status], "unknown")
})

# --- Output contract --------------------------------------------------------

test_that("every input record is classified, whatever its coordinates", {
  occ <- rbind(
    mk_occ("1", "Alnus glutinosa", "NO", NA_real_, NA_real_), # no coords
    mk_occ("2", "Alnus glutinosa", "NO", NA_real_, 60),       # missing lon
    mk_occ("3", "Alnus glutinosa", "NO", 10, NA_real_),       # missing lat
    mk_occ("4", "Alnus glutinosa", "NO", 10, 60)              # complete
  )
  result <- run(occ)

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
      "native_status_source"
    )
  )
  expect_false("buffered" %in% names(result))
})

test_that("record columns are returned unchanged", {
  occ <- mk_occ(c("1", "2"), "Alnus glutinosa", c("NO", "DE"))
  result <- run(occ)

  setkey(occ, gbifID)
  expect_equal(
    result[, names(occ), with = FALSE],
    occ,
    ignore_attr = "class"
  )
})

# --- Country-code classification --------------------------------------------

test_that("a record without coordinates resolves from its country code", {
  result <- run(mk_occ("1", "Alnus glutinosa", "NO"))

  expect_equal(result$native_status, "native")
  expect_equal(result$native_status_source, "country")
  expect_equal(result$LEVEL3_COD, "NOR")
})

test_that("an introduced taxon resolves as introduced from its country code", {
  # Acorus calamus is introduced in Norway (NOR, introduced = 1).
  result <- run(mk_occ("1", "Acorus calamus", "NO"))

  expect_equal(result$native_status, "introduced")
  expect_equal(result$native_status_source, "country")
  expect_equal(result$LEVEL3_COD, "NOR")
})

test_that("a multi-area country is adjudicated by status preference", {
  # ISO code "CN" maps to eight Level 3 areas; "Abutilon guineense" is native
  # in CHC (China South-Central) and introduced in CHH (Hainan). Native wins
  # and the native area is reported.
  result <- run(mk_occ("1", "Abutilon guineense", "CN"))

  expect_equal(result$native_status, "native")
  expect_equal(result$native_status_source, "country")
  expect_equal(result$LEVEL3_COD, "CHC")
})

test_that("a hybrid recorded with ASCII 'x' matches the U+00D7 name", {
  # The U+00D7 hybrid "x Bolboschoenoplectus" is native in CHN (China
  # North-Central), one of the Level 3 areas mapped from ISO code "CN".
  result <- run(mk_occ("1", "x Bolboschoenoplectus", "CN"))

  expect_equal(result$native_status, "native")
  expect_equal(result$native_status_source, "country")
  expect_equal(result$LEVEL3_COD, "CHN")
})

test_that("a mapped country with no distribution hit is no_entry", {
  result <- run(mk_occ("1", "Test absentia ficta", "NO"))

  expect_equal(result$native_status, "unknown")
  expect_equal(result$native_status_source, "no_entry")
  expect_true(is.na(result$LEVEL3_COD))
})

test_that("a code that is missing, empty, or unmapped stays unmatched", {
  # Every record is kept. A code that is `NA` or "" is not a country, and "ZZ"
  # is a country that maps to no Level 3 area; all three are "unmatched",
  # which is distinct from a mapped country with no distribution entry.
  occ <- mk_occ(
    c("1", "2", "3"),
    "Alnus glutinosa",
    c(NA_character_, "", "ZZ")
  )
  result <- run(occ)

  expect_equal(nrow(result), 3L)
  expect_true(all(result$native_status == "unknown"))
  expect_true(all(result$native_status_source == "unmatched"))
  expect_true(all(is.na(result$LEVEL3_COD)))
})

test_that("a mapped but entry-less country is distinguished from an unmatched one", {
  # The two "no hit" sources are the whole point of keeping such records.
  result <- run(mk_occ(
    c("1", "2"),
    "Test absentia ficta",
    c("NO", "ZZ")
  ))

  expect_equal(result[gbifID == "1", native_status_source], "no_entry")
  expect_equal(result[gbifID == "2", native_status_source], "unmatched")
})

# --- Empty input ------------------------------------------------------------

test_that("an empty input returns an empty nativeDetected", {
  occ <- mk_occ(character(), character(), character())
  result <- run(occ)

  expect_equal(nrow(result), 0L)
  expect_s3_class(result, "nativeDetected")
})
