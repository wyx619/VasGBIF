# ---------------------------------------------------------------------------
# Tests for import_records() and the import print method.
#
# The fixtures build small tab-separated GBIF downloads in both supported
# formats: a 'SIMPLE_CSV' ZIP holding a single data file, and a minimal
# Darwin Core Archive holding meta.xml + occurrence.txt.
# ---------------------------------------------------------------------------

# --- Helpers ----------------------------------------------------------------

make_gbif_zip <- function(dwca = FALSE, filename = "gbif-download.csv") {
  directory <- tempfile("gbif-test-")
  dir.create(directory)

  fields <- c(
    "gbifID", "order", "family", "species", "taxonRank", "scientificName",
    "verbatimScientificName", "countryCode", "locality", "occurrenceStatus",
    "decimalLatitude", "decimalLongitude", "coordinateUncertaintyInMeters",
    "elevation", "eventDate", "day", "month", "year", "basisOfRecord",
    "institutionCode", "collectionCode", "identifiedBy", "recordedBy", "issue"
  )

  records <- data.table(
    gbifID = c("1001", "1002"),
    order = c("Rosales", "Rosales"),
    family = c("Rosaceae", "Rosaceae"),
    species = c("Rosa canina", "Rosa rubiginosa"),
    taxonRank = c("SPECIES", "SPECIES"),
    scientificName = c("Rosa canina", "Rosa rubiginosa"),
    verbatimScientificName = c("Rosa canina", "Rosa rubiginosa"),
    countryCode = c("GB", "DE"),
    locality = c("London", "Berlin"),
    occurrenceStatus = c("PRESENT", "PRESENT"),
    decimalLatitude = c(51.5074, 52.52),
    decimalLongitude = c(-0.1278, 13.405),
    coordinateUncertaintyInMeters = c(100, 50),
    elevation = c(5, 34),
    eventDate = c("2020-06-01", "2021-07-02"),
    day = c(1L, 2L),
    month = c(6L, 7L),
    year = c(2020L, 2021L),
    basisOfRecord = c("PRESERVED_SPECIMEN", "PRESERVED_SPECIMEN"),
    institutionCode = c("TEST", "TEST"),
    collectionCode = c("BOT", "BOT"),
    identifiedBy = c("Collector One", "Collector Two"),
    recordedBy = c("Collector One", "Collector Two"),
    issue = c(
      "COORDINATE_ROUNDED|COUNTRY_COORDINATE_MISMATCH",
      ""
    )
  )[, ..fields]

  data_path <- file.path(directory, filename)
  data.table::fwrite(records, data_path, sep = "\t", quote = FALSE)

  if (dwca) {
    # A minimal Darwin Core Archive: meta.xml plus the occurrence core.
    writeLines("<archive/>", file.path(directory, "meta.xml"))
    file.rename(data_path, file.path(directory, "occurrence.txt"))
    archive_members <- c("meta.xml", "occurrence.txt")
  } else {
    archive_members <- filename
  }

  zip_path <- file.path(directory, "gbif-download.zip")
  old_directory <- setwd(directory)
  on.exit(setwd(old_directory), add = TRUE)
  utils::zip(zip_path, archive_members, flags = "-j")
  unlink(file.path(directory, archive_members))

  list(zip = zip_path, directory = directory)
}

# --- Output contract --------------------------------------------------------

test_that("import_records imports a SIMPLE_CSV archive as an import data.table", {
  fixture <- make_gbif_zip()
  res <- suppressMessages(import_records(fixture$zip))

  expect_s3_class(res, "import")
  expect_s3_class(res, "data.table")
  expect_equal(nrow(res), 2L)
  expect_identical(res$gbifID, c("1001", "1002"))
  expect_type(res$gbifID, "character")
})

test_that("import_records keeps the selected GBIF fields and the raw issue column", {
  fixture <- make_gbif_zip()
  res <- suppressMessages(import_records(fixture$zip))

  expect_setequal(names(res), c(
    "gbifID", "order", "family", "species", "taxonRank", "scientificName",
    "verbatimScientificName", "countryCode", "locality", "occurrenceStatus",
    "decimalLatitude", "decimalLongitude", "coordinateUncertaintyInMeters",
    "elevation", "eventDate", "day", "month", "year", "basisOfRecord",
    "institutionCode", "collectionCode", "identifiedBy", "recordedBy", "issue"
  ))
  expect_identical(
    res$issue,
    c("COORDINATE_ROUNDED|COUNTRY_COORDINATE_MISMATCH", "")
  )
})

test_that("import_records reads a Darwin Core Archive", {
  fixture <- make_gbif_zip(dwca = TRUE)
  res <- suppressMessages(import_records(fixture$zip))

  expect_s3_class(res, "import")
  expect_equal(nrow(res), 2L)
  expect_setequal(res$scientificName, c("Rosa canina", "Rosa rubiginosa"))
})

test_that("the import table feeds extract_issues", {
  fixture <- make_gbif_zip()
  occ <- suppressMessages(import_records(fixture$zip))
  res <- suppressMessages(extract_issues(occ))

  # the raw pipe-separated field is reduced to a per-record count
  expect_s3_class(res, "data.table")
  expect_named(res, c("gbifID", "issue_count"))
  expect_identical(res$gbifID, occ$gbifID)
  expect_equal(res$issue_count[1], 2)
  expect_equal(res$issue_count[2], 0)
})

# --- tempdir handling -------------------------------------------------------

test_that("a user-supplied tempdir is never deleted, only its extracted file", {
  fixture <- make_gbif_zip()
  outdir <- tempfile("gbif-out-")
  on.exit(unlink(outdir, recursive = TRUE, force = TRUE), add = TRUE)

  suppressMessages(import_records(fixture$zip, tempdir = outdir))

  # the directory the caller named is left in place; only the extracted member
  # is unlinked, so unrelated files in a shared directory are never at risk
  expect_true(dir.exists(outdir))
  expect_false(file.exists(file.path(outdir, "gbif-download.csv")))
})

test_that("remove_tempfile = TRUE deletes a directory this call created itself", {
  fixture <- make_gbif_zip()
  before <- list.files(tempdir(), "^VasGBIF-", full.names = TRUE)

  suppressMessages(import_records(fixture$zip))

  expect_setequal(
    list.files(tempdir(), "^VasGBIF-", full.names = TRUE),
    before
  )
})

test_that("a non-empty tempdir warns about potential overwrites", {
  fixture <- make_gbif_zip()
  outdir <- tempfile("gbif-out-")
  dir.create(outdir)
  writeLines("existing", file.path(outdir, "existing.txt"))
  on.exit(unlink(outdir, recursive = TRUE, force = TRUE), add = TRUE)

  expect_warning(
    suppressMessages(import_records(fixture$zip, tempdir = outdir)),
    "already contains"
  )
})

test_that("keeping the extraction directory is announced", {
  fixture <- make_gbif_zip()
  outdir <- tempfile("gbif-out-")
  on.exit(unlink(outdir, recursive = TRUE, force = TRUE), add = TRUE)

  expect_message(
    import_records(fixture$zip, tempdir = outdir, remove_tempfile = FALSE),
    "Extracted files will be preserved in"
  )
})

# --- Installed extdata ------------------------------------------------------

test_that("import_records does not modify the installed extdata directory", {
  gbif_file <- system.file(
    "extdata",
    "0003386-260721160103020.zip",
    package = "VasGBIF"
  )
  skip_if(gbif_file == "", "GBIF extdata archive is unavailable")
  extdata_directory <- dirname(gbif_file)
  files_before <- list.files(extdata_directory, all.files = TRUE)

  suppressMessages(import_records(gbif_file))

  expect_identical(
    list.files(extdata_directory, all.files = TRUE),
    files_before
  )
})

# --- Input validation -------------------------------------------------------

test_that("import_records rejects invalid paths", {
  expect_error(import_records(path = 1), "single character string")
  expect_error(import_records(path = ""), "SIMPLE_CSV or DWCA")

  # a file that exists but is not a GBIF occurrence table is rejected on its
  # header, not on its extension
  not_gbif <- tempfile(fileext = ".csv")
  writeLines("not,a,gbif,file", not_gbif)
  on.exit(unlink(not_gbif), add = TRUE)

  expect_error(
    import_records(path = not_gbif),
    "does not look like a GBIF occurrence table"
  )
})

# --- Print method -----------------------------------------------------------

test_that("print shows the record count", {
  fixture <- make_gbif_zip()
  res <- suppressMessages(import_records(fixture$zip))

  out <- capture.output(print(res))
  expect_true(any(grepl("<import> 2 records", out)))

  expect_invisible(print(res))
})

test_that("print handles a degraded object", {
  x <- structure(1, class = "import")
  out <- capture.output(print(x))
  expect_true(any(grepl("<import> 0 records", out)))
})
