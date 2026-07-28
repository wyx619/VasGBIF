# ---------------------------------------------------------------------------
# Helper: build mock inputs for get_collections()
# ---------------------------------------------------------------------------
make_collections_inputs <- function(
    n = 2L,
    event_dates = NULL,
    lats = NULL,
    lons = NULL,
    taxon_names = NULL
) {
  gbif_ids <- as.character(seq_len(n))
  event_dates <- event_dates %||% rep("2020-06-15", n)
  lats <- lats %||% c(45.1234, 46.5678)[seq_len(n)]
  lons <- lons %||% c(10.1234, 11.5678)[seq_len(n)]
  taxon_names <- taxon_names %||% sprintf("Species_%s", LETTERS[seq_len(n)])

  occ <- data.table::data.table(
    gbifID = gbif_ids,
    eventDate = event_dates,
    decimalLatitude = lats,
    decimalLongitude = lons
  )
  occ_import <- list(occ = occ)
  class(occ_import) <- "import"

  occ_taxa_checked <- data.table::data.table(
    gbifID = gbif_ids,
    wcvp_taxon_name = taxon_names
  )
  taxa_checked <- list(occ_taxa_checked = occ_taxa_checked)
  class(taxa_checked) <- "occ_taxa"

  list(occ_import = occ_import, taxa_checked = taxa_checked)
}

`%||%` <- function(x, y) if (is.null(x)) y else x

# ---------------------------------------------------------------------------
# Tests: return structure
# ---------------------------------------------------------------------------

test_that("get_collections returns a 'collections' object", {
  inp <- make_collections_inputs(n = 2)
  result <- get_collections(inp$occ_import, inp$taxa_checked)

  expect_s3_class(result, "collections")
  expect_named(result, c("occ_key", "complete_keys", "incomplete_keys", "runtime"))
  expect_s3_class(result$occ_key, "data.table")
  expect_true("collection_key" %in% names(result$occ_key))
})

test_that("occ_key has the same number of rows as input", {
  inp <- make_collections_inputs(n = 3)
  result <- get_collections(inp$occ_import, inp$taxa_checked)

  expect_equal(nrow(result$occ_key), 3L)
})

# ---------------------------------------------------------------------------
# Tests: collection_key construction
# ---------------------------------------------------------------------------

test_that("collection_key has the format taxon|date|lat|lon", {
  inp <- make_collections_inputs(
    n = 1,
    event_dates = "2020-06-15",
    lats = 45.1234,
    lons = 10.5678,
    taxon_names = "Rosa_canina"
  )
  result <- get_collections(
    inp$occ_import,
    inp$taxa_checked,
    precision = 2L
  )

  key <- result$occ_key$collection_key
  # Should be: Rosa_canina|numeric_date|45.12|10.57
  parts <- strsplit(key, "\\|")[[1]]
  expect_length(parts, 4L)
  expect_equal(parts[1], "Rosa_canina")
  expect_equal(parts[3], "45.12")
  expect_equal(parts[4], "10.57")
})

test_that("precision controls rounding of coordinates in the key", {
  inp <- make_collections_inputs(
    n = 1,
    lats = 45.12345,
    lons = 10.12345
  )

  r1 <- get_collections(inp$occ_import, inp$taxa_checked, precision = 1L)
  r2 <- get_collections(inp$occ_import, inp$taxa_checked, precision = 3L)

  # precision=1: 45.1, 10.1
  # precision=3: 45.123, 10.123
  k1 <- strsplit(r1$occ_key$collection_key, "\\|")[[1]]
  k3 <- strsplit(r2$occ_key$collection_key, "\\|")[[1]]
  expect_equal(k1[3], "45.1")
  expect_equal(k3[3], "45.123")
})

test_that("same coordinates at same precision produce identical keys", {
  inp <- make_collections_inputs(
    n = 2,
    lats = c(45.1234, 45.1239),
    lons = c(10.5678, 10.5671),
    event_dates = c("2020-06-15", "2020-06-15"),
    taxon_names = c("SpA", "SpA")
  )
  result <- get_collections(inp$occ_import, inp$taxa_checked, precision = 2L)

  keys <- strsplit(result$occ_key$collection_key, "\\|")
  # Rounding to 2 dp makes coords equal
  expect_equal(keys[[1]][3], keys[[2]][3])
  expect_equal(keys[[1]][4], keys[[2]][4])
})

# ---------------------------------------------------------------------------
# Tests: key completeness
# ---------------------------------------------------------------------------

test_that("complete_keys and incomplete_keys are counted correctly", {
  # Two records: one with valid data, one with NA coordinates
  inp <- make_collections_inputs(
    n = 2,
    lats = c(45.0, NA_real_),
    lons = c(10.0, NA_real_)
  )
  result <- get_collections(inp$occ_import, inp$taxa_checked)

  expect_equal(result$complete_keys, 1L)
  expect_equal(result$incomplete_keys, 1L)
})

test_that("missing eventDate produces an incomplete key", {
  inp <- make_collections_inputs(
    n = 1,
    event_dates = ""
  )
  result <- get_collections(inp$occ_import, inp$taxa_checked)

  expect_equal(result$complete_keys, 0L)
  expect_equal(result$incomplete_keys, 1L)
  expect_match(
    result$occ_key$collection_key,
    "(^|\\|)NA(\\||$)"
  )
})

test_that("records sharing the same complete key are counted once", {
  inp <- make_collections_inputs(
    n = 2,
    lats = c(45.1234, 45.1234),
    lons = c(10.5678, 10.5678),
    event_dates = c("2020-06-15", "2020-06-15"),
    taxon_names = c("SpA", "SpA")
  )
  result <- get_collections(inp$occ_import, inp$taxa_checked, precision = 2L)

  # Same key → 1 distinct complete key, 0 incomplete
  expect_equal(result$complete_keys, 1L)
  expect_equal(result$incomplete_keys, 0L)
})

# ---------------------------------------------------------------------------
# Tests: precision validation
# ---------------------------------------------------------------------------

test_that("precision rejects non-integer values", {
  inp <- make_collections_inputs(n = 1)
  expect_error(
    get_collections(inp$occ_import, inp$taxa_checked, precision = 1.5),
    "precision"
  )
})

test_that("precision rejects values <= 0", {
  inp <- make_collections_inputs(n = 1)
  expect_error(
    get_collections(inp$occ_import, inp$taxa_checked, precision = 0),
    "precision"
  )
  expect_error(
    get_collections(inp$occ_import, inp$taxa_checked, precision = -1),
    "precision"
  )
})

test_that("precision rejects non-numeric input", {
  inp <- make_collections_inputs(n = 1)
  expect_error(
    get_collections(inp$occ_import, inp$taxa_checked, precision = "2"),
    "precision"
  )
})

# ---------------------------------------------------------------------------
# Tests: eventDate parsing
# ---------------------------------------------------------------------------

test_that("eventDate with time component is parsed correctly", {
  inp <- make_collections_inputs(
    n = 1,
    event_dates = "2020-06-15T12:30:00"
  )
  result <- get_collections(inp$occ_import, inp$taxa_checked)

  # Key should not contain time information
  expect_false(grepl("12:30", result$occ_key$collection_key))
})

test_that("eventDate with only year-month is parsed", {
  inp <- make_collections_inputs(
    n = 1,
    event_dates = "2020-06"
  )
  result <- get_collections(inp$occ_import, inp$taxa_checked)

  # Should not be NA
  expect_false(grepl("\\|NA\\|", result$occ_key$collection_key))
})
