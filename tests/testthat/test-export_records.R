# ---------------------------------------------------------------------------
# Tests for export_records().
#
# export_records() consumes the spatial output of detect_native_coord(), which
# carries validated coordinates for every record, and writes it straight out.
# Inputs with missing coordinates (e.g. the output of detect_native_country())
# are rejected.
# ---------------------------------------------------------------------------

# --- Helpers ----------------------------------------------------------------

# Read a gzipped CSV without requiring the optional 'R.utils' package that
# fread() needs to decompress .gz files itself.
read_gz <- function(path) {
  fread(text = readLines(gzfile(path), warn = FALSE))
}

# A minimal nativeDetected object as detect_native_coord() returns it: every
# record carries validated coordinates.
mk_native_detected_coord <- function() {
  out <- data.table(
    gbifID = c("1", "2", "3", "4", "5"),
    Accepted_name = c("A", "B", "C", "D", "E"),
    decimalLongitude = c(10, 20, 30, 40, 50),
    decimalLatitude = c(40, 50, 60, 70, 80),
    LEVEL3_COD = c("NOR", "POL", "NOR", "NOR", NA_character_),
    native_status = c("native", "introduced", "native", "native", "unknown"),
    native_status_source = rep("spatial", 5),
    buffered = rep(FALSE, 5)
  )
  class(out) <- c("nativeDetected", class(out))
  out
}

# --- Input validation -------------------------------------------------------

test_that("default (missing) inputs error with a clear message", {
  expect_error(
    export_records(),
    '`native_detected_coord` must be a "nativeDetected" object'
  )
})

test_that("native_detected_coord must be a nativeDetected object", {
  expect_error(
    export_records(native_detected_coord = iris, export_path = tempdir()),
    '`native_detected_coord` must be a "nativeDetected" object'
  )
})

test_that("native_detected_coord must contain the required columns", {
  for (col in c("gbifID", "native_status", "decimalLongitude", "decimalLatitude")) {
    nd <- mk_native_detected_coord()
    nd[[col]] <- NULL
    expect_error(
      export_records(native_detected_coord = nd, export_path = tempdir()),
      paste0("missing required column\\(s\\): ", col),
      info = col
    )
  }
})

test_that("records with missing coordinates are rejected", {
  # The output of detect_native_country() carries the coordinate columns but
  # all values are missing; that is exactly what this check must catch.
  nd <- mk_native_detected_coord()
  nd[1:2, `:=`(decimalLongitude = NA_real_, decimalLatitude = NA_real_)]

  expect_error(
    export_records(native_detected_coord = nd, export_path = tempdir()),
    "2 record\\(s\\) with missing coordinates"
  )
})

test_that("export_path must be a single directory path", {
  nd <- mk_native_detected_coord()
  for (bad in list(NA_character_, 123, c("dir1", "dir2"))) {
    expect_error(
      export_records(native_detected_coord = nd, export_path = bad),
      "must be a single directory path",
      info = paste(deparse(bad), collapse = "")
    )
  }
})

test_that("export_path must not be an existing file", {
  nd <- mk_native_detected_coord()
  tmp <- tempfile("export-file-")
  file.create(tmp)
  on.exit(unlink(tmp))

  expect_error(
    export_records(native_detected_coord = nd, export_path = tmp),
    "exists but is a file"
  )
})

# --- Export behaviour -------------------------------------------------------

test_that("writes two compressed CSV files to an existing directory", {
  nd <- mk_native_detected_coord()
  export_dir <- tempfile("export-dir-")
  dir.create(export_dir)
  on.exit(unlink(export_dir, recursive = TRUE, force = TRUE))

  expect_no_warning(
    export_records(native_detected_coord = nd, export_path = export_dir)
  )
  expect_true(file.exists(file.path(export_dir, "all_records.csv.gz")))
  expect_true(file.exists(file.path(export_dir, "native_records.csv.gz")))
  expect_false(file.exists(file.path(export_dir, "CoordinateProblematic_records.csv.gz")))
})

test_that("all_records is written straight from native_detected_coord", {
  nd <- mk_native_detected_coord()
  export_dir <- tempfile("export-dir-")
  dir.create(export_dir)
  on.exit(unlink(export_dir, recursive = TRUE, force = TRUE))

  suppressMessages(
    export_records(native_detected_coord = nd, export_path = export_dir)
  )

  out <- read_gz(file.path(export_dir, "all_records.csv.gz"))
  # No join, so the columns are exactly those of native_detected_coord
  expect_named(out, names(nd))
  expect_equal(nrow(out), 5L)
  expect_setequal(out$gbifID, c(1, 2, 3, 4, 5))
  expect_identical(out[gbifID == 2, native_status], "introduced")
  expect_identical(out[gbifID == 5, native_status], "unknown")
})

test_that("native_records contains only the native subset", {
  nd <- mk_native_detected_coord()
  export_dir <- tempfile("export-dir-")
  dir.create(export_dir)
  on.exit(unlink(export_dir, recursive = TRUE, force = TRUE))

  suppressMessages(
    export_records(native_detected_coord = nd, export_path = export_dir)
  )

  out <- read_gz(file.path(export_dir, "native_records.csv.gz"))
  expect_setequal(out$gbifID, c(1, 3, 4))
  expect_true(all(out$native_status == "native"))
})

test_that("creates a missing export directory with a warning", {
  nd <- mk_native_detected_coord()
  export_dir <- tempfile("export-new-")
  on.exit(unlink(export_dir, recursive = TRUE, force = TRUE))

  expect_warning(
    export_records(native_detected_coord = nd, export_path = export_dir),
    "export_path does not exist, creating"
  )
  expect_true(dir.exists(export_dir))
  expect_true(file.exists(file.path(export_dir, "all_records.csv.gz")))
})

test_that("returns NULL invisibly", {
  nd <- mk_native_detected_coord()
  export_dir <- tempfile("export-dir-")
  dir.create(export_dir)
  on.exit(unlink(export_dir, recursive = TRUE, force = TRUE))

  expect_invisible(
    export_records(native_detected_coord = nd, export_path = export_dir)
  )
  ret <- suppressMessages(
    export_records(native_detected_coord = nd, export_path = export_dir)
  )
  expect_null(ret)
})

test_that("reports progress messages", {
  nd <- mk_native_detected_coord()
  export_dir <- tempfile("export-dir-")
  dir.create(export_dir)
  on.exit(unlink(export_dir, recursive = TRUE, force = TRUE))

  expect_message(
    export_records(native_detected_coord = nd, export_path = export_dir),
    "Exporting records"
  )
  expect_message(
    export_records(native_detected_coord = nd, export_path = export_dir),
    "Done"
  )
})
