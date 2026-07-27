make_gbif_zip <- function(filename = "gbif-download.csv") {
  directory <- tempfile("gbif-test-")
  dir.create(directory)

  fields <- c(
    "gbifID",
    "occurrenceID",
    "family",
    "taxonRank",
    "scientificName",
    "verbatimScientificName",
    "countryCode",
    "locality",
    "stateProvince",
    "occurrenceStatus",
    "decimalLatitude",
    "decimalLongitude",
    "eventDate",
    "day",
    "month",
    "year",
    "basisOfRecord",
    "institutionCode",
    "collectionCode",
    "catalogNumber",
    "recordNumber",
    "identifiedBy",
    "dateIdentified",
    "recordedBy",
    "typeStatus",
    "mediaType",
    "issue",
    "coordinateUncertaintyInMeters"
  )

  records <- data.table::data.table(
    gbifID = c("1001", "1002"),
    occurrenceID = c("occ-1", "occ-2"),
    family = c("Rosaceae", "Rosaceae"),
    taxonRank = c("SPECIES", "SPECIES"),
    scientificName = c("Rosa canina", "Rosa rubiginosa"),
    verbatimScientificName = c("Rosa canina", "Rosa rubiginosa"),
    countryCode = c("GB", "DE"),
    locality = c("London", "Berlin"),
    stateProvince = c("England", "Berlin"),
    occurrenceStatus = c("PRESENT", "PRESENT"),
    decimalLatitude = c(51.5074, 52.52),
    decimalLongitude = c(-0.1278, 13.405),
    eventDate = c("2020-06-01", "2021-07-02"),
    day = c(1L, 2L),
    month = c(6L, 7L),
    year = c(2020L, 2021L),
    basisOfRecord = c("PRESERVED_SPECIMEN", "PRESERVED_SPECIMEN"),
    institutionCode = c("TEST", "TEST"),
    collectionCode = c("BOT", "BOT"),
    catalogNumber = c("A1", "A2"),
    recordNumber = c("R1", "R2"),
    identifiedBy = c("Collector One", "Collector Two"),
    dateIdentified = c("2020-06-10", "2021-07-10"),
    recordedBy = c("Collector One", "Collector Two"),
    typeStatus = c("", ""),
    mediaType = c("StillImage", ""),
    issue = c(
      "COORDINATE_ROUNDED|COUNTRY_COORDINATE_MISMATCH",
      ""
    ),
    coordinateUncertaintyInMeters = c(100, 50)
  )[, ..fields]

  data_path <- file.path(directory, filename)
  zip_path <- file.path(directory, "gbif-download.zip")
  data.table::fwrite(records, data_path, sep = "\t", quote = FALSE)

  old_directory <- setwd(directory)
  on.exit(setwd(old_directory), add = TRUE)
  utils::zip(zip_path, filename, flags = "-j")
  unlink(data_path)

  list(zip = zip_path, extracted = data_path)
}

test_that("import_records imports a GBIF ZIP archive", {
  fixture <- make_gbif_zip()

  result <- import_records(fixture$zip)

  expect_s3_class(result, "import")
  expect_named(result, c("occ", "occ_issue", "summary", "runtime"))
  expect_s3_class(result$occ, "data.table")
  expect_equal(nrow(result$occ), 2L)
  expect_identical(result$occ$gbifID, c("1001", "1002"))
  expect_named(result$occ, c(
    "gbifID", "occurrenceID", "family", "taxonRank", "scientificName",
    "verbatimScientificName", "countryCode", "locality", "stateProvince",
    "occurrenceStatus", "decimalLatitude", "decimalLongitude", "eventDate",
    "day", "month", "year", "basisOfRecord", "institutionCode",
    "collectionCode", "catalogNumber", "recordNumber", "identifiedBy",
    "dateIdentified", "recordedBy", "typeStatus", "mediaType", "issue",
    "coordinateUncertaintyInMeters"
  ))
})

test_that("import_records extracts GBIF issue flags", {
  fixture <- make_gbif_zip()

  result <- import_records(fixture$zip)

  expect_s3_class(result$occ_issue, "data.table")
  expect_identical(result$occ_issue$gbifID, c("1001", "1002"))
  expect_identical(
    result$occ_issue$COORDINATE_ROUNDED,
    c(TRUE, FALSE)
  )
  expect_identical(
    result$occ_issue$COUNTRY_COORDINATE_MISMATCH,
    c(TRUE, FALSE)
  )
  expect_equal(
    result$summary[issue_keys == "COORDINATE_ROUNDED", N],
    1
  )
})

test_that("import_records extracts outside the ZIP directory", {
  remove_fixture <- make_gbif_zip()
  import_records(remove_fixture$zip, remove_tempfile = TRUE)
  expect_identical(file.exists(remove_fixture$extracted), FALSE)

  keep_fixture <- make_gbif_zip()
  messages <- capture_messages(
    import_records(keep_fixture$zip, remove_tempfile = FALSE)
  )
  preserve_message <- grep(
    "^Preserved extracted files in ",
    messages,
    value = TRUE
  )
  preserved_directory <- trimws(sub(
    "^Preserved extracted files in ",
    "",
    preserve_message
  ))
  on.exit(unlink(preserved_directory, recursive = TRUE, force = TRUE), add = TRUE)

  expect_identical(file.exists(keep_fixture$extracted), FALSE)
  expect_length(preserve_message, 1L)
  expect_identical(dir.exists(preserved_directory), TRUE)
  expect_identical(
    file.exists(file.path(preserved_directory, "gbif-download.csv")),
    TRUE
  )
})

test_that("import_records does not modify the installed extdata directory", {
  gbif_file <- system.file(
    "extdata",
    "0003386-260721160103020.zip",
    package = "VasGBIF"
  )
  skip_if(gbif_file == "", "GBIF extdata archive is unavailable")
  extdata_directory <- dirname(gbif_file)
  files_before <- list.files(extdata_directory, all.files = TRUE)

  import_records(gbif_file)

  expect_identical(
    list.files(extdata_directory, all.files = TRUE),
    files_before
  )
})

test_that("import_records rejects invalid paths", {
  expect_snapshot(error = TRUE, import_records(path = 1))
  expect_snapshot(error = TRUE, import_records(path = ""))
  expect_snapshot(error = TRUE, import_records(path = "records.csv"))
})
