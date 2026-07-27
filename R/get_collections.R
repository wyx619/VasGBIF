#' @title Generate collection event keys from taxon name, date, and coordinates
#'
#' @description Builds a composite key for each occurrence record by combining the
#' accepted taxon name from [check_taxon()], the collection date, and the rounded
#' geographic coordinates. Records sharing the same key are likely to represent
#' the same collection event and can be treated as duplicates.
#'
#' @param occ_import An `import` object returned by [import_records()].
#' @param taxa_checked A `occ_taxa` object returned by
#'   [check_taxon()], used to supply the accepted taxon name for each
#'   record.
#' @param precision Integer number of decimal places used to round latitude and
#'   longitude when constructing the spatial portion of the key. This indirectly
#'   controls the spatial tolerance for treating two records as the same
#'   collection event. Typical choices:
#'   - `1`: ~10 km
#'   - `2`: ~1 km (default)
#'   - `3`: ~100 m
#'   - `4`: ~10 m
#'
#'   The default of `2` balances the fact that GBIF coordinates are often
#'   recorded to 5 decimal places (~1 m) whereas the accompanying
#'   `coordinateUncertaintyInMeters` is commonly around 500 m, making
#'   sub-100 m grouping unreliable without additional filtering.
#'
#' @details
#' ## Key construction
#'
#' The collection key is a pipe-delimited string with four components:
#'
#' ```
#' wcvp_taxon_name | eventDate_numeric | rounded_latitude | rounded_longitude
#' ```
#'
#' - `wcvp_taxon_name`: the accepted taxon name from `taxa_checked`.
#' - `eventDate_numeric`: the `eventDate` field with time-of-day and ISO
#'   separators removed, parsed as a date with [lubridate::parse_date_time()]
#'   (accepting truncated `ymd` orders), and converted to a numeric value.
#' - `rounded_latitude` and `rounded_longitude`: `decimalLatitude` and
#'   `decimalLongitude` rounded to `precision` decimal places.
#'
#' Any component that ends up as `NA` produces an incomplete key.
#'
#' ## Choosing precision
#'
#' GBIF occurrence records often carry coordinates at 5 decimal places (~1 m
#' at the equator) alongside a `coordinateUncertaintyInMeters` field that
#' typically ranges from tens to hundreds of metres. Rounding coordinates via
#' `precision` lets you define a spatial tolerance appropriate for your data
#' quality expectations, effectively deciding how close two records must be to
#' share a key.
#'
#' ## Key classification
#'
#' Keys are considered **complete** when all four components are non-missing.
#' Keys containing `NA` in at least one position (detected by the pattern
#' `(^|\\|)NA(\\||$)`) are counted as **incomplete**.
#'
#' @returns A list of class `"collections"` with four elements:
#'
#' - `occ_key`: a `data.table` of the occurrence records with an added
#'   `collection_key` column.
#' - `complete_keys`: the number of distinct complete keys.
#' - `incomplete_keys`: the number of distinct incomplete keys (those with at
#'   least one `NA` component).
#' - `runtime`: the elapsed execution time.
#'
#' @import data.table
#' @importFrom dplyr %>%
#' @import stringi
#' @importFrom lubridate parse_date_time as_date
#' @seealso [set_vouchers()], which consumes the output of this function.
#' @examplesIf interactive()
#' collection_keys <- get_collections(
#'   occ_import = occ_import,
#'   taxa_checked = taxa_checked,
#'   precision = 2
#' )
#' @export
get_collections <- function(
  occ_import = NA,
  taxa_checked = NA,
  precision = 2L
) {
  stopifnot(
    is.numeric(precision) &&
      length(precision) == 1L &&
      !is.na(precision) &&
      is.finite(precision) &&
      precision > 0 &&
      precision == floor(precision)
  )
  start <- Sys.time()

  occ <- occ_import$occ %>% setDT()

  occ <- merge(
    occ,
    taxa_checked$occ_taxa_checked[, .(gbifID, wcvp_taxon_name)],
    by = "gbifID",
    all.x = TRUE
  )

  occ[,
    collection_key := paste(
      wcvp_taxon_name,
      eventDate %>%
        stri_replace_first_regex("[T/].*$", "") %>%
        parse_date_time(orders = "ymd", truncated = 2, quiet = TRUE) %>%
        as_date() %>%
        as.numeric(),
      decimalLatitude %>% round(digits = precision),
      decimalLongitude %>% round(digits = precision),
      sep = "|"
    )
  ]

  summary <- occ[, .N, by = collection_key][order(-N)]
  incomplete_keys <- summary[
    collection_key %>% stri_detect_regex("(^|\\|)NA(\\||$)"),
    .N
  ]
  complete_keys <- nrow(summary) - incomplete_keys

  end <- Sys.time()
  used <- end - start
  message(paste('used', used %>% round(1), attributes(used)$units))
  collection_keys <- list(
    occ_key = occ,
    complete_keys = complete_keys,
    incomplete_keys = incomplete_keys,
    runtime = end - start
  )
  class(collection_keys) <- 'collections'
  return(collection_keys)
}
