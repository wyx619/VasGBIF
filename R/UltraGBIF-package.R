#' @title Fast and Easy Compilation of Vascular Plants Occurrence Records from GBIF
#' @name VasGBIF
#' @keywords package
#'
#' @description
#' \if{html}{\figure{logo.png}{options: width="120" alt="logo" style="float: right"}}
#'
#' GBIF hosts over 500 million tracheophyte (vascular plant) occurrence
#' records, but processing them typically involves complex workflows and
#' substantial computational overhead. **VasGBIF** is a fast, plant-optimised
#' R package that parses, validates, and consolidates GBIF occurrence records
#' into analysis-ready datasets.
#'
#' VasGBIF integrates taxonomic resolution via the [TNRS], spatial validation
#' via [CoordinateCleaner], duplicate consolidation, and native-range
#' annotation against WCVP and WGSRPD within a single high-performance
#' pipeline. Its vectorised design and selective parallelisation let it process
#' one million records on a laptop in under 15 minutes without specialised
#' hardware.
#'
#' @details
#' ## Pipeline overview
#'
#' VasGBIF provides a reproducible workflow organised into four sequential
#' stages built around seven core functions. The core pipeline typically
#' retains approximately 35% of input records as high-quality, non-redundant
#' data.
#'
#' ### Stage 1 — Import and taxonomic standardisation
#'
#' - [import_records()]: loads a GBIF occurrence download ZIP, extracts the
#'   occurrence table, and parses GBIF issue flags.
#' - [check_taxon()]: submits species- and infraspecific-rank names to the
#'   Taxonomic Name Resolution Service (TNRS; Boyle et al. 2013) for
#'   resolution against the World Checklist of Vascular Plants (WCVP).
#'   Synonyms are resolved to accepted names; names that cannot be matched
#'   are flagged for review.
#'
#' ### Stage 2 — Duplicate detection via collection-event keys
#'
#' - [get_collections()]: builds a composite key for each record from its
#'   accepted taxon name, collection date, and rounded coordinates. Records
#'   sharing the same key are treated as potential duplicates from a single
#'   gathering event.
#' - [set_vouchers()]: scores each record on metadata completeness (nine
#'   fields) and geospatial quality (GBIF issue flags) and selects the
#'   highest-scoring record in each duplicate group as the master digital
#'   voucher. Records with incomplete keys are kept as independent vouchers.
#'
#' ### Stage 3 — Coordinate validation and native-status annotation
#'
#' - [refine_records()]: restores missing metadata from duplicate records via
#'   [restore_duplicates()], then validates coordinates with
#'   [CoordinateCleaner::clean_coordinates()] (Zizka et al. 2019) to flag spatial errors such as
#'   centroids, capitals, marine coordinates, and zero coordinates. Matches
#'   validated coordinates to [WGSRPD Level 3][WGSRPD3] and [WCVP
#'   distribution][Distributions] data via [detect_native_status()] to
#'   classify each record as native, introduced, extinct, location_doubtful,
#'   or unknown.
#'
#' ### Stage 4 — Export and visualisation
#'
#' - [export_records()]: writes the refined records to disk as three
#'   gzip-compressed CSV files: all usable records, the native subset, and
#'   records that failed coordinate validation.
#' - [map_records()]: renders refined records on interactive maps via
#'   [`mapView()`][mapview::mapView], with geohash-based decluttering and
#'   colour-coding by native status. Supports multiple basemap layers
#'   (OpenStreetMap, Esri World Imagery, and others).
#'
#' ## Quick start
#'
#' The built-in example dataset lets you run the full pipeline without a
#' GBIF download:
#'
#' ```r
#' library(VasGBIF)
#'
#' # Step 1: Import (built-in example, or use your own ZIP)
#' gbif_file <- system.file(
#'   "extdata", "0003386-260721160103020.zip",
#'   package = "VasGBIF"
#' )
#' occ_import <- import_records(path = gbif_file)
#'
#' # Step 2: Resolve taxon names against WCVP
#' taxa_checked <- check_taxon(occ_import = occ_import, accuracy = 0.9)
#'
#' # Step 3: Build collection-event keys
#' collection_keys <- get_collections(
#'   occ_import = occ_import,
#'   taxa_checked = taxa_checked,
#'   precision = 2L
#' )
#'
#' # Step 4: Select digital vouchers
#' voucher <- set_vouchers(
#'   occ_import = occ_import,
#'   taxa_checked = taxa_checked,
#'   collection_keys = collection_keys
#' )
#'
#' # Step 5: Validate coordinates and annotate native status
#' refined_records <- refine_records(
#'   voucher = voucher,
#'   threads = 4
#' )
#'
#' # Step 6: Export records
#' export_records(refined_records = refined_records,
#'   export_path = getwd())
#'
#' # Optional: visualise on an interactive map
#' map_records(refined_records = refined_records, precision = 3,
#'   cex = 3)
#' ```
#'
#' ## Performance
#'
#' VasGBIF achieves its speed through several architectural choices:
#'
#' - **C/C++ backends**: core operations are delegated to [data.table],
#'   [stringi], and [terra] — packages written in C/C++ that bypass R's
#'   per-iteration interpretive overhead.
#' - **Vectorisation over explicit loops**: functions such as [set_vouchers()]
#'   use vectorised string matching [`stri_detect_fixed()`][stringi::stri_detect_fixed]
#'   and conditional assignment [`fcase()`][data.table::fcase] to process
#'   entire columns in a single compiled call rather than iterating in R.
#' - **SIMD exploitation**: vectorised routines in [stringi] and
#'   [`terra::extract()`][terra::extract] allow the compiler to emit SIMD
#'   instructions (AVX, AVX-512) that process multiple data elements per CPU
#'   cycle.
#' - **Memory-efficient design**: [data.table]'s in-place modification
#'   `:=`, [`set()`][data.table::set]) avoids unnecessary copies, and
#'   contiguous memory access patterns improve CPU cache utilisation.
#' - **Selective parallelisation**: [refine_records()] partitions the dataset
#'   into chunks and distributes [CoordinateCleaner] validation across
#'   workers via [foreach] and [doParallel], combining vectorised processing
#'   within each chunk with parallel execution across chunks.
#'
#' On a standard laptop, VasGBIF compiles one million occurrence records
#' within 15 minutes.
#'
#' @examplesIf interactive()
#' # Three vignettes walk through the entire VasGBIF workflow, from
#' # data acquisition to final export:
#' vignette("GetRecords",   package = "VasGBIF")  # search & download GBIF data
#' vignette("Example",      package = "VasGBIF")  # quick-start with built-in data
#' vignette("Application",  package = "VasGBIF")  # real-world full-pipeline walk-through
#'
#' @references
#' 1. Appelhans, Tim, Florian Detsch, Christoph Reudenbach, and Stefan
#'    Woellauer. 2023. "Mapview: Interactive Viewing of Spatial Data in R."
#'    <https://CRAN.R-project.org/package=mapview>.
#'
#' 2. Boyle, Brad, Nicole Hopkins, Zhenyuan Lu, Juan Antonio Raygoza Garay,
#'    Dmitry Mozzherin, Tony Rees, Naim Matasci, et al. 2013. "The Taxonomic
#'    Name Resolution Service: An Online Tool for Automated Standardization
#'    of Plant Names." *BMC Bioinformatics* 14 (1): 16.
#'    \doi{10.1186/1471-2105-14-16}.
#'
#' 3. Chirico, Michael. 2023. "geohashTools: Tools for Working with
#'    Geohashes." <https://CRAN.R-project.org/package=geohashTools>.
#'
#' 4. De Melo, Pablo Hendrigo Alves, Nadia Bystriakova, Eve Lucas, and
#'    Alexandre K. Monro. 2024. "A New R Package to Parse Plant Species
#'    Occurrence Records into Unique Collection Events Efficiently Reduces
#'    Data Redundancy." *Scientific Reports* 14 (1): 5450.
#'    \doi{10.1038/s41598-024-56158-3}.
#'
#' 5. Vilela, Bruno, and Fabricio Villalobos. 2015. "letsR: A New R Package
#'    for Data Handling and Analysis in Macroecology." Edited by Timothée
#'    Poisot. *Methods in Ecology and Evolution* 6 (10): 1229-34.
#'    \doi{10.1111/2041-210x.12401}.
#'
#' 6. Zizka, Alexander, Daniele Silvestro, Tobias Andermann, Josue Azevedo,
#'    Camila Duarte Ritter, Daniel Edler, Harith Farooq, et al. 2019.
#'    "CoordinateCleaner: Standardized Cleaning of Occurrence Records from
#'    Biological Collection Databases." Edited by Tiago Quental.
#'    *Methods in Ecology and Evolution* 10 (5): 744-51.
#'    \doi{10.1111/2041-210X.13152}.
#'
#' @import bit64
NULL

# ---- Suppress data.table NSE notes in R CMD check ---------------------------
utils::globalVariables(c(
  # dplyr pipe placeholder
  ".",
  # data.table specials
  "N",
  # ---- GBIF occurrence fields (from import_records) ----
  "gbifID",
  "scientificName",
  "taxonRank",
  "eventDate",
  "decimalLatitude",
  "decimalLongitude",
  "countryCode",
  "institutionCode",
  "catalogNumber",
  "recordedBy",
  "recordNumber",
  "stateProvince",
  "locality",
  "identifiedBy",
  # ---- WCVP taxonomic fields (from TNRS / check_taxon) ----
  "wcvp_searchedName",
  "Name_submitted",
  "Name_matched_id",
  "Name_matched",
  "Author_matched",
  "Taxonomic_status",
  "Accepted_name_id",
  "Accepted_name",
  "Accepted_name_author",
  "Accepted_name_rank",
  "Accepted_family",
  "wcvp_plant_name_id",
  "wcvp_taxon_rank",
  "wcvp_taxon_status",
  "wcvp_family",
  "wcvp_taxon_name",
  "wcvp_taxon_authors",
  "wcvp_accepted_plant_name_id",
  "wcvp_reviewed",
  "wcvp_taxon_status_of_searchedName",
  "wcvp_plant_name_id_of_searchedName",
  "wcvp_taxon_authors_of_searchedName",
  "wcvp_verified_author",
  "wcvp_verified_speciesName",
  "wcvp_searchNotes",
  "ori_sp_name",
  # ---- VasGBIF internal columns (from set_vouchers etc.) ----
  "collection_key",
  "COUNTRY_INVALID",
  "coordinates_validated_by_gbif_issue",
  "geospatial_quality",
  "verbatim_quality",
  "moreInformativeRecord",
  "is_non_groupable",
  "num_duplicates",
  "max_info_score",
  "num_unique_taxa",
  "coord_priority",
  "best_lat",
  "best_lon",
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
  "VasGBIF_restored_from_duplicate",
  # ---- i.* join columns (data.table merge-by-reference) ----
  "i.wcvp_taxon_name",
  "i.wcvp_plant_name_id",
  "i.num_unique_taxa",
  "i.clean_value",
  # ---- Temporary variables ----
  "tem_year",
  "tem_institutionCode",
  "tem_catalogNumber",
  "tem_recordedBy",
  "tem_recordNumber",
  "tem_COUNTRY",
  "tem_stateProvince",
  "tem_locality",
  "tem_identifiedBy",
  "clean_value",
  "best_value",
  "..col_tmp",
  "..cols_to_keep",
  "..fields_to_parse",
  # ---- refine_records mapping columns ----
  "taxon_name",
  "native_status",
  "location_doubtful",
  "introduced",
  "extinct",
  "area_code_l3",
  "LEVEL3_COD",
  "summary",
  # ---- refine_records mapping columns ----
  ".summary",
  # ---- check_taxon temp column ----
  "wcvp_searchedName2",
  # ---- map_records ----
  "geohash",
  # ---- Package datasets ----
  "EnumOccurrenceIssue",
  "constant",
  "Distributions",
  "WGSRPD3",
  "WorldLandMap",
  # ---- utils::data suggestion (used in package doc examples) ----
  "data"
))
