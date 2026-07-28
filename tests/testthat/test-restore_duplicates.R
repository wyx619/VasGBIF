# ---------------------------------------------------------------------------
# Helper: build a minimal occ_digital_voucher data.table
# ---------------------------------------------------------------------------
make_restore_input <- function(
    n_usable = 2L,
    n_dup = 2L,
    group_size = NULL
) {
  n_total <- n_usable + n_dup
  if (is.null(group_size)) group_size <- n_total

  # Build records sharing the same collection_key (a single group)
  dt <- data.table::data.table(
    gbifID                             = as.character(seq_len(n_total)),
    institutionCode                    = "INST",
    collectionCode                     = "BOT",
    basisOfRecord                      = "PRESERVED_SPECIMEN",
    catalogNumber                      = sprintf("CAT%d", seq_len(n_total)),
    recordNumber                       = sprintf("RN%d", seq_len(n_total)),
    recordedBy                         = "Rec",
    occurrenceStatus                   = "PRESENT",
    eventDate                          = c(rep("", n_usable), rep("2020-06-15", n_dup)),
    year                               = c(rep(NA_integer_, n_usable), rep(2020L, n_dup)),
    month                              = c(rep(NA_integer_, n_usable), rep(6L, n_dup)),
    day                                = c(rep(NA_integer_, n_usable), rep(15L, n_dup)),
    identifiedBy                       = c(rep("", n_usable), rep("Collector X", n_dup)),
    countryCode                        = c(rep("", n_usable), rep("CN", n_dup)),
    stateProvince                      = c(rep("", n_usable), rep("Yunnan", n_dup)),
    locality                           = c(rep("", n_usable), rep("Kunming", n_dup)),
    dateIdentified                     = "",
    scientificName                     = "Species_A",
    typeStatus                         = "",
    family                             = "Testaceae",
    decimalLatitude                    = 25.0,
    decimalLongitude                   = 102.0,
    taxonRank                          = "Species",
    issue                              = "",
    geospatial_quality                 = 0L,
    verbatim_quality                   = 5L,
    moreInformativeRecord              = 5L,
    coordinates_validated_by_gbif_issue = TRUE,
    wcvp_plant_name_id                 = "pid-1",
    wcvp_taxon_rank                    = "Species",
    wcvp_taxon_status                  = "Accepted",
    wcvp_family                        = "Testaceae",
    wcvp_taxon_name                    = "Species_A",
    wcvp_taxon_authors                 = "L.",
    wcvp_reviewed                      = "N",
    wcvp_searchedName                  = "Species_A",
    wcvp_searchNotes                   = "Accepted",
    VasGBIF_digital_voucher            = c(rep(TRUE, n_usable), rep(FALSE, n_dup)),
    VasGBIF_duplicates                 = n_total > 1L,
    VasGBIF_num_duplicates             = n_total,
    VasGBIF_non_groupable_duplicates   = FALSE,
    VasGBIF_duplicates_grouping_status = "groupable",
    VasGBIF_unidentified_sample        = FALSE,
    VasGBIF_sample_taxon_name          = "Species_A",
    VasGBIF_sample_taxon_name_status   = "identified",
    VasGBIF_number_taxon_names         = 1L,
    VasGBIF_useful_for_spatial_analysis = TRUE,
    VasGBIF_decimalLatitude            = 25.0,
    VasGBIF_decimalLongitude           = 102.0,
    VasGBIF_dataset_result             = c(rep("usable", n_usable), rep("duplicate", n_dup)),
    VasGBIF_wcvp_plant_name_id         = "pid-1",
    VasGBIF_wcvp_taxon_rank            = "Species",
    VasGBIF_wcvp_taxon_status          = "Accepted",
    VasGBIF_wcvp_family                = "Testaceae",
    VasGBIF_wcvp_taxon_name            = "Species_A",
    VasGBIF_wcvp_taxon_authors         = "L.",
    VasGBIF_wcvp_reviewed              = "N",
    collection_key                     = "Species_A|18497|25.00|102.00"
  )
  dt
}

# ---------------------------------------------------------------------------
# Tests: basic behaviour
# ---------------------------------------------------------------------------

test_that("restore_duplicates returns only usable records", {
  dt <- make_restore_input(n_usable = 1, n_dup = 2)
  result <- restore_duplicates(dt)

  expect_equal(nrow(result), 1L)
  expect_true(all(result$VasGBIF_dataset_result == "usable"))
})

test_that("restore_duplicates adds VasGBIF_restored_from_duplicate column", {
  dt <- make_restore_input(n_usable = 1, n_dup = 1)
  result <- restore_duplicates(dt)

  expect_true("VasGBIF_restored_from_duplicate" %in% names(result))
  expect_type(result$VasGBIF_restored_from_duplicate, "logical")
})

# ---------------------------------------------------------------------------
# Tests: field restoration
# ---------------------------------------------------------------------------

test_that("eventDate is restored from duplicate", {
  dt <- make_restore_input(n_usable = 1, n_dup = 1)
  result <- restore_duplicates(dt)

  expect_equal(result$eventDate, "2020-06-15")
  expect_true(result$VasGBIF_restored_from_duplicate)
})

test_that("year is restored and coerced to integer", {
  dt <- make_restore_input(n_usable = 1, n_dup = 1)
  result <- restore_duplicates(dt)

  expect_equal(result$year, 2020L)
  expect_type(result$year, "integer")
})

test_that("locality is restored from duplicate", {
  dt <- make_restore_input(n_usable = 1, n_dup = 1)
  result <- restore_duplicates(dt)

  expect_equal(result$locality, "KUNMING")
})

test_that("all mergeable fields are restored", {
  dt <- make_restore_input(n_usable = 1, n_dup = 1)
  result <- restore_duplicates(dt)

  fields <- c("eventDate", "year", "month", "day",
              "identifiedBy", "countryCode", "stateProvince", "locality")
  for (f in fields) {
    expect_false(
      is.na(result[[f]]) || result[[f]] == "",
      info = paste("Field", f, "was not restored")
    )
  }
})

# ---------------------------------------------------------------------------
# Tests: only usable records with duplicates get restoration
# ---------------------------------------------------------------------------

test_that("usable record without duplicates is not modified", {
  dt <- make_restore_input(n_usable = 1, n_dup = 0)
  result <- restore_duplicates(dt)

  # eventDate should still be empty (no duplicate to restore from)
  expect_equal(result$eventDate, "")
  expect_false(result$VasGBIF_restored_from_duplicate)
})

test_that("already populated fields are not overwritten", {
  dt <- make_restore_input(n_usable = 1, n_dup = 1)
  dt[VasGBIF_dataset_result == "usable", eventDate := "2021-01-01"]

  result <- restore_duplicates(dt)

  # Only eventDate was already filled, but other fields should still restore
  expect_equal(result$eventDate, "2021-01-01")
  expect_equal(result$locality, "KUNMING")
})

# ---------------------------------------------------------------------------
# Tests: "NA" string handling
# ---------------------------------------------------------------------------

test_that('"NA" string is treated as missing', {
  dt <- make_restore_input(n_usable = 1, n_dup = 1)
  dt[VasGBIF_dataset_result == "usable", eventDate := "NA"]
  dt[VasGBIF_dataset_result == "usable", VasGBIF_restored_from_duplicate := FALSE]

  result <- restore_duplicates(dt)

  expect_equal(result$eventDate, "2020-06-15")
})

# ---------------------------------------------------------------------------
# Tests: multiple duplicates, first valid candidate used
# ---------------------------------------------------------------------------

test_that("first valid duplicate value is used when multiple duplicates exist", {
  dt <- make_restore_input(n_usable = 1, n_dup = 2)
  # Give duplicates different locality values
  dt[VasGBIF_dataset_result == "duplicate" & gbifID == "2", locality := "Kunming_A"]
  dt[VasGBIF_dataset_result == "duplicate" & gbifID == "3", locality := "Kunming_B"]

  result <- restore_duplicates(dt)

  # First duplicate (gbifID=2) value should be used
  expect_equal(result$locality, "KUNMING_A")
})

# ---------------------------------------------------------------------------
# Tests: long values are skipped
# ---------------------------------------------------------------------------

test_that("duplicate values longer than 10000 characters are skipped", {
  dt <- make_restore_input(n_usable = 1, n_dup = 1)
  dt[VasGBIF_dataset_result == "duplicate", locality := paste(rep("X", 10001), collapse = "")]

  result <- restore_duplicates(dt)

  # Too-long value should be skipped, locality stays empty
  expect_equal(result$locality, "")
})

# ---------------------------------------------------------------------------
# Tests: special character stripping in restored values
# ---------------------------------------------------------------------------

test_that("special characters are stripped from restored values", {
  dt <- make_restore_input(n_usable = 1, n_dup = 1)
  dt[VasGBIF_dataset_result == "duplicate", locality := "Kunming{*}()\\"]

  result <- restore_duplicates(dt)

  expect_equal(result$locality, "KUNMING")
})

# ---------------------------------------------------------------------------
# Tests: year with non-numeric content
# ---------------------------------------------------------------------------

test_that("year field handles non-numeric content gracefully", {
  dt <- make_restore_input(n_usable = 1, n_dup = 1)
  suppressWarnings(
    dt[VasGBIF_dataset_result == "duplicate", year := "2020A"]
  )

  result <- restore_duplicates(dt)

  # After stripping special chars: "2020A" → "2020A" (no special chars to strip)
  # as.integer("2020A") → NA (with warning suppressed)
  expect_true(is.na(result$year))
})
