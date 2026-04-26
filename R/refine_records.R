#' @title Validate coordinates, restore metadata, and extract geographic distribution status
#' @name refine_records
#'
#' @description This module validates spatial information and restores detailed metadata for usable
#' vouchers. It performs automated coordinate validation using CoordinateCleaner (Zizka et al., 2019)
#' to flag spatial errors (e.g., centroids, capitals, institutions). It also extracts native status
#' information based on the World Geographical Scheme for Recording Plant Distributions (WGSRPD) to
#' classify records as native or non-native.
#'
#' The function implements the following workflow:
#' \itemize{
#'   \item \strong{Metadata restoration}: For each digital voucher identified in the previous step,
#'   consolidates missing or incomplete metadata fields from its associated duplicate records.
#'   Fields such as locality descriptions, habitat information, and collection dates are merged
#'   to produce the most complete record possible
#'   \item \strong{Coordinate validation}: Applies CoordinateCleaner's automated spatial validation
#'   suite to detect and flag common geospatial errors, including records located at country centroids,
#'   capital cities, biodiversity institutions, maritime coordinates, and other known error patterns
#'   \item \strong{Geographic distribution extraction}: Matches each record's coordinates against
#'   WGSRPD Level 3 areas and cross-references with WCVP (World Checklist of Vascular Plants)
#'   distribution data to determine whether the occurrence falls within the species' native range
#'   \item \strong{Native status classification}: Classifies records as "native", "introduced",
#'   "extinct", "location_doubtful", or "unknown" based on the intersection of observed coordinates
#'   with documented distribution areas
#'   \item \strong{Parallel processing}: Distributes coordinate validation across multiple threads
#'   to accelerate processing of large datasets
#' }
#'
#' @param voucher UltraGBIF_voucher object from \code{\link{set_digital_voucher}}
#' @param threads number of threads for parallel coordinate validation. Can be specified as:
#'   \itemize{
#'     \item An integer >= 1: absolute number of threads to use
#'     \item A value between 0 and 1: proportion of available cores to use (e.g., 0.5 = 50%)
#'   }
#'   Default is 4.
#' @param save_path local directory path where refined records will be exported as compressed CSV files.
#'   If not provided, results are returned in memory only.
#' @param tests character vector specifying which CoordinateCleaner validation tests to apply.
#'   Choose one or more from: \code{"capitals"}, \code{"centroids"}, \code{"equal"}, \code{"gbif"},
#'   \code{"institutions"}, \code{"outliers"}, \code{"seas"}, \code{"zeros"}.
#'   Default is all tests.
#'
#' @details
#' \strong{Metadata Restoration Strategy:}
#'
#' For each voucher record marked as "usable", the function identifies duplicate records sharing
#' the same collection event key. It then iterates through a predefined set of metadata fields
#' (e.g., \code{Ctrl_identifiedBy}, \code{Ctrl_locality}, \code{Ctrl_habitat}) and fills in missing
#' values from the first available duplicate. Fields exceeding 10,000 characters are excluded to
#' prevent memory issues.
#'
#' \strong{Coordinate Validation Tests:}
#'
#' The following spatial validation tests are available via CoordinateCleaner:
#' \itemize{
#'   \item \code{capitals}: Flags records located at country capital coordinates
#'   \item \code{centroids}: Flags records at country or province centroids
#'   \item \code{equal}: Flags records with identical latitude and longitude values
#'   \item \code{gbif}: Flags records matching known GBIF geospatial issues
#'   \item \code{institutions}: Flags records at known herbarium or museum coordinates
#'   \item \code{outliers}: Flags records that are geographic outliers within their species' range
#'   \item \code{seas}: Flags records located in marine areas for terrestrial species
#'   \item \code{zeros}: Flags records at coordinates (0, 0)
#' }
#'
#' \strong{WGSRPD Area Classification:}
#'
#' The native status classification is determined by intersecting validated coordinates with
#' WGSRPD Level 3 administrative areas and cross-referencing with WCVP distribution data:
#' \itemize{
#'   \item \code{native}: Record falls within the species' documented native range
#'   \item \code{introduced}: Record falls within an area where the species is known to be introduced
#'   \item \code{extinct}: Record falls within an area where the species is documented as extinct
#'   \item \code{location_doubtful}: WCVP flags the distribution record as uncertain
#'   \item \code{unknown}: No matching distribution data or area assignment available
#' }
#'
#'
#'
#' @return UltraGBIF_refine list containing:
#'   \itemize{
#'     \item \code{native_records}: A data.table of records classified as native occurrences,
#'     including validated coordinates, restored metadata, and WGSRPD area codes
#'     \item \code{other_records}: A data.table of records classified as non-native (introduced,
#'     extinct, location_doubtful, or unknown)
#'     \item \code{runtime}: Execution time of the function
#'   }
#' When \code{save_path} is specified, two compressed CSV files are generated:
#' \itemize{
#'   \item \code{usable_refined_records.csv.gz}: All refined records with validated coordinates
#'   and restored metadata
#'   \item \code{native_refined_records.csv.gz}: Subset of refined records classified as native
#'   occurrences
#' }
#' @references
#' \itemize{
#'    \item Zizka, A., Silvestro, D., Andermann, T., Azevedo, J., Duarte Ritter, C., Edler, D., Farooq, H.,
#' Herdean, A., Ariza, M., Scharn, R., Svantesson, S., Wengstrom, N., Vitecek, S., & Antonelli, A.
#' (2019). CoordinateCleaner: Standardized cleaning of occurrence records from biological collection
#' databases. \emph{Methods in Ecology and Evolution}, 10(5), 744-751. \doi{10.1111/2041-210X.13152}
#'    \item Govaerts, R., Nic Lughadha, E., Black, N. et al. The World Checklist of Vascular Plants,
#'    a continuously updated resource for exploring global plant diversity.
#'    \emph{Sci Data} 8, 215 (2021). \doi{10.1038/s41597-021-00997-6}
#'}
#' @import data.table
#' @importFrom dplyr %>%
#' @import foreach
#' @import doParallel
#' @import rnaturalearthdata
#' @importFrom utils head
#' @import stringi
#' @seealso \code{\link[CoordinateCleaner]{clean_coordinates}}
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
#'
#' refined_records <- refine_records(voucher = voucher,
#' threads = 4,
#' save_path = getwd(),
#' tests = c("capitals", "centroids", "equal", "gbif",
#' "institutions", "outliers", "seas","zeros"))
#'}
#' @export
refine_records<-function(voucher = NA,
                         threads = 4,
                         save_path = NA,
                         tests = c("capitals",
                                   "centroids",
                                   "equal",
                                   "gbif",
                                   "institutions",
                                   "outliers",
                                   "seas",
                                   "zeros"))
{
  start=Sys.time()

  restore_duplicates <- function(occ_digital_voucher = NULL) {

    MAX_FIELD_LENGTH <- 10000
    fields_to_merge <- c(
      'Ctrl_identifiedBy', 'Ctrl_year', 'Ctrl_stateProvince', 'Ctrl_municipality',
      'Ctrl_locality', 'Ctrl_countryCode', 'Ctrl_eventDate', 'Ctrl_habitat',
      'Ctrl_level0Name', 'Ctrl_level1Name', 'Ctrl_level2Name', 'Ctrl_level3Name'
    )
    fields_to_parse <- c(
      'Ctrl_gbifID', 'Ctrl_bibliographicCitation', 'Ctrl_language',
      'Ctrl_institutionCode', 'Ctrl_collectionCode', 'Ctrl_datasetName',
      'Ctrl_basisOfRecord', 'Ctrl_catalogNumber', 'Ctrl_recordNumber',
      'Ctrl_recordedBy', 'Ctrl_occurrenceStatus', 'Ctrl_eventDate',
      'Ctrl_year', 'Ctrl_month', 'Ctrl_day', 'Ctrl_habitat',
      'Ctrl_eventRemarks', 'Ctrl_countryCode',
      'Ctrl_stateProvince', 'Ctrl_municipality', 'Ctrl_county',
      'Ctrl_locality', 'Ctrl_issue', 'Ctrl_level0Name', 'Ctrl_level1Name',
      'Ctrl_level2Name', 'Ctrl_level3Name', 'Ctrl_identifiedBy',
      'Ctrl_dateIdentified', 'Ctrl_scientificName', 'Ctrl_taxonRank',
      'Ctrl_decimalLatitude', 'Ctrl_decimalLongitude',
      'Ctrl_nameRecordedBy_Standard', 'Ctrl_recordNumber_Standard',
      'Ctrl_key', 'Ctrl_geospatial_quality',
      'Ctrl_verbatim_quality', 'Ctrl_moreInformativeRecord',
      'Ctrl_coordinates_validated_by_gbif_issue',
      "wcvp_plant_name_id", "wcvp_taxon_rank", "wcvp_taxon_status",
      "wcvp_family", "wcvp_taxon_name", "wcvp_taxon_authors",
      "wcvp_reviewed", "wcvp_searchedName", "wcvp_searchNotes",
      'UltraGBIF_digital_voucher', 'UltraGBIF_duplicates',
      'UltraGBIF_num_duplicates', 'UltraGBIF_non_groupable_duplicates',
      'UltraGBIF_duplicates_grouping_status', 'UltraGBIF_unidentified_sample',
      'UltraGBIF_sample_taxon_name', 'UltraGBIF_sample_taxon_name_status',
      'UltraGBIF_number_taxon_names', 'UltraGBIF_useful_for_spatial_analysis',
      'UltraGBIF_decimalLatitude', 'UltraGBIF_decimalLongitude',
      'UltraGBIF_wcvp_plant_name_id', 'UltraGBIF_wcvp_taxon_rank',
      'UltraGBIF_wcvp_taxon_status', 'UltraGBIF_wcvp_family',
      'UltraGBIF_wcvp_taxon_name', 'UltraGBIF_wcvp_taxon_authors',
      'UltraGBIF_wcvp_reviewed', 'UltraGBIF_dataset_result'
    )

    occ_tmp <- occ_digital_voucher[, ..fields_to_parse][, UltraGBIF_merged := FALSE]
    occ_in <- occ_tmp[UltraGBIF_dataset_result == "usable"]
    occ_dup <- occ_tmp[UltraGBIF_dataset_result == "duplicate"]
    merge_keys <- occ_in[UltraGBIF_duplicates == TRUE, unique(Ctrl_key)]
    rm(occ_tmp)
    setkeyv(occ_dup, "Ctrl_key")
    setkeyv(occ_in, "Ctrl_key")
    all_relevant_dups <- occ_dup[.(merge_keys)]
    for (field in fields_to_merge) {
      empty_keys <- occ_in[
        (is.na(get(field)) | get(field) == "" | get(field) == "NA") &
          UltraGBIF_duplicates == TRUE,
        unique(Ctrl_key)
      ]
      if (length(empty_keys) == 0) next

      candidates <- all_relevant_dups[
        .(empty_keys), on = "Ctrl_key"][
          !is.na(get(field)) &
            get(field) != "" &
            get(field) != "NA" &
            stringi::stri_length(get(field)) <= MAX_FIELD_LENGTH &
            stringi::stri_length(get(field)) > 0
        ][, .(best_value = head(get(field), 1)), by = Ctrl_key]

      if (nrow(candidates) == 0) next

      if (field == 'Ctrl_year') {
        candidates[, clean_value := suppressWarnings(as.integer(
          stringi::stri_trans_toupper(
            stringi::stri_replace_all_regex(best_value, "[\\{\\}\\[\\]\\(\\)\\\\\\*]", "")
          )
        ))]
      } else {
        candidates[, clean_value := stringi::stri_trans_toupper(
          stringi::stri_replace_all_regex(best_value, "[\\{\\}\\[\\]\\(\\)\\\\\\*]", "")
        )]
      }

      occ_in[candidates,
             c(field, "UltraGBIF_merged") := .(i.clean_value, TRUE),
             on = "Ctrl_key"]
      message(paste("Restoring",stri_replace_all_fixed(field,"Ctrl_","")))
    }
    return(occ_in)
  }

  voucher <- restore_duplicates(voucher$occ_digital_voucher)

  voucher[is.na(UltraGBIF_wcvp_taxon_name),`:=`(UltraGBIF_wcvp_taxon_rank=wcvp_taxon_rank,
                                                UltraGBIF_wcvp_taxon_status=wcvp_taxon_status,
                                                UltraGBIF_wcvp_family=wcvp_family,
                                                UltraGBIF_wcvp_taxon_name=wcvp_taxon_name,
                                                UltraGBIF_wcvp_taxon_authors=wcvp_taxon_authors,
                                                UltraGBIF_wcvp_reviewed=wcvp_reviewed)]

  voucher[,Ctrl_gbifID:=as.character(Ctrl_gbifID)]
  message("Validating coordinates")

  use_multi_threads<-function(x) {
    total=parallel::detectCores()
    if (!is.numeric(x))
    {stop("input must be numeric")}

    if (x > total)
    {stop("more than all available threads!")}

    if (x >= 1)
    {message(paste0(round(x),"/",total," ","threads used"))
      return(round(x))}

    if (x <= 0)
    {stop("illegal !!!")}

    if (0 < x && x < 1)
    {message(paste0(round(total*x)),"/",total," ","threads used")
      return(round(total*x))}
  }

  threads <- threads%>%as.numeric()%>%use_multi_threads()
  chunks_list <- voucher[,.(Ctrl_gbifID,
                            UltraGBIF_decimalLongitude,
                            UltraGBIF_decimalLatitude,
                            UltraGBIF_wcvp_plant_name_id,
                            Ctrl_countryCode,
                            UltraGBIF_wcvp_taxon_name)]%>%
    split(.,ceiling(seq_len(nrow(.)) / (nrow(.)/threads)))

  seas_ref=seas_ref

  coord <- function(data){
    suppressWarnings(CoordinateCleaner::clean_coordinates(data,
                                         lon = "UltraGBIF_decimalLongitude",
                                         lat = "UltraGBIF_decimalLatitude",
                                         species = "UltraGBIF_wcvp_plant_name_id",
                                         tests = tests,
                                         seas_ref = seas_ref,
                                         value = "clean",
                                         verbose = FALSE))
  }

  cl <- parallel::makeCluster(threads)

  registerDoParallel(cl)


  results_final_sf_ori <- foreach(data=chunks_list,
                                  .multicombine = T,
                                  .errorhandling = "remove",
                                  .packages = c("CoordinateCleaner","rnaturalearthdata","dplyr"),
                                  .inorder = F) %dopar% {coord(data)}

  results_final_sf_ori <- rbindlist(results_final_sf_ori,fill = T)

  parallel::stopCluster(cl)
  rm(chunks_list)
  species <- results_final_sf_ori[, unique(UltraGBIF_wcvp_taxon_name)]

  local <- ref_wcvp_names[taxon_name %chin% results_final_sf_ori$UltraGBIF_wcvp_taxon_name,]%>%
    merge(wcvp_distributions,by = "plant_name_id")

  local[,wcvp_area_status := fcase(
    location_doubtful == 1,"location_doubtful",
    introduced == 1, "introduced",
    extinct == 1,"extinct",
    introduced == 0 & extinct == 0 & location_doubtful == 0, "native",
    default = "unknown")][,c("introduced", "extinct", "location_doubtful") := NULL]

  wgsrpd3_map <- terra::vect(wgsrpd3)

  local_status <- function(taxon=NA_character_,results_final_sf_ori="") {

    species_df <- local[taxon_name == taxon,.(area_code_l3, wcvp_area_status)]

    if (nrow(species_df) == 0) {
      return(data.table(
        LEVEL3_COD = NA_character_,
        wcvp_area_status = "unknown",
        Ctrl_gbifID = results_final_sf_ori[UltraGBIF_wcvp_taxon_name == taxon,Ctrl_gbifID]
      ))
    }

    occurrence_points <- results_final_sf_ori[UltraGBIF_wcvp_taxon_name == taxon,
                                              .(Ctrl_gbifID,UltraGBIF_decimalLongitude,UltraGBIF_decimalLatitude)] %>%
      terra::vect(geom = c("UltraGBIF_decimalLongitude", "UltraGBIF_decimalLatitude"), crs = "EPSG:4326")

    distribution <-  terra::merge(wgsrpd3_map,species_df,
                                  by.x = "LEVEL3_COD",
                                  by.y = "area_code_l3")%>%.[, c("LEVEL3_COD", "wcvp_area_status")]

    extracted_data <- terra::extract(distribution,occurrence_points)%>%setDT()%>%unique(by="id.y")

    extracted_data[,.(Ctrl_gbifID=results_final_sf_ori[UltraGBIF_wcvp_taxon_name == taxon,Ctrl_gbifID],
                      LEVEL3_COD=LEVEL3_COD,
                      wcvp_area_status=fifelse(is.na(wcvp_area_status),"unknown",wcvp_area_status))]

  }

  area_final <- list()

  message("Extracting WGSRPD information")

  for (i in 1:length(species)) {
    area_final[[i]] <- local_status(taxon = species[i],results_final_sf_ori=results_final_sf_ori)
    if (i%%1000==0|i==length(species)) {
      message(paste("Extracting",i,"/",length(species)))
    }
  }

  area_final <- area_final%>%rbindlist(fill = T)%>%unique()

  results <- merge(voucher,area_final, by = "Ctrl_gbifID")
  final_col <- c("Ctrl_gbifID", "Ctrl_basisOfRecord", "Ctrl_catalogNumber",
                 "Ctrl_recordNumber", "Ctrl_recordedBy", "Ctrl_occurrenceStatus",
                 "Ctrl_eventDate", "Ctrl_key", "UltraGBIF_decimalLatitude", "UltraGBIF_decimalLongitude",
                 "UltraGBIF_wcvp_family", "UltraGBIF_wcvp_plant_name_id", "UltraGBIF_wcvp_taxon_status",
                 "UltraGBIF_wcvp_taxon_name", "UltraGBIF_wcvp_taxon_authors","UltraGBIF_merged",
                 "LEVEL3_COD", "wcvp_area_status","UltraGBIF_useful_for_spatial_analysis")
  native_records <- results[wcvp_area_status == "native", ..final_col]

  other_records <- results[wcvp_area_status != "native",..final_col]

  save_path <- tryCatch(
    dirname(gbif_occurrence_file),
    error = function(e) NA
  )
  if(!is.na(save_path)){
    tryCatch({
      message("Exporting refined records")
      fwrite(results,
             file = paste0(save_path,'/usable_refined_records.csv.gz'),
             encoding = "UTF-8")
      fwrite(native_records,
             file = paste0(save_path,'/native_refined_records.csv.gz'),
             encoding = "UTF-8")
    }, error = function(e) {
      # Print error message but do not stop execution
      warning("File export failed: ", e$message)
    })
  } else {warning('Check your save_path, remember to save results!')}

  end=Sys.time()
  used=end-start
  message(paste('used',used%>%round(1),attributes(used)$units))
  refined_records <- list(native_records=native_records,
                          other_records=other_records,
                          runtime=end-start)
  class(refined_records) <- 'UltraGBIF_refine'
  return(refined_records)
}
