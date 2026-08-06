# ---------------------------------------------------------------------------
# Tests for map_records().
#
# map_records() now reads everything from `native_detected`, which carries the
# record columns as well as the classification.
#
# The installed mapview stores only the point geometry in the returned
# object's @object slot (an sfc_POINT, no attribute table), so deduplication
# behaviour is asserted through the coordinates and count of the rendered
# points. If mapview changes its return structure, pts_of() must be revisited.
# ---------------------------------------------------------------------------

# --- Helpers ----------------------------------------------------------------

# A nativeDetected table as detect_native_status() now returns it: the record
# columns plus the classification columns.
mk_native_detected <- function(
  gbifID,
  native_status,
  name = "Sp alpha",
  lon = 10,
  lat = 60,
  source = "spatial"
) {
  n <- length(gbifID)
  out <- data.table(
    gbifID = gbifID,
    gbif_issues = rep("", n),
    Accepted_name = rep_len(name, n),
    scientificName = rep_len(name, n),
    Taxonomic_status = rep("accepted", n),
    order = rep("Fagales", n),
    family = rep("Betulaceae", n),
    basisOfRecord = rep("HUMAN_OBSERVATION", n),
    decimalLongitude = rep_len(lon, n),
    decimalLatitude = rep_len(lat, n),
    native_status = native_status,
    native_status_source = rep_len(source, n)
  )
  class(out) <- c("nativeDetected", class(out))
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

build_map <- function(nd, precision = 3) {
  suppressMessages(map_records(
    native_detected = nd,
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
  expect_error(
    map_records(native_detected = iris),
    '`native_detected` must be a "nativeDetected" object'
  )
})

test_that("native_detected must carry every required column", {
  required <- c(
    "gbifID",
    "native_status",
    "native_status_source",
    "gbif_issues",
    "Accepted_name",
    "scientificName",
    "Taxonomic_status",
    "order",
    "family",
    "basisOfRecord",
    "decimalLatitude",
    "decimalLongitude"
  )
  for (col in required) {
    nd <- mk_native_detected("1", "native")
    nd[[col]] <- NULL
    expect_error(
      map_records(native_detected = nd),
      paste0("missing required column\\(s\\): ", col),
      info = col
    )
  }
})

test_that("precision must be a single positive integer", {
  nd <- mk_native_detected("1", "native")
  for (bad in list(0, -1, 2.5, NA_real_, "3", c(3, 4))) {
    expect_error(
      map_records(native_detected = nd, precision = bad),
      "`precision` must be a single positive integer",
      info = paste(deparse(bad), collapse = "")
    )
  }
})

test_that("cex must be a single positive number", {
  nd <- mk_native_detected("1", "native")
  for (bad in list(0, -1, NA_real_, "3", c(3, 3))) {
    expect_error(
      map_records(native_detected = nd, cex = bad),
      "`cex` must be a single positive number",
      info = paste(deparse(bad), collapse = "")
    )
  }
})

# --- Deduplication and record selection ------------------------------------

test_that("returns a mapview object", {
  map <- build_map(mk_native_detected("1", "native"))
  expect_s4_class(map, "mapview")
})

test_that("identical records in one cell collapse to a single point", {
  nd <- mk_native_detected(c("1", "2", "3"), rep("native", 3))
  pts <- pts_of(build_map(nd))
  expect_equal(nrow(pts), 1L)
  expect_equal(pts, data.frame(X = 10, Y = 60), tolerance = 1e-9)
})

test_that("native_status splits records inside the same cell", {
  nd <- mk_native_detected(
    c("1", "2", "3"),
    c("native", "introduced", "location_doubtful")
  )
  pts <- pts_of(build_map(nd))
  expect_equal(nrow(pts), 3L)
  expect_equal(pts,
               data.frame(X = c(10, 10, 10), Y = c(60, 60, 60)),
               tolerance = 1e-9)
})

test_that("species splits records inside the same cell", {
  nd <- mk_native_detected(
    c("1", "2"),
    rep("native", 2),
    name = c("Sp alpha", "Sp beta")
  )
  pts <- pts_of(build_map(nd))
  expect_equal(nrow(pts), 2L)
})

test_that("records in different cells are not deduplicated", {
  nd <- mk_native_detected(
    c("1", "2"),
    rep("native", 2),
    lon = c(10, 30),
    lat = c(60, 30)
  )
  pts <- pts_of(build_map(nd))
  expect_equal(nrow(pts), 2L)
  expect_equal(pts, data.frame(X = c(10, 30), Y = c(60, 30)), tolerance = 1e-9)
})

test_that("unknown status records are excluded", {
  nd <- mk_native_detected(c("1", "2"), c("native", "unknown"))
  pts <- pts_of(build_map(nd))
  expect_equal(nrow(pts), 1L)
  expect_equal(pts, data.frame(X = 10, Y = 60), tolerance = 1e-9)
})

test_that("coordinateless records are dropped before deduplication", {
  nd <- mk_native_detected(
    c("1", "2", "3"),
    rep("native", 3),
    lon = c(10, NA, 10),
    lat = c(60, 60, NA)
  )
  pts <- pts_of(build_map(nd))
  expect_equal(nrow(pts), 1L)
  expect_equal(pts, data.frame(X = 10, Y = 60), tolerance = 1e-9)
})

test_that("higher precision retains more points (finer cells)", {
  nd <- mk_native_detected(
    c("1", "2"),
    rep("native", 2),
    lon = c(10, 10.01),
    lat = c(60, 60.01)
  )
  expect_equal(nrow(pts_of(build_map(nd, precision = 3))), 1L)
  expect_equal(nrow(pts_of(build_map(nd, precision = 6))), 2L)
})

test_that("first record of each group is the representative point", {
  # No join is performed, so the row order of native_detected is preserved and
  # record "1" (at 10, 60) is the first row of the group.
  nd <- mk_native_detected(
    c("1", "2"),
    rep("native", 2),
    lon = c(10, 10.01),
    lat = c(60, 60.01)
  )
  pts <- pts_of(build_map(nd, precision = 3))
  expect_equal(nrow(pts), 1L)
  expect_equal(pts, data.frame(X = 10, Y = 60), tolerance = 1e-9)
})
