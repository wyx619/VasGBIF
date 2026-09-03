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
#' via [CoordinateCleaner], and native-range annotation against WCVP and
#' WGSRPD within a single high-performance pipeline. Its vectorised design
#' and selective parallelisation let it process one million records on a
#' laptop in under 15 minutes without specialised hardware.
#'
#' @details
#' ## Pipeline overview
#'
#' VasGBIF provides a reproducible workflow organised into eight sequential
#' steps. Each step progressively filters records through taxonomic, quality,
#' and coordinate checks, transforming GBIF occurrence records into
#' analysis-ready datasets.
#'
#' 1. **Import Records** - [import_records()]: reads a GBIF occurrence
#'    download ZIP ('SIMPLE_CSV' or Darwin Core Archive), extracts the
#'    occurrence table, and returns an `"import"` data.table of the fields
#'    required by the workflow. No records are filtered at this step - all
#'    diagnostic flags are preserved for later quality scoring.
#'
#' 2. **Extract GBIF Issues** - [extract_gbif_issues()]: expands the raw
#'    pipe-separated `issue` column into one logical indicator column per GBIF
#'    issue code, plus a companion summary ranking issues by how many records
#'    they flag.
#'
#' 3. **Check Taxon Name** - [check_taxon()]: submits species- and
#'    infraspecific-rank names to the Taxonomic Name Resolution Service (TNRS;
#'    Boyle et al. 2013) for resolution against the World Checklist of
#'    Vascular Plants (WCVP) or World Flora Online (WFO). Synonyms are
#'    resolved to accepted names; records that fail the match-score threshold
#'    or lack an accepted/synonym status are excluded from the downstream
#'    table and reported in the `summary` for manual review.
#'
#' 4. **Custom Filter** - [customized_filter()]: joins the imported records with
#'    the resolved taxonomy and the parsed issue flags, then applies the
#'    enabled filter rules (country code, coordinate uncertainty, GBIF issue
#'    count, event date, collector and identifier fields) to retain only
#'    high-quality records. Every rule is independently toggleable, and each
#'    step is recorded in a per-rule audit table (see *Flexible and fluent
#'    custom filter system*).
#'
#' 5. **Refine Coordinates** - [clean_coordinates()]: validates coordinates
#'    with [CoordinateCleaner::clean_coordinates()] (Zizka et al. 2019) to
#'    flag spatial errors such as centroids, capitals, marine coordinates, and
#'    zero coordinates, splitting records into cleaned and problematic tables.
#'    Records that pass all tests go to `CoordinateCleaned`; those that fail
#'    any test or lack complete coordinates go to `CoordinateProblematic`.
#'    Validation is parallelized across user-specified threads.
#'
#' 6. **Detect Native Status** - [detect_native_coord()] and
#'    [detect_native_country()]: match each record against WCVP distribution
#'    data (the internal `Distributions` dataset) via WGSRPD Level 3 areas to
#'    classify it as native, introduced, extinct, location_doubtful, or
#'    unknown. [detect_native_coord()] processes records from
#'    `CoordinateCleaned` (those with validated coordinates);
#'    [detect_native_country()] processes all records from
#'    `CoordinateProblematic` (both coordinateless records and those that
#'    failed validation) using country codes (see *Precise native-status
#'    detection system*).
#'
#' 7. **Map Records** - [map_records()]: renders refined records on
#'    interactive maps via [`mapView()`][mapview::mapView], with geohash-based
#'    decluttering to reduce visual overlap. Records are colour-coded by
#'    native status, and multiple basemap layers are supported (OpenStreetMap,
#'    Esri World Imagery, and others).
#'
#' 8. **Export Records** - [export_records()]: writes the classified records
#'    to disk as two gzip-compressed CSV files: all usable records and the
#'    native subset.
#'
#' ## Precise native-status detection system
#'
#' [detect_native_coord()] and [detect_native_country()] are the analytical
#' core of VasGBIF: together they assign a native, introduced, extinct,
#' location_doubtful, or unknown classification to every occurrence by
#' matching the record's identification and position against authoritative
#' WCVP distribution data (the internal `Distributions` dataset) organised by
#' WGSRPD Level 3 areas. Classification is split across two functions so that
#' the most precise available evidence always wins: records from
#' `CoordinateCleaned` (those with validated coordinates) are matched
#' spatially by [detect_native_coord()], and records from
#' `CoordinateProblematic` (coordinateless records and those that failed
#' validation) are matched through their country code by
#' [detect_native_country()].
#'
#' **Spatial classification.** [detect_native_coord()] overlays records with
#' validated coordinates on the WGSRPD Level 3 polygon map with
#' [terra::extract()] - a single vectorised call that assigns every point its
#' area code in compiled code. Each area code is looked up in a distribution
#' table classified from the WCVP flags (`introduced`, `extinct`,
#' `location_doubtful`) with a fixed priority:
#'
#' 1. `location_doubtful` wins over every other flag;
#' 2. otherwise `introduced`;
#' 3. otherwise `extinct`;
#' 4. otherwise, when no flag is set, the area is `native`;
#' 5. any remaining case is `unknown`.
#'
#' A record that falls in several areas at once receives the most preferred
#' status (`native` first), never an arbitrary one. Coastal points that fall
#' just outside a polygon are still matched through a geodesic buffer
#' (`buffer_km`, applied in metres by [terra::buffer()] so its meaning is
#' identical at every latitude); buffered hits always rank below exact ones,
#' so a genuine in-polygon match is never displaced by a buffered candidate.
#' The buffer pass is chunked (`buffer_chunk_size`) to keep the relate matrix
#' small.
#'
#' **Country-code classification.** [detect_native_country()] matches records
#' from `CoordinateProblematic` through `countryCode` mapped to WGSRPD Level 3
#' areas by the `Level3maping` table. This includes both coordinateless
#' records and records that failed coordinate validation tests. No geometry is
#' used, so this pass is nearly free.
#'
#' Every classification records how it was obtained in
#' `native_status_source` - `spatial` / `spatial_buffered` for spatial
#' matches (exact and buffered), `country_code` for country-code matches,
#' `country_code_no_entry` when the country mapped but the taxon has no
#' distribution entry there, and `unmatched` when no usable key exists - so
#' the entire decision chain is auditable.
#'
#' **Precision without a speed penalty.** Hybrid markers are normalised so
#' `Alnus x pubescens` matches the multiplication-sign variant recorded in the
#' distributions; and neither the spatial overlay nor the distribution
#' lookup ever iterates record-by-record in R. Both functions return a
#' `nativeDetected` table keyed by `gbifID` that retains every column of the
#' input records and appends `LEVEL3_COD`, `native_status`,
#' `native_status_source`, and `buffered`; the spatial result feeds directly
#' into [export_records()] and [map_records()] without any join back to
#' `cleaned_coordinates`.
#'
#' ## Flexible and fluent custom filter system
#'
#' [customized_filter()] turns the raw download into an analysis-ready
#' occurrence table. It joins the three preceding outputs (`occ_import`,
#' `taxa_checked`, `gbif_issue`) into one table, then walks a user-selected
#' set of quality rules - one vectorised [data.table] pass per rule - with
#' every step audited.
#'
#' **Fluent rule control.** Each rule is an independently toggleable
#' argument. Three rules are on by default (`countryCode`,
#' `coordinateUncertainty <= 10000` m, `gbif_issues_max <= 5`), giving
#' sensible out-of-the-box behaviour; `date`, `identifiedBy`, and
#' `recordedBy` are opt-in, so no information is discarded without an
#' explicit choice. Numeric thresholds share one uniform "off" convention -
#' `NULL`, `NA`, or `''` - so any rule can be disabled without restructuring
#' the call.
#'
#' **Auditable pipeline.** Every step - the `taxon_resolved` join as well as
#' each enabled rule - is logged in the returned `summary` table (`rule`,
#' `dropped`, `remaining`), making the effect of each decision visible and
#' reproducible. The joins are deliberately strict: the taxonomic join drops
#' unresolved names instead of carrying `NA` taxonomy forward, and the
#' one-to-one issue join is verified at runtime, stopping if any record
#' lacks an issue count.
#'
#' **Careful collector and identifier detection.** The `identifiedBy` and
#' `recordedBy` rules remove only values that contain no named person:
#' missing or empty values, a curated multilingual keyword list (`unknown`,
#' `anonymous`, `desconocido`, `inconnu`, `unbekannt`, plus Chinese terms for
#' "unknown", "unnamed", "anonymous" and "no details"), and whole-value
#' patterns such as `s.n.` and `n/a`. Name separators (`,`, `;`, `&`, `+`,
#' `and`, and their full-width CJK equivalents) protect values that mix a
#' keyword with a real name, and word-boundary matching keeps the CJK
#' keywords from splitting genuine names - deliberately conservative so
#' that real records are never dropped.
#'
#' The output `customFiltered` object carries every downstream column in
#' `occ_filtered` and a per-rule `summary` that exposes the whole filtering
#' decision chain at a glance.
#'
#' ## Quick start
#'
#' The built-in example dataset lets you run the full pipeline without a
#' GBIF download:
#'
#' ```r
#' library(VasGBIF)
#'
#'
#' gbif_file <- system.file(
#'   "extdata", "0003386-260721160103020.zip",
#'   package = "VasGBIF"
#' )
#'
#' occ_import <- import_records(path = gbif_file)
#'
#'
#' gbif_issue <- extract_gbif_issues(occ_import)
#'
#'
#' taxa_checked <- check_taxon(occ_import = occ_import, accuracy = 0.85)
#'
#'
#' filtered <- customized_filter(
#'   occ_import = occ_import,
#'   taxa_checked = taxa_checked,
#'   gbif_issue = gbif_issue
#' )
#'
#'
#' cleaned_coordinates <- clean_coordinates(
#'   customized_filtered = filtered,
#'   threads = 4
#' )
#'
#' native_detected_coord <- detect_native_coord(
#'   cleaned_coordinates = cleaned_coordinates
#' )
#'
#'
#' native_detected_country <- detect_native_country(
#'   cleaned_coordinates = cleaned_coordinates
#' )
#'
#' map_records(
#'   native_detected_coord = native_detected_coord,
#'   precision = 3,
#'   cex = 3
#' )
#'
#' export_records(
#'   native_detected_coord = native_detected_coord,
#'   export_path = getwd()
#' )
#'
#' ```
#'
#' ## Performance
#'
#' VasGBIF achieves its speed through several architectural choices:
#'
#' - **C/C++ backends**: core operations are delegated to [data.table],
#'   [stringi], and [terra] - packages written in C/C++ that bypass R's
#'   per-iteration interpretive overhead.
#' - **Vectorisation over explicit loops**: operations such as issue-flag
#'   detection in [extract_gbif_issues()] and native-status lookups in
#'   [detect_native_coord()] and [detect_native_country()] process entire
#'   columns in compiled calls rather than iterating in R.
#' - **SIMD exploitation**: vectorised routines in [stringi] and
#'   [`terra::extract()`][terra::extract] allow the compiler to emit SIMD
#'   instructions (AVX, AVX-512) that process multiple data elements per CPU
#'   cycle.
#' - **Memory-efficient design**: [data.table]'s in-place modification `:=`
#'   avoids unnecessary copies, and contiguous memory access patterns improve
#'   CPU cache utilisation.
#' - **Selective parallelisation**: [clean_coordinates()] partitions the
#'   dataset into chunks and distributes [CoordinateCleaner] validation
#'   across workers via [foreach] and [doParallel], combining vectorised
#'   processing within each chunk with parallel execution across chunks.
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
#' 4. Govaerts, R. et al. (2021). The World Checklist of Vascular Plants, a
#'    continuously updated resource for exploring global plant diversity.
#'    *Scientific Data*, 8, 215. \doi{10.1038/s41597-021-00997-6}
#'
#' 5. Zizka, Alexander, Daniele Silvestro, Tobias Andermann, Josue Azevedo,
#'    Camila Duarte Ritter, Daniel Edler, Harith Farooq, et al. 2019.
#'    "CoordinateCleaner: Standardized Cleaning of Occurrence Records from
#'    Biological Collection Databases." Edited by Tiago Quental.
#'    *Methods in Ecology and Evolution* 10 (5): 744-51.
#'    \doi{10.1111/2041-210X.13152}.
#'
#' 6. Vilela, Bruno, and Fabricio Villalobos. 2015. "letsR: A New R Package
#'    for Data Handling and Analysis in Macroecology." Edited by Timothee
#'    Poisot. *Methods in Ecology and Evolution* 6 (10): 1229-34.
#'    \doi{10.1111/2041-210x.12401}.
#'
#' @import bit64
NULL

# ---- Suppress data.table NSE notes in R CMD check ---------------------------
utils::globalVariables(c(
  # dplyr pipe placeholder
  ".",
  # data.table specials
  "N",
  # ---- GBIF occurrence fields (from import_records / customized_filter) ----
  "gbifID",
  "order",
  "family",
  "species",
  "taxonRank",
  "scientificName",
  "verbatimScientificName",
  "countryCode",
  "locality",
  "occurrenceStatus",
  "basisOfRecord",
  "decimalLatitude",
  "decimalLongitude",
  "coordinateUncertaintyInMeters",
  "elevation",
  "eventDate",
  "day",
  "month",
  "year",
  "institutionCode",
  "collectionCode",
  "identifiedBy",
  "recordedBy",
  "issue",
  # ---- GBIF issue parsing (from extract_gbif_issues) ----
  "issue_count",
  "gbif_issues",
  # ---- TNRS result fields (from check_taxon) ----
  "ID",
  "Name_submitted",
  "Overall_score",
  "Taxonomic_status",
  "Accepted_name",
  "Accepted_species",
  "Accepted_name_id",
  "Accepted_name_rank",
  "Accepted_family",
  "Source",
  # ---- customized_filter summary ----
  "rule",
  "dropped",
  "remaining",
  # ---- CoordinateCleaner flags (from clean_coordinates) ----
  ".summary",
  ".zer",
  ".equ",
  ".gbif",
  ".cap",
  ".cen",
  ".sea",
  ".inst",
  ".otl",
  ".value",
  # ---- native status (from detect_native_coord / detect_native_country) ----
  "LEVEL3_COD",
  "native_status",
  "native_status_source",
  "buffered",
  "area_code_l3",
  "location_doubtful",
  "introduced",
  "extinct",
  # ---- native detection internals ----
  "occurrence_id",
  "name_key",
  "taxon_key",
  "candidate_area",
  "status_rank",
  "match_type",
  "channel",
  "mapped",
  "L3 code",
  "L3 ISOcode",
  # data.table join-result prefixes
  "i.candidate_area",
  "i.native_status",
  "i.source",
  "i.buffered",
  "i.status",
  "i.rank",
  # ---- export_records ----
  "summary",
  # ---- map_records ----
  "geohash",
  # ---- Package datasets ----
  "EnumOccurrenceIssue",
  "constant",
  "Distributions",
  "Level3maping",
  "WGSRPD3",
  "WorldLandMap",
  # ---- utils::data suggestion (used in package doc examples) ----
  "data",
  'i.Accepted_name',
  'i.Accepted_name_id',
  'i.Accepted_species',
  'i.Source',
  'i.Taxonomic_status',
  'i.issue_count'
))
