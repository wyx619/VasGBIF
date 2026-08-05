# ---------------------------------------------------------------------------
# Tests for map_records().
#
# The installed mapview stores only the point geometry in the returned
# object's @object slot (an sfc_POINT, no attribute table), so deduplication
# behaviour is asserted through the coordinates and count of the rendered
# points. If mapview changes its return structure, pts_of() must be revisited.
# ---------------------------------------------------------------------------

# --- Helpers ----------------------------------------------------------------

mk_native_detected <- function(gbifID, native_status, source = "accepted_name") {
  out <- data.table(
    gbifID = gbifID,
    native_status = native_status,
    native_status_source = source
  )
  class(out) <- c("nativeDetected", class(out))
  out
}

mk_cleaned <- function(gbifID, name, lon, lat) {
  n <- length(gbifID)
  data.table(
    gbifID = gbifID,
    gbif_issues = rep("", n),
    Accepted_name = name,
    scientificName = name,
    Taxonomic_status = rep("accepted", n),
    order = rep("Fagales", n),
    family = rep("Betulaceae", n),
    basisOfRecord = rep("HUMAN_OBSERVATION", n),
    decimalLongitude = lon,
    decimalLatitude = lat
  )
}

mk_refined_coordinates <- function(cleaned) {
  out <- list(
    CoordinateCleaned = cleaned,
    CoordinateProblematic = data.table(),
    Coordinateless = data.table()
  )
  class(out) <- "CoordinateRefined"
  out
}

# Point coordinates rendered by mapview, sorted for order-independent
# comparisons.
pts_of <- function(map) {
  coords <- sf::st_coordinates(map@object[[1]])
  coords <- as.data.frame(coords)
  coords <- coords[order(coords$X, coords$Y), , drop = FALSE]
  rownames(coords) <- NULL
  coords
}

build_map <- function(nd, cleaned, precision = 3) {
  suppressMessages(map_records(
    native_detected = nd,
    refined_coordinates = mk_refined_coordinates(cleaned),
    precision = precision,
    cex = 3
  ))
}

# --- Signature validation ---------------------------------------------------

test_that("default (missing) inputs error with a clear message", {
  expect_error(
    map_records(),
    '`native_detected` must be a "nativeDetected" object'
  )
})

test_that("native_detected must be a nativeDetected object", {
  cleaned <- mk_cleaned("1", "Sp alpha", 10, 60)
  expect_error(
    map_records(native_detected = iris,
                refined_coordinates = mk_refined_coordinates(cleaned)),
    '`native_detected` must be a "nativeDetected" object'
  )
})

test_that("refined_coordinates must be a CoordinateRefined object", {
  nd <- mk_native_detected("1", "native")
  expect_error(
    map_records(native_detected = nd,
                refined_coordinates = list(CoordinateCleaned = mk_cleaned("1", "Sp alpha", 10, 60))),
    '`refined_coordinates` must be a "CoordinateRefined" object'
  )
})

test_that("native_detected must carry gbifID, native_status, native_status_source", {
  cleaned <- mk_cleaned("1", "Sp alpha", 10, 60)
  for (col in c("gbifID", "native_status", "native_status_source")) {
    nd <- data.table(gbifID = "1", native_status = "native",
                     native_status_source = "accepted_name")
    nd[[col]] <- NULL
    class(nd) <- c("nativeDetected", class(nd))
    expect_error(
      map_records(native_detected = nd,
                  refined_coordinates = mk_refined_coordinates(cleaned)),
      paste0("missing required column\\(s\\): ", col),
      info = col
    )
  }
})

test_that("CoordinateCleaned must carry the required columns", {
  nd <- mk_native_detected("1", "native")
  for (col in c("gbifID", "family", "decimalLatitude", "decimalLongitude")) {
    cleaned <- mk_cleaned("1", "Sp alpha", 10, 60)
    cleaned[[col]] <- NULL
    expect_error(
      map_records(native_detected = nd,
                  refined_coordinates = mk_refined_coordinates(cleaned)),
      paste0("missing required column\\(s\\): ", col),
      info = col
    )
  }
})

test_that("precision must be a single positive integer", {
  nd <- mk_native_detected("1", "native")
  rc <- mk_refined_coordinates(mk_cleaned("1", "Sp alpha", 10, 60))
  for (bad in list(0, -1, 2.5, NA_real_, "3", c(3, 4))) {
    expect_error(
      map_records(native_detected = nd, refined_coordinates = rc, precision = bad),
      "`precision` must be a single positive integer",
      info = paste(deparse(bad), collapse = "")
    )
  }
})

test_that("cex must be a single positive number", {
  nd <- mk_native_detected("1", "native")
  rc <- mk_refined_coordinates(mk_cleaned("1", "Sp alpha", 10, 60))
  for (bad in list(0, -1, NA_real_, "3", c(3, 3))) {
    expect_error(
      map_records(native_detected = nd, refined_coordinates = rc, cex = bad),
      "`cex` must be a single positive number",
      info = paste(deparse(bad), collapse = "")
    )
  }
})

# --- Deduplication and record selection ------------------------------------

test_that("returns a mapview object", {
  nd <- mk_native_detected("1", "native")
  map <- build_map(nd, mk_cleaned("1", "Sp alpha", 10, 60))
  expect_s4_class(map, "mapview")
})

test_that("identical records in one cell collapse to a single point", {
  nd <- mk_native_detected(c("1", "2", "3"), c("native", "native", "native"))
  cleaned <- mk_cleaned(c("1", "2", "3"), "Sp alpha", c(10, 10, 10), c(60, 60, 60))
  pts <- pts_of(build_map(nd, cleaned))
  expect_equal(nrow(pts), 1L)
  expect_equal(pts, data.frame(X = 10, Y = 60), tolerance = 1e-9)
})

test_that("native_status splits records inside the same cell", {
  nd <- mk_native_detected(c("1", "2", "3"),
                           c("native", "introduced", "location_doubtful"))
  cleaned <- mk_cleaned(c("1", "2", "3"), "Sp alpha", c(10, 10, 10), c(60, 60, 60))
  pts <- pts_of(build_map(nd, cleaned))
  expect_equal(nrow(pts), 3L)
  expect_equal(pts,
               data.frame(X = c(10, 10, 10), Y = c(60, 60, 60)),
               tolerance = 1e-9)
})

test_that("species splits records inside the same cell", {
  nd <- mk_native_detected(c("1", "2"), c("native", "native"))
  cleaned <- rbind(
    mk_cleaned("1", "Sp alpha", 10, 60),
    mk_cleaned("2", "Sp beta", 10, 60)
  )
  pts <- pts_of(build_map(nd, cleaned))
  expect_equal(nrow(pts), 2L)
})

test_that("records in different cells are not deduplicated", {
  nd <- mk_native_detected(c("1", "2"), c("native", "native"))
  cleaned <- mk_cleaned(c("1", "2"), "Sp alpha", c(10, 30), c(60, 30))
  pts <- pts_of(build_map(nd, cleaned))
  expect_equal(nrow(pts), 2L)
  expect_equal(pts, data.frame(X = c(10, 30), Y = c(60, 30)), tolerance = 1e-9)
})

test_that("unknown status records are excluded", {
  nd <- mk_native_detected(c("1", "2"), c("native", "unknown"))
  cleaned <- mk_cleaned(c("1", "2"), "Sp alpha", c(10, 10), c(60, 60))
  pts <- pts_of(build_map(nd, cleaned))
  expect_equal(nrow(pts), 1L)
  expect_equal(pts, data.frame(X = 10, Y = 60), tolerance = 1e-9)
})

test_that("records with missing coordinates are dropped before deduplication", {
  nd <- mk_native_detected(c("1", "2", "3"), c("native", "native", "native"))
  cleaned <- data.table(
    gbifID = c("1", "2", "3"),
    gbif_issues = rep("", 3),
    Accepted_name = rep("Sp alpha", 3),
    scientificName = rep("Sp alpha", 3),
    Taxonomic_status = rep("accepted", 3),
    order = rep("Fagales", 3),
    family = rep("Betulaceae", 3),
    basisOfRecord = rep("HUMAN_OBSERVATION", 3),
    decimalLongitude = c(10, NA, 10),
    decimalLatitude = c(60, 60, NA)
  )
  pts <- pts_of(build_map(nd, cleaned))
  expect_equal(nrow(pts), 1L)
  expect_equal(pts, data.frame(X = 10, Y = 60), tolerance = 1e-9)
})

test_that("records missing from CoordinateCleaned are dropped (inner join)", {
  nd <- mk_native_detected(c("1", "2"), c("native", "native"))
  cleaned <- mk_cleaned("1", "Sp alpha", 10, 60)
  pts <- pts_of(build_map(nd, cleaned))
  expect_equal(nrow(pts), 1L)
})

test_that("higher precision retains more points (finer cells)", {
  nd <- mk_native_detected(c("1", "2"), c("native", "native"))
  cleaned <- mk_cleaned(c("1", "2"), "Sp alpha", c(10, 10.01), c(60, 60.01))
  expect_equal(nrow(pts_of(build_map(nd, cleaned, precision = 3))), 1L)
  expect_equal(nrow(pts_of(build_map(nd, cleaned, precision = 6))), 2L)
})

test_that("first record of each group is the representative point", {
  # merge sorts by gbifID, so "1" (at 10, 60) is the first row of the group
  nd <- mk_native_detected(c("1", "2"), c("native", "native"))
  cleaned <- mk_cleaned(c("1", "2"), "Sp alpha", c(10, 10.01), c(60, 60.01))
  pts <- pts_of(build_map(nd, cleaned, precision = 3))
  expect_equal(nrow(pts), 1L)
  expect_equal(pts, data.frame(X = 10, Y = 60), tolerance = 1e-9)
})
