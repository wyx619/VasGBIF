# ---------------------------------------------------------------------------
# Helper: build minimal mock inputs for set_vouchers()
# ---------------------------------------------------------------------------

# A complete verbatim_fields list (all 9 fields present)
all_fields <- list(
  recordedBy = TRUE, recordNumber = TRUE, year = TRUE,
  institutionCode = TRUE, catalogNumber = TRUE, locality = TRUE,
  stateProvince = TRUE, COUNTRY = TRUE, identifiedBy = TRUE
)
# An empty verbatim_fields list (no fields present) — note: COUNTRY depends
# on !COUNTRY_INVALID, so tem_COUNTRY=TRUE unless COUNTRY_INVALID is an issue.
no_fields <- list(
  recordedBy = FALSE, recordNumber = FALSE, year = FALSE,
  institutionCode = FALSE, catalogNumber = FALSE, locality = FALSE,
  stateProvince = FALSE, COUNTRY = FALSE, identifiedBy = FALSE
)

make_voucher_inputs <- function(
    n = 3L,
    collection_keys = NULL,
    lat = NULL,
    lon = NULL,
    verbatim_fields = NULL,
    issues = NULL,
    wcvp_status = NULL,
    wcvp_name = NULL,
    wcvp_pid = NULL
) {
  force(n)

  gbif_ids         <- as.character(seq_len(n))
  collection_keys  <- collection_keys %||%
    sprintf("Sp|2020-01-01|%.2f|%.2f", seq_len(n), seq_len(n))
  lat              <- lat %||% rep(45.0, n)
  lon              <- lon %||% rep(10.0, n)
  verbatim_fields  <- verbatim_fields %||% rep(list(all_fields), n)
  issues           <- issues %||% rep(list(character()), n)
  wcvp_status      <- wcvp_status %||% rep("Accepted", n)
  wcvp_name        <- wcvp_name %||% sprintf("Species_%s", LETTERS[seq_len(n)])
  wcvp_pid         <- wcvp_pid %||% sprintf("pid-%d", seq_len(n))

  # ---- occ_issue ----
  issue_names <- EnumOccurrenceIssue$constant
  issue_mat <- matrix(FALSE, nrow = n, ncol = length(issue_names))
  colnames(issue_mat) <- issue_names
  for (i in seq_len(n)) {
    for (iss in issues[[i]]) {
      if (iss %in% issue_names) issue_mat[i, iss] <- TRUE
    }
  }
  occ_issue <- data.table::as.data.table(issue_mat)
  occ_issue[, gbifID := gbif_ids]
  data.table::setcolorder(occ_issue, "gbifID")

  occ_import <- list(occ_issue = occ_issue)
  class(occ_import) <- "import"

  # ---- occ_taxa_checked ----
  occ_taxa_checked <- data.table::data.table(
    gbifID             = gbif_ids,
    wcvp_taxon_name    = wcvp_name,
    wcvp_plant_name_id = wcvp_pid,
    wcvp_taxon_rank    = "Species",
    wcvp_taxon_status  = wcvp_status,
    wcvp_family        = "Testaceae",
    wcvp_taxon_authors = "L.",
    wcvp_reviewed      = "N",
    wcvp_searchedName  = wcvp_name,
    wcvp_searchNotes   = "Accepted"
  )
  taxa_checked <- list(occ_taxa_checked = occ_taxa_checked)
  class(taxa_checked) <- "occ_taxa"

  # ---- occ_key (collection_keys$occ_key) ----
  occ_key <- data.table::data.table(
    gbifID            = gbif_ids,
    collection_key    = collection_keys,
    decimalLatitude   = lat,
    decimalLongitude  = lon,
    year              = ifelse(vapply(verbatim_fields, `[[`, logical(1), "year"),
                               2020L, NA_integer_),
    institutionCode   = ifelse(vapply(verbatim_fields, `[[`, logical(1), "institutionCode"),
                               "INST", ""),
    catalogNumber     = ifelse(vapply(verbatim_fields, `[[`, logical(1), "catalogNumber"),
                               "CAT1", ""),
    recordedBy        = ifelse(vapply(verbatim_fields, `[[`, logical(1), "recordedBy"),
                               "Rec", ""),
    recordNumber      = ifelse(vapply(verbatim_fields, `[[`, logical(1), "recordNumber"),
                               "RN1", ""),
    stateProvince     = ifelse(vapply(verbatim_fields, `[[`, logical(1), "stateProvince"),
                               "SP", ""),
    locality          = ifelse(vapply(verbatim_fields, `[[`, logical(1), "locality"),
                               "Loc", ""),
    identifiedBy      = ifelse(vapply(verbatim_fields, `[[`, logical(1), "identifiedBy"),
                               "IDer", ""),
    occurrenceStatus  = "PRESENT",
    basisOfRecord     = "PRESERVED_SPECIMEN",
    collectionCode    = "BOT",
    scientificName    = wcvp_name,
    family            = "Testaceae",
    taxonRank         = "Species",
    eventDate         = "2020-01-01",
    month             = 1L,
    day               = 1L,
    countryCode       = "XX",
    dateIdentified    = "2020-06-01",
    typeStatus        = "",
    issue             = vapply(issues, paste, character(1), collapse = "|"),
    wcvp_taxon_name   = wcvp_name
  )
  collection_keys <- list(occ_key = occ_key)
  class(collection_keys) <- "collections"

  list(
    occ_import      = occ_import,
    taxa_checked    = taxa_checked,
    collection_keys = collection_keys
  )
}

`%||%` <- function(x, y) if (is.null(x)) y else x

# ---------------------------------------------------------------------------
# Tests: return structure
# ---------------------------------------------------------------------------

test_that("set_vouchers returns a 'vouchers' object with correct elements", {
  inp <- make_voucher_inputs(n = 2)
  result <- set_vouchers(
    occ_import = inp$occ_import,
    taxa_checked = inp$taxa_checked,
    collection_keys = inp$collection_keys
  )

  expect_s3_class(result, "vouchers")
  expect_named(result, c("occ_digital_voucher", "occ_results", "runtime"))
  expect_s3_class(result$occ_digital_voucher, "data.table")
  expect_s3_class(result$occ_results, "data.table")
  expect_s3_class(result$runtime, "difftime")
})

test_that("occ_results contains the expected columns", {
  inp <- make_voucher_inputs(n = 2)
  result <- set_vouchers(
    occ_import = inp$occ_import,
    taxa_checked = inp$taxa_checked,
    collection_keys = inp$collection_keys
  )

  expected_cols <- c(
    "gbifID", "geospatial_quality", "verbatim_quality",
    "moreInformativeRecord", "VasGBIF_digital_voucher",
    "VasGBIF_duplicates", "VasGBIF_num_duplicates",
    "VasGBIF_non_groupable_duplicates",
    "VasGBIF_duplicates_grouping_status",
    "coordinates_validated_by_gbif_issue",
    "VasGBIF_unidentified_sample",
    "VasGBIF_wcvp_plant_name_id",
    "VasGBIF_sample_taxon_name",
    "VasGBIF_sample_taxon_name_status",
    "VasGBIF_number_taxon_names",
    "VasGBIF_useful_for_spatial_analysis",
    "VasGBIF_decimalLatitude",
    "VasGBIF_decimalLongitude"
  )
  expect_true(all(expected_cols %in% names(result$occ_results)))
})

test_that("occ_digital_voucher contains VasGBIF_dataset_result", {
  inp <- make_voucher_inputs(n = 2)
  result <- set_vouchers(
    occ_import = inp$occ_import,
    taxa_checked = inp$taxa_checked,
    collection_keys = inp$collection_keys
  )

  expect_true(
    "VasGBIF_dataset_result" %in% names(result$occ_digital_voucher)
  )
  expect_true(all(
    result$occ_digital_voucher$VasGBIF_dataset_result %in%
      c("usable", "duplicate", "unusable")
  ))
})

# ---------------------------------------------------------------------------
# Tests: verbatim_quality
# ---------------------------------------------------------------------------

test_that("verbatim_quality scores 9 when all fields are present", {
  inp <- make_voucher_inputs(n = 1, verbatim_fields = list(all_fields))
  result <- set_vouchers(
    occ_import = inp$occ_import,
    taxa_checked = inp$taxa_checked,
    collection_keys = inp$collection_keys
  )
  expect_equal(result$occ_results$verbatim_quality, 9)
})

test_that("verbatim_quality scores 0 when all fields empty (incl. COUNTRY_INVALID)", {
  # tem_COUNTRY = !COUNTRY_INVALID, so COUNTRY_INVALID must be TRUE
  inp <- make_voucher_inputs(
    n = 1,
    verbatim_fields = list(no_fields),
    issues = list("COUNTRY_INVALID")
  )
  result <- set_vouchers(
    occ_import = inp$occ_import,
    taxa_checked = inp$taxa_checked,
    collection_keys = inp$collection_keys
  )
  expect_equal(result$occ_results$verbatim_quality, 0)
})

# ---------------------------------------------------------------------------
# Tests: geospatial_quality
# ---------------------------------------------------------------------------

test_that("geospatial_quality is 0 when no geospatial issues exist", {
  inp <- make_voucher_inputs(n = 1)
  result <- set_vouchers(
    occ_import = inp$occ_import,
    taxa_checked = inp$taxa_checked,
    collection_keys = inp$collection_keys
  )
  expect_equal(result$occ_results$geospatial_quality, 0)
})

test_that("geospatial_quality is -1 for a score-1 issue", {
  inp <- make_voucher_inputs(n = 1, issues = list("COORDINATE_ROUNDED"))
  result <- set_vouchers(
    occ_import = inp$occ_import,
    taxa_checked = inp$taxa_checked,
    collection_keys = inp$collection_keys
  )
  expect_equal(result$occ_results$geospatial_quality, -1)
})

test_that("geospatial_quality is -3 for a score-2 issue", {
  inp <- make_voucher_inputs(
    n = 1,
    issues = list("PRESUMED_SWAPPED_COORDINATE")
  )
  result <- set_vouchers(
    occ_import = inp$occ_import,
    taxa_checked = inp$taxa_checked,
    collection_keys = inp$collection_keys
  )
  expect_equal(result$occ_results$geospatial_quality, -3)
})

test_that("geospatial_quality is -9 for a score-3 issue", {
  inp <- make_voucher_inputs(n = 1, issues = list("ZERO_COORDINATE"))
  result <- set_vouchers(
    occ_import = inp$occ_import,
    taxa_checked = inp$taxa_checked,
    collection_keys = inp$collection_keys
  )
  expect_equal(result$occ_results$geospatial_quality, -9)
})

test_that("geospatial_quality is -9 when coordinates are missing", {
  inp <- make_voucher_inputs(n = 1, lat = NA_real_, lon = NA_real_)
  result <- set_vouchers(
    occ_import = inp$occ_import,
    taxa_checked = inp$taxa_checked,
    collection_keys = inp$collection_keys
  )
  expect_equal(result$occ_results$geospatial_quality, -9)
})

test_that("geospatial_quality uses most severe issue (score-3 beats score-1)", {
  inp <- make_voucher_inputs(
    n = 1,
    issues = list(c("COORDINATE_ROUNDED", "ZERO_COORDINATE"))
  )
  result <- set_vouchers(
    occ_import = inp$occ_import,
    taxa_checked = inp$taxa_checked,
    collection_keys = inp$collection_keys
  )
  expect_equal(result$occ_results$geospatial_quality, -9)
})

# ---------------------------------------------------------------------------
# Tests: moreInformativeRecord
# ---------------------------------------------------------------------------

test_that("moreInformativeRecord = verbatim_quality + geospatial_quality", {
  inp <- make_voucher_inputs(
    n = 1,
    issues = list("COORDINATE_ROUNDED"),   # geospatial = -1
    verbatim_fields = list(all_fields)      # verbatim = 9
  )
  result <- set_vouchers(
    occ_import = inp$occ_import,
    taxa_checked = inp$taxa_checked,
    collection_keys = inp$collection_keys
  )
  expect_equal(result$occ_results$moreInformativeRecord, 8)
})

# ---------------------------------------------------------------------------
# Tests: non-groupable records
# ---------------------------------------------------------------------------

test_that("non-groupable records are marked as digital vouchers", {
  inp <- make_voucher_inputs(
    n = 3,
    collection_keys = c("Sp|NA|45.00|10.00",         # non-groupable
                        "Sp|2020-01-01|45.00|10.00",  # groupable
                        "Sp|2020-01-01|45.00|10.00")  # groupable (same key)
  )
  result <- set_vouchers(
    occ_import = inp$occ_import,
    taxa_checked = inp$taxa_checked,
    collection_keys = inp$collection_keys
  )

  occ_res <- result$occ_results
  # Record 1 is non-groupable → digital voucher, non_groupable flag
  expect_true(occ_res$VasGBIF_digital_voucher[1])
  expect_true(occ_res$VasGBIF_non_groupable_duplicates[1])
  expect_equal(
    occ_res$VasGBIF_duplicates_grouping_status[1],
    "not groupable: incomplete collection key"
  )
  # Records 2-3 are groupable
  expect_equal(
    occ_res$VasGBIF_duplicates_grouping_status[2],
    "groupable"
  )
})

test_that("empty collection_key is non-groupable", {
  inp <- make_voucher_inputs(
    n = 2,
    collection_keys = c("", "Sp|2020-01-01|45.00|10.00")
  )
  result <- set_vouchers(
    occ_import = inp$occ_import,
    taxa_checked = inp$taxa_checked,
    collection_keys = inp$collection_keys
  )

  expect_true(result$occ_results$VasGBIF_non_groupable_duplicates[1])
  expect_equal(
    result$occ_results$VasGBIF_duplicates_grouping_status[1],
    "not groupable: incomplete collection key"
  )
})

# ---------------------------------------------------------------------------
# Tests: groupable voucher selection
# ---------------------------------------------------------------------------

test_that("record with highest moreInformativeRecord becomes digital voucher", {
  inp <- make_voucher_inputs(
    n = 2,
    collection_keys = c("Sp|2020-01-01|45.00|10.00",
                        "Sp|2020-01-01|45.00|10.00"),
    verbatim_fields = list(no_fields, all_fields),
    issues = list("COUNTRY_INVALID", character())
  )
  result <- set_vouchers(
    occ_import = inp$occ_import,
    taxa_checked = inp$taxa_checked,
    collection_keys = inp$collection_keys
  )

  occ_res <- result$occ_results
  # Record 1: verbatim=0, geospatial=-1 → moreInformativeRecord=-1
  # Record 2: verbatim=9, geospatial=0  → moreInformativeRecord=9
  expect_false(occ_res$VasGBIF_digital_voucher[1])
  expect_true(occ_res$VasGBIF_digital_voucher[2])
})

# ---------------------------------------------------------------------------
# Tests: tie-breaking
# ---------------------------------------------------------------------------

test_that("ties are broken by row order (first record wins)", {
  inp <- make_voucher_inputs(
    n = 2,
    collection_keys = c("Sp|2020-01-01|45.00|10.00",
                        "Sp|2020-01-01|45.00|10.00"),
    verbatim_fields = list(all_fields, all_fields)
  )
  result <- set_vouchers(
    occ_import = inp$occ_import,
    taxa_checked = inp$taxa_checked,
    collection_keys = inp$collection_keys
  )

  expect_true(result$occ_results$VasGBIF_digital_voucher[1])
  expect_false(result$occ_results$VasGBIF_digital_voucher[2])
})

# ---------------------------------------------------------------------------
# Tests: coordinate propagation
# ---------------------------------------------------------------------------

test_that("voucher coordinates are propagated to group members", {
  inp <- make_voucher_inputs(
    n = 2,
    collection_keys = c("Sp|2020-01-01|45.00|10.00",
                        "Sp|2020-01-01|45.00|10.00"),
    lat = c(45.0, 46.0),
    lon = c(10.0, 11.0),
    issues = list(character(), "ZERO_COORDINATE"),
    verbatim_fields = list(all_fields, all_fields)
  )
  result <- set_vouchers(
    occ_import = inp$occ_import,
    taxa_checked = inp$taxa_checked,
    collection_keys = inp$collection_keys
  )

  occ_res <- result$occ_results
  # Record 1: geospatial=0, verbatim=9 → 9 (wins)
  # Record 2: geospatial=-9, verbatim=9 → 0
  expect_true(occ_res$VasGBIF_digital_voucher[1])
  expect_false(occ_res$VasGBIF_digital_voucher[2])
  expect_equal(occ_res$VasGBIF_decimalLatitude,  c(45, 45))
  expect_equal(occ_res$VasGBIF_decimalLongitude, c(10, 10))
})

# ---------------------------------------------------------------------------
# Tests: taxonomic consensus
# ---------------------------------------------------------------------------

test_that("groupable records get the most frequent accepted name", {
  inp <- make_voucher_inputs(
    n = 3,
    collection_keys = rep("SpA|2020-01-01|45.00|10.00", 3),
    wcvp_status = c("Accepted", "Accepted", "Accepted"),
    wcvp_name   = c("SpA", "SpA", "SpB"),
    wcvp_pid    = c("pid-A", "pid-A", "pid-B")
  )
  result <- set_vouchers(
    occ_import = inp$occ_import,
    taxa_checked = inp$taxa_checked,
    collection_keys = inp$collection_keys
  )

  occ_res <- result$occ_results
  expect_equal(occ_res$VasGBIF_sample_taxon_name, rep("SpA", 3))
  expect_equal(occ_res$VasGBIF_wcvp_plant_name_id, rep("pid-A", 3))
  expect_equal(occ_res$VasGBIF_number_taxon_names, rep(2L, 3))
  expect_equal(
    occ_res$VasGBIF_sample_taxon_name_status,
    rep("divergent identifications", 3)
  )
})

test_that("groupable records with one accepted name are 'identified'", {
  inp <- make_voucher_inputs(
    n = 2,
    collection_keys = rep("SpA|2020-01-01|45.00|10.00", 2),
    wcvp_status = rep("Accepted", 2),
    wcvp_name   = rep("SpA", 2),
    wcvp_pid    = rep("pid-A", 2)
  )
  result <- set_vouchers(
    occ_import = inp$occ_import,
    taxa_checked = inp$taxa_checked,
    collection_keys = inp$collection_keys
  )

  occ_res <- result$occ_results
  expect_equal(
    occ_res$VasGBIF_sample_taxon_name_status,
    rep("identified", 2)
  )
  expect_equal(occ_res$VasGBIF_number_taxon_names, rep(1L, 2))
  expect_false(any(occ_res$VasGBIF_unidentified_sample))
})

test_that("groupable records with mixed resolved/unresolved names use the accepted name", {
  inp <- make_voucher_inputs(
    n = 3,
    collection_keys = rep("SpA|2020-01-01|45.00|10.00", 3),
    wcvp_status = c("Unresolved", "Unresolved", "Accepted"),
    wcvp_name   = c("", "", "SpA"),
    wcvp_pid    = c("", "", "pid-A")
  )
  result <- set_vouchers(
    occ_import = inp$occ_import,
    taxa_checked = inp$taxa_checked,
    collection_keys = inp$collection_keys
  )

  occ_res <- result$occ_results
  # One accepted name → "identified", name propagates to all
  expect_equal(
    occ_res$VasGBIF_sample_taxon_name_status,
    rep("identified", 3)
  )
  expect_equal(occ_res$VasGBIF_number_taxon_names, rep(1L, 3))
  expect_false(any(occ_res$VasGBIF_unidentified_sample))
})

# ---------------------------------------------------------------------------
# Tests: final classification
# ---------------------------------------------------------------------------

test_that("digital voucher with taxon and coords is 'usable'", {
  inp <- make_voucher_inputs(n = 1, verbatim_fields = list(all_fields))
  result <- set_vouchers(
    occ_import = inp$occ_import,
    taxa_checked = inp$taxa_checked,
    collection_keys = inp$collection_keys
  )

  expect_equal(
    result$occ_digital_voucher$VasGBIF_dataset_result,
    "usable"
  )
})

test_that("digital voucher without valid coords is 'unusable'", {
  inp <- make_voucher_inputs(
    n = 1,
    lat = NA_real_,
    lon = NA_real_,
    verbatim_fields = list(all_fields)
  )
  result <- set_vouchers(
    occ_import = inp$occ_import,
    taxa_checked = inp$taxa_checked,
    collection_keys = inp$collection_keys
  )

  expect_equal(
    result$occ_digital_voucher$VasGBIF_dataset_result,
    "unusable"
  )
})

test_that("digital voucher that is unidentified is 'unusable'", {
  inp <- make_voucher_inputs(
    n = 2,
    collection_keys = c("Sp|NA|45.00|10.00", "Sp|2020-01-01|45.00|10.00"),
    wcvp_status = c("Unresolved", "Accepted"),
    wcvp_name = c("", "SpA"),
    wcvp_pid = c("", "pid-A"),
    verbatim_fields = list(all_fields, all_fields)
  )
  result <- set_vouchers(
    occ_import = inp$occ_import,
    taxa_checked = inp$taxa_checked,
    collection_keys = inp$collection_keys
  )

  # Record 1: non-groupable, unidentified → unusable
  expect_equal(
    result$occ_digital_voucher$VasGBIF_dataset_result[1],
    "unusable"
  )
  # Record 2: groupable, identified, valid coords → usable
  expect_equal(
    result$occ_digital_voucher$VasGBIF_dataset_result[2],
    "usable"
  )
})

test_that("non-voucher record is 'duplicate'", {
  inp <- make_voucher_inputs(
    n = 2,
    collection_keys = rep("Sp|2020-01-01|45.00|10.00", 2),
    verbatim_fields = list(no_fields, all_fields),
    issues = list("COUNTRY_INVALID", character())
  )
  result <- set_vouchers(
    occ_import = inp$occ_import,
    taxa_checked = inp$taxa_checked,
    collection_keys = inp$collection_keys
  )

  occ_all <- result$occ_digital_voucher
  expect_equal(occ_all$VasGBIF_dataset_result[1], "duplicate")
  expect_equal(occ_all$VasGBIF_dataset_result[2], "usable")
})

# ---------------------------------------------------------------------------
# Tests: edge cases
# ---------------------------------------------------------------------------

test_that("single record works correctly", {
  inp <- make_voucher_inputs(n = 1)
  result <- set_vouchers(
    occ_import = inp$occ_import,
    taxa_checked = inp$taxa_checked,
    collection_keys = inp$collection_keys
  )

  expect_true(result$occ_results$VasGBIF_digital_voucher)
  expect_equal(result$occ_results$VasGBIF_num_duplicates, 1L)
  expect_equal(nrow(result$occ_digital_voucher), 1L)
})

test_that("records with zero lat/lon are treated as having invalid coordinates", {
  # Zero coordinates invalidate coordinate_validated_by_gbif_issue but do NOT
  # trigger geospatial_quality = -9 (that only applies to NA/missing coords).
  inp <- make_voucher_inputs(n = 1, lat = 0, lon = 0)
  result <- set_vouchers(
    occ_import = inp$occ_import,
    taxa_checked = inp$taxa_checked,
    collection_keys = inp$collection_keys
  )

  occ_res <- result$occ_results
  expect_false(occ_res$coordinates_validated_by_gbif_issue)
  expect_false(occ_res$VasGBIF_useful_for_spatial_analysis)
})

test_that("VasGBIF_num_duplicates reflects group size for groupable records", {
  inp <- make_voucher_inputs(
    n = 3,
    collection_keys = c("A|2020-01-01|45.00|10.00",
                        "A|2020-01-01|45.00|10.00",
                        "B|2020-01-01|46.00|11.00")
  )
  result <- set_vouchers(
    occ_import = inp$occ_import,
    taxa_checked = inp$taxa_checked,
    collection_keys = inp$collection_keys
  )

  occ_res <- result$occ_results
  expect_equal(occ_res$VasGBIF_num_duplicates[1:2], c(2L, 2L))
  expect_equal(occ_res$VasGBIF_num_duplicates[3], 1L)
})
