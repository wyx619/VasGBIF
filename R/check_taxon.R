#' Resolve taxon names via the Taxonomic Name Resolution Service
#'
#' Submits plant scientific names from a GBIF occurrence table to the
#' Taxonomic Name Resolution Service ('TNRS') and resolves them against the
#' World Checklist of Vascular Plants ('WCVP') or World Flora Online ('WFO'),
#' depending on `sources` (default `"wcvp"`). Spelling errors are corrected,
#' variant spellings are standardised, and synonyms are converted to their
#' currently accepted names. Only records that meet the `accuracy` threshold,
#' have an accepted or synonym `Taxonomic_status`, and resolve to an accepted
#' name at species rank or below are returned in `occ_taxa_checked`.
#'
#' @param occ_import An `"import"` `data.table` returned by [import_records()],
#'   containing at least the columns `gbifID`, `scientificName`, and
#'   `taxonRank`.
#' @param accuracy Numeric scalar between `0` and `1`. Minimum 'TNRS' match
#'   score for a resolution to be accepted. Defaults to `0.85`. Records whose
#'   `Overall_score` falls below this threshold are excluded from
#'   `occ_taxa_checked`. Passed directly to [TNRS::TNRS()].
#' @param sources Character vector naming the taxonomic sources to resolve
#'   against. Defaults to `"wcvp"` (World Checklist of Vascular Plants).
#'   `"wfo"` (World Flora Online) is also accepted. Multiple
#'   sources can be combined, e.g. `c("wcvp", "wfo")`; the 'TNRS' API then
#'   returns the best match across all selected sources and the `Source`
#'   column records which source provided it. Passed directly to [TNRS::TNRS()].
#' @param timeout_minutes Numeric scalar. Timeout per 'TNRS' chunk attempt in
#'   minutes. Defaults to `20`. If an attempt exceeds the timeout it is
#'   abandoned and retried.
#'
#' @details
#' ## Taxon rank filtering
#'
#' Only records whose `taxonRank` is one of `"SPECIES"`, `"VARIETY"`,
#' `"SUBSPECIES"`, or `"FORM"` are submitted to 'TNRS'. Records at genus rank
#' or above are excluded from the query and are absent from both `summary`
#' and `occ_taxa_checked`.
#'
#' This check filters on the `taxonRank` reported by GBIF for the submitted
#' record. It is distinct from the output-side check on `Accepted_name_rank`
#' described under "Output filtering", which filters on the rank of the
#' *resolved* accepted name returned by 'TNRS'.
#'
#' ## Chunked submission
#'
#' Unique names are submitted in chunks of up to 4,000 to respect 'TNRS' API
#' limits. Each name is assigned a row identifier before chunking, so the
#' identifiers stay unique across the whole query. Results from all chunks are
#' combined with [data.table::rbindlist()] and then de-duplicated by `ID`,
#' guarding against occasional duplicate rows returned by the API.
#'
#' ## Joining results back to occurrences
#'
#' 'TNRS' does not echo submitted names verbatim: commas are replaced by
#' spaces and diacritics are normalised, so `Name_submitted` in the response
#' may differ from the string that was sent. Results are therefore joined back
#' to the occurrence table through the row identifier echoed in the `ID`
#' column, which maps each result to the exact `scientificName` submitted.
#'
#' ## Output filtering
#'
#' After merging 'TNRS' results back into the occurrence table, only records
#' satisfying **all** of the following conditions are kept in
#' `occ_taxa_checked`:
#'
#' - `Overall_score >= accuracy`
#' - `Taxonomic_status` is `"Accepted"` or `"Synonym"`
#' - `Accepted_name_rank` is neither empty nor `"genus"`
#'
#' The rank condition excludes records whose best match only reached a
#' genus-level or unranked accepted name, even when the score and status
#' would pass. Records that fail any condition (unresolved names,
#' low-confidence matches, names with uncertain status, or genus-level
#' resolutions) are present in `summary` for manual review but absent from
#' `occ_taxa_checked`.
#'
#' ## Retry logic
#'
#' Each chunk is attempted up to three times. An attempt that exceeds
#' `timeout_minutes` or that returns no rows is abandoned and retried, with a
#' five-second pause between attempts, guarding against transient network
#' failures. If all attempts fail for a chunk, the function stops with an
#' informative error.
#'
#' @returns An object of class `"occ_taxa"`, implemented as a named list with
#'   three elements:
#'
#' * `occ_taxa_checked`: a `data.table` of occurrence records that passed the
#'   `accuracy` threshold and have an `"Accepted"` or `"Synonym"`
#'   `Taxonomic_status`. Columns from `occ_import` (`gbifID`,
#'   `scientificName`) are joined with the following 'TNRS' result columns:
#'   `Overall_score`, `Taxonomic_status`, `Accepted_name`, `Accepted_species`,
#'   `Accepted_name_id`, `Accepted_name_rank`, `Accepted_family`, `Source`.
#' * `summary`: a `data.table` of unique 'TNRS' resolution results (one row
#'   per submitted name), useful for reviewing match quality and identifying
#'   names that require manual attention. `scientificName` holds the string as
#'   submitted, while `Name_submitted` holds the possibly rewritten form
#'   echoed by 'TNRS'; comparing the two exposes names the API altered.
#' * `runtime`: a `difftime` object recording the total elapsed time.
#'
#' @seealso
#' * [import_records()] for the first step that produces the `occ_import`
#'   input.
#' * [extract_gbif_issues()] for the parallel step that processes issue flags.
#' * [TNRS::TNRS()] for the underlying name resolution function.
#' * [print.occ_taxa()] for a compact summary of the result.
#'
#' @references
#' Boyle, B. et al. (2013). The taxonomic name resolution service: an online
#' tool for automated standardisation of plant names. *BMC Bioinformatics*,
#' 14, 16. \doi{10.1186/1471-2105-14-16}
#'
#' Govaerts, R. et al. (2021). The World Checklist of Vascular Plants, a
#' continuously updated resource for exploring global plant diversity.
#' *Scientific Data*, 8, 215. \doi{10.1038/s41597-021-00997-6}
#'
#' @importFrom dplyr %>%
#' @import data.table
#' @import stringi
#' @import TNRS
#'
#' @examplesIf interactive()
#' gbif_file <- system.file(
#'   "extdata",
#'   "0003386-260721160103020.zip",
#'   package = "VasGBIF"
#' )
#' occ <- import_records(path = gbif_file)
#' taxa_checked <- check_taxon(occ_import = occ, accuracy = 0.85)
#' head(taxa_checked$summary, 10)
#' nrow(taxa_checked$occ_taxa_checked)
#'
#' @export
check_taxon <- function(
  occ_import = NA,
  accuracy = 0.85,
  sources = "wcvp",
  timeout_minutes = 20
) {
  if (!inherits(occ_import, "import")) {
    stop(
      "`occ_import` must be an \"import\" object returned by ",
      "`import_records()`.",
      call. = FALSE
    )
  }

  missing_cols <- setdiff(
    c("gbifID", "scientificName", "taxonRank"),
    names(occ_import)
  )
  if (length(missing_cols) > 0) {
    stop(
      "`occ_import` is missing required column(s): ",
      paste(missing_cols, collapse = ", "),
      ".",
      call. = FALSE
    )
  }

  if (nrow(occ_import) == 0) {
    stop("`occ_import` contains no records.", call. = FALSE)
  }

  start <- Sys.time()

  occ <- occ_import[, .(gbifID, scientificName, taxonRank)]

  taxon_levels <- c('SPECIES', 'VARIETY', 'SUBSPECIES', 'FORM')

  occ_search <- occ[
    stri_trans_toupper(taxonRank) %chin% taxon_levels,
    unique(scientificName)
  ]

  if (length(occ_search) == 0) {
    stop(
      "`occ_import` contains no records at species rank or below, ",
      "so there are no names to resolve.",
      call. = FALSE
    )
  }

  check_initial <- data.frame(
    ID = seq_along(occ_search),
    taxon = occ_search
  )

  chunk_list <- split(
    check_initial,
    ceiling(seq_len(nrow(check_initial)) / 4000)
  )
  n_chunks <- length(chunk_list)
  check_result_list <- list()

  for (i in seq_len(n_chunks)) {
    chunk <- chunk_list[[i]]
    message(paste(
      "Processing chunk",
      i,
      "of",
      n_chunks,
      "(rows",
      nrow(chunk),
      ")"
    ))

    chunk_result <- data.frame()
    attempt <- 1
    max_attempts <- 3
    timeout_secs <- timeout_minutes * 60

    while (attempt <= max_attempts && nrow(chunk_result) == 0) {
      tryCatch(
        {
          if (attempt > 1) {
            message(paste("Retry attempt", attempt, "of", max_attempts))
          }

          setTimeLimit(elapsed = timeout_secs, transient = TRUE)
          chunk_result <- TNRS(
            chunk,
            sources = sources,
            classification = "wfo",
            mode = "resolve",
            matches = "best",
            accuracy = accuracy,
            skip_internet_check = TRUE
          ) %>%
            data.table::setDT()
          setTimeLimit()

          if (nrow(chunk_result) == 0) {
            message("Query succeeded but returned empty result. Retrying...")
          }
        },
        error = function(e) {
          message(paste("TNRS query failed:", conditionMessage(e)))
          chunk_result <<- data.frame()
          setTimeLimit()
        }
      )

      attempt <- attempt + 1
      if (nrow(chunk_result) == 0 && attempt <= max_attempts) {
        Sys.sleep(5)
      }
    }

    if (nrow(chunk_result) == 0) {
      stop(
        "Network error: TNRS API is unreachable for chunk ",
        i,
        ". Please try again later."
      )
    }

    check_result_list[[i]] <- chunk_result
  }

  check_result <- data.table::rbindlist(check_result_list)

  result <- check_result[, .(
    ID,
    Name_submitted,
    Overall_score,
    Taxonomic_status,
    Accepted_name,
    Accepted_species,
    Accepted_name_id,
    Accepted_name_rank,
    Accepted_family,
    Source
  )]

  # TNRS rewrites submitted names (commas become spaces, diacritics are
  # normalised), so `Name_submitted` is not a reliable join key. The echoed
  # `ID` is the only stable link back to the string that was sent.
  result[, ID := as.integer(ID)]

  if (anyNA(result$ID) || !all(result$ID %in% seq_along(occ_search))) {
    stop(
      "TNRS returned unrecognised row identifiers; results cannot be mapped ",
      "back to the submitted names.",
      call. = FALSE
    )
  }

  # Remove duplicates returned by TNRS API
  result <- unique(result, by = "ID")

  result[, scientificName := occ_search[ID]]
  setcolorder(result, c("scientificName", "ID", "Name_submitted"))

  occ_taxa <- merge(
    occ[, .(gbifID, scientificName)],
    result,
    by = "scientificName",
    all.x = TRUE
  )

  occ_taxa[, c("ID", "Name_submitted") := NULL]

  occ_taxa_checked <- occ_taxa[
    Overall_score >= accuracy &
      Taxonomic_status %chin% c("Accepted", "Synonym") &
      Accepted_name_rank != '' &
      Accepted_name_rank != 'genus',
  ]

  end <- Sys.time()
  used <- end - start
  message(paste('used', used %>% round(1), attributes(used)$units))

  taxa_checked <- list(
    occ_taxa_checked = occ_taxa_checked,
    summary = result,
    runtime = used
  )
  class(taxa_checked) <- 'occ_taxa'
  return(taxa_checked)
}

#' Print an `occ_taxa` object
#'
#' Displays a summary of a taxonomic resolution result based on
#' `occ_taxa_checked`: the number of records, the number of distinct
#' `scientificName` values, a table of distinct name counts
#' (`scientificName`, `Accepted_name`, `Accepted_species`), the `Source`
#' breakdown, and the top three `Accepted_name` values by record count,
#' followed by the elapsed runtime. The records themselves are not shown; use
#' [head()] or `View()` to inspect them.
#'
#' @param x An object of class `"occ_taxa"` returned by [check_taxon()].
#' @param ... Additional arguments (unused, retained for S3 compatibility).
#'
#' @return Invisibly returns `x`.
#'
#' @export
print.occ_taxa <- function(x, ...) {
  checked_tbl <- if (is.data.frame(x$occ_taxa_checked)) {
    as.data.table(x$occ_taxa_checked)
  } else {
    NULL
  }
  n_checked <- if (is.null(checked_tbl)) 0L else nrow(checked_tbl)

  cat("<occ_taxa> ", n_checked, " records", sep = "")
  if (!is.null(checked_tbl) && "scientificName" %chin% names(checked_tbl)) {
    cat(
      " | ",
      uniqueN(checked_tbl$scientificName),
      " unique scientificName",
      sep = ""
    )
  }
  cat("\n")

  if (is.null(checked_tbl) || n_checked == 0L) {
    if (!is.null(x$runtime)) {
      cat("\nruntime: ", format(x$runtime), "\n", sep = "")
    }
    return(invisible(x))
  }

  name_cols <- c("scientificName", "Accepted_name", "Accepted_species")
  if (all(name_cols %chin% names(checked_tbl))) {
    distinct_counts <- data.table(
      column = name_cols,
      n = vapply(
        name_cols,
        function(col) uniqueN(checked_tbl[[col]]),
        integer(1)
      )
    )
    cat("\nDistinct names in occ_taxa_checked:\n")
    print(distinct_counts)
  }

  if ("Source" %chin% names(checked_tbl)) {
    source_counts <- checked_tbl[, .N, by = Source][order(-N)]
    cat("\nSource of checked records:\n")
    print(source_counts)
  }

  if ("Accepted_name" %chin% names(checked_tbl)) {
    top_name <- checked_tbl[, .N, by = Accepted_name][order(-N)][seq_len(min(
      3,
      .N
    ))]
    setnames(top_name, "N", "records")
    cat("\nTop 3 Accepted_name by records:\n")
    print(top_name)
  }

  if (!is.null(x$runtime)) {
    cat("\nruntime: ", format(x$runtime), "\n", sep = "")
  }

  invisible(x)
}
