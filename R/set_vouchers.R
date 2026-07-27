#' @title Select master digital vouchers from duplicate groups via quality scoring
#'
#' @description Identifies and selects the best representative record (the
#' *digital voucher*) from each group of duplicate occurrence records that
#' share the same collection event key. Records are scored across two quality
#' dimensions, and the highest-scoring record in each group is retained.
#'
#' @param occ_import An `import` object returned by [import_records()]. Used
#'   for the `occ_issue` table containing GBIF geospatial issue flags.
#' @param taxa_checked An `occ_taxa` object returned by [check_taxon()]. Used
#'   for the WCVP taxonomic resolution of each record.
#' @param collection_keys A `collections` object returned by
#'   [get_collections()]. Used for the `collection_key` that groups records
#'   into collection events.
#'
#' @details
#' ## How the collection key identifies duplicates
#'
#' The `collection_key` from [get_collections()] has the form
#' `taxon|eventDate|latitude|longitude`. Records that share the **same,
#' complete** key are considered potential duplicates from a single
#' gathering event and are processed as a group. Records whose key is
#' missing or contains `NA` in any component cannot be grouped and are
#' each treated as an independent voucher.
#'
#' ## Quality scoring system
#'
#' Each record receives a total quality score (`moreInformativeRecord`)
#' computed as the sum of two sub-scores:
#'
#' `moreInformativeRecord = verbatim_quality + geospatial_quality`
#'
#' ### `verbatim_quality` — record completeness (0–9)
#'
#' One point for each of these nine fields that is present and non-empty:
#' `recordedBy`, `recordNumber`, `year`, `institutionCode`,
#' `catalogNumber`, `locality`, `stateProvince`, `countryCode` (via
#' `COUNTRY_INVALID`), and `identifiedBy`. A record with all nine fields
#' scores 9; one with none scores 0.
#'
#' ### `geospatial_quality` — coordinate issue penalty (0 to −9)
#'
#' Derived from the GBIF issue flags catalogued in `EnumOccurrenceIssue`:
#'
#' - `0`: no known geospatial issues.
#' - `−1`: at least one severity-1 (cosmetic) issue, e.g.
#'   `COORDINATE_ROUNDED`.
#' - `−3`: at least one severity-2 (potential) issue, e.g.
#'   `COUNTRY_COORDINATE_MISMATCH`.
#' - `−9`: at least one severity-3 (exclusion) issue, e.g.
#'   `ZERO_COORDINATE`, or coordinates are missing entirely.
#'
#' ### Worked example
#'
#' Suppose three records share the collection key
#' `Saxifraga oppositifolia|17095|30.45|79.07`:
#'
#' | Record | `recordedBy` | `year` | ... | `verbatim_quality` | GBIF issues | `geospatial_quality` | `moreInformativeRecord` |
#' |--------|-------------|--------|-----|--------------------|-------------|-------------------------|---------------------------|
#' | A (complete, no issues) | ✓ | ✓ | ... | 7 | none | 0 | **7** |
#' | B (sparse, minor issue) | ✗ | ✗ | ... | 3 | `COORDINATE_ROUNDED` | −1 | 2 |
#' | C (missing coordinates) | ✓ | ✓ | ... | 6 | `ZERO_COORDINATE` | −9 | −3 |
#'
#' Record A has the highest `moreInformativeRecord` (7) and becomes the
#' digital voucher. Its coordinates are propagated to B and C. Records B
#' and C are classified as `"duplicate"`.
#'
#' ### Tie-breaking
#'
#' If two records tie for the highest score, the one appearing first in
#' the data (smallest row index) is chosen. This is deterministic but
#' arbitrary; users concerned about a specific tie should inspect those
#' groups directly.
#'
#' ## Voucher selection
#'
#' Within each group, the record with the highest `moreInformativeRecord`
#' is marked `VasGBIF_digital_voucher = TRUE`. Its coordinates
#' (prioritising validated coordinates from the voucher itself) are
#' assigned to all members of the group via `VasGBIF_decimalLatitude`
#' and `VasGBIF_decimalLongitude`.
#'
#' ## Taxonomic consensus
#'
#' For groupable records, the most frequent accepted taxon name (from
#' WCVP) in the group is assigned to all members. Groups are classified
#' as:
#'
#' - `"identified"`: a single accepted name dominates.
#' - `"divergent identifications"`: multiple accepted names appear.
#' - `"unidentified"`: no accepted name is present.
#'
#' Non-groupable records take their taxon identity directly from their own
#' WCVP resolution.
#'
#' ## Final dataset classification
#'
#' `VasGBIF_dataset_result` assigns one of three labels:
#'
#' - `"usable"`: digital voucher, taxonomically identified, and spatially
#'   useful (has validated coordinates).
#' - `"duplicate"`: not the digital voucher of its group.
#' - `"unusable"`: digital voucher but either unidentified, lacking
#'   validated coordinates, or both.
#'
#' @returns A list of class `"vouchers"` with three elements:
#'
#' - `occ_digital_voucher`: a `data.table` with all occurrence records
#'   and their quality scores, voucher status, grouping flags, taxonomic
#'   assignments, and final classification. Key columns include
#'   `moreInformativeRecord`, `VasGBIF_digital_voucher`,
#'   `VasGBIF_duplicates`, `VasGBIF_dataset_result`, and
#'   `VasGBIF_duplicates_grouping_status`.
#' - `occ_results`: a `data.table` with only the quality-assessment and
#'   result columns, keyed by `gbifID`.
#' - `runtime`: the elapsed execution time.
#'
#' @import data.table
#' @import stringi
#' @importFrom dplyr %>% select
#' @references
#' De Melo, Pablo Hendrigo Alves, Nadia Bystriakova, Eve Lucas, and
#' Alexandre K. Monro. 2024. "A New R Package to Parse Plant Species
#' Occurrence Records into Unique Collection Events Efficiently Reduces
#' Data Redundancy." *Scientific Reports* 14 (1): 5450.
#' doi:10.1038/s41598-024-56158-3.
#' @examplesIf interactive()
#' taxa_checked <- check_taxon(occ_import = occ_import, accuracy = 0.9)
#'
#' collection_keys <- get_collections(
#'   occ_import = occ_import,
#'   taxa_checked = taxa_checked,
#'   precision = 2L
#' )
#'
#' voucher <- set_vouchers(
#'   occ_import = occ_import,
#'   taxa_checked = taxa_checked,
#'   collection_keys = collection_keys
#' )
#' @export
set_vouchers <- function(
  occ_import = NA,
  taxa_checked = NA,
  collection_keys = NA
) {
  start <- Sys.time()

  # ============================================================================
  # SECTION 1: Data Preparation and Quality Field Calculation
  # ============================================================================
  message("Starting voucher preparation...")

  {
    EnumOccurrenceIssue <- EnumOccurrenceIssue

    occ_issue <- occ_import$occ_issue %>% setorder(gbifID)
    occ_wcvp_check_name <- taxa_checked$occ_taxa_checked %>% setorder(gbifID)
    occ_in <- collection_keys$occ_key %>% setorder(gbifID)

    # Combine all data sources
    occ <- cbind(
      occ_issue %>% select(-gbifID),
      occ_in %>% select(-wcvp_taxon_name),
      occ_wcvp_check_name %>% select(-gbifID)
    )

    occ[is.na(wcvp_taxon_rank), wcvp_taxon_rank := '']
    occ[is.na(wcvp_taxon_status), wcvp_taxon_status := '']

    # Identify geospatial issue categories from EnumOccurrenceIssue
    index_tmp1 <- EnumOccurrenceIssue$score == 1 &
      EnumOccurrenceIssue$type ==
        'geospatial' %>%
          ifelse(is.na(.), FALSE, .)
    index_tmp2 <- EnumOccurrenceIssue$score == 2 &
      EnumOccurrenceIssue$type ==
        'geospatial' %>%
          ifelse(is.na(.), FALSE, .)
    index_tmp3 <- EnumOccurrenceIssue$score == 3 &
      EnumOccurrenceIssue$type ==
        'geospatial' %>%
          ifelse(is.na(.), FALSE, .)

    # Calculate record completeness flags
    occ[, `:=`(
      tem_year = !is.na(year) & year != "" & year > 10,
      tem_institutionCode = !is.na(institutionCode) & institutionCode != "",
      tem_catalogNumber = !is.na(catalogNumber) & catalogNumber != "",
      tem_recordedBy = !is.na(recordedBy) & recordedBy != "",
      tem_recordNumber = !is.na(recordNumber) & recordNumber != "",
      tem_COUNTRY = !COUNTRY_INVALID,
      tem_stateProvince = !is.na(stateProvince) & stateProvince != "",
      tem_locality = !is.na(locality) & locality != "",
      tem_identifiedBy = !is.na(identifiedBy) & identifiedBy != ""
    )]
  }

  # ============================================================================
  # SECTION 2: Calculate Quality Scores
  # ============================================================================
  message("Calculating quality scores...")

  {
    # Get column names for each issue severity level
    a3 <- (EnumOccurrenceIssue$constant[index_tmp3 == TRUE])
    a2 <- (EnumOccurrenceIssue$constant[index_tmp2 == TRUE])
    a1 <- (EnumOccurrenceIssue$constant[index_tmp1 == TRUE])

    # Initialize result columns
    occ[, `:=`(
      geospatial_quality = 0,
      verbatim_quality = 0,
      moreInformativeRecord = 0,
      VasGBIF_digital_voucher = FALSE,
      VasGBIF_duplicates = FALSE,
      VasGBIF_non_groupable_duplicates = FALSE,
      VasGBIF_num_duplicates = 0,
      VasGBIF_duplicates_grouping_status = '',
      coordinates_validated_by_gbif_issue = FALSE,
      VasGBIF_unidentified_sample = TRUE,
      VasGBIF_wcvp_plant_name_id = '',
      VasGBIF_sample_taxon_name = '',
      VasGBIF_sample_taxon_name_status = '',
      VasGBIF_number_taxon_names = 0,
      VasGBIF_useful_for_spatial_analysis = FALSE,
      VasGBIF_decimalLatitude = NA_real_,
      VasGBIF_decimalLongitude = NA_real_
    )]

    # Validate coordinates based on GBIF issues
    occ[,
      coordinates_validated_by_gbif_issue := rowSums(.SD) == 0,
      .SDcols = a3
    ]
    occ[,
      coordinates_validated_by_gbif_issue := ifelse(
        is.na(decimalLongitude) |
          is.na(decimalLatitude) |
          decimalLatitude == '' |
          decimalLongitude == '' |
          decimalLatitude == 0 |
          decimalLongitude == 0,
        FALSE,
        coordinates_validated_by_gbif_issue
      )
    ]
    occ[,
      coordinates_validated_by_gbif_issue := ifelse(
        is.na(coordinates_validated_by_gbif_issue),
        FALSE,
        coordinates_validated_by_gbif_issue
      )
    ]

    # Calculate geospatial quality score
    occ[,
      geospatial_quality := fcase(
        rowSums(.SD[, a3, with = FALSE]) > 0 , -9 ,
        rowSums(.SD[, a2, with = FALSE]) > 0 , -3 ,
        rowSums(.SD[, a1, with = FALSE]) > 0 , -1 ,
        default = 0
      )
    ]
    occ[
      is.na(decimalLongitude) |
        is.na(decimalLatitude) |
        decimalLatitude == '' |
        decimalLongitude == '',
      geospatial_quality := -9
    ]

    # Calculate verbatim quality score (record completeness)
    occ[,
      verbatim_quality := tem_recordedBy +
        tem_recordNumber +
        tem_year +
        tem_institutionCode +
        tem_catalogNumber +
        tem_locality +
        tem_stateProvince +
        tem_COUNTRY +
        tem_identifiedBy
    ]

    # Calculate total quality score
    occ[, moreInformativeRecord := geospatial_quality + verbatim_quality]
  }

  # Step 1: Identify incomplete collection keys from get_collections()
  # collection_key format: taxon|eventDate|latitude|longitude
  # Any NA segment makes the key non-groupable
  message("Pre-compute grouping key patterns...")

  occ[,
    is_non_groupable := is.na(collection_key) |
      collection_key == "" |
      stri_detect_regex(collection_key, "(^|\\|)NA(\\||$)")
  ]

  # Step 2: Handle non-groupable records in batch
  message("Handle non-groupable records")
  # These records are treated as individual samples with no duplicates
  occ[
    is_non_groupable == TRUE,
    `:=`(
      VasGBIF_digital_voucher = TRUE,
      VasGBIF_non_groupable_duplicates = TRUE,
      VasGBIF_duplicates = FALSE,
      VasGBIF_num_duplicates = 1L,

      # Set taxon information based on acceptance status
      VasGBIF_wcvp_plant_name_id = fifelse(
        wcvp_taxon_status == "Accepted",
        as.character(wcvp_plant_name_id),
        ""
      ),
      VasGBIF_sample_taxon_name = fifelse(
        wcvp_taxon_status == "Accepted",
        as.character(wcvp_taxon_name),
        ""
      ),
      VasGBIF_unidentified_sample = fifelse(
        wcvp_taxon_status == "Accepted",
        FALSE,
        TRUE
      ),
      VasGBIF_number_taxon_names = fifelse(
        wcvp_taxon_status == "Accepted",
        1L,
        0L
      ),
      VasGBIF_sample_taxon_name_status = fifelse(
        wcvp_taxon_status == "Accepted",
        "identified",
        "unidentified"
      ),

      # Set coordinate information based on validation status
      VasGBIF_decimalLatitude = fifelse(
        coordinates_validated_by_gbif_issue == TRUE,
        as.double(decimalLatitude),
        NA_real_
      ),
      VasGBIF_decimalLongitude = fifelse(
        coordinates_validated_by_gbif_issue == TRUE,
        as.double(decimalLongitude),
        NA_real_
      ),
      VasGBIF_useful_for_spatial_analysis = coordinates_validated_by_gbif_issue,

      # Incomplete taxon|date|lat|lon key from get_collections()
      VasGBIF_duplicates_grouping_status = "not groupable: incomplete collection key"
    )
  ]

  # Step 3: Process groupable records
  message("Process groupable records...")
  setkey(occ, collection_key)

  # Calculate group statistics and identify digital vouchers
  occ[is_non_groupable == FALSE, num_duplicates := .N, by = collection_key]

  occ[
    is_non_groupable == FALSE,
    max_info_score := max(moreInformativeRecord),
    by = collection_key
  ]

  occ[
    is_non_groupable == FALSE,
    VasGBIF_digital_voucher := moreInformativeRecord == max_info_score &
      .I == .I[which.max(moreInformativeRecord)],
    by = collection_key
  ]

  # Set basic grouping information
  occ[
    is_non_groupable == FALSE,
    `:=`(
      VasGBIF_duplicates_grouping_status = "groupable",
      VasGBIF_duplicates = num_duplicates > 1,
      VasGBIF_num_duplicates = num_duplicates
    )
  ]

  # Step 4: Process taxonomic information for groupable records (Optimized)
  message("Process taxonomic information for groupable records...")

  sub_dt <- occ[
    is_non_groupable == FALSE &
      wcvp_taxon_status == "Accepted" &
      !is.na(wcvp_taxon_name),
    .(collection_key, wcvp_taxon_name, wcvp_plant_name_id)
  ]

  if (nrow(sub_dt) > 0) {
    taxon_counts <- sub_dt[,
      .N,
      by = .(collection_key, wcvp_taxon_name, wcvp_plant_name_id)
    ]

    setorder(
      taxon_counts,
      collection_key,
      -N,
      wcvp_taxon_name,
      wcvp_plant_name_id
    )

    selected_taxa <- taxon_counts[, .SD[1], by = collection_key]

    unique_counts <- taxon_counts[,
      .(num_unique_taxa = .N),
      by = collection_key
    ]

    occ[
      selected_taxa,
      on = "collection_key",
      `:=`(
        VasGBIF_sample_taxon_name = i.wcvp_taxon_name,
        VasGBIF_wcvp_plant_name_id = i.wcvp_plant_name_id
      )
    ]

    occ[
      unique_counts,
      on = "collection_key",
      num_unique_taxa := i.num_unique_taxa
    ]
  }

  occ[
    is_non_groupable == FALSE,
    `:=`(
      VasGBIF_sample_taxon_name = fifelse(
        is.na(VasGBIF_sample_taxon_name),
        "",
        VasGBIF_sample_taxon_name
      ),
      VasGBIF_wcvp_plant_name_id = fifelse(
        is.na(VasGBIF_wcvp_plant_name_id),
        "",
        VasGBIF_wcvp_plant_name_id
      ),
      VasGBIF_number_taxon_names = fifelse(
        is.na(num_unique_taxa),
        0L,
        num_unique_taxa
      ),
      VasGBIF_sample_taxon_name_status = fcase(
        is.na(num_unique_taxa) | num_unique_taxa == 0L , "unidentified"              ,
        num_unique_taxa == 1L                          , "identified"                ,
        num_unique_taxa > 1L                           , "divergent identifications" ,
        default = "unidentified"
      ),
      VasGBIF_unidentified_sample = (is.na(num_unique_taxa) |
        num_unique_taxa == 0L)
    )
  ]

  rm(sub_dt, taxon_counts, selected_taxa, unique_counts)

  # Step 5: Assign coordinates for groupable records
  message("Assign coordinates for groupable records...")
  # Create coordinate priority score (higher for digital voucher and better quality)
  occ[
    is_non_groupable == FALSE,
    coord_priority := fifelse(
      coordinates_validated_by_gbif_issue == TRUE,
      VasGBIF_digital_voucher * 1000000 + geospatial_quality,
      -1
    )
  ]

  # Get the coordinates from the record with highest priority
  occ[
    is_non_groupable == FALSE,
    `:=`(
      best_lat = fifelse(
        any(coordinates_validated_by_gbif_issue == TRUE),
        decimalLatitude[which.max(coord_priority)],
        NA_real_
      ),
      best_lon = fifelse(
        any(coordinates_validated_by_gbif_issue == TRUE),
        decimalLongitude[which.max(coord_priority)],
        NA_real_
      )
    ),
    by = collection_key
  ]

  # Assign the selected coordinates to all records in the group
  occ[
    is_non_groupable == FALSE,
    `:=`(
      VasGBIF_decimalLatitude = best_lat,
      VasGBIF_decimalLongitude = best_lon,
      VasGBIF_useful_for_spatial_analysis = !is.na(best_lat)
    )
  ]

  # Step 6: Clean up temporary columns
  message("Clean up temps...")
  occ[, `:=`(
    is_non_groupable = NULL,
    num_duplicates = NULL,
    max_info_score = NULL,
    num_unique_taxa = NULL,
    coord_priority = NULL,
    best_lat = NULL,
    best_lon = NULL
  )]

  # Select result columns
  occ_results <- occ[, .(
    gbifID,
    geospatial_quality,
    verbatim_quality,
    moreInformativeRecord,
    VasGBIF_digital_voucher,
    VasGBIF_duplicates,
    VasGBIF_num_duplicates,
    VasGBIF_non_groupable_duplicates,
    VasGBIF_duplicates_grouping_status,
    coordinates_validated_by_gbif_issue,
    VasGBIF_unidentified_sample,
    VasGBIF_wcvp_plant_name_id,
    VasGBIF_sample_taxon_name,
    VasGBIF_sample_taxon_name_status,
    VasGBIF_number_taxon_names,
    VasGBIF_useful_for_spatial_analysis,
    VasGBIF_decimalLatitude,
    VasGBIF_decimalLongitude
  )] %>%
    setorder(gbifID)

  # ============================================================================
  # SECTION 3: Combine with Original Data and Add Final Classifications
  # ============================================================================
  message("Merging...")

  {
    # Combine all data
    occ_all <- cbind(occ_in, occ_wcvp_check_name, occ_results) %>% setDT()
    col_tmp <- unique(names(occ_all))
    occ_all <- occ_all[, ..col_tmp]

    # Add final dataset result classification
    occ_all[,
      VasGBIF_dataset_result := fcase(
        VasGBIF_digital_voucher == TRUE & VasGBIF_unidentified_sample == FALSE & VasGBIF_useful_for_spatial_analysis == TRUE                                               , "usable"    ,
        VasGBIF_digital_voucher == FALSE                                                                                                                                       , "duplicate" ,
        VasGBIF_digital_voucher == TRUE & (VasGBIF_unidentified_sample == TRUE | VasGBIF_useful_for_spatial_analysis == FALSE | is.na(VasGBIF_decimalLongitude) == TRUE) , "unusable"
      )
    ]

    # Merge with WCVP accepted name details
    name_tmp <- occ_wcvp_check_name[, .(
      wcvp_plant_name_id = as.character(wcvp_plant_name_id),
      wcvp_taxon_rank,
      wcvp_taxon_status,
      wcvp_family,
      wcvp_taxon_name,
      wcvp_taxon_authors,
      wcvp_reviewed
    )] %>%
      unique(by = "wcvp_plant_name_id") %>%
      setnames(paste0('VasGBIF_', names(.))) %>%
      stats::na.omit()

    occ_all <- merge(
      occ_all,
      name_tmp,
      by = 'VasGBIF_wcvp_plant_name_id',
      all.x = TRUE
    )

    # Select final columns
    cols_to_keep <- c(
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
      "decimalLatitude",
      "decimalLongitude",
      "typeStatus",
      "family",
      "taxonRank",
      "issue",
      "collection_key",
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
      "VasGBIF_wcvp_reviewed"
    )

    occ_all <- occ_all[, ..cols_to_keep]
  }

  # ============================================================================
  # SECTION 4: Return Results
  # ============================================================================

  end <- Sys.time()

  used <- end - start
  message(paste('used', used %>% round(1), attributes(used)$units))
  voucher <- list(
    occ_digital_voucher = occ_all,
    occ_results = occ_results,
    runtime = end - start
  )
  class(voucher) <- 'vouchers'
  return(voucher)
}
