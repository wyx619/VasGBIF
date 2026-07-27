#' @title Restore missing metadata from duplicate records
#'
#' @description Internal helper that fills missing metadata fields in usable
#' voucher records using values from their associated duplicate records that
#' share the same collection event key.
#'
#' @param occ_digital_voucher A `data.table` of digital voucher records, as
#'   produced by internal vouchering steps. Must contain the columns listed in
#'   `fields_to_parse` as well as `VasGBIF_dataset_result` and
#'   `collection_key`.
#'
#' @details
#' The function operates on two subsets of the input: records marked
#' `"usable"` and those marked `"duplicate"`. For each metadata field listed
#' in `fields_to_merge` (`eventDate`, `year`, `month`, `day`,
#' `identifiedBy`, `countryCode`, `stateProvince`, `locality`), it:
#'
#' - Identifies usable records whose value for that field is missing, empty,
#'   or `"NA"`.
#' - Searches the duplicate records with the same `collection_key` for a
#'   non-missing candidate value of reasonable length (no more than 10,000
#'   characters).
#' - Copies the first valid candidate into the usable record and sets
#'   `VasGBIF_restored_from_duplicate = TRUE`.
#'
#' The `year` field receives special treatment: after cleaning, the candidate
#' text is coerced to integer.
#'
#' Only the usable records (with restored fields) are returned.
#'
#' @returns A `data.table` containing only the usable records, with missing
#'   metadata fields filled from duplicates where possible and a logical flag
#'   `VasGBIF_restored_from_duplicate` indicating whether restoration
#'   occurred for each row.
#'
#' @import data.table
#' @importFrom stringi stri_length stri_trans_toupper stri_replace_all_regex
#' @keywords internal
restore_duplicates <- function(occ_digital_voucher = NULL) {
  MAX_FIELD_LENGTH <- 10000
  fields_to_merge <- c(
    "eventDate",
    "year",
    "month",
    "day",
    "identifiedBy",
    "countryCode",
    "stateProvince",
    "locality"
  )

  fields_to_parse <- c(
    "gbifID",
    "institutionCode",
    "collectionCode",
    "basisOfRecord",
    "catalogNumber",
    "recordNumber",
    "recordedBy",
    "occurrenceStatus",
    "eventDate",
    "year",
    "month",
    "day",
    "identifiedBy",
    "countryCode",
    "stateProvince",
    "locality",
    "dateIdentified",
    "scientificName",
    "typeStatus",
    "family",
    "decimalLatitude",
    "decimalLongitude",
    "taxonRank",
    "issue",
    "geospatial_quality",
    "verbatim_quality",
    "moreInformativeRecord",
    "coordinates_validated_by_gbif_issue",
    "wcvp_plant_name_id",
    "wcvp_taxon_rank",
    "wcvp_taxon_status",
    "wcvp_family",
    "wcvp_taxon_name",
    "wcvp_taxon_authors",
    "wcvp_reviewed",
    "wcvp_searchedName",
    "wcvp_searchNotes",
    "VasGBIF_digital_voucher",
    "VasGBIF_duplicates",
    "VasGBIF_num_duplicates",
    "VasGBIF_non_groupable_duplicates",
    "VasGBIF_duplicates_grouping_status",
    "VasGBIF_unidentified_sample",
    "VasGBIF_sample_taxon_name",
    "VasGBIF_sample_taxon_name_status",
    "VasGBIF_number_taxon_names",
    "VasGBIF_useful_for_spatial_analysis",
    "VasGBIF_decimalLatitude",
    "VasGBIF_decimalLongitude",
    "VasGBIF_dataset_result",
    "VasGBIF_wcvp_plant_name_id",
    "VasGBIF_wcvp_taxon_rank",
    "VasGBIF_wcvp_taxon_status",
    "VasGBIF_wcvp_family",
    "VasGBIF_wcvp_taxon_name",
    "VasGBIF_wcvp_taxon_authors",
    "VasGBIF_wcvp_reviewed",
    "collection_key"
  )

  occ_tmp <- occ_digital_voucher[, ..fields_to_parse][,
    VasGBIF_restored_from_duplicate := FALSE
  ]
  occ_in <- occ_tmp[VasGBIF_dataset_result == "usable"]
  occ_dup <- occ_tmp[VasGBIF_dataset_result == "duplicate"]
  merge_keys <- occ_in[VasGBIF_duplicates == TRUE, unique(collection_key)]
  rm(occ_tmp)
  setkeyv(occ_dup, "collection_key")
  setkeyv(occ_in, "collection_key")
  all_relevant_dups <- occ_dup[.(merge_keys)]
  for (field in fields_to_merge) {
    empty_keys <- occ_in[
      (is.na(get(field)) | get(field) == "" | get(field) == "NA") &
        VasGBIF_duplicates == TRUE,
      unique(collection_key)
    ]
    if (length(empty_keys) == 0) {
      message("Skipping ", field, ": no empty values to restore")
      next
    }

    candidates <- all_relevant_dups[
      .(empty_keys),
      on = "collection_key"
    ][
      !is.na(get(field)) &
        get(field) != "" &
        get(field) != "NA" &
        stringi::stri_length(get(field)) <= MAX_FIELD_LENGTH &
        stringi::stri_length(get(field)) > 0
    ][, .(best_value = head(get(field), 1)), by = collection_key]

    if (nrow(candidates) == 0) {
      message(
        "Skipping ",
        field,
        ": ",
        length(empty_keys),
        " empty keys, but no valid duplicate values found"
      )
      next
    }

    if (field %in% c('year', 'month', 'day')) {
      candidates[,
        clean_value := suppressWarnings(as.integer(
          stringi::stri_trans_toupper(
            stringi::stri_replace_all_regex(
              best_value,
              "[\\{\\}\\[\\]\\(\\)\\\\\\*]",
              ""
            )
          )
        ))
      ]
    } else {
      candidates[,
        clean_value := stringi::stri_trans_toupper(
          stringi::stri_replace_all_regex(
            best_value,
            "[\\{\\}\\[\\]\\(\\)\\\\\\*]",
            ""
          )
        )
      ]
    }

    occ_in[
      candidates,
      c(field, "VasGBIF_restored_from_duplicate") := .(i.clean_value, TRUE),
      on = "collection_key"
    ]
    message(
      "Restored ",
      field,
      " for ",
      nrow(candidates),
      " collection keys"
    )
  }
  return(occ_in)
}
