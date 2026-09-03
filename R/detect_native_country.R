#' @title Detect native status from country codes
#'
#' @description Assigns a native status classification to occurrence records
#' that lack usable coordinates by matching their `countryCode` against WCVP
#' distribution data (the internal `Distributions` dataset) via WGSRPD Level 3
#' areas. `countryCode` is mapped to candidate Level 3 areas by the
#' `Level3maping` table; no geometry is used. The same flag priority as
#' [detect_native_coord()] applies:
#'
#' 1. If `location_doubtful == 1`, the area is classified as
#'    `"location_doubtful"` regardless of other flags.
#' 2. Otherwise, if `introduced == 1`, the area is `"introduced"`.
#' 3. Otherwise, if `extinct == 1`, the area is `"extinct"`.
#' 4. If all three flags are `0`, the area is `"native"`.
#' 5. Any remaining case defaults to `"unknown"`.
#'
#' All records from `CoordinateProblematic` are classified, including both
#' records that lack coordinates (missing longitude or latitude) and records
#' with complete coordinates that failed validation tests. Records from
#' `CoordinateCleaned` (those that passed validation) should be classified
#' using [detect_native_coord()] instead.
#'
#' @details
#' `L3 ISOcode` in `Level3maping` is reproduced as published and is **not** a
#' complete or one-to-one concordance. A single ISO code usually maps to
#' several Level 3 units (for example `CN` maps to eight), so a country code
#' identifies a *set* of candidate areas; a record is assigned the most
#' preferred status among the areas its taxon occurs in (`"native"` first).
#' Records whose country code is missing or empty, or maps to no Level 3
#' area, stay `"unmatched"`; records whose country maps to areas but whose
#' taxon has no distribution entry there are `"country_code_no_entry"`.
#'
#' @param cleaned_coordinates A `CoordinateRefined` object returned by
#'   [clean_coordinates()]. All records from `CoordinateProblematic` are
#'   classified, including both coordinateless records and records that failed
#'   coordinate validation tests.
#'
#' @returns A `nativeDetected` object - a `data.table` subclass with one row
#' @returns A `nativeDetected` object - a `data.table` subclass with one row
#'   per record from `CoordinateProblematic`
#'   (`cleaned_coordinates$CoordinateProblematic`), keyed by `gbifID`. Every
#'   column of the input:
#'
#' - `LEVEL3_COD`: the assigned WGSRPD Level 3 area code, or `NA` if the
#'   record could not be matched
#' - `native_status`: one of `"native"`, `"introduced"`, `"extinct"`,
#'   `"location_doubtful"`, or `"unknown"`
#' - `native_status_source`: `"country_code"` for a mapped hit;
#'   `"country_code_no_entry"` when the country mapped to areas but the taxon
#'   had no distribution entry there; `"unmatched"` when the record had no
#'   usable country code.
#' - `buffered`: always `FALSE`; no geometry is used.
#'
#' The intermediate matching columns used internally (taxon keys, candidate
#' areas, match ranks) are not returned.
#'
#' @seealso [detect_native_coord()] for records with validated coordinates,
#'   [print.nativeDetected()] for a compact summary of the result.
#' @examplesIf interactive() && exists("cleaned_coordinates")
#' # Classify the coordinate-less records. `cleaned_coordinates` comes from
#' # `clean_coordinates()`, whose example creates it when run first.
#' native_country <- detect_native_country(cleaned_coordinates = cleaned_coordinates)
#' native_country <- detect_native_country(customized_filtered = filtered)
#' native_country
#'
#' @import data.table
#' @importFrom dplyr %>%
#' @export
detect_native_country <- function(cleaned_coordinates = NA) {
  t1 <- Sys.time()

  if (!inherits(cleaned_coordinates, "CoordinateRefined")) {
    stop(
      '`cleaned_coordinates` must be a "CoordinateRefined" object from clean_coordinates().',
      call. = FALSE
    )
  }

  CoordinateProblematic <- cleaned_coordinates$CoordinateProblematic

  required_cols <- c(
    "gbifID",
    "Accepted_name",
    "countryCode",
    "decimalLongitude",
    "decimalLatitude"
  )
  missing_cols <- setdiff(required_cols, names(CoordinateProblematic))
  if (length(missing_cols) > 0L) {
    stop(
      "`cleaned_coordinates$CoordinateProblematic` is missing required column(s): ",
      paste(missing_cols, collapse = ", "),
      call. = FALSE
    )
  }

  # The input columns are carried into the result, so a name that collides with
  # a classification column would be silently renamed by the final join. This
  # happens if an already-classified table is passed back in.
  status_cols <- c(
    "LEVEL3_COD",
    "native_status",
    "native_status_source",
    "buffered"
  )
  clashing_cols <- intersect(status_cols, names(CoordinateProblematic))
  if (length(clashing_cols) > 0L) {
    stop(
      "`cleaned_coordinates$CoordinateProblematic` already contains the classification ",
      "column(s): ",
      paste(clashing_cols, collapse = ", "),
      ". Pass the output of `cleaned_coordinates()`, not an already-classified ",
      "table.",
      call. = FALSE
    )
  }

  Problematic <- CoordinateProblematic[countryCode != '', ]

  message("Detecting native status by country code")

  records <- Problematic[, .(
    gbifID,
    name_key = canonical_taxon_name(Accepted_name),
    countryCode
  )]

  lookup_keys <- unique(records$name_key)
  lookup_keys <- lookup_keys[!is.na(lookup_keys)]
  native_distributions <- build_distribution_lookup(lookup_keys)

  # `countryCode` is mapped to the set of Level 3 areas carrying that ISO code
  # in `Level3maping`; many countries map to several areas, so every matching
  # area becomes a candidate and the preferred status wins (see
  # `adjudicate()`). Areas without an ISO code are stored as "" in the source
  # table, so both `NA` and "" codes are excluded and stay "unmatched".
  l3_by_iso <- unique(Level3maping[
    !is.na(`L3 ISOcode`) & `L3 ISOcode` != "",
    .(countryCode = `L3 ISOcode`, candidate_area = `L3 code`)
  ])

  records[, `:=`(
    occurrence_id = .I,
    # `%chin%` never matches NA, so records without a usable country code are
    # excluded from the candidate expansion below.
    mapped = countryCode %chin% unique(l3_by_iso$countryCode),
    LEVEL3_COD = NA_character_,
    native_status = NA_character_,
    native_status_source = NA_character_,
    buffered = FALSE
  )]

  country_candidates <- records[mapped == TRUE][
    l3_by_iso,
    on = "countryCode",
    .(occurrence_id, name_key, candidate_area),
    allow.cartesian = TRUE
  ]
  country_candidates[, `:=`(
    match_type = "exact",
    native_status = NA_character_,
    status_rank = NA_integer_,
    source = NA_character_
  )]

  link_status(country_candidates, "name_key", native_distributions)
  country_candidates[
    !is.na(native_status),
    source := "country_code"
  ]

  resolved_country <- adjudicate(country_candidates)

  records[
    resolved_country,
    `:=`(
      LEVEL3_COD = i.candidate_area,
      native_status = i.native_status,
      native_status_source = i.source,
      buffered = i.buffered
    ),
    on = "occurrence_id"
  ]

  records[
    is.na(native_status),
    `:=`(
      native_status = "unknown",
      native_status_source = fifelse(
        mapped,
        "country_code_no_entry",
        "unmatched"
      ),
      buffered = FALSE
    )
  ]

  status <- records[, .(
    gbifID,
    LEVEL3_COD,
    native_status,
    native_status_source,
    buffered
  )]

  # Reattach the record columns. A status is only interpretable next to the
  # record it describes, and every consumer otherwise has to join back to
  # `customized_filtered` to recover them.
  result <- merge(Problematic, status, by = "gbifID")

  if (nrow(result) != nrow(status)) {
    stop(
      "Reattaching the record columns changed the row count (",
      nrow(status),
      " -> ",
      nrow(result),
      "); `gbifID` is not unique in `customized_filtered$occ_filtered`.",
      call. = FALSE
    )
  }

  # The output is keyed by `gbifID` so the returned table stays sorted by
  # `gbifID` with `sorted = "gbifID"`, matching `detect_native_coord()`.
  setkey(result, gbifID)
  class(result) <- c("nativeDetected", class(result))
  used <- Sys.time() - t1
  message(paste('used', used %>% round(1), attributes(used)$units))

  result
}
