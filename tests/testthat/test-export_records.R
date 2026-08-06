# ---------------------------------------------------------------------------
# Tests for export_records().
#
# `native_detected` now carries every column of the input records, so
# export_records() writes it straight out. Records that failed coordinate
# validation are never classified and are not part of the output.
# ---------------------------------------------------------------------------

# --- Helpers ----------------------------------------------------------------

# Read a gzipped CSV without requiring the optional 'R.utils' package that
# fread() needs to decompress .gz files itself.
read_gz <- function(path) {
  fread(text = readLines(gzfile(path), warn = FALSE))
}

# Records 1-3 have coordinates, 4-5 do not, mirroring what
# detect_native_status() returns after rejoining both tables.
mk_native_detected <- function() {
  out <- data.table(
    gbifID = c("1", "2", "3", "4", "5"),
    Accepted_name = c("A", "B", "C", "D", "E"),
    decimalLongitude = c(10, 20, 30, NA_real_, NA_real_),
    decimalLatitude = c(40, 50, 60, NA_real_, NA_real_),
    LEVEL3_COD = c("NOR", "POL", "NOR", "NOR", NA_character_),
    native_status = c("native", "introduced", "native", "native", "unknown"),
    native_status_source = rep("accepted_name", 5),
    buffered = rep(FALSE, 5)
  )
  class(out) <- c("nativeDetected", class(out))
  out
}

# --- Input validation -------------------------------------------------------

test_that("default (missing) inputs error with a clear message", {
  expect_error(
    export_records(),
    '`native_detected` must be a "nativeDetected" object'
  )
})

test_that("native_detected must be a nativeDetected object", {
  expect_error(
    export_records(native_detected = iris, export_path = tempdir()),
    '`native_detected` must be a "nativeDetected" object'
  )
})

test_that("native_detected must contain gbifID and native_status", {
  for (col in c("gbifID", "native_status")) {
    nd <- mk_native_detected()
    nd[[col]] <- NULL
    expect_error(
      export_records(native_detected = nd, export_path = tempdir()),
      paste0("missing required column\\(s\\): ", col),
      info = col
    )
  }
})

test_that("export_path must be a single directory path", {
  nd <- mk_native_detected()
  for (bad in list(NA_character_, 123, c("dir1", "dir2"))) {
    expect_error(
      export_records(native_detected = nd, export_path = bad),
      "must be a single directory path",
      info = paste(deparse(bad), collapse = "")
    )
  }
})

test_that("export_path must not be an existing file", {
  nd <- mk_native_detected()
  tmp <- tempfile("export-file-")
  file.create(tmp)
  on.exit(unlink(tmp))

  expect_error(
    export_records(native_detected = nd, export_path = tmp),
    "exists but is a file"
  )
})

# --- Export behaviour -------------------------------------------------------

test_that("writes two compressed CSV files to an existing directory", {
  nd <- mk_native_detected()
  export_dir <- tempfile("export-dir-")
  dir.create(export_dir)
  on.exit(unlink(export_dir, recursive = TRUE, force = TRUE))

  expect_no_warning(
    export_records(native_detected = nd, export_path = export_dir)
  )
  expect_true(file.exists(file.path(export_dir, "all_records.csv.gz")))
  expect_true(file.exists(file.path(export_dir, "native_records.csv.gz")))
  expect_false(file.exists(file.path(export_dir, "CoordinateProblematic_records.csv.gz")))
})

test_that("all_records is written straight from native_detected", {
  nd <- mk_native_detected()
  export_dir <- tempfile("export-dir-")
  dir.create(export_dir)
  on.exit(unlink(export_dir, recursive = TRUE, force = TRUE))

  suppressMessages(
    export_records(native_detected = nd, export_path = export_dir)
  )

  out <- read_gz(file.path(export_dir, "all_records.csv.gz"))
  # No join, so the columns are exactly those of native_detected
  expect_named(out, names(nd))
  expect_equal(nrow(out), 5L)
  expect_setequal(out$gbifID, c(1, 2, 3, 4, 5))
  expect_identical(out[gbifID == 2, native_status], "introduced")
  expect_identical(out[gbifID == 5, native_status], "unknown")
  # records without coordinates are included
  expect_true(all(is.na(out[gbifID %in% c(4, 5), decimalLatitude])))
})

test_that("native_records contains only the native subset", {
  nd <- mk_native_detected()
  export_dir <- tempfile("export-dir-")
  dir.create(export_dir)
  on.exit(unlink(export_dir, recursive = TRUE, force = TRUE))

  suppressMessages(
    export_records(native_detected = nd, export_path = export_dir)
  )

  out <- read_gz(file.path(export_dir, "native_records.csv.gz"))
  expect_setequal(out$gbifID, c(1, 3, 4))
  expect_true(all(out$native_status == "native"))
})

test_that("creates a missing export directory with a warning", {
  nd <- mk_native_detected()
  export_dir <- tempfile("export-new-")
  on.exit(unlink(export_dir, recursive = TRUE, force = TRUE))

  expect_warning(
    export_records(native_detected = nd, export_path = export_dir),
    "export_path does not exist, creating"
  )
  expect_true(dir.exists(export_dir))
  expect_true(file.exists(file.path(export_dir, "all_records.csv.gz")))
})

test_that("returns NULL invisibly", {
  nd <- mk_native_detected()
  export_dir <- tempfile("export-dir-")
  dir.create(export_dir)
  on.exit(unlink(export_dir, recursive = TRUE, force = TRUE))

  expect_invisible(
    export_records(native_detected = nd, export_path = export_dir)
  )
  ret <- suppressMessages(
    export_records(native_detected = nd, export_path = export_dir)
  )
  expect_null(ret)
})

test_that("reports progress messages", {
  nd <- mk_native_detected()
  export_dir <- tempfile("export-dir-")
  dir.create(export_dir)
  on.exit(unlink(export_dir, recursive = TRUE, force = TRUE))

  expect_message(
    export_records(native_detected = nd, export_path = export_dir),
    "Exporting records"
  )
  expect_message(
    export_records(native_detected = nd, export_path = export_dir),
    "Done"
  )
})
