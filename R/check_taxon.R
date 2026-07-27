#' @title Resolve taxon names via the Taxonomic Name Resolution Service
#'
#' @description Submits plant scientific names to the Taxonomic Name Resolution
#' Service (TNRS) and resolves them against the World Checklist of Vascular
#' Plants (WCVP). The TNRS corrects spelling errors, standardises variant
#' spellings, and converts synonyms to their currently accepted names.
#'
#' The function works in three phases:
#'
#' 1. Extracts unique names at species-level ranks (species, subspecies,
#'    variety, form) and submits them to the TNRS in chunks of up to 4,000
#'    names.
#' 2. Post-processes the TNRS response into a structured `data.table` with
#'    WCVP identifiers, accepted names, taxonomic status, and a resolution
#'    outcome label.
#' 3. Merges the results back into the full occurrence table. Records above
#'    species rank are not submitted and retain `NA` in all WCVP fields.
#'
#' @param occ_import An `import` object returned by [import_records()].
#' @param accuracy Numeric threshold between `0` and `1` controlling the
#'   minimum match score for a name to be considered resolved. The default is
#'   `0.9`. Passed to [TNRS::TNRS()].
#' @param sources Character vector of taxonomic sources. The effective
#'   default is `"wcvp"`. `"wfo"` is also accepted.
#'
#' @details
#' ## Taxon rank filtering
#'
#' Only records whose `taxonRank` is one of `"SPECIES"`, `"VARIETY"`,
#' `"SUBSPECIES"`, or `"FORM"` are submitted to the TNRS. Records at genus
#' rank or above are retained in the output but receive `NA` for all WCVP
#' fields and are not part of the resolution process.
#'
#' ## Handling of unresolved and uncertain names
#'
#' All records are **retained** in the output — none are removed. Names that
#' cannot be resolved are identifiable through the `wcvp_searchNotes` column:
#'
#' - `"Accepted"`: the submitted name is already an accepted name in WCVP.
#' - `"Updated"`: the submitted name is a synonym and has been resolved to
#'   its accepted name. The accepted name appears in `wcvp_taxon_name` and
#'   its WCVP identifier in `wcvp_plant_name_id`.
#' - `"Not found"`: the TNRS could not match the name to any WCVP entry, or
#'   the match has no accepted name. All WCVP fields (`wcvp_taxon_name`,
#'   `wcvp_plant_name_id`, `wcvp_family`, etc.) are `NA` for these records.
#'
#' Names with uncertain taxonomic status in WCVP — including *unplaced*,
#' *unresolved*, *illegitimate*, and *invalid* names — typically receive no
#' accepted name from the TNRS and are therefore classified as
#' `"Not found"`. They remain in the dataset with `NA` WCVP fields so that
#' users can inspect and manually curate them.
#'
#' Names that the TNRS resolves only to genus level are also reclassified as
#' `"Not found"`, since a genus-level identification is too coarse to be
#' useful for the duplicate-detection and native-status workflows that
#' consume this output.
#'
#' ## Review flag
#'
#' The `wcvp_reviewed` column is `"N"` for every name that received an
#' accepted WCVP match (i.e. `wcvp_searchNotes` is `"Accepted"` or
#' `"Updated"`). It is `NA` for names classified as `"Not found"`. Users can
#' manually set it to `"Y"` after verifying a resolution, or fill it for
#' unresolved names after manual curation.
#'
#' ## Retry logic
#'
#' Each TNRS chunk query is attempted up to 3 times with a 5-second wait
#' between attempts and a 20-minute timeout per attempt. This guards against
#' transient network failures and API timeouts.
#'
#' @returns A list of class `"occ_taxa"` with three elements:
#'
#' - `occ_taxa_checked`: a `data.table` of all occurrence records (one row
#'   per `gbifID`) with WCVP taxonomic columns appended. Key columns include
#'   `wcvp_searchedName` (the original submitted name), `wcvp_taxon_name`
#'   (the accepted name), `wcvp_plant_name_id`, `wcvp_family`,
#'   `wcvp_taxon_rank`, `wcvp_searchNotes`, and `wcvp_reviewed`.
#' - `summary`: a `data.table` of unique resolution outcomes (one row per
#'   submitted name), suitable for reviewing results and identifying names
#'   that require manual attention.
#' - `runtime`: the elapsed execution time.
#'
#' @references
#'
#' - Boyle, B. et al. (2013). The taxonomic name resolution service: an
#'   online tool for automated standardisation of plant names. *BMC
#'   Bioinformatics*, 14, 16. doi:10.1186/1471-2105-14-16
#' - Govaerts, R. et al. (2021). The World Checklist of Vascular Plants, a
#'   continuously updated resource for exploring global plant diversity.
#'   *Scientific Data*, 8, 215. doi:10.1038/s41597-021-00997-6
#'
#' @importFrom dplyr %>% case_when if_else select
#' @import data.table
#' @import stringi
#' @import TNRS
#' @seealso [`TNRS()`][TNRS::TNRS]
#' @examplesIf interactive()
#' taxa_checked <- check_taxon(occ_import = occ_import, accuracy = 0.9)
#' @export
check_taxon <- function(
  occ_import = NA,
  accuracy = 0.9,
  sources = c("wcvp", "wfo")
) {
  if (missing(sources)) {
    sources <- "wcvp"
  }
  start <- Sys.time()

  occ <- occ_import$occ[, .(gbifID, scientificName, taxonRank)]

  taxon_levels <- c('SPECIES', 'VARIETY', 'SUBSPECIES', 'FORM')
  occ_all <- occ[, .(
    gbifID,
    wcvp_searchedName = scientificName,
    taxonRank
  )]
  name_search <- occ_all[
    stri_trans_toupper(taxonRank) %chin% taxon_levels,
    unique(wcvp_searchedName)
  ]

  check_initial <- data.frame(
    ID = 1:length(name_search),
    taxon = name_search
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
    timeout_secs <- 20 * 60

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
        "Network error: TNRS API is unreachable for chunk",
        i,
        ". Please try again later."
      )
    }

    check_result_list[[i]] <- chunk_result
  }

  check_result <- data.table::rbindlist(check_result_list)

  check_temp <- check_result[, .(
    ori_sp_name = Name_submitted,
    wcvp_plant_name_id_of_searchedName = Name_matched_id,
    wcvp_searchedName = Name_matched,
    wcvp_taxon_authors_of_searchedName = Author_matched,
    wcvp_taxon_status_of_searchedName = Taxonomic_status,
    wcvp_plant_name_id = Accepted_name_id,
    wcvp_taxon_name = Accepted_name,
    wcvp_taxon_authors = Accepted_name_author,
    wcvp_accepted_plant_name_id = Accepted_name_id,
    wcvp_taxon_rank = Accepted_name_rank,
    wcvp_family = Accepted_family
  )]
  for (col in names(check_temp)) {
    set(
      check_temp,
      i = which(check_temp[[col]] == ""),
      j = col,
      value = NA_character_
    )
  }
  check_temp[, `:=`(
    wcvp_verified_author = NA_real_,
    wcvp_verified_speciesName = NA_real_,
    wcvp_searchNotes = NA_character_,
    wcvp_reviewed = NA_character_
  )]
  check_temp[,
    wcvp_reviewed := fifelse(is.na(wcvp_plant_name_id), NA_character_, "N")
  ]
  check_temp[,
    wcvp_taxon_status := fifelse(
      is.na(wcvp_plant_name_id),
      NA_character_,
      "Accepted"
    )
  ]
  check_temp[,
    wcvp_verified_author := fifelse(
      is.na(wcvp_taxon_authors_of_searchedName) & is.na(wcvp_taxon_authors),
      0L,
      100L
    )
  ]
  check_temp[,
    wcvp_verified_speciesName := fifelse(
      is.na(wcvp_accepted_plant_name_id),
      0L,
      100L
    )
  ]
  check_temp[,
    wcvp_searchNotes := fcase(
      wcvp_verified_speciesName == 0L                 , "Not found" ,
      wcvp_taxon_status_of_searchedName != "Accepted" , "Updated"   ,
      default = "Accepted"
    )
  ]
  check_temp[
    wcvp_taxon_rank == "genus",
    `:=`(
      wcvp_verified_speciesName = 0L,
      wcvp_searchNotes = "Not found",
      wcvp_taxon_status = NA_character_,
      wcvp_reviewed = NA_character_
    )
  ]
  result <- check_temp

  occ_taxa <- merge(
    occ_all %>%
      select(-taxonRank) %>%
      mutate(
        wcvp_searchedName2 = wcvp_searchedName %>%
          stri_replace_all_fixed(',', " ")
      ),
    result %>% select(-wcvp_searchedName),
    by.x = "wcvp_searchedName2",
    by.y = "ori_sp_name",
    all.x = T
  )

  occ_taxa[, wcvp_searchedName2 := NULL]
  summary <- unique(result[, ori_sp_name := NULL])

  end <- Sys.time()
  used <- end - start
  message(paste('used', used %>% round(1), attributes(used)$units))
  taxa_checked <- list(
    occ_taxa_checked = occ_taxa,
    summary = summary,
    runtime = used
  )
  class(taxa_checked) <- 'occ_taxa'
  return(taxa_checked)
}
