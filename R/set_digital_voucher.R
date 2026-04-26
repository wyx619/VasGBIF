#' @title Select master digital voucher through multi-dimensional quality scoring
#' @name set_digital_voucher
#'
#' @description This function identifies and selects the master digital voucher from groups of
#' duplicate GBIF records by applying a multi-dimensional quality scoring system. Records possessing
#' a "full collection mark" (defined as the combination of cleaned \code{Family + RecordBy +
#' RecordNumber/EventDate}) are grouped, and those within each group are scored across multiple
#' dimensions. The record exhibiting the highest metadata quality is retained as the digital voucher.
#' Conversely, records lacking any component of this definition are treated as unique entities; each
#' serves as its own grouping unit and proceeds directly to the multi-dimensional scoring phase
#' without aggregation. This strategy preserves the most geographically informative data while
#' minimizing redundancy, thereby enhancing spatial reliability.
#'
#' The function implements the following workflow:
#' \itemize{
#'   \item \strong{Record grouping}: Groups records by their collection event key
#'   (\code{Ctrl_key}). Records with complete keys are aggregated
#'   as duplicates; records with incomplete keys are treated as independent samples
#'   \item \strong{Quality scoring}: Evaluates each record on two dimensions:
#'   \itemize{
#'     \item \emph{Record Completeness}: Binary presence/absence scoring across ten metadata fields
#'     \item \emph{Geospatial Quality}: Penalty-based scoring derived from GBIF geospatial issue flags
#'   }
#'   \item \strong{Voucher selection}: Within each group, the record with the highest total score
#'   (Record Completeness + Geospatial Quality) is designated as the master digital voucher
#'   \item \strong{Coordinate assignment}: For grouped records, coordinates from the highest-priority
#'   record (voucher with validated coordinates) are assigned to all members of the group
#'   \item \strong{Taxonomic resolution}: For each group, the most frequently occurring accepted
#'   taxon name is selected as the representative taxonomic identity
#' }
#'
#' @param occ_import imported GBIF records from \code{\link{import_records}}
#' @param taxa_checked UltraGBIF_taxa_checked list from \code{\link{check_occ_taxon}}
#' @param collection_key UltraGBIF_collection_key list from \code{\link{set_collection_mark}}
#'
#' @details
#'
#' \strong{Multi-Dimensional Quality Scoring System:}
#'
#' The quality scoring system evaluates each record across two dimensions:
#'
#' \itemize{
#'   \item \emph{Record Completeness}: Calculated as the sum of binary flags (1 = present, 0 = absent)
#'   for the following 10 fields: \code{recordedBy}, \code{recordNumber}, \code{year},
#'   \code{institutionCode}, \code{catalogNumber}, \code{locality}, \code{municipality},
#'   \code{countryCode}, \code{stateProvince}, and \code{identifiedBy}. Higher scores indicate
#'   more complete metadata.
#'
#'   \item \emph{Geospatial Quality}: Derived from GBIF geospatial issue flags in
#'   \code{EnumOccurrenceIssue}, classified into three severity levels:
#'   \itemize{
#'     \item \emph{No Impact} (\code{selection_score = -1}): Issues not affecting coordinate accuracy
#'     \item \emph{Potential Impact} (\code{selection_score = -3}): Issues that may affect coordinate accuracy
#'     \item \emph{Exclusion} (\code{selection_score = -9}): Records with severe geospatial issues
#'   }
#' }
#'
#' The final quality score combines these two dimensions, with the record exhibiting the highest
#' score within each group selected as the digital voucher.
#'
#' \strong{Grouping Status Classification:}
#'
#' The \code{UltraGBIF_duplicates_grouping_status} field indicates the grouping outcome for each record:
#' \itemize{
#'   \item \code{groupable}: Complete collection key; duplicates identified and grouped
#'   \item \code{not groupable}: Cannot be grouped due to missing information:
#'     \itemize{
#'       \item \code{no recordedBy and no recordNumber}: Both collector name and collection number are missing
#'       \item \code{no recordNumber}: Collection number is missing
#'       \item \code{no recordedBy}: Collector name is missing
#'     }
#' }
#'
#'
#'
#' @return UltraGBIF_voucher list containing:
#'   \itemize{
#'     \item \code{occ_digital_voucher}: A data.table containing all processed fields, including
#'     original occurrence data, quality scores, grouping information, taxonomic assignments,
#'     and final dataset classifications
#'     \item \code{occ_results}: A data.table containing only the quality assessment and result
#'     fields (e.g., quality scores, voucher status, coordinate validation)
#'     \item \code{runtime}: Execution time of the function
#'   }
#'
#' The \code{occ_digital_voucher} data.table is the core output of \code{\link{set_digital_voucher}}.
#' It contains all processed fields, including original occurrence data, quality scores, grouping
#' information, taxonomic assignments, and final dataset classifications.
#'
#' The \code{occ_digital_voucher} table includes the following key fields:
#' \itemize{
#'   \item \code{UltraGBIF_digital_voucher}: Logical; \code{TRUE} if the record is selected as the
#'   master voucher for its group
#'   \item \code{UltraGBIF_duplicates}: Logical; \code{TRUE} if the record belongs to a group with
#'   multiple members
#'   \item \code{UltraGBIF_num_duplicates}: Integer; count of records within the same group
#'   \item \code{UltraGBIF_non_groupable_duplicates}: Logical; \code{TRUE} if the record cannot be
#'   grouped due to incomplete collection key components
#'   \item \code{UltraGBIF_duplicates_grouping_status}: Character; grouping outcome classification
#'   (see Grouping Status Classification above)
#'   \item \code{UltraGBIF_dataset_result}: Final classification; one of "usable", "duplicate",
#'   or "unusable"
#' }
#' @import data.table
#' @import stringi
#' @importFrom dplyr %>% select
#'
#' @examples
#' \dontrun{
#' taxa_checked <- check_occ_taxon(occ_import = occ_import,accuracy = 0.9)
#'
#' collectors_dictionary <- check_collectors(occ_import = occ_import,
#' min_char = 2)
#'
#' collection_key <- set_collection_mark(occ_import = occ_import,
#' collectors_dictionary = collectors_dictionary)
#'
#' voucher <- set_digital_voucher(occ_import = occ_import,
#' taxa_checked = taxa_checked,
#' collection_key = collection_key)
#'}
#' @references
#' De Melo, Pablo Hendrigo Alves, Nadia Bystriakova, Eve Lucas, and Alexandre K. Monro. 2024.
#'   "A New R Package to Parse Plant Species Occurrence Records into Unique Collection Events
#'   Efficiently Reduces Data Redundancy." \emph{Scientific Reports} 14 (1): 5450.
#'   \doi{10.1038/s41598-024-56158-3}.
#' @export
set_digital_voucher <- function(occ_import = NA,
                                taxa_checked = NA,
                                collection_key = NA)
{
  start <- Sys.time()

  # ============================================================================
  # SECTION 1: Data Preparation and Quality Field Calculation
  # ============================================================================
  message("Starting voucher preparation...")

  {
    EnumOccurrenceIssue <- EnumOccurrenceIssue
    occ <- occ_import$occ %>% setDT() %>% setorder(Ctrl_gbifID)
    occ_in <- occ %>% setorder(Ctrl_gbifID)
    occ_gbif_issue <- occ_import$occ_gbif_issue %>% setorder(Ctrl_gbifID)
    occ_wcvp_check_name <- taxa_checked$occ_wcvp_check_name %>% setorder(Ctrl_gbifID)
    occ_collectorsDictionary <- collection_key$collection_key %>% setorder(Ctrl_gbifID)

    # Combine all data sources
    occ <- cbind(occ_gbif_issue %>% select(-Ctrl_gbifID),
                 occ_in, occ_wcvp_check_name %>% select(-Ctrl_gbifID),
                 occ_collectorsDictionary %>% select(-Ctrl_gbifID))
    setDT(occ)
    occ[is.na(wcvp_taxon_rank), wcvp_taxon_rank := '']
    occ[is.na(wcvp_taxon_status), wcvp_taxon_status := '']

    # Identify geospatial issue categories from EnumOccurrenceIssue
    index_tmp1 <- EnumOccurrenceIssue$score == 1 & EnumOccurrenceIssue$type == 'geospatial' %>%
      ifelse(is.na(.), FALSE, .)
    index_tmp2 <- EnumOccurrenceIssue$score == 2 & EnumOccurrenceIssue$type == 'geospatial' %>%
      ifelse(is.na(.), FALSE, .)
    index_tmp3 <- EnumOccurrenceIssue$score == 3 & EnumOccurrenceIssue$type == 'geospatial' %>%
      ifelse(is.na(.), FALSE, .)

    # Calculate record completeness flags
    occ[, `:=`(
      tem_year = !is.na(Ctrl_year) & (Ctrl_year == "" | Ctrl_year == 0 | Ctrl_year <= 10),
      tem_institutionCode = !is.na(Ctrl_institutionCode) & Ctrl_institutionCode != "",
      tem_catalogNumber = !is.na(Ctrl_catalogNumber) & Ctrl_catalogNumber != "",
      tem_recordedBy = !is.na(Ctrl_recordedBy) & Ctrl_recordedBy != "",
      tem_recordNumber = !is.na(Ctrl_recordNumber) & Ctrl_recordNumber != "",
      tem_COUNTRY = !COUNTRY_INVALID,
      tem_stateProvince = !is.na(Ctrl_stateProvince) & Ctrl_stateProvince != "",
      tem_municipality = !is.na(Ctrl_municipality) & Ctrl_municipality != "",
      tem_locality = !is.na(Ctrl_locality) & Ctrl_locality != "",
      tem_identifiedBy = !is.na(Ctrl_identifiedBy) & Ctrl_identifiedBy != ""
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
      Ctrl_geospatial_quality = 0,
      Ctrl_verbatim_quality = 0,
      Ctrl_moreInformativeRecord = 0,
      UltraGBIF_digital_voucher = FALSE,
      UltraGBIF_duplicates = FALSE,
      UltraGBIF_non_groupable_duplicates = FALSE,
      UltraGBIF_num_duplicates = 0,
      UltraGBIF_duplicates_grouping_status = '',
      Ctrl_coordinates_validated_by_gbif_issue = FALSE,
      UltraGBIF_unidentified_sample = TRUE,
      UltraGBIF_wcvp_plant_name_id = '',
      UltraGBIF_sample_taxon_name = '',
      UltraGBIF_sample_taxon_name_status = '',
      UltraGBIF_number_taxon_names = 0,
      UltraGBIF_useful_for_spatial_analysis = FALSE,
      UltraGBIF_decimalLatitude = NA_real_,
      UltraGBIF_decimalLongitude = NA_real_
    )]

    # Validate coordinates based on GBIF issues
    occ[, Ctrl_coordinates_validated_by_gbif_issue := rowSums(.SD) == 0, .SDcols = a3]
    occ[, Ctrl_coordinates_validated_by_gbif_issue := ifelse(
      Ctrl_hasCoordinate == FALSE | Ctrl_decimalLatitude == 0 | Ctrl_decimalLongitude == 0,
      FALSE,
      Ctrl_coordinates_validated_by_gbif_issue)]
    occ[, Ctrl_coordinates_validated_by_gbif_issue := ifelse(
      is.na(Ctrl_coordinates_validated_by_gbif_issue),
      FALSE,
      Ctrl_coordinates_validated_by_gbif_issue)]

    # Calculate geospatial quality score
    occ[, Ctrl_geospatial_quality := fcase(
      rowSums(.SD[, a3, with = FALSE]) > 0, -9,
      rowSums(.SD[, a2, with = FALSE]) > 0, -3,
      rowSums(.SD[, a1, with = FALSE]) > 0, -1,
      default = 0
    )]
    occ[Ctrl_hasCoordinate == FALSE, Ctrl_geospatial_quality := -9]

    # Calculate verbatim quality score (record completeness)
    occ[, Ctrl_verbatim_quality := tem_recordedBy + tem_recordNumber + tem_year +
          tem_institutionCode + tem_catalogNumber + tem_locality +
          tem_municipality + tem_stateProvince + tem_COUNTRY + tem_identifiedBy]

    # Calculate total quality score
    occ[, Ctrl_moreInformativeRecord := Ctrl_geospatial_quality + Ctrl_verbatim_quality]

  }


  # Step 1: Pre-compute grouping key patterns using vectorized string operations
  # This identifies records that cannot be grouped due to missing information
  message("Pre-compute grouping key patterns...")
  occ[, grouping_pattern := fcase(
    # Condition 1: FAMILY_UNKNOWN_ (with neither recordedBy nor recordNumber)
    stri_endswith_fixed(Ctrl_key,'_UNKNOWN_'),"FAMILY__",

    # Condition 2: FAMILY_recordedBy_ (only without recordedBy)
    stri_detect_fixed(Ctrl_key, "_UNKNOWN_") &
      !stri_endswith_fixed(Ctrl_key, "_"),"FAMILY_recordedBy_",

    # Condition 3: FAMILY__recordNumber (only without recordNumber)
    !stri_detect_fixed(Ctrl_key, "_UNKNOWN_") &
      stri_endswith_fixed(Ctrl_key, "_"),"FAMILY__recordNumber",

    # Default: Groupable
    default = "groupable"
  )]

  # Create logic flag column
  occ[, `:=`(
    FAMILY__ = grouping_pattern == "FAMILY__",
    FAMILY_recordedBy_ = grouping_pattern == "FAMILY_recordedBy_",
    FAMILY__recordNumber = grouping_pattern == "FAMILY__recordNumber",
    is_non_groupable = grouping_pattern != "groupable"
  )]

  # Step 2: Handle non-groupable records in batch
  message("Handle non-groupable records")
  # These records are treated as individual samples with no duplicates
  occ[is_non_groupable == TRUE, `:=`(
    UltraGBIF_digital_voucher = TRUE,
    UltraGBIF_non_groupable_duplicates = TRUE,
    UltraGBIF_duplicates = FALSE,
    UltraGBIF_num_duplicates = 1L,

    # Set taxon information based on acceptance status
    UltraGBIF_wcvp_plant_name_id = fifelse(wcvp_taxon_status == "Accepted",
                                           as.character(wcvp_plant_name_id),
                                           ""),
    UltraGBIF_sample_taxon_name = fifelse(wcvp_taxon_status == "Accepted",
                                          as.character(wcvp_taxon_name),
                                          ""),
    UltraGBIF_unidentified_sample = fifelse(wcvp_taxon_status == "Accepted", FALSE, TRUE),
    UltraGBIF_number_taxon_names = fifelse(wcvp_taxon_status == "Accepted", 1L, 0L),
    UltraGBIF_sample_taxon_name_status = fifelse(wcvp_taxon_status == "Accepted",
                                                 "identified",
                                                 "unidentified"),

    # Set coordinate information based on validation status
    UltraGBIF_decimalLatitude = fifelse(Ctrl_coordinates_validated_by_gbif_issue == TRUE,
                                        Ctrl_decimalLatitude%>%as.double(),
                                        NA_real_),
    UltraGBIF_decimalLongitude = fifelse(Ctrl_coordinates_validated_by_gbif_issue == TRUE,
                                         Ctrl_decimalLongitude%>%as.double(),
                                         NA_real_),
    UltraGBIF_useful_for_spatial_analysis = Ctrl_coordinates_validated_by_gbif_issue,

    # Set grouping status description
    UltraGBIF_duplicates_grouping_status = fcase(
      FAMILY__ == TRUE, "not groupable: no recordedBy and no recordNumber",
      FAMILY__recordNumber == TRUE, "not groupable: no recordNumber",
      FAMILY_recordedBy_ == TRUE, "not groupable: no recordedBy",
      default = "not groupable"
    )
  )]

  # Step 3: Process groupable records
  message("Process groupable records...")
  # Set key for efficient grouping operations
  setkey(occ, Ctrl_key)

  # Calculate group statistics and identify digital vouchers
  occ[is_non_groupable == FALSE,
      num_duplicates := .N,
      by = Ctrl_key]

  occ[is_non_groupable == FALSE,
      max_info_score := max(Ctrl_moreInformativeRecord),
      by = Ctrl_key]

  occ[is_non_groupable == FALSE,
      UltraGBIF_digital_voucher := Ctrl_moreInformativeRecord == max_info_score &
        .I == .I[which.max(Ctrl_moreInformativeRecord)],
      by = Ctrl_key]

  # Set basic grouping information
  occ[is_non_groupable == FALSE, `:=`(
    UltraGBIF_duplicates_grouping_status = "groupable",
    UltraGBIF_duplicates = num_duplicates > 1,
    UltraGBIF_num_duplicates = num_duplicates
  )]


  # Step 4: Process taxonomic information for groupable records (Optimized)
  message("Process taxonomic information for groupable records...")

  sub_dt <- occ[is_non_groupable == FALSE &
                  wcvp_taxon_status == "Accepted" &
                  !is.na(wcvp_taxon_name),
                .(Ctrl_key, wcvp_taxon_name, wcvp_plant_name_id)]

  if (nrow(sub_dt) > 0) {

    taxon_counts <- sub_dt[, .N, by = .(Ctrl_key,
                                        wcvp_taxon_name, wcvp_plant_name_id)]

    setorder(taxon_counts, Ctrl_key, -N, wcvp_taxon_name, wcvp_plant_name_id)

    selected_taxa <- taxon_counts[, .SD[1], by = Ctrl_key]

    unique_counts <- taxon_counts[, .(num_unique_taxa = .N), by = Ctrl_key]

    occ[selected_taxa, on = "Ctrl_key",
        `:=`(UltraGBIF_sample_taxon_name = i.wcvp_taxon_name,
             UltraGBIF_wcvp_plant_name_id = i.wcvp_plant_name_id)]

    occ[unique_counts, on = "Ctrl_key",
        num_unique_taxa := i.num_unique_taxa]
  }

  occ[is_non_groupable == FALSE, `:=`(
    UltraGBIF_sample_taxon_name = fifelse(is.na(UltraGBIF_sample_taxon_name), "", UltraGBIF_sample_taxon_name),
    UltraGBIF_wcvp_plant_name_id = fifelse(is.na(UltraGBIF_wcvp_plant_name_id), "", UltraGBIF_wcvp_plant_name_id),
    UltraGBIF_number_taxon_names = fifelse(is.na(num_unique_taxa), 0L, num_unique_taxa),
    UltraGBIF_sample_taxon_name_status = fcase(
      is.na(num_unique_taxa) | num_unique_taxa == 0L, "unidentified",
      num_unique_taxa == 1L, "identified",
      num_unique_taxa > 1L, "divergent identifications",
      default = "unidentified"
    ),
    UltraGBIF_unidentified_sample = (is.na(num_unique_taxa) | num_unique_taxa == 0L)
  )]

  rm(sub_dt, taxon_counts, selected_taxa, unique_counts)

  # Step 5: Assign coordinates for groupable records
  message("Assign coordinates for groupable records...")
  # Create coordinate priority score (higher for digital voucher and better quality)
  occ[is_non_groupable == FALSE,
      coord_priority := fifelse(
        Ctrl_coordinates_validated_by_gbif_issue == TRUE,
        UltraGBIF_digital_voucher * 1000000 + Ctrl_geospatial_quality,
        -1
      )]

  # Get the coordinates from the record with highest priority
  occ[is_non_groupable == FALSE,
      `:=`(
        best_lat = fifelse(
          any(Ctrl_coordinates_validated_by_gbif_issue == TRUE),
          Ctrl_decimalLatitude[which.max(coord_priority)],
          NA_real_
        ),
        best_lon = fifelse(
          any(Ctrl_coordinates_validated_by_gbif_issue == TRUE),
          Ctrl_decimalLongitude[which.max(coord_priority)],
          NA_real_
        )
      ),
      by = Ctrl_key]

  # Assign the selected coordinates to all records in the group
  occ[is_non_groupable == FALSE, `:=`(
    UltraGBIF_decimalLatitude = best_lat,
    UltraGBIF_decimalLongitude = best_lon,
    UltraGBIF_useful_for_spatial_analysis = !is.na(best_lat)
  )]

  # Step 6: Clean up temporary columns
  message("Clean up temps...")
  occ[, `:=`(
    grouping_pattern = NULL,
    FAMILY__ = NULL,
    FAMILY_recordedBy_ = NULL,
    FAMILY__recordNumber = NULL,
    is_non_groupable = NULL,
    num_duplicates = NULL,
    max_info_score = NULL,
    #taxon_id = NULL,
    num_unique_taxa = NULL,
    #selected_taxon = NULL,
    coord_priority = NULL,
    best_lat = NULL,
    best_lon = NULL
  )]


  # Select result columns
  occ_results <- occ[, .(Ctrl_gbifID,
                         Ctrl_geospatial_quality,
                         Ctrl_verbatim_quality,
                         Ctrl_moreInformativeRecord,
                         UltraGBIF_digital_voucher,
                         UltraGBIF_duplicates,
                         UltraGBIF_num_duplicates,
                         UltraGBIF_non_groupable_duplicates,
                         UltraGBIF_duplicates_grouping_status,
                         Ctrl_coordinates_validated_by_gbif_issue,
                         UltraGBIF_unidentified_sample,
                         UltraGBIF_wcvp_plant_name_id,
                         UltraGBIF_sample_taxon_name,
                         UltraGBIF_sample_taxon_name_status,
                         UltraGBIF_number_taxon_names,
                         UltraGBIF_useful_for_spatial_analysis,
                         UltraGBIF_decimalLatitude,
                         UltraGBIF_decimalLongitude)] %>% setorder(Ctrl_gbifID)


  # ============================================================================
  # SECTION 8: Combine with Original Data and Add Final Classifications
  # ============================================================================
  message("Merging...")

  {
    # Combine all data
    occ_all <- cbind(occ_in, occ_wcvp_check_name, occ_collectorsDictionary, occ_results) %>% setDT()
    col_tmp <- unique(names(occ_all))
    occ_all <- occ_all[, ..col_tmp]

    # Add final dataset result classification
    occ_all[, UltraGBIF_dataset_result := fcase(
      UltraGBIF_digital_voucher == TRUE &
        UltraGBIF_unidentified_sample == FALSE &
        UltraGBIF_useful_for_spatial_analysis == TRUE , "usable",
      UltraGBIF_digital_voucher == FALSE, "duplicate",
      UltraGBIF_digital_voucher == TRUE &
        (UltraGBIF_unidentified_sample == TRUE |
           UltraGBIF_useful_for_spatial_analysis == FALSE |
           is.na(UltraGBIF_decimalLongitude) == TRUE), "unusable"
    )]

    # Merge with WCVP accepted name details
    name_tmp <- occ_wcvp_check_name[, .(wcvp_plant_name_id = as.character(wcvp_plant_name_id),
                                        wcvp_taxon_rank,
                                        wcvp_taxon_status,
                                        wcvp_family,
                                        wcvp_taxon_name,
                                        wcvp_taxon_authors,
                                        wcvp_reviewed)] %>%
      unique(by = "wcvp_plant_name_id") %>%
      setnames(paste0('UltraGBIF_', names(.))) %>%
      stats::na.omit()

    occ_all <- merge(occ_all, name_tmp, by = 'UltraGBIF_wcvp_plant_name_id', all.x = TRUE)

    # Select final columns
    cols_to_keep <- c("Ctrl_gbifID", "Ctrl_bibliographicCitation", "Ctrl_language",
                      "Ctrl_institutionCode", "Ctrl_collectionCode", "Ctrl_datasetName",
                      "Ctrl_basisOfRecord", "Ctrl_catalogNumber", "Ctrl_recordNumber",
                      "Ctrl_recordedBy", "Ctrl_georeferenceVerificationStatus",
                      "Ctrl_occurrenceStatus", "Ctrl_eventDate", "Ctrl_year", "Ctrl_month",
                      "Ctrl_day", "Ctrl_habitat", "Ctrl_identifiedBy", "Ctrl_eventRemarks",
                      "Ctrl_locationID", "Ctrl_higherGeography", "Ctrl_islandGroup",
                      "Ctrl_island", "Ctrl_countryCode", "Ctrl_stateProvince",
                      "Ctrl_municipality", "Ctrl_county", "Ctrl_locality",
                      "Ctrl_verbatimLocality", "Ctrl_locationRemarks", "Ctrl_level0Name",
                      "Ctrl_level1Name", "Ctrl_level2Name", "Ctrl_level3Name",
                      "Ctrl_identifiedBy", "Ctrl_dateIdentified", "Ctrl_scientificName",
                      "Ctrl_decimalLatitude", "Ctrl_decimalLongitude", "Ctrl_identificationQualifier",
                      "Ctrl_typeStatus", "Ctrl_family", "Ctrl_taxonRank", "Ctrl_issue",
                      "Ctrl_nameRecordedBy_Standard", "Ctrl_recordNumber_Standard",
                      "Ctrl_key", "Ctrl_geospatial_quality",
                      "Ctrl_verbatim_quality", "Ctrl_moreInformativeRecord",
                      "Ctrl_coordinates_validated_by_gbif_issue", "wcvp_plant_name_id",
                      "wcvp_taxon_rank", "wcvp_taxon_status", "wcvp_family",
                      "wcvp_taxon_name", "wcvp_taxon_authors", "wcvp_reviewed",
                      "wcvp_searchedName", "wcvp_searchNotes", "UltraGBIF_digital_voucher",
                      "UltraGBIF_duplicates", "UltraGBIF_num_duplicates",
                      "UltraGBIF_non_groupable_duplicates", "UltraGBIF_duplicates_grouping_status",
                      "UltraGBIF_unidentified_sample", "UltraGBIF_sample_taxon_name",
                      "UltraGBIF_sample_taxon_name_status", "UltraGBIF_number_taxon_names",
                      "UltraGBIF_useful_for_spatial_analysis", "UltraGBIF_decimalLatitude",
                      "UltraGBIF_decimalLongitude", "UltraGBIF_dataset_result", "UltraGBIF_wcvp_plant_name_id",
                      "UltraGBIF_wcvp_taxon_rank", "UltraGBIF_wcvp_taxon_status",
                      "UltraGBIF_wcvp_family", "UltraGBIF_wcvp_taxon_name",
                      "UltraGBIF_wcvp_taxon_authors", "UltraGBIF_wcvp_reviewed")

    occ_all <- occ_all[, ..cols_to_keep]
  }

  # ============================================================================
  # SECTION 9: Return Results
  # ============================================================================

  end <- Sys.time()

  used=end-start
  message(paste('used',used%>%round(1),attributes(used)$units))
  voucher <- list(
    occ_digital_voucher = occ_all,
    occ_results = occ_results,
    runtime = end - start
  )
  class(voucher) <- 'UltraGBIF_voucher'
  return(voucher)
}


