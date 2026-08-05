# ---------------------------------------------------------------------------
# Tests for export_records().
# ---------------------------------------------------------------------------

# --- Helpers ----------------------------------------------------------------

# Read a gzipped CSV without requiring the optional 'R.utils' package that
# fread() needs to decompress .gz files itself.
read_gz <- function(path) {
  fread(text = readLines(gzfile(path), warn = FALSE))
}

mk_refined_coordinates <- function() {
  cleaned <- data.table(
    gbifID = c("1", "2", "3"),
    decimalLongitude = c(10, 20, 30),
    decimalLatitude = c(40, 50, 60),
    Accepted_name = c("A", "B", "C")
  )
  coordinateless <- data.table(
    gbifID = c("4", "5"),
    decimalLongitude = c(NA_real_, NA_real_),
    decimalLatitude = c(NA_real_, NA_real_),
    Accepted_name = c("D", "E")
  )
  problematic <- data.table(
    gbifID = "6",
    decimalLongitude = 0,
    decimalLatitude = 0,
    Accepted_name = "F"
  )
  out <- list(
    CoordinateCleaned = cleaned,
    CoordinateProblematic = problematic,
    Coordinateless = coordinateless,
    runtime = structure(1.5, class = "difftime", units = "secs")
  )
  class(out) <- "CoordinateRefined"
  out
}

mk_native_detected <- function() {
  out <- data.table(
    gbifID = c("1", "2", "3", "4", "5"),
    native_status = c("native", "introduced", "native", "native", "unknown"),
    native_status_source = rep("accepted_name", 5)
  )
  class(out) <- c("nativeDetected", class(out))
  out
}

# --- Input validation -------------------------------------------------------

test_that("default (missing) inputs error with a clear message", {
  expect_error(
    export_records(),
    '`refined_coordinates` must be a "CoordinateRefined" object'
  )
})

test_that("refined_coordinates must be a CoordinateRefined object", {
  nd <- mk_native_detected()
  expect_error(
    export_records(refined_coordinates = iris, native_detected = nd,
                   export_path = tempdir()),
    '`refined_coordinates` must be a "CoordinateRefined" object'
  )
})

test_that("native_detected must be a nativeDetected object", {
  rc <- mk_refined_coordinates()
  expect_error(
    export_records(refined_coordinates = rc, native_detected = iris,
                   export_path = tempdir()),
    '`native_detected` must be a "nativeDetected" object'
  )
})

test_that("CoordinateCleaned, Coordinateless and CoordinateProblematic must be data.frames", {
  nd <- mk_native_detected()
  for (nm in c("CoordinateCleaned", "Coordinateless", "CoordinateProblematic")) {
    rc <- mk_refined_coordinates()
    rc[[nm]] <- NULL
    expect_error(
      export_records(refined_coordinates = rc, native_detected = nd,
                     export_path = tempdir()),
      paste0("`refined_coordinates\\$", nm, "` must be a data.frame"),
      info = nm
    )
  }
})

test_that("CoordinateCleaned and Coordinateless must contain gbifID", {
  nd <- mk_native_detected()
  for (nm in c("CoordinateCleaned", "Coordinateless")) {
    rc <- mk_refined_coordinates()
    rc[[nm]] <- rc[[nm]][, !"gbifID", with = FALSE]
    expect_error(
      export_records(refined_coordinates = rc, native_detected = nd,
                     export_path = tempdir()),
      paste0("missing required column\\(s\\): gbifID"),
      info = nm
    )
  }
})

test_that("native_detected must contain gbifID and native_status", {
  rc <- mk_refined_coordinates()
  for (col in c("gbifID", "native_status")) {
    nd <- mk_native_detected()
    nd[[col]] <- NULL
    expect_error(
      export_records(refined_coordinates = rc, native_detected = nd,
                     export_path = tempdir()),
      paste0("missing required column\\(s\\): ", col),
      info = col
    )
  }
})

test_that("CoordinateCleaned and Coordinateless must share identical columns", {
  nd <- mk_native_detected()
  rc <- mk_refined_coordinates()
  rc$Coordinateless <- rc$Coordinateless[, .(gbifID, decimalLongitude, decimalLatitude)]
  expect_error(
    export_records(refined_coordinates = rc, native_detected = nd,
                   export_path = tempdir()),
    "must have identical columns"
  )
})

test_that("export_path must be a single directory path", {
  rc <- mk_refined_coordinates()
  nd <- mk_native_detected()
  for (bad in list(NA_character_, 123, c("dir1", "dir2"))) {
    expect_error(
      export_records(refined_coordinates = rc, native_detected = nd,
                     export_path = bad),
      "must be a single directory path",
      info = paste(deparse(bad), collapse = "")
    )
  }
})

test_that("export_path must not be an existing file", {
  rc <- mk_refined_coordinates()
  nd <- mk_native_detected()
  tmp <- tempfile("export-file-")
  file.create(tmp)
  on.exit(unlink(tmp))

  expect_error(
    export_records(refined_coordinates = rc, native_detected = nd,
                   export_path = tmp),
    "exists but is a file"
  )
})

# --- Export behaviour -------------------------------------------------------

test_that("writes three compressed CSV files to an existing directory", {
  rc <- mk_refined_coordinates()
  nd <- mk_native_detected()
  export_dir <- tempfile("export-dir-")
  dir.create(export_dir)
  on.exit(unlink(export_dir, recursive = TRUE, force = TRUE))

  expect_no_warning(
    export_records(refined_coordinates = rc, native_detected = nd,
                   export_path = export_dir)
  )
  expect_true(file.exists(file.path(export_dir, "all_records.csv.gz")))
  expect_true(file.exists(file.path(export_dir, "native_records.csv.gz")))
  expect_true(file.exists(file.path(export_dir, "CoordinateProblematic_records.csv.gz")))
})

test_that("all_records joins coordinate tables with native status by gbifID", {
  rc <- mk_refined_coordinates()
  nd <- mk_native_detected()
  export_dir <- tempfile("export-dir-")
  dir.create(export_dir)
  on.exit(unlink(export_dir, recursive = TRUE, force = TRUE))

  suppressMessages(
    export_records(refined_coordinates = rc, native_detected = nd,
                   export_path = export_dir)
  )

  out <- read_gz(file.path(export_dir, "all_records.csv.gz"))
  setkey(out, gbifID)
  expect_equal(nrow(out), 5L)
  expect_setequal(out$gbifID, c("1", "2", "3", "4", "5"))
  expect_identical(out[gbifID == "2", native_status], "introduced")
  expect_identical(out[gbifID == "5", native_status], "unknown")
  # records without coordinates are included
  expect_true(all(is.na(out[gbifID %in% c("4", "5"), decimalLatitude])))
})

test_that("native_records contains only the native subset", {
  rc <- mk_refined_coordinates()
  nd <- mk_native_detected()
  export_dir <- tempfile("export-dir-")
  dir.create(export_dir)
  on.exit(unlink(export_dir, recursive = TRUE, force = TRUE))

  suppressMessages(
    export_records(refined_coordinates = rc, native_detected = nd,
                   export_path = export_dir)
  )

  out <- read_gz(file.path(export_dir, "native_records.csv.gz"))
  setkey(out, gbifID)
  expect_setequal(out$gbifID, c("1", "3", "4"))
  expect_true(all(out$native_status == "native"))
})

test_that("CoordinateProblematic_records contains the failing records", {
  rc <- mk_refined_coordinates()
  nd <- mk_native_detected()
  export_dir <- tempfile("export-dir-")
  dir.create(export_dir)
  on.exit(unlink(export_dir, recursive = TRUE, force = TRUE))

  suppressMessages(
    export_records(refined_coordinates = rc, native_detected = nd,
                   export_path = export_dir)
  )

  out <- read_gz(file.path(export_dir, "CoordinateProblematic_records.csv.gz"))
  expect_setequal(out$gbifID, "6")
})

test_that("creates a missing export directory with a warning", {
  rc <- mk_refined_coordinates()
  nd <- mk_native_detected()
  export_dir <- tempfile("export-new-")
  on.exit(unlink(export_dir, recursive = TRUE, force = TRUE))

  expect_warning(
    export_records(refined_coordinates = rc, native_detected = nd,
                   export_path = export_dir),
    "export_path does not exist, creating"
  )
  expect_true(dir.exists(export_dir))
  expect_true(file.exists(file.path(export_dir, "all_records.csv.gz")))
})

test_that("returns NULL invisibly", {
  rc <- mk_refined_coordinates()
  nd <- mk_native_detected()
  export_dir <- tempfile("export-dir-")
  dir.create(export_dir)
  on.exit(unlink(export_dir, recursive = TRUE, force = TRUE))

  expect_invisible(
    export_records(refined_coordinates = rc, native_detected = nd,
                   export_path = export_dir)
  )
  ret <- suppressMessages(
    export_records(refined_coordinates = rc, native_detected = nd,
                   export_path = export_dir)
  )
  expect_null(ret)
})

test_that("reports progress messages", {
  rc <- mk_refined_coordinates()
  nd <- mk_native_detected()
  export_dir <- tempfile("export-dir-")
  dir.create(export_dir)
  on.exit(unlink(export_dir, recursive = TRUE, force = TRUE))

  expect_message(
    export_records(refined_coordinates = rc, native_detected = nd,
                   export_path = export_dir),
    "Exporting records"
  )
  expect_message(
    export_records(refined_coordinates = rc, native_detected = nd,
                   export_path = export_dir),
    "Done"
  )
})
