test_that("set_threads is exported", {
  expect_identical(getExportedValue("VasGBIF", "set_threads"), set_threads)
})

test_that("set_threads accepts an absolute thread count", {
  withr::local_envvar("_R_CHECK_LIMIT_CORES_" = "FALSE")
  total <- parallel::detectCores()
  requested <- min(2, total)

  expect_message(
    result <- set_threads(requested),
    paste0(requested, "/", total, " threads used"),
    fixed = TRUE
  )
  expect_identical(result, as.numeric(requested))
})

test_that("set_threads converts a proportion of available cores", {
  withr::local_envvar("_R_CHECK_LIMIT_CORES_" = "FALSE")
  total <- parallel::detectCores()
  expected <- round(total * 0.5)

  expect_message(
    result <- set_threads(0.5),
    paste0(expected, "/", total, " threads used"),
    fixed = TRUE
  )
  expect_identical(result, as.numeric(expected))
})

test_that("set_threads rounds numeric thread counts", {
  withr::local_envvar("_R_CHECK_LIMIT_CORES_" = "FALSE")
  skip_if(parallel::detectCores() < 2)

  expect_message(result <- set_threads(1.6), "2/", fixed = TRUE)
  expect_identical(result, 2)
})

test_that("set_threads rejects invalid inputs", {
  expect_snapshot(error = TRUE, set_threads("2"))
  expect_snapshot(error = TRUE, set_threads(0))
})

test_that("set_threads caps requests exceeding available cores", {
  withr::local_envvar("_R_CHECK_LIMIT_CORES_" = "FALSE")
  total <- parallel::detectCores()

  expect_message(
    result <- set_threads(total + 1),
    "x exceeds available threads; capping to"
  )
  expect_identical(result, as.numeric(total))
})

test_that("set_threads caps threads during R CMD check", {
  skip_on_cran()
  withr::local_envvar("_R_CHECK_LIMIT_CORES_" = "TRUE")

  expect_message(
    result <- set_threads(4),
    "R CMD check limits cores to 2; capping",
    fixed = TRUE
  )
  expect_identical(result, 2)
})
