#' @title Detect native status from WGSRPD distributions
#'
#' @description Assigns a native status classification to each occurrence
#' record by matching it against WCVP distribution data (the internal
#' `Distributions` dataset) via WGSRPD Level 3 areas. Classification uses only
#' the spatial stage: the records in `input` are overlaid on the WGSRPD Level 3
#' polygon map (via [terra::extract()]) to assign an area code to each record.
#' That area code is looked up in a distribution table classified from the
#' WCVP flags (`introduced`, `extinct`, `location_doubtful`) with the
#' following priority:
#'
#' 1. If `location_doubtful == 1`, the area is classified as
#'    `"location_doubtful"` regardless of other flags.
#' 2. Otherwise, if `introduced == 1`, the area is `"introduced"`.
#' 3. Otherwise, if `extinct == 1`, the area is `"extinct"`.
#' 4. If all three flags are `0`, the area is `"native"`.
#' 5. Any remaining case defaults to `"unknown"`.
#'
#' A record that falls in several areas at once is assigned the most preferred
#' status (`"native"` first). Unresolved records may be buffered (`buffer_km`)
#' so coastal points just outside a polygon can still be matched; buffered
#' hits are ranked below exact ones.
#'
#' Every record must carry a usable coordinate. Records without one are **not**
#' classified here; classify them with [detect_native_country()], which matches
#' them through their `countryCode` without using geometry.
#'
#' @details
#' **Coordinate reference system.** Both the occurrence points and the
#' internal `WGSRPD3` polygons are assumed to be in longitude/latitude
#' (EPSG:4326); the function asserts this on the polygon side. `buffer_km` is
#' applied as metres via [terra::buffer()]'s geodesic buffer, so it keeps the
#' same meaning at every latitude.
#'
#' **Input.** Any table-like object that [data.table::as.data.table()] can
#' convert is accepted - a `data.frame`, a `data.table`, a tibble, or a list of
#' equal-length columns - provided it carries the species and
#' coordinate columns named by `species`, `longitude` and `latitude`. It does
#' not have to come from [par_clean_coordinates()]. Pass the
#' validated-coordinate table (for example `refined_coordinates$CoordinateCleaned`)
#' so the records that failed coordinate validation are left to
#' [detect_native_country()] instead of being classified by geometry. If
#' `input` has no `gbifID`, one is created as a character sequence number. The
#' column-name arguments are independent of the data: a column that happens to
#' share a name with one of them (for example a `species` column) does not
#' interfere, and `species = "species"` is a valid way to select it.
#'
#' @param input A table holding one occurrence record per row, with the species
#'   and coordinate columns named by `species`, `longitude` and `latitude`.
#'   Anything [data.table::as.data.table()] can convert is accepted, so a
#'   `data.frame`, `data.table`, tibble or list of equal-length columns all
#'   work. Typically the `CoordinateCleaned` table of a `CoordinateRefined`
#'   object returned by [par_clean_coordinates()]. Every record must carry a
#'   non-missing coordinate.
#' @param species,longitude,latitude Names of the columns in `input` holding the
#'   species name and the coordinates. Default to the GBIF field names
#'   `"Accepted_name"`, `"decimalLongitude"` and `"decimalLatitude"`.
#' @param buffer_km Numeric scalar. Width of the spatial buffer in km applied
#'   to records the exact spatial match left unresolved. `0` disables the
#'   buffer. Defaults to `10`.
#' @param buffer_chunk_size Numeric scalar. Maximum number of records buffered
#'   in one chunk, keeping the relate matrix small. Defaults to `2000`.
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
#' - `native_status_source`: how the status was inferred. `"exact"` is a direct
#'   spatial match, `"buffered"` a match obtained through the geodesic buffer,
#'   and `"unmatched"` a record that matched no area at all.
#'
#' The intermediate matching columns used internally (taxon keys, candidate
#' areas, match ranks) are not returned. Because the record columns are
#' carried through, the result holds a second copy of the input data: for large
#' inputs, the input table can be dropped once the classification is in
#' hand.
#'
#' @seealso [detect_native_country()] for records without coordinates,
#'   [print.nativeDetected()] for a compact summary of the result.
#'
#' @examplesIf interactive() && exists("refined_coordinates")
#' # Classify the records with validated coordinates. `refined_coordinates`
#' # comes from `par_clean_coordinates()`, whose example creates it when run
#' # first.
#' native_coord <- detect_native_coord(refined_coordinates$CoordinateCleaned)
#' native_coord
#'
#' @import data.table
#' @importFrom dplyr %>%
#' @export
detect_native_coord <- function(
  input = NA,
  species = "Accepted_name",
  longitude = "decimalLongitude",
  latitude = "decimalLatitude",
  buffer_km = 10,
  buffer_chunk_size = 2000
) {
  t1 <- Sys.time()

  if (
    !is.numeric(buffer_km) ||
      length(buffer_km) != 1L ||
      is.na(buffer_km) ||
      buffer_km < 0
  ) {
    stop("`buffer_km` must be a single non-negative number.", call. = FALSE)
  }

  if (
    !is.numeric(buffer_chunk_size) ||
      length(buffer_chunk_size) != 1L ||
      is.na(buffer_chunk_size) ||
      buffer_chunk_size < 1
  ) {
    stop("`buffer_chunk_size` must be a single positive number.", call. = FALSE)
  }

  # ---- validate the input and resolve the column names ----
  for (arg in c("species", "longitude", "latitude")) {
    value <- get(arg)
    if (!is.character(value) || length(value) != 1L || is.na(value)) {
      stop("`", arg, "` must be a single column name.", call. = FALSE)
    }
  }
  if (anyDuplicated(c(species, longitude, latitude)) > 0L) {
    stop(
      "`species`, `longitude` and `latitude` must name three distinct columns.",
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

  missing_cols <- setdiff(c(species, longitude, latitude), names(records))
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

  # The overlay below assumes a coordinate for every record: a missing value
  # would become a point at an undefined location rather than a record that is
  # left unclassified. Records without usable coordinates belong to
  # `detect_native_country()`.
  n_missing_coord <- sum(
    is.na(records[[longitude]]) | is.na(records[[latitude]])
  )
  if (n_missing_coord > 0L) {
    stop(
      "`input` contains ",
      n_missing_coord,
      " record(s) with a missing coordinate; classify records without usable ",
      "coordinates with `detect_native_country()` instead.",
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

  # The species and coordinate vectors are pulled out before the working table
  # is built: inside `[.data.table`, `j` is evaluated against the columns, so a
  # column named `species` would shadow the `species` argument and the lookup
  # would silently address the wrong values.
  species_values <- records[[species]]
  longitude_values <- records[[longitude]]
  latitude_values <- records[[latitude]]

  # Fixed internal names for the working table, so the rest of the function -
  # and in particular the `terra` calls - never has to know what the input
  # called its columns.
  occurrences <- data.table(
    occurrence_id = seq_len(nrow(records)),
    gbifID = records[["gbifID"]],
    name_key = canonical_taxon_name(species_values),
    lon = longitude_values,
    lat = latitude_values
  )

  lookup_keys <- unique(occurrences$name_key)
  lookup_keys <- lookup_keys[!is.na(lookup_keys)]

  native_distributions <- build_distribution_lookup(lookup_keys)

  # The internal `WGSRPD3` polygons and the occurrence points are both lon/lat
  # (EPSG:4326); assert the polygon side so a future data change cannot
  # silently break the overlay.
  WGSRPD3map <- terra::vect(WGSRPD3)
  if (!terra::is.lonlat(WGSRPD3map)) {
    stop(
      "`WGSRPD3` polygons must be in a longitude/latitude CRS.",
      call. = FALSE
    )
  }

  message("Detecting native status")

  occurrence_points <- occurrences[, .(
    occurrence_id,
    lon,
    lat
  )] %>%
    terra::vect(
      geom = c("lon", "lat"),
      crs = "EPSG:4326"
    )

  extracted_areas <- terra::extract(
    WGSRPD3map[, "LEVEL3_COD"],
    occurrence_points
  ) %>%
    setDT()

  # The join below matches `extract()`'s `id.y` (a positional index into
  # `occurrence_points`) against `occurrence_id` (assigned from `.I`). The two
  # only agree because `occurrence_id` still equals the row number of
  # `occurrences`. Reordering or subsetting `occurrences` after construction
  # would break that silently -- wrong areas, no error -- so assert it.
  if (!identical(occurrences$occurrence_id, seq_len(nrow(occurrences)))) {
    stop(
      "`occurrence_id` must equal the row number of `occurrences` for the ",
      "spatial join to be valid; it is no longer a plain `.I` sequence.",
      call. = FALSE
    )
  }

  if (!setequal(extracted_areas$id.y, occurrences$occurrence_id)) {
    stop(
      "`terra::extract()` returned no candidate row for every occurrence: ",
      "`id.y` does not cover 1:",
      nrow(occurrences),
      ".",
      call. = FALSE
    )
  }

  # A point may lie in several WGSRPD areas at once (e.g. on a shared
  # boundary); keep every candidate area here and adjudicate below instead
  # of keeping the first one extract happens to return.
  setnames(extracted_areas, "id.y", "occurrence_id")
  setnames(extracted_areas, "LEVEL3_COD", "candidate_area")

  candidates <- occurrences[
    extracted_areas,
    .(occurrence_id, name_key, candidate_area),
    on = "occurrence_id"
  ]
  candidates[, `:=`(
    match_type = "exact",
    native_status = NA_character_,
    status_rank = NA_integer_,
    source = NA_character_
  )]

  # Attach distribution status to a candidate table by taxon name.
  link_status(candidates, "name_key", native_distributions)
  candidates[
    !is.na(native_status),
    source := "exact"
  ]

  resolved <- adjudicate(candidates)

  # Buffer pass: records that failed every exact candidate are turned into
  # buffer_km-wide disks and intersected with the WGSRPD areas, so coastal
  # records sitting just outside a polygon can still be assigned a status.
  # Buffered hits are ranked below exact ones, and only unresolved records
  # are processed, in chunks to keep the relate matrix small.
  if (buffer_km > 0) {
    unresolved <- occurrences[
      !occurrence_id %in% resolved$occurrence_id,
      .(occurrence_id, name_key, lon, lat)
    ]

    # A record whose taxon has no row at all in `native_distributions` cannot be
    # rescued by widening its geometry, so drop it before paying for `buffer()`
    # and `relate()`.
    known_keys <- unique(native_distributions$taxon_key)
    unresolved <- unresolved[name_key %chin% known_keys]

    if (nrow(unresolved) > 0) {
      message("Buffering ", nrow(unresolved), " unresolved records")

      # Never chunk larger than the number of records being buffered.
      chunk <- min(buffer_chunk_size, nrow(unresolved))
      buffer_candidates <- lapply(
        split(
          seq_len(nrow(unresolved)),
          ceiling(seq_len(nrow(unresolved)) / chunk)
        ),
        function(idx) {
          pts <- terra::vect(
            unresolved[idx, .(lon, lat)],
            geom = c("lon", "lat"),
            crs = "EPSG:4326"
          )
          # `terra::buffer()` interprets `width` in metres even for lon/lat
          # geometries (geodesic buffer), so `buffer_km` stays independent of
          # latitude.
          buf <- terra::buffer(pts, width = buffer_km * 1000)
          pairs <- which(
            terra::relate(buf, WGSRPD3map[, "LEVEL3_COD"], "intersects"),
            arr.ind = TRUE
          )
          if (!nrow(pairs)) {
            return(data.table(
              occurrence_id = integer(),
              candidate_area = character()
            ))
          }
          data.table(
            occurrence_id = unresolved$occurrence_id[idx[pairs[, 1]]],
            candidate_area = terra::values(WGSRPD3map)$LEVEL3_COD[pairs[, 2]]
          )
        }
      )
      buffered <- rbindlist(buffer_candidates)
      buffered[, `:=`(
        match_type = "buffered",
        native_status = NA_character_,
        status_rank = NA_integer_,
        source = NA_character_
      )]

      if (nrow(buffered) > 0) {
        buffered <- merge(
          buffered,
          unresolved[, .(occurrence_id, name_key)],
          by = "occurrence_id"
        )
        link_status(buffered, "name_key", native_distributions)
        buffered[
          !is.na(native_status),
          source := "buffered"
        ]
        resolved <- rbind(resolved, adjudicate(buffered))
      }
    }
  }

  # Initialise the output columns up front so an empty `resolved` (no record
  # matched any polygon) still leaves `occurrences` well-formed; rows without
  # a resolved hit keep these defaults and are filled below.
  occurrences[, `:=`(
    LEVEL3_COD = NA_character_,
    native_status = NA_character_,
    native_status_source = NA_character_
  )]

  occurrences[
    resolved,
    `:=`(
      LEVEL3_COD = i.candidate_area,
      native_status = i.native_status,
      native_status_source = i.source
    ),
    on = "occurrence_id"
  ]

  # An unmatched record is labelled the same way whether the buffer pass ran
  # and missed or was skipped as hopeless. That keeps the pre-buffer filter
  # unobservable: dropping records whose taxon has no row at all cannot change
  # any column of the output.
  occurrences[
    is.na(native_status),
    `:=`(
      native_status = "unknown",
      native_status_source = "unmatched"
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
  # `sorted = "gbifID"`, matching `detect_native_country()`.
  setkey(result, gbifID)
  class(result) <- c("nativeDetected", class(result))
  used <- Sys.time() - t1
  message(paste('used', used %>% round(1), attributes(used)$units))

  result
}
#' Normalise a taxon name for cross-source matching
#'
#' Maps the hybrid marker U+00D7 to the ASCII " x " used by TNRS, collapses
#' runs of whitespace, and trims the ends. Applied to both occurrence names
#' and (in `build_distribution_lookup()`) to distribution names so the two
#' sides compare on a common spelling.
#'
#' @param x A character vector of taxon names.
#'
#' @returns `x` with hybrid markers and whitespace normalised.
#'
#' @noRd
canonical_taxon_name <- function(x) {
  x %>%
    stri_replace_all_fixed("\u00d7", " x ") %>%
    stri_replace_all_regex("\\s+", " ") %>%
    stri_trim_both()
}

# Priority used to adjudicate between several candidate areas for one record:
# native first, unknown last. This is distinct from the within-area flag
# priority in `build_distribution_lookup()`.
native_status_priority <- c(
  "native",
  "introduced",
  "location_doubtful",
  "extinct",
  "unknown"
)

#' Build the classified distribution table for a set of taxon keys
#'
#' `Distributions` writes hybrids with U+00D7, TNRS returns an ASCII "x", so
#' the two sides must be compared through `canonical_taxon_name()`. The
#' distribution names are canonicalised here rather than rewriting occurrence
#' names into WCVP spelling: that rewrite is a lossy inverse -- it cannot
#' reproduce the leading marker of a nothogenus ("x Butyagrus" never becomes
#' the U+00D7 form), which silently dropped every genus-level hybrid before the
#' join could see it. Only the distinct names are canonicalised;
#' `Distributions` has far more rows than names.
#'
#' @param lookup_keys A character vector of canonical taxon keys.
#'
#' @returns A `data.table` with one row per `(taxon_key, area_code_l3)`:
#'   `taxon_key`, `area_code_l3`, `native_status`, `status_rank`.
#'
#' @noRd
build_distribution_lookup <- function(lookup_keys) {
  distribution_names <- unique(Distributions$taxon_name)
  matched_names <- data.table(
    taxon_name = distribution_names,
    taxon_key = canonical_taxon_name(distribution_names)
  )[taxon_key %chin% lookup_keys]

  nd <- Distributions[matched_names, on = "taxon_name", nomatch = NULL]
  nd[,
    native_status := fcase(
      location_doubtful == 1                                  , "location_doubtful" ,
      introduced == 1                                         , "introduced"        ,
      extinct == 1                                            , "extinct"           ,
      introduced == 0 & extinct == 0 & location_doubtful == 0 , "native"            ,
      default = "unknown"
    )
  ][, c("introduced", "extinct", "location_doubtful") := NULL]

  # One taxon may appear twice for the same area once hybrid spellings are
  # merged; keep the most preferred status (native first) so a join cannot
  # duplicate records. The same ordering is used downstream to adjudicate
  # points that fall in several WGSRPD areas at once.
  nd[, status_rank := chmatch(native_status, native_status_priority)]
  setorder(nd, taxon_key, area_code_l3, status_rank)
  unique(nd, by = c("taxon_key", "area_code_l3"))
}

#' Attach distribution status to candidate rows
#'
#' Updates candidate rows that are still unmatched, joining on the canonical
#' taxon key and a candidate area code. `source` is filled by the caller
#' afterwards so labels can differ between the spatial and country-code
#' stages.
#'
#' @param cand A candidate `data.table` with columns `occurrence_id`,
#'   `candidate_area`, `native_status`, `status_rank`, `source`.
#' @param key Column name in `cand` holding the canonical taxon key.
#' @param native_distributions The classified distribution table from
#'   `build_distribution_lookup()`.
#'
#' @returns `cand`, invisibly, modified in place.
#'
#' @noRd
link_status <- function(cand, key, native_distributions) {
  pool <- cand[is.na(native_status)]
  if (!nrow(pool)) {
    return(invisible(cand))
  }

  updates <- merge(
    pool[, .(occurrence_id, candidate_area, key_col = pool[[key]])],
    native_distributions[, .(
      taxon_key,
      area_code_l3,
      status = native_status,
      rank = status_rank
    )],
    by.x = c("key_col", "candidate_area"),
    by.y = c("taxon_key", "area_code_l3")
  )

  cand[
    updates,
    `:=`(
      native_status = i.status,
      status_rank = i.rank
    ),
    on = c("occurrence_id", "candidate_area")
  ]
  invisible(cand)
}

#' Reduce candidate rows to one status per occurrence
#'
#' Exact hits beat buffered ones, and within a match type the more preferred
#' status wins (native first, see `native_status_priority`); remaining ties
#' follow candidate order.
#'
#' @param cand A candidate `data.table` (see `link_status()`).
#'
#' @returns A `data.table` with one row per resolved `occurrence_id`:
#'   `occurrence_id`, `candidate_area`, `native_status`, `source`.
#'
#' @noRd
adjudicate <- function(cand) {
  cand[!is.na(native_status)][
    order(match_type != "exact", status_rank)
  ][
    !duplicated(occurrence_id)
  ][, .(
    occurrence_id,
    candidate_area,
    native_status,
    source
  )]
}

#' Print a `nativeDetected` object
#'
#' Displays a compact summary of a native status classification: the number of
#' records, and the counts by `native_status` and by `native_status_source`.
#' The records themselves are not shown; use [head()] or `View()` to inspect
#' them.
#'
#' @param x An object of class `"nativeDetected"` returned by
#'   [detect_native_coord()] or [detect_native_country()].
#' @param ... Additional arguments (unused, retained for S3 compatibility).
#'
#' @return Invisibly returns `x`.
#'
#' @export
print.nativeDetected <- function(x, ...) {
  # A subset of a nativeDetected object may have lost the classification
  # columns (e.g. `x[, .(gbifID)]`); fall back to the plain data.table print
  # rather than failing on the summary lookup.
  if (!all(c("native_status", "native_status_source") %chin% names(x))) {
    class_orig <- class(x)
    setattr(x, "class", c("data.table", "data.frame"))
    on.exit(setattr(x, "class", class_orig), add = TRUE)
    print(x, ...)
    return(invisible(x))
  }

  status_counts <- x[,
    .N,
    by = native_status
  ][
    order(factor(native_status, levels = native_status_priority))
  ]
  source_counts <- x[,
    .N,
    by = native_status_source
  ][
    order(native_status_source)
  ]

  cat("<nativeDetected> ", nrow(x), " records", sep = "")
  if (!is.null(key(x))) {
    cat(" (keyed by ", paste(key(x), collapse = ", "), ")", sep = "")
  }
  cat("\n\nnative_status:\n")
  # The count tables inherit the `nativeDetected` class from
  # `x[, .N, by = ...]`; strip it so `print()` dispatches to
  # `print.data.table` instead of recursing into this method.
  setattr(status_counts, "class", c("data.table", "data.frame"))
  print(status_counts)
  cat("\nnative_status_source:\n")
  setattr(source_counts, "class", c("data.table", "data.frame"))
  print(source_counts)

  invisible(x)
}
