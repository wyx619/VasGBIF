#' @title Detect native status from country codes
#'
#' @description Assigns a native status classification to occurrence records
#' by matching their country code against WCVP distribution data (the internal
#' `Distributions` dataset) via WGSRPD Level 3 areas. The country code is mapped
#' to candidate Level 3 areas by the `Level3maping` table; no geometry is used.
#' The same flag priority as [detect_native_coord()] applies:
#'
#' 1. If `location_doubtful == 1`, the area is classified as
#'    `"location_doubtful"` regardless of other flags.
#' 2. Otherwise, if `introduced == 1`, the area is `"introduced"`.
#' 3. Otherwise, if `extinct == 1`, the area is `"extinct"`.
#' 4. If all three flags are `0`, the area is `"native"`.
#' 5. Any remaining case defaults to `"unknown"`.
#'
#' This stage needs no geometry, so it classifies every record handed to it,
#' including records that lack coordinates entirely. Records with validated
#' coordinates are better classified with [detect_native_coord()], whose spatial
#' match is more precise.
#'
#' @details
#' `L3 ISOcode` in `Level3maping` is reproduced as published and is **not** a
#' complete or one-to-one concordance. A single ISO code usually maps to
#' several Level 3 units (for example `CN` maps to eight), so a country code
#' identifies a *set* of candidate areas; a record is assigned the most
#' preferred status among the areas its taxon occurs in (`"native"` first).
#'
#' Every input record is returned. A record whose country code is missing or
#' empty, or maps to no Level 3 area, is kept with
#' `native_status_source = "unmatched"`; a record whose country maps to areas
#' but whose taxon has no distribution entry there is `"no_entry"`.
#'
#' **Input.** Any table-like object that [data.table::as.data.table()] can
#' convert is accepted - a `data.frame`, a `data.table`, a tibble, or a list of
#' equal-length columns - provided it carries the species and
#' country-code columns named by `species` and `country`. No coordinate column
#' is required. Pass the problematic-coordinate table (for example
#' `refined_coordinates$CoordinateProblematic`). If `input` has no `gbifID`, one
#' is created as a character sequence number. The column-name arguments are
#' independent of the data: a column that happens to share a name with one of
#' them (for example a `species` column) does not interfere, and
#' `species = "species"` is a valid way to select it.
#'
#' @param input A table holding one occurrence record per row, with the species
#'   and country-code columns named by `species` and `country`. Anything
#'   [data.table::as.data.table()] can convert is accepted. Typically the
#'   `CoordinateProblematic` table of a `CoordinateRefined` object returned by
#'   [par_clean_coordinates()]. Missing coordinates are allowed: no geometry is
#'   used.
#' @param species,country Names of the columns in `input` holding the species
#'   name and the country code. Default to the GBIF field names
#'   `"Accepted_name"` and `"countryCode"`.
#'
#' @returns A `nativeDetected` object - a `data.table` subclass with one row
#'   per input record (every row of `input`), keyed by `gbifID`. Every column of
#'   the input records is retained unchanged, with three classification columns
#'   appended:
#'
#' - `LEVEL3_COD`: the assigned WGSRPD Level 3 area code, or `NA` if the
#'   record could not be matched
#' - `native_status`: one of `"native"`, `"introduced"`, `"extinct"`,
#'   `"location_doubtful"`, or `"unknown"`
#' - `native_status_source`: `"country"` for a mapped hit; `"no_entry"` when the
#'   country mapped to areas but the taxon had no distribution entry there;
#'   `"unmatched"` when the record had no usable country code.
#'
#' The intermediate matching columns used internally (taxon keys, candidate
#' areas, match ranks) are not returned.
#'
#' @seealso [detect_native_coord()] for records with validated coordinates,
#'   [print.nativeDetected()] for a compact summary of the result.
#'
#' @examplesIf interactive() && exists("refined_coordinates")
#' # Classify the records that failed coordinate validation. `refined_coordinates`
#' # comes from `par_clean_coordinates()`, whose example creates it when run
#' # first.
#' native_country <- detect_native_country(
#'   refined_coordinates$CoordinateProblematic
#' )
#' native_country
#'
#' @import data.table
#' @importFrom dplyr %>%
#' @export
detect_native_country <- function(
  input = NA,
  species = "Accepted_name",
  country = "countryCode"
) {
  t1 <- Sys.time()

  # ---- validate the column names ----
  for (arg in c("species", "country")) {
    value <- get(arg)
    if (!is.character(value) || length(value) != 1L || is.na(value)) {
      stop("`", arg, "` must be a single column name.", call. = FALSE)
    }
  }
  if (anyDuplicated(c(species, country)) > 0L) {
    stop(
      "`species` and `country` must name two distinct columns.",
      call. = FALSE
    )
  }

  # `as.data.table()` returns a `data.table` unchanged, so `copy()` is what
  # actually keeps the column edit below from reaching the caller's table. Any
  # input it can convert is accepted: gating on `is.data.frame()` would turn
  # away a matrix or a list of equal-length columns that carries the needed
  # columns just as well.
  records <- tryCatch(
    data.table::copy(data.table::as.data.table(input)),
    error = function(e) {
      stop(
        "`input` could not be converted to a data.table: ",
        conditionMessage(e),
        call. = FALSE
      )
    }
  )

  missing_cols <- setdiff(c(species, country), names(records))
  if (length(missing_cols) > 0L) {
    stop(
      "`input` is missing required column(s): ",
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
    "native_status_source"
  )
  clashing_cols <- intersect(status_cols, names(records))
  if (length(clashing_cols) > 0L) {
    stop(
      "`input` already contains the classification column(s): ",
      paste(clashing_cols, collapse = ", "),
      ". Pass the output of `par_clean_coordinates()`, not an already-classified ",
      "table.",
      call. = FALSE
    )
  }

  # `gbifID` is the join key of the classification below and the key of the
  # result, but it is a GBIF field rather than a requirement of the method, so
  # an input without one gets a sequence number.
  if (!"gbifID" %in% names(records)) {
    records[, gbifID := as.character(seq_len(.N))]
    data.table::setcolorder(records, "gbifID")
  }

  # The species and country-code vectors are pulled out before the working table
  # is built: inside `[.data.table`, `j` is evaluated against the columns, so a
  # column named `species` or `country` would shadow the argument of the same
  # name and the lookup would silently address the wrong values.
  species_values <- records[[species]]
  country_values <- records[[country]]

  occurrences <- data.table(
    occurrence_id = seq_len(nrow(records)),
    gbifID = records[["gbifID"]],
    name_key = canonical_taxon_name(species_values),
    countryCode = country_values
  )

  lookup_keys <- unique(occurrences$name_key)
  lookup_keys <- lookup_keys[!is.na(lookup_keys)]
  native_distributions <- build_distribution_lookup(lookup_keys)

  message("Detecting native status by country code")

  # `countryCode` is mapped to the set of Level 3 areas carrying that ISO code
  # in `Level3maping`; many countries map to several areas, so every matching
  # area becomes a candidate and the preferred status wins (see
  # `adjudicate()`). Areas without an ISO code are stored as "" in the source
  # table, so both `NA` and "" codes are excluded and stay "unmatched".
  l3_by_iso <- unique(Level3maping[
    !is.na(`L3 ISOcode`) & `L3 ISOcode` != "",
    .(countryCode = `L3 ISOcode`, candidate_area = `L3 code`)
  ])

  occurrences[, `:=`(
    # `%chin%` never matches NA, so a record with a missing or empty code gets
    # `mapped = FALSE` and stays out of the candidate expansion below without
    # being dropped from the result.
    mapped = countryCode %chin% unique(l3_by_iso$countryCode),
    LEVEL3_COD = NA_character_,
    native_status = NA_character_,
    native_status_source = NA_character_
  )]

  country_candidates <- occurrences[mapped == TRUE][
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
    source := "country"
  ]

  resolved_country <- adjudicate(country_candidates)

  occurrences[
    resolved_country,
    `:=`(
      LEVEL3_COD = i.candidate_area,
      native_status = i.native_status,
      native_status_source = i.source
    ),
    on = "occurrence_id"
  ]

  occurrences[
    is.na(native_status),
    `:=`(
      native_status = "unknown",
      native_status_source = fifelse(
        mapped,
        "no_entry",
        "unmatched"
      )
    )
  ]

  status <- occurrences[, .(
    gbifID,
    LEVEL3_COD,
    native_status,
    native_status_source
  )]

  # Reattach the record columns. A status is only interpretable next to the
  # record it describes, and every consumer otherwise has to join back to
  # `input` to recover them.
  result <- merge(records, status, by = "gbifID")

  if (nrow(result) != nrow(status)) {
    stop(
      "Reattaching the record columns changed the row count (",
      nrow(status),
      " -> ",
      nrow(result),
      "); `gbifID` is not unique across `input`.",
      call. = FALSE
    )
  }

  # The output is keyed by `gbifID` so it stays sorted by `gbifID` with
  # `sorted = "gbifID"`, matching `detect_native_coord()`.
  setkey(result, gbifID)
  class(result) <- c("nativeDetected", class(result))
  used <- Sys.time() - t1
  message(paste('used', used %>% round(1), attributes(used)$units))

  result
}
