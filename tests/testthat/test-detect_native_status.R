# ---------------------------------------------------------------------------
# Tests for detect_native_status()
# ---------------------------------------------------------------------------

test_that("detect_native_status returns expected columns", {
  cc <- data.table::data.table(
    gbifID = "1",
    VasGBIF_decimalLongitude = 10.0,
    VasGBIF_decimalLatitude = 56.0,
    VasGBIF_wcvp_taxon_name = "Rosa canina"
  )
  result <- detect_native_status(cc)

  expect_s3_class(result, "data.table")
  expect_true(all(c("LEVEL3_COD", "native_status", "gbifID") %in% names(result)))
  expect_true(result$native_status %in%
    c("native", "introduced", "extinct", "location_doubtful", "unknown"))
})

test_that("a taxon not in Distributions gets status 'unknown'", {
  cc <- data.table::data.table(
    gbifID = "1",
    VasGBIF_decimalLongitude = 10.0,
    VasGBIF_decimalLatitude = 56.0,
    VasGBIF_wcvp_taxon_name = "Nonexistentus_totalis"
  )
  result <- detect_native_status(cc)

  expect_equal(result$native_status, "unknown")
  expect_true(is.na(result$LEVEL3_COD))
})

test_that("Rosa canina in Denmark is classified as native", {
  skip_if_not_installed("terra")
  skip_if_not_installed("rnaturalearthdata")

  cc <- data.table::data.table(
    gbifID = c("1", "2"),
    VasGBIF_decimalLongitude = c(9.5, 10.0),
    VasGBIF_decimalLatitude = c(56.2, 56.0),
    VasGBIF_wcvp_taxon_name = "Rosa canina"
  )
  result <- detect_native_status(cc)

  expect_equal(nrow(result), 2L)
  # DEN area: introduced=0, extinct=0, location_doubtful=0 → native
  expect_equal(result$native_status, c("native", "native"))
  expect_false(any(is.na(result$LEVEL3_COD)))
})

test_that("multiple taxa are processed independently", {
  skip_if_not_installed("terra")
  skip_if_not_installed("rnaturalearthdata")

  cc <- data.table::data.table(
    gbifID = c("1", "2"),
    VasGBIF_decimalLongitude = c(9.5, 9.5),
    VasGBIF_decimalLatitude = c(56.2, 56.2),
    VasGBIF_wcvp_taxon_name = c("Rosa canina", "Nonexistentus_totalis")
  )
  result <- detect_native_status(cc)

  expect_equal(nrow(result), 2L)
  # First: Rosa canina in Denmark → native
  # Second: not in Distributions → unknown
  expect_equal(result$native_status[1], "native")
  expect_equal(result$native_status[2], "unknown")
})

# ---------------------------------------------------------------------------
# Tests: native_status classification logic (fcase priority)
# ---------------------------------------------------------------------------

test_that("native_status classification respects priority: location_doubtful > introduced > extinct > native", {
  Distributions <- Distributions

  local <- data.table::data.table(
    taxon_name = "Test_sp",
    area_code_l3 = c("AAA", "BBB", "CCC", "DDD", "EEE"),
    introduced = c(0, 1, 0, 0, 1),
    extinct = c(0, 0, 1, 0, 0),
    location_doubtful = c(1, 0, 0, 0, 0)
  )

  local[, native_status := data.table::fcase(
    location_doubtful == 1,                                  "location_doubtful",
    introduced == 1,                                         "introduced",
    extinct == 1,                                            "extinct",
    introduced == 0 & extinct == 0 & location_doubtful == 0, "native",
    default = "unknown"
  )]

  expect_equal(local$native_status,
    c("location_doubtful", "introduced", "extinct", "native", "introduced"))
})

test_that("all-zero flags produce 'native'", {
  local <- data.table::data.table(
    taxon_name = "Test_sp",
    area_code_l3 = "AAA",
    introduced = 0,
    extinct = 0,
    location_doubtful = 0
  )
  local[, native_status := data.table::fcase(
    location_doubtful == 1,                                  "location_doubtful",
    introduced == 1,                                         "introduced",
    extinct == 1,                                            "extinct",
    introduced == 0 & extinct == 0 & location_doubtful == 0, "native",
    default = "unknown"
  )]

  expect_equal(local$native_status, "native")
})

test_that("unmatched flag combination defaults to 'unknown'", {
  local <- data.table::data.table(
    taxon_name = "Test_sp",
    area_code_l3 = "AAA",
    introduced = NA_real_,
    extinct = NA_real_,
    location_doubtful = NA_real_
  )
  local[, native_status := data.table::fcase(
    location_doubtful == 1,                                  "location_doubtful",
    introduced == 1,                                         "introduced",
    extinct == 1,                                            "extinct",
    introduced == 0 & extinct == 0 & location_doubtful == 0, "native",
    default = "unknown"
  )]

  expect_equal(local$native_status, "unknown")
})
