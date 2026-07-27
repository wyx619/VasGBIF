# Changelog

## VasGBIF 3.5.1

### Bug Fixes

- **[`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md):
  fixed merge failure for names containing commas.** The TNRS internally
  converts commas to spaces in submitted scientific names, but the merge
  key on the package side used the original comma-containing name,
  causing records to fail to match their TNRS resolution results. A
  comma-stripped key column (`wcvp_searchedName2`) is now created for
  the merge, while the original `wcvp_searchedName` is preserved
  unchanged.
- **[`refine_records()`](https://wyx619.github.io/VasGBIF/reference/refine_records.md):
  removed erroneous pre-filter before
  [`restore_duplicates()`](https://wyx619.github.io/VasGBIF/reference/restore_duplicates.md).**
  The call
  `restore_duplicates(voucher$occ_digital_voucher[VasGBIF_dataset_result != "unusable"])`
  stripped all `unusable` records from the input.

## VasGBIF 3.5.0

*Major release: package renamed from UltraGBIF to VasGBIF with a
substantially simplified pipeline.*

### Breaking Changes

#### Package Rename

- The package has been renamed from **UltraGBIF** to **VasGBIF**. All
  function names, class names, and column prefixes have been updated
  accordingly (e.g., `UltraGBIF_dataset_result` →
  `VasGBIF_dataset_result`).

#### Removed Functions

- `check_collectors()` and `get_collectors_name()` have been removed.
  The collector-based duplicate detection stage has been replaced by a
  coordinate- and date-based collection-event key system in
  [`get_collections()`](https://wyx619.github.io/VasGBIF/reference/get_collections.md).
- `check_occ_taxon()` replaced by
  [`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md).
- `set_collection_mark()` replaced by
  [`get_collections()`](https://wyx619.github.io/VasGBIF/reference/get_collections.md).
- `set_digital_voucher()` replaced by
  [`set_vouchers()`](https://wyx619.github.io/VasGBIF/reference/set_vouchers.md).

#### Removed Data

- `occ_import`, `ref_wcvp_names`, `seas_ref`, and `wcvp_distributions`
  datasets have been removed from the package. The internal datasets
  `Distributions`, `WGSRPD3`, `WorldLandMap`, and `EnumOccurrenceIssue`
  remain available.

#### Function Signature Changes

- [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md):
  parameter `GBIF_file` renamed to `path`; `only_PRESERVED_SPECIMEN`
  removed; new `remove_tempfile` parameter.
- [`refine_records()`](https://wyx619.github.io/VasGBIF/reference/refine_records.md):
  parameter `export_path` removed (use
  [`export_records()`](https://wyx619.github.io/VasGBIF/reference/export_records.md)
  instead); `save_path` removed; return value is now a `refined` object
  with elements `all_records`, `CoordinateProblematic`, and `runtime`.
- [`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md)
  replaces `check_occ_taxon()`: default `sources` changed from
  `c("wcvp", "wfo")` to `"wcvp"` only.

### New Functions

- [`detect_native_status()`](https://wyx619.github.io/VasGBIF/reference/detect_native_status.md)
  detects native status by matching validated coordinates to WGSRPD
  Level 3 polygons and WCVP distribution data. Classification uses a
  priority-based scheme: location_doubtful \> introduced \> extinct \>
  native \> unknown.
- [`export_records()`](https://wyx619.github.io/VasGBIF/reference/export_records.md)
  writes refined records to disk as three gzip-compressed CSV files: all
  usable records, the native subset, and records that failed coordinate
  validation.
- [`restore_duplicates()`](https://wyx619.github.io/VasGBIF/reference/restore_duplicates.md)
  is a new internal helper that fills missing metadata fields
  (`eventDate`, `year`, `month`, `day`, `identifiedBy`, `countryCode`,
  `stateProvince`, `locality`) in usable voucher records using data from
  duplicate records sharing the same collection key.

### Improvements

- **Simplified pipeline**: The workflow has been reduced from 8 modules
  (with collector checking) to 7 core functions across 4 stages. The
  collector name standardization stage has been removed entirely;
  duplicate detection now uses composite keys of
  `taxon_name|eventDate|latitude|longitude` via
  [`get_collections()`](https://wyx619.github.io/VasGBIF/reference/get_collections.md).
- [`refine_records()`](https://wyx619.github.io/VasGBIF/reference/refine_records.md)
  has been modularised into a three-step internal pipeline:
  [`restore_duplicates()`](https://wyx619.github.io/VasGBIF/reference/restore_duplicates.md)
  → CoordinateCleaner →
  [`detect_native_status()`](https://wyx619.github.io/VasGBIF/reference/detect_native_status.md).
- [`get_collections()`](https://wyx619.github.io/VasGBIF/reference/get_collections.md)
  builds collection-event keys from resolved taxon names, event dates,
  and rounded coordinates, with user-controlled spatial precision.
- [`set_vouchers()`](https://wyx619.github.io/VasGBIF/reference/set_vouchers.md)
  implements a refined quality scoring system (metadata completeness +
  geospatial penalty) and returns a `vouchers` object.
- [`restore_duplicates()`](https://wyx619.github.io/VasGBIF/reference/restore_duplicates.md)
  now restores `month` and `day` in addition to the previously restored
  fields.
- [`set_threads()`](https://wyx619.github.io/VasGBIF/reference/set_threads.md)
  is now exported for normalising thread counts.

### Dependency Changes

- Removed `tokenizers` from Imports (no longer needed after collector
  module removal).
- Added `lubridate` to Imports.
- Added `@import bit64` to NAMESPACE.

### Documentation

- All roxygen2 documentation rewritten in Markdown-first style (roxygen2
  ≥ 8.0.0).
- `RoxygenNote` replaced by `Config/roxygen2/version: 8.0.0` in
  DESCRIPTION.
- Pipeline overview in package documentation and README updated to
  reflect the seven-function, four-stage workflow.
- `Tutorial_of_UltraGBIF.Rmd` vignette replaced by `Application.Rmd` and
  `Example.Rmd`.
- [`utils::globalVariables()`](https://rdrr.io/r/utils/globalVariables.html)
  expanded to suppress data.table NSE notes in R CMD check.
- Author field de-anonymised with ORCID.

## VasGBIF 3.4.1

### Bug Fixes

- fix some big integers with `bit64`
- fix function `refine_records` with *identifiedBy*

## VasGBIF 3.4.0

### Improvements

- change Record Completeness Score calculation in
  `set_digital_voucher()`, replace *fieledNotes* with *identifiedBy*.
- test the package on R 4.6.0

## VasGBIF 3.3.2

### Improvements

- fix some help documents.

## VasGBIF 3.3.1

### Improvements

- update lots of help documents.
- remove functions about richness.

## VasGBIF 3.3.0

### Improvements

- `check_occ_taxon` Implemented timeout and automatic redial logic for
  data chunks to resolve connection hangs during TNRS queries, ensuring
  robust processing of large datasets under unstable network conditions.

## VasGBIF 3.2.9

### Bug Fixes

- debug `check_occ_taxon`

### Improvements

- perf(`check_occ_taxon`): Optimize TNRS query performance by processing
  large datasets in chunks

## VasGBIF 3.2.8

### Improvements

- **Enhanced TNRS error handling**: Improved the retry mechanism in
  `check_occ_taxon()` with proper error catching using
  [`tryCatch()`](https://rdrr.io/r/base/conditions.html) instead of
  [`try()`](https://rdrr.io/r/base/try.html). The function now provides
  informative error messages and gracefully handles network failures
  when the TNRS API is unreachable.
- **Added LazyData compression**: Added `LazyDataCompression: gzip` to
  DESCRIPTION to reduce package size and meet CRAN requirements.

### Bug Fixes

- **Fixed `check_occ_taxon()` retry logic crash**: Resolved an issue
  where TNRS API failures caused the function to hang indefinitely.
  Changed initialization from `NULL` to empty
  [`data.frame()`](https://rdrr.io/r/base/data.frame.html) and added
  proper error handling to ensure
  [`nrow()`](https://rspatial.github.io/terra/reference/dimensions.html)
  operations work correctly during retry attempts.

### Documentation

- **Standardized DOI citation format**: Updated all R documentation
  files to use `\doi{}` macro instead of `\url{https://doi.org/...}` for
  academic reference formatting across `VasGBIF-package.R`,
  `import_records.R`, `check_occ_taxon.R`, `refine_records.R`,
  `plot_richness.R`, and `data.R`.
- **Updated README.md**: Refreshed the README with the new four-stage
  workflow diagram, updated installation instructions, and refined
  descriptions of all modules.
- **Complete tutorial restructuring**: Rewrote `Tutorial_of_VasGBIF.Rmd`
  following a 4-stage, 8-module structure with academic English, clear
  organization, and comprehensive workflow explanations. Added summary
  section for core modules with statistics table explaining data
  reduction process.

## VasGBIF 3.2.7

### Major Improvements

#### Dependency Restructuring

- **Removed dependency on rWCVP and rWCVPdata**: VasGBIF now fully
  relies on the Taxonomic Name Resolution Service (TNRS) for taxonomic
  name resolution instead of the discontinued rWCVP packages. This
  critical change enables VasGBIF to meet CRAN submission requirements,
  as packages published on CRAN may only depend on other CRAN-hosted
  packages. Users can now install VasGBIF with a single
  `install.packages("VasGBIF")` call.
- **Streamlined taxonomic databases**: The required WCVP databases are
  now bundled within the package, eliminating external data dependencies
  and ensuring consistent behavior across installations.

#### Taxonomic Name Resolution

- **Integrated TNRS (Taxonomic Name Resolution Service)**: Implemented a
  more mature and widely adopted name correction scheme that fully
  replaces the original complex scripts. The TNRS queries the World
  Checklist of Vascular Plants (WCVP) to resolve synonyms, correct
  misspellings, and standardize plant scientific names.
- **Enhanced taxonomic workflow**: The `check_occ_taxon()` function now
  provides detailed TNRS workflow documentation, including the four-step
  resolution process (Parse → Match → Correct → Select Best Match),
  making the taxonomic standardization process transparent and
  understandable for users.

#### Performance Optimization

- **Vectorized Set Digital Voucher**: For the most time-consuming step
  in the “Set Digital Voucher” stage—the “Process taxonomic information
  for groupable records” phase—vectorization techniques have been fully
  leveraged, resulting in a further 40% speedup of the
  `set_digital_voucher()` function.
- **Optimized richness calculation**: Deeply integrated and optimized
  the richness calculation and heatmap plotting functionality inspired
  by `lets.presab.points` and `plot.PresenceAbsence` from the letsR
  package (Vilela & Villalobos, 2015). The implementation fully
  leverages vectorized `terra` operations to avoid explicit looping when
  filling large presence-absence matrices, achieving nearly a
  hundredfold speedup over traditional approaches.
- **Efficient collection event key generation**: Optimized the algorithm
  for generating collection event keys, reducing computational overhead
  in the `set_collection_mark()` function.

#### Functionality Enhancements

- **Refactored collector name standardization**: Completely restructured
  the collector name normalization and collection event mark generation
  functionality. The new `check_collectors()` function simplifies the
  workflow by using `tokenizers::tokenize_words()` for robust word
  tokenization, replacing the previous complex string splitting logic
  with multiple parameters.

- **New S3 class system**: Introduced R’s S3 class system for VasGBIF
  objects, providing a clearer workflow structure with well-defined
  return types:

  - `VasGBIF_import` class for
    [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md)
    output
  - `VasGBIF_taxa_checked` class for `check_occ_taxon()` output
  - `VasGBIF_collection_key` class for `set_collection_mark()` output
  - `VasGBIF_voucher` class for `set_digital_voucher()` output
  - `VasGBIF_refined` class for
    [`refine_records()`](https://wyx619.github.io/VasGBIF/reference/refine_records.md)
    output

- **Deleted deprecated ref_dictionary data**: Removed the built-in
  collector name reference dictionary (`ref_dictionary`) and related
  functions, reducing package size and simplifying dependencies.

### Bug Fixes

- **Fixed `plot_richness.R` raster value extraction error**: Resolved an
  intermittent error (`invalid name(s)`) in the
  [`terra::values()`](https://rspatial.github.io/terra/reference/values.html)
  operation by adding cell ID validation and using direct raster object
  access instead of the unstable layer name accessor
  (`ras_richness$richness`).

### Documentation

- **Comprehensive roxygen2 documentation**: Systematically optimized and
  enriched help documentation across all 8 R modules. Every exported
  function now includes:

  - Structured `@description` with workflow explanation using `\itemize`
  - Detailed `@param` specifications with type and default value
    information
  - Multi-section `@details` with `\strong` subsection headers
  - Comprehensive `@return` descriptions
  - Academic references where applicable

- **Package-level documentation**: Added complete package-level
  documentation in `VasGBIF-package.R`, providing:

  - Three-stage workflow overview (Data Acquisition → Duplicate Removal
    → Refine Records)
  - Eight-module function reference with cross-links
  - Quick start example code demonstrating the complete workflow
  - Performance optimization technical details (C/C++ backend
    integration, vectorization, SIMD exploitation, memory-efficient
    design, chunk-based parallelization)
  - Numbered reference list for all cited literature

- **Updated README.md**: Refreshed the README with the new four-stage
  workflow diagram, updated installation instructions, and refined
  descriptions of all modules.

- **Unified reference formatting**: Standardized all citations across
  documentation files to use `\enumerate` for numbered reference lists.

### Code Quality

- **Cleaned code formatting**: Removed redundant imports and
  standardized code style across all R files.
- **Removed deprecated functions**: Deleted obsolete functions including
  `check_occ_name()`, `prepare_collectors_dictionary()`,
  `generate_collection_mark()`, and `usecores()`, replacing them with
  their more streamlined successors.
