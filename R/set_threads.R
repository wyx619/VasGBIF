#' Normalize the number of worker threads
#'
#' Converts either an absolute thread count or a proportion of available CPU
#' cores into an integer number of worker threads. The number of available cores
#' is determined by [parallel::detectCores()].
#'
#' @param x A numeric scalar. Values greater than or equal to `1` specify an
#'   absolute number of threads and are rounded to the nearest integer. Values
#'   strictly between `0` and `1` specify a proportion of available cores; the
#'   resulting number of threads is also rounded to the nearest integer.
#'
#' @return An integer-like numeric scalar giving the normalized number of worker
#'   threads. A message reports the selected and available thread counts.
#'
#' @details
#' Absolute thread counts exceeding the number of cores reported by
#' [parallel::detectCores()] are silently capped to that limit with a message.
#' Values less than or equal to zero and non-numeric inputs produce an error.
#'
#' During `R CMD check` (when the environment variable `_R_CHECK_LIMIT_CORES_`
#' is set to `"TRUE"`), threads are capped to a maximum of 2 to comply with the
#' check environment limit on parallel processes.
#'
#' This function is also used by [refine_records()] to normalize its `threads`
#' argument.
#'
#' @seealso [parallel::detectCores()], [refine_records()]
#' @export
#'
#' @examples
#' set_threads(1)
#' set_threads(0.5)
set_threads <- function(x) {
  total <- parallel::detectCores()
  if (!is.numeric(x)) {
    stop("input must be numeric")
  }

  if (isTRUE(as.logical(Sys.getenv("_R_CHECK_LIMIT_CORES_", "FALSE")))) {
    if (x > 2) {
      message("R CMD check limits cores to 2; capping")
      x <- 2
    }
    total <- min(total, 2L)
  }

  if (x > total) {
    message("x exceeds available threads; capping to ", total)
    x <- total
  }

  if (x >= 1) {
    message(paste0(round(x), "/", total, " ", "threads used"))
    return(round(x))
  }

  if (x <= 0) {
    stop("illegal !!!")
  }

  if (0 < x && x < 1) {
    message(paste0(round(total * x)), "/", total, " ", "threads used")
    return(round(total * x))
  }
}
