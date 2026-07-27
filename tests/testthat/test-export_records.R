make_mock_refined <- function() {
  records <- data.table::data.table(
    gbifID = c("1", "2", "3"),
    native_status = c("native", "introduced", "native"),
    LEVEL3_COD = c("ABC", "DEF", "GHI"),
    VasGBIF_decimalLongitude = c(10, 20, 30),
    VasGBIF_decimalLatitude = c(40, 50, 60)
  )

  problematic <- data.table::data.table(
    gbifID = c("4", "5"),
    VasGBIF_decimalLongitude = c(0, 0),
    VasGBIF_decimalLatitude = c(0, 0)
  )

  structure(
    list(
      all_records = records,
      CoordinateProblematic = problematic,
      runtime = structure(1.5, class = "difftime", units = "secs")
    ),
    class = "refined"
  )
}

test_that("export_records writes to an existing directory", {
  refined <- make_mock_refined()
  export_dir <- tempfile("export-test-")
  dir.create(export_dir)
  on.exit(unlink(export_dir, recursive = TRUE, force = TRUE))

  messages <- capture_messages(
    export_records(refined, export_dir)
  )

  expect_match(messages, "Exporting records", all = FALSE)
  expect_true(file.exists(file.path(export_dir, "usable_refined_records.csv.gz")))
  expect_true(file.exists(file.path(export_dir, "native_refined_records.csv.gz")))
  expect_true(file.exists(file.path(
    export_dir, "CoordinateProblematic_records.csv.gz"
  )))
})

test_that("export_records creates directory when it does not exist", {
  refined <- make_mock_refined()
  export_dir <- tempfile("export-new-")

  expect_warning(
    export_records(refined, export_dir),
    "export_path does not exist, creating"
  )
  on.exit(unlink(export_dir, recursive = TRUE, force = TRUE))

  expect_true(dir.exists(export_dir))
  expect_true(file.exists(file.path(export_dir, "usable_refined_records.csv.gz")))
})

test_that("export_records stops when path is an existing file", {
  refined <- make_mock_refined()
  tmp <- tempfile("export-file-")
  file.create(tmp)
  on.exit(unlink(tmp))

  expect_error(
    export_records(refined, tmp),
    "exists but is a file"
  )
})

test_that("export_records stops when path is NA", {
  refined <- make_mock_refined()

  expect_error(
    export_records(refined, NA),
    "must be a single directory path"
  )
})

test_that("export_records stops when path is not a character", {
  refined <- make_mock_refined()

  expect_error(
    export_records(refined, 123),
    "must be a single directory path"
  )
})

test_that("export_records stops when path has length > 1", {
  refined <- make_mock_refined()

  expect_error(
    export_records(refined, c("dir1", "dir2")),
    "must be a single directory path"
  )
})
