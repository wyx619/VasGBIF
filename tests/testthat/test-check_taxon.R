# ---------------------------------------------------------------------------
# Tests for check_taxon() and the occ_taxa print method.
#
# check_taxon() calls the TNRS web API, so every behavioural test replaces
# `TNRS` in the package namespace with a mock via local_mocked_bindings().
# The mock emits the deterministic columns the pipeline expects; per-taxon
# overrides (score, status, rank, ...) are passed through make_mock_tnrs().
# ---------------------------------------------------------------------------

# --- Helpers ----------------------------------------------------------------

mk_import <- function(gbifID, scientificName, taxonRank) {
  out <- data.table(
    gbifID = gbifID,
    scientificName = scientificName,
    taxonRank = taxonRank
  )
  class(out) <- c("import", "data.table", "data.frame")
  out
}

# A TNRS stand-in. `overrides` maps a submitted name to a named list of
# column values that replace the defaults for that name.
make_mock_tnrs <- function(overrides = list()) {
  force(overrides)
  function(chunk, sources = "wcvp", classification = "wfo", mode = "resolve",
           matches = "best", accuracy = 0.85, skip_internet_check = TRUE) {
    n <- nrow(chunk)
    fields <- list(
      Overall_score = rep(0.95, n),
      Taxonomic_status = rep("Accepted", n),
      Accepted_name = chunk$taxon,
      Accepted_species = chunk$taxon,
      Accepted_name_id = paste0("wcvp-", chunk$ID),
      Accepted_name_rank = rep("species", n),
      Accepted_family = rep("Testaceae", n),
      Source = rep(sources[1], n)
    )
    for (i in seq_len(n)) {
      tx <- chunk$taxon[i]
      if (tx %in% names(overrides)) {
        for (nm in names(overrides[[tx]])) {
          fields[[nm]][i] <- overrides[[tx]][[nm]]
        }
      }
    }
    data.frame(
      ID = chunk$ID,
      Name_submitted = gsub(",", " ", chunk$taxon, fixed = TRUE),
      fields,
      stringsAsFactors = FALSE
    )
  }
}

# Evaluate `code`, capturing its messages and returning the value.
capture_messages <- function(code) {
  msgs <- character()
  value <- withCallingHandlers(
    code,
    message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
  list(value = value, messages = msgs)
}

# --- Input validation -------------------------------------------------------

test_that("default (missing) inputs error with a clear message", {
  expect_error(check_taxon(), "must be an \"import\" object")
})

test_that("occ_import must be an import object", {
  expect_error(check_taxon(occ_import = iris), "must be an \"import\" object")
})

test_that("occ_import must carry the required columns", {
  for (col in c("gbifID", "scientificName", "taxonRank")) {
    occ <- mk_import("1", "Alnus glutinosa", "SPECIES")
    occ[[col]] <- NULL
    expect_error(
      check_taxon(occ_import = occ),
      "missing required column",
      info = col
    )
  }
})

test_that("an empty occ_import errors", {
  occ <- mk_import(character(0), character(0), character(0))
  expect_error(check_taxon(occ_import = occ), "contains no records")
})

test_that("records only above species rank error", {
  occ <- mk_import(
    c("1", "2"),
    c("Quercus", "Fabaceae"),
    c("GENUS", "FAMILY")
  )
  expect_error(
    check_taxon(occ_import = occ),
    "no records at species rank or below"
  )
})

# --- Output contract --------------------------------------------------------

test_that("resolves accepted names into an occ_taxa object", {
  occ <- mk_import(
    c("1", "2", "3", "4"),
    c("Alnus glutinosa", "Alnus glutinosa", "Quercus robur", "Rosa canina"),
    c("SPECIES", "SPECIES", "SPECIES", "SPECIES")
  )
  local_mocked_bindings(TNRS = make_mock_tnrs(), .package = "VasGBIF")
  res <- suppressMessages(check_taxon(occ_import = occ))

  expect_s3_class(res, "occ_taxa")
  expect_named(res, c("occ_taxa_checked", "summary", "runtime"))
  expect_s3_class(res$occ_taxa_checked, "data.table")
  expect_s3_class(res$summary, "data.table")
  expect_s3_class(res$runtime, "difftime")
  # Three unique names resolved; the duplicated name keeps both records.
  expect_equal(nrow(res$summary), 3L)
  expect_equal(nrow(res$occ_taxa_checked), 4L)
})

# --- Output filtering -------------------------------------------------------

test_that("records failing the accuracy or status threshold are excluded", {
  occ <- mk_import(
    as.character(1:5),
    c("Good name", "Low score", "No status", "Synonym", "Genus hit"),
    rep("SPECIES", 5)
  )
  mock <- make_mock_tnrs(list(
    "Low score" = list(Overall_score = 0.5),
    "No status" = list(Taxonomic_status = "No status"),
    "Synonym" = list(Taxonomic_status = "Synonym"),
    "Genus hit" = list(Accepted_name_rank = "genus")
  ))
  local_mocked_bindings(TNRS = mock, .package = "VasGBIF")
  res <- suppressMessages(check_taxon(occ_import = occ))

  # summary keeps every submitted name for review
  expect_equal(nrow(res$summary), 5L)
  expect_setequal(res$occ_taxa_checked$scientificName, c("Good name", "Synonym"))
})

# --- Taxon rank filtering ---------------------------------------------------

test_that("genus-rank and above records are never submitted", {
  occ <- mk_import(
    c("1", "2", "3"),
    c("Alnus glutinosa", "Quercus", "Fabaceae"),
    c("SPECIES", "GENUS", "FAMILY")
  )
  submitted <- character()
  mock <- function(chunk, ...) {
    submitted <<- c(submitted, chunk$taxon)
    make_mock_tnrs()(chunk, ...)
  }
  local_mocked_bindings(TNRS = mock, .package = "VasGBIF")
  res <- suppressMessages(check_taxon(occ_import = occ))

  expect_identical(submitted, "Alnus glutinosa")
  expect_equal(nrow(res$summary), 1L)
  expect_equal(nrow(res$occ_taxa_checked), 1L)
})

test_that("species and infraspecific ranks are submitted", {
  occ <- mk_import(
    c("1", "2", "3", "4"),
    c(
      "Alnus glutinosa",
      "Alnus glutinosa var. pubescens",
      "Alnus glutinosa subsp. barbata",
      "Alnus glutinosa f. quercifolia"
    ),
    c("SPECIES", "VARIETY", "SUBSPECIES", "FORM")
  )
  local_mocked_bindings(TNRS = make_mock_tnrs(), .package = "VasGBIF")
  res <- suppressMessages(check_taxon(occ_import = occ))

  expect_equal(nrow(res$summary), 4L)
  expect_equal(nrow(res$occ_taxa_checked), 4L)
})

# --- Chunking ---------------------------------------------------------------

test_that("names are submitted in chunks of up to 4000 with unique IDs", {
  n_names <- 4001
  occ <- mk_import(
    gbifID = as.character(seq_len(n_names)),
    scientificName = paste0("Taxon ficticium ", seq_len(n_names)),
    taxonRank = rep("SPECIES", n_names)
  )
  local_mocked_bindings(TNRS = make_mock_tnrs(), .package = "VasGBIF")
  run <- capture_messages(check_taxon(occ_import = occ))
  res <- run$value
  expect_true(any(grepl("Processing chunk 2 of 2", run$messages)))

  expect_equal(nrow(res$summary), n_names)
  expect_equal(nrow(res$occ_taxa_checked), n_names)
  expect_false(anyDuplicated(res$summary$ID) > 0)
  expect_identical(res$summary$ID, seq_len(n_names))
})

# --- API response handling --------------------------------------------------

test_that("duplicate rows returned by the API are removed", {
  occ <- mk_import("1", "Alnus glutinosa", "SPECIES")
  mock <- function(chunk, ...) {
    out <- make_mock_tnrs()(chunk, ...)
    rbind(out, out)
  }
  local_mocked_bindings(TNRS = mock, .package = "VasGBIF")
  res <- suppressMessages(check_taxon(occ_import = occ))

  expect_equal(nrow(res$summary), 1L)
  expect_false(anyDuplicated(res$summary$ID) > 0)
  expect_equal(nrow(res$occ_taxa_checked), 1L)
})

test_that("unrecognised row identifiers error", {
  occ <- mk_import("1", "Alnus glutinosa", "SPECIES")
  mock <- function(chunk, ...) {
    out <- make_mock_tnrs()(chunk, ...)
    out$ID <- out$ID + 1000
    out
  }
  local_mocked_bindings(TNRS = mock, .package = "VasGBIF")
  expect_error(
    suppressMessages(check_taxon(occ_import = occ)),
    "unrecognised row identifiers"
  )
})

# --- Retry logic ------------------------------------------------------------
# These two tests intentionally include the 5-second pause between attempts.

test_that("an empty first response is retried", {
  occ <- mk_import("1", "Alnus glutinosa", "SPECIES")
  state <- new.env()
  state$calls <- 0L
  mock <- function(chunk, ...) {
    state$calls <- state$calls + 1L
    if (state$calls == 1L) return(data.frame())
    make_mock_tnrs()(chunk, ...)
  }
  local_mocked_bindings(TNRS = mock, .package = "VasGBIF")
  run <- capture_messages(check_taxon(occ_import = occ))
  res <- run$value
  expect_true(any(grepl("Query succeeded but returned empty result", run$messages)))
  expect_equal(state$calls, 2L)
  expect_equal(nrow(res$occ_taxa_checked), 1L)
})

test_that("a persistently failing chunk errors", {
  occ <- mk_import("1", "Alnus glutinosa", "SPECIES")
  local_mocked_bindings(
    TNRS = function(chunk, ...) data.frame(),
    .package = "VasGBIF"
  )
  expect_error(
    suppressMessages(check_taxon(occ_import = occ)),
    "Network error: TNRS API is unreachable"
  )
})

# --- Print method -----------------------------------------------------------

test_that("print shows distinct names, sources, and top accepted names", {
  occ <- mk_import(
    c("1", "2", "3", "4"),
    c(
      "Alnus glutinosa",
      "Alnus glutinosa",
      "Alnus glutinosa var. pubescens",
      "Quercus robur"
    ),
    c("SPECIES", "SPECIES", "VARIETY", "SPECIES")
  )
  mock <- make_mock_tnrs(list(
    "Alnus glutinosa var. pubescens" = list(
      Taxonomic_status = "Synonym",
      Accepted_name = "Alnus glutinosa",
      Accepted_species = "Alnus glutinosa"
    )
  ))
  local_mocked_bindings(TNRS = mock, .package = "VasGBIF")
  res <- suppressMessages(check_taxon(occ_import = occ))

  out <- capture.output(print(res))
  expect_true(any(grepl("<occ_taxa> 4 records | 3 unique scientificName", out)))
  expect_true(any(grepl("Distinct names in occ_taxa_checked:", out)))
  expect_true(any(grepl("scientificName", out)))
  expect_true(any(grepl("Accepted_species", out)))
  expect_true(any(grepl("Source of checked records:", out)))
  expect_true(any(grepl("wcvp", out)))
  expect_true(any(grepl("Top 3 Accepted_name by records:", out)))
  expect_true(any(grepl("Alnus glutinosa", out)))
  expect_true(any(grepl("Quercus robur", out)))
  expect_true(any(grepl("runtime:", out)))
  # Fewer than three distinct names must not pad the table with NA rows.
  expect_false(any(grepl("<NA>", out)))
  # The removed blocks must not reappear.
  expect_false(any(grepl("Top 3 Accepted_species", out)))
  expect_false(any(grepl("Accepted_family", out)))

  expect_invisible(print(res))
})

test_that("top tables do not pad beyond the number of distinct names", {
  x <- list(
    occ_taxa_checked = data.table(
      gbifID = c("1", "2"),
      scientificName = c("Alnus glutinosa", "Quercus robur"),
      Accepted_name = c("Alnus glutinosa", "Quercus robur"),
      Accepted_species = c("Alnus glutinosa", "Quercus robur"),
      Accepted_family = c("Betulaceae", "Fagaceae"),
      Source = c("wcvp", "wcvp")
    ),
    runtime = as.difftime(1, units = "secs")
  )
  class(x) <- "occ_taxa"
  out <- capture.output(print(x))
  expect_false(any(grepl("<NA>", out)))
  expect_true(any(grepl("Alnus glutinosa", out)))
  expect_true(any(grepl("Quercus robur", out)))
})

test_that("print falls back to a minimal header for degraded elements", {
  x <- list(
    occ_taxa_checked = data.table(gbifID = c("1", "2")),
    summary = data.table(ID = c(1L, 2L))
  )
  class(x) <- "occ_taxa"
  out <- capture.output(print(x))
  expect_true(any(grepl("<occ_taxa> 2 records", out)))
  expect_false(any(grepl("Distinct names", out)))
  expect_false(any(grepl("Source of checked records", out)))
  expect_false(any(grepl("runtime", out)))
})

test_that("print handles missing elements", {
  x <- structure(list(), class = "occ_taxa")
  expect_no_error(out <- capture.output(print(x)))
  expect_true(any(grepl("<occ_taxa> 0 records", out)))
})

test_that("print handles an empty checked table but keeps runtime", {
  x <- list(
    occ_taxa_checked = data.table(
      gbifID = character(0),
      scientificName = character(0)
    ),
    runtime = as.difftime(1, units = "secs")
  )
  class(x) <- "occ_taxa"
  out <- capture.output(print(x))
  expect_true(any(grepl("<occ_taxa> 0 records", out)))
  expect_true(any(grepl("runtime:", out)))
  expect_false(any(grepl("Distinct names", out)))
})
