#' @title Export classified records to compressed CSV files
#'
#' @description Writes the results of [detect_native_coord()] and/or
#'   [detect_native_country()] to disk as gzip-compressed CSV files. Each
#'   classification supplied produces two files: all of its classified records
#'   and the native subset.
#'
#' @param native_detected_coord A `nativeDetected` object returned by
#'   [detect_native_coord()], containing records with validated coordinates. It
#'   must carry `gbifID`, `native_status`, `decimalLongitude` and
#'   `decimalLatitude`, and none of its coordinates may be missing. Optional,
#'   but at least one of `native_detected_coord` and `native_detected_country`
#'   must be supplied.
#' @param native_detected_country A `nativeDetected` object returned by
#'   [detect_native_country()], containing the records classified through their
#'   `countryCode`. It must carry `gbifID` and `native_status`; missing
#'   coordinates are allowed. Optional, but at least one of the two
#'   classification arguments must be supplied.
#' @param export_path Directory where the compressed CSV files should be written.
#'
#' @returns Called for its side effect of writing files to `export_path`. Returns
#'   `NULL` invisibly.
#'
#' @details
#' Each classification supplied is written as its own pair of files, so the two
#' sets never overwrite each other:
#'
#' - `all_records_coord.csv.gz`: every record classified by
#'   [detect_native_coord()], with all its columns and its native status
#' - `native_records_coord.csv.gz`: the subset of those records classified as
#'   `"native"`
#' - `all_records_country.csv.gz`: every record classified by
#'   [detect_native_country()], with all its columns and its native status
#' - `native_records_country.csv.gz`: the subset of those records classified as
#'   `"native"`
#'
#' Only the pair belonging to a supplied argument is written, so supplying one
#' argument leaves the files of the other untouched. The two sets are exported
#' separately rather than bound together: this function never writes a combined
#' table.
#'
#' The two `all_records_*` files are likewise not a partition of a single input
#' and cannot be row-bound with each other. They carry different columns - the
#' coordinate result comes from `CoordinateCleaned`, whereas the country-code
#' result comes from `CoordinateProblematic`, which keeps its per-test verdict
#' columns - and [detect_native_country()] classifies only the records it
#' receives with a usable `countryCode`.
#'
#' Both arguments already carry every column of the input records, so no join is
#' performed here: each table is written straight from the object.
#'
#' `native_detected_coord` must carry coordinates for every record: it is the
#' spatial output of [detect_native_coord()], which only classifies records with
#' validated coordinates. The function stops if `decimalLongitude` or
#' `decimalLatitude` is missing for any of its records, which catches the two
#' arguments being swapped. `native_detected_country` carries no such
#' requirement, because [detect_native_country()] classifies the records that
#' failed coordinate validation - including records whose coordinates are
#' entirely absent.
#'
#' Files are written with `fwrite(encoding = "UTF-8")`. `export_path` is
#' validated before writing: if it is not a single character path or exists as
#' a file (not a directory), the function stops with an error; if it does not
#' exist, a warning is emitted and the directory is created automatically.
#'
#' @import data.table
#' @seealso [detect_native_coord()], [detect_native_country()],
#'   [par_clean_coordinates()]
#' @export
export_records <- function(
  native_detected_coord = NA,
  native_detected_country = NA,
  export_path = NA
) {
  # ---- validate inputs ----
  # A default of `NA` is how an omitted argument presents itself; `NULL` is
  # accepted as "omitted" too so an explicitly absent value works as well.
  is_absent <- function(x) {
    is.null(x) || (is.atomic(x) && length(x) == 1L && is.na(x))
  }

  coord_supplied <- !is_absent(native_detected_coord)
  country_supplied <- !is_absent(native_detected_country)

  if (!coord_supplied && !country_supplied) {
    stop(
      "Supply at least one of `native_detected_coord` or ",
      "`native_detected_country`.",
      call. = FALSE
    )
  }

  if (coord_supplied) {
    check_native_detected(
      native_detected_coord,
      arg_name = "native_detected_coord",
      producer = "detect_native_coord()",
      required_cols = c(
        "gbifID",
        "native_status",
        "decimalLongitude",
        "decimalLatitude"
      )
    )

    # The spatial stage classifies records with validated coordinates only, so a
    # `native_detected_coord` carrying missing coordinates is a misuse (a
    # country-code result passed in the wrong argument), not a legitimate input.
    n_missing_coord <- sum(
      is.na(native_detected_coord[["decimalLongitude"]]) |
        is.na(native_detected_coord[["decimalLatitude"]])
    )
    if (n_missing_coord > 0L) {
      stop(
        "`native_detected_coord` contains ",
        n_missing_coord,
        " record(s) with missing coordinates; it must be the output of ",
        "`detect_native_coord()`, which carries coordinates for every record.",
        call. = FALSE
      )
    }
  }

  if (country_supplied) {
    check_native_detected(
      native_detected_country,
      arg_name = "native_detected_country",
      producer = "detect_native_country()",
      required_cols = c("gbifID", "native_status")
    )
  }

  # ---- validate export path ----
  if (
    !is.character(export_path) || length(export_path) != 1 || is.na(export_path)
  ) {
    stop("export_path must be a single directory path, not NA")
  }

  if (dir.exists(export_path)) {
    # directory already exists - proceed
  } else if (file.exists(export_path)) {
    stop("export_path exists but is a file, not a directory: ", export_path)
  } else {
    warning("export_path does not exist, creating: ", export_path)
    dir.create(export_path, recursive = TRUE)
  }

  # ---- write ----
  tryCatch(
    {
      message("Exporting records")
      if (coord_supplied) {
        write_native_group(
          native_detected_coord,
          label = "Records with validated coordinates",
          suffix = "coord",
          export_path = export_path
        )
      }
      if (country_supplied) {
        write_native_group(
          native_detected_country,
          label = "Records classified by country code",
          suffix = "country",
          export_path = export_path
        )
      }
      message("Done")
    },
    error = function(e) {
      stop("File export failed: ", e$message)
    }
  )
}

#' Check one `nativeDetected` argument of [export_records()]
#'
#' Confirms the argument is a `nativeDetected` object and carries the columns
#' the export needs, so a misuse is reported against the argument name that was
#' actually passed rather than surfacing later as a `data.table` error.
#'
#' @param x The object supplied for the argument.
#' @param arg_name Name of the argument, used in the error message.
#' @param producer Name of the function that produces a valid `x`, used in the
#'   error message.
#' @param required_cols Columns `x` must carry.
#'
#' @returns `NULL`, invisibly; called for its errors.
#'
#' @noRd
check_native_detected <- function(x, arg_name, producer, required_cols) {
  if (!inherits(x, "nativeDetected")) {
    stop(
      "`",
      arg_name,
      "` must be a \"nativeDetected\" object from ",
      producer,
      ".",
      call. = FALSE
    )
  }

  missing_cols <- setdiff(required_cols, names(x))
  if (length(missing_cols) > 0L) {
    stop(
      "`",
      arg_name,
      "` is missing required column(s): ",
      paste(missing_cols, collapse = ", "),
      call. = FALSE
    )
  }

  invisible(NULL)
}

#' Write one classification group to compressed CSV files
#'
#' Writes the group's records and its `"native"` subset to `export_path`, naming
#' the two files with `suffix` so several groups can share a directory.
#'
#' @param records A `nativeDetected` table to write.
#' @param label Human-readable name of the group, used in the messages.
#' @param suffix Suffix distinguishing this group's file names.
#' @param export_path Directory to write to.
#'
#' @returns `NULL`, invisibly; called for its side effects.
#'
#' @noRd
write_native_group <- function(records, label, suffix, export_path) {
  message(paste0(label, ": ", records[, .N], " records finally left"))

  native_records <- records[native_status == "native", ]

  message(paste0(label, ": ", native_records[, .N], " of them are native"))

  fwrite(
    records,
    file = file.path(export_path, paste0("all_records_", suffix, ".csv.gz")),
    encoding = "UTF-8"
  )
  fwrite(
    native_records,
    file = file.path(export_path, paste0("native_records_", suffix, ".csv.gz")),
    encoding = "UTF-8"
  )

  invisible(NULL)
}
