# ---------------------------------------------------------------------------
# Helper: build a minimal mock voucher data.table
# ---------------------------------------------------------------------------
make_refine_voucher <- function(
    n = 1L,
    dataset_results = NULL,
    lats = NULL,
    lons = NULL,
    taxon_names = NULL,
    country_codes = NULL
) {
  dataset_results <- dataset_results %||% rep("usable", n)
  lats <- lats %||% rep(56.2, n)
  lons <- lons %||% rep(9.5, n)
  taxon_names <- taxon_names %||% rep("Rosa canina", n)
  country_codes <- country_codes %||% rep("DK", n)

  dt <- data.table::data.table(
    gbifID                             = as.character(seq_len(n)),
    institutionCode                    = "INST",
    collectionCode                     = "BOT",
    basisOfRecord                      = "PRESERVED_SPECIMEN",
    catalogNumber                      = sprintf("CAT%d", seq_len(n)),
    recordNumber                       = sprintf("RN%d", seq_len(n)),
    recordedBy                         = "Rec",
    occurrenceStatus                   = "PRESENT",
    eventDate                          = "2020-06-15",
    year                               = 2020L,
    month                              = 6L,
    day                                = 15L,
    identifiedBy                       = "Collector X",
    countryCode                        = country_codes,
    stateProvince                      = "",
    locality                           = "",
    dateIdentified                     = "2020-06-20",
    scientificName                     = taxon_names,
    typeStatus                         = "",
    family                             = "Rosaceae",
    decimalLatitude                    = lats,
    decimalLongitude                   = lons,
    taxonRank                          = "Species",
    issue                              = "",
    geospatial_quality                 = 0L,
    verbatim_quality                   = 9L,
    moreInformativeRecord              = 9L,
    coordinates_validated_by_gbif_issue = TRUE,
    wcvp_plant_name_id                 = "pid-1",
    wcvp_taxon_rank                    = "Species",
    wcvp_taxon_status                  = "Accepted",
    wcvp_family                        = "Rosaceae",
    wcvp_taxon_name                    = taxon_names,
    wcvp_taxon_authors                 = "L.",
    wcvp_reviewed                      = "N",
    wcvp_searchedName                  = taxon_names,
    wcvp_searchNotes                   = "Accepted",
    VasGBIF_digital_voucher            = TRUE,
    VasGBIF_duplicates                 = FALSE,
    VasGBIF_num_duplicates             = 1L,
    VasGBIF_non_groupable_duplicates   = FALSE,
    VasGBIF_duplicates_grouping_status = "groupable",
    VasGBIF_unidentified_sample        = FALSE,
    VasGBIF_sample_taxon_name          = taxon_names,
    VasGBIF_sample_taxon_name_status   = "identified",
    VasGBIF_number_taxon_names         = 1L,
    VasGBIF_useful_for_spatial_analysis = TRUE,
    VasGBIF_decimalLatitude            = lats,
    VasGBIF_decimalLongitude           = lons,
    VasGBIF_dataset_result             = dataset_results,
    VasGBIF_wcvp_plant_name_id         = "pid-1",
    VasGBIF_wcvp_taxon_rank            = "Species",
    VasGBIF_wcvp_taxon_status          = "Accepted",
    VasGBIF_wcvp_family                = "Rosaceae",
    VasGBIF_wcvp_taxon_name            = taxon_names,
    VasGBIF_wcvp_taxon_authors         = "L.",
    VasGBIF_wcvp_reviewed              = "N",
    collection_key                     = sprintf("%s|18497|%.2f|%.2f",
      taxon_names, lats, lons)
  )
  dt
}

`%||%` <- function(x, y) if (is.null(x)) y else x

# ---------------------------------------------------------------------------
# Tests: return structure
# ---------------------------------------------------------------------------

test_that("refine_records returns a 'refined' object", {
  skip_if_not_installed("CoordinateCleaner")
  skip_if_not_installed("terra")
  dt <- make_refine_voucher(n = 1)
  voucher <- list(occ_digital_voucher = dt)
  class(voucher) <- "vouchers"

  result <- refine_records(voucher = voucher, threads = 1)

  expect_s3_class(result, "refined")
  expect_named(result, c("all_records", "CoordinateProblematic", "runtime"))
  expect_s3_class(result$all_records, "data.table")
  expect_s3_class(result$CoordinateProblematic, "data.table")
  expect_s3_class(result$runtime, "difftime")
})

test_that("all_records contains native_status column", {
  skip_if_not_installed("CoordinateCleaner")
  skip_if_not_installed("terra")
  dt <- make_refine_voucher(n = 1)
  voucher <- list(occ_digital_voucher = dt)
  class(voucher) <- "vouchers"

  result <- refine_records(voucher = voucher, threads = 1)

  expect_true("native_status" %in% names(result$all_records))
  expect_true(
    result$all_records$native_status %in%
      c("native", "introduced", "extinct", "location_doubtful", "unknown")
  )
})

# ---------------------------------------------------------------------------
# Tests: coordinate validation
# ---------------------------------------------------------------------------

test_that("valid coordinates produce empty CoordinateProblematic", {
  skip_if_not_installed("CoordinateCleaner")
  skip_if_not_installed("terra")
  dt <- make_refine_voucher(n = 1, lats = 56.2, lons = 9.5)
  voucher <- list(occ_digital_voucher = dt)
  class(voucher) <- "vouchers"

  result <- refine_records(
    voucher = voucher,
    threads = 1,
    tests = c("capitals", "centroids", "equal", "gbif", "institutions", "zeros")
  )

  # Denmark (56.2, 9.5) is a valid natural location
  expect_equal(nrow(result$CoordinateProblematic), 0L)
})

test_that("zero coordinates are flagged by the 'zeros' test", {
  skip_if_not_installed("CoordinateCleaner")
  skip_if_not_installed("terra")
  dt <- make_refine_voucher(
    n = 2,
    lats = c(0, 56.2),
    lons = c(0, 9.5)
  )
  voucher <- list(occ_digital_voucher = dt)
  class(voucher) <- "vouchers"

  result <- refine_records(
    voucher = voucher,
    threads = 1,
    tests = c("zeros")
  )

  # One zero-coord record flagged, one valid passes
  expect_equal(nrow(result$CoordinateProblematic), 1L)
  expect_equal(nrow(result$all_records), 1L)
})

test_that("equal lat/lon coordinates are flagged by the 'equal' test", {
  skip_if_not_installed("CoordinateCleaner")
  skip_if_not_installed("terra")
  dt <- make_refine_voucher(
    n = 2,
    lats = c(45, 56.2),
    lons = c(45, 9.5)
  )
  voucher <- list(occ_digital_voucher = dt)
  class(voucher) <- "vouchers"

  result <- refine_records(
    voucher = voucher,
    threads = 1,
    tests = c("equal")
  )

  expect_equal(nrow(result$CoordinateProblematic), 1L)
  expect_equal(nrow(result$all_records), 1L)
})

# ---------------------------------------------------------------------------
# Tests: tests parameter
# ---------------------------------------------------------------------------

test_that("empty tests vector runs no coordinate checks", {
  skip_if_not_installed("CoordinateCleaner")
  skip_if_not_installed("terra")
  dt <- make_refine_voucher(n = 1, lats = 0, lons = 0)
  voucher <- list(occ_digital_voucher = dt)
  class(voucher) <- "vouchers"

  result <- refine_records(
    voucher = voucher,
    threads = 1,
    tests = character()
  )

  # With no tests, even (0,0) should not be flagged
  expect_equal(nrow(result$CoordinateProblematic), 0L)
})

# ---------------------------------------------------------------------------
# Tests: excludes 'unusable' records
# ---------------------------------------------------------------------------

test_that("records with VasGBIF_dataset_result = 'unusable' are dropped by restore_duplicates", {
  skip_if_not_installed("CoordinateCleaner")
  skip_if_not_installed("terra")
  # restore_duplicates() filters to VasGBIF_dataset_result == "usable" only
  dt <- make_refine_voucher(n = 2, dataset_results = c("usable", "unusable"))
  voucher <- list(occ_digital_voucher = dt)
  class(voucher) <- "vouchers"

  result <- refine_records(voucher = voucher, threads = 1)

  # Only the "usable" record survives restore_duplicates
  expect_equal(nrow(result$all_records), 1L)
  expect_equal(result$all_records$VasGBIF_dataset_result, "usable")
})
