# UltraGBIF 3.4.1

## Bug Fixes

- fix some big integers with `bit64`
- fix function `refine_records` with *identifiedBy*

# UltraGBIF 3.4.0

## Improvements

- change Record Completeness Score calculation in `set_digital_voucher()`, replace *fieledNotes* with *identifiedBy*.
- test the package on R 4.6.0

# UltraGBIF 3.3.2

## Improvements

- fix some help documents.

# UltraGBIF 3.3.1

## Improvements

- update lots of help documents.
- remove functions about richness.

# UltraGBIF 3.3.0

## Improvements

- `check_occ_taxon` Implemented timeout and automatic redial logic for data chunks to resolve connection hangs during TNRS queries, ensuring robust processing of large datasets under unstable network conditions.

# UltraGBIF 3.2.9

## Bug Fixes

- debug `check_occ_taxon`

## Improvements

- perf(`check_occ_taxon`): Optimize TNRS query performance by processing large datasets in chunks

# UltraGBIF 3.2.8

## Improvements

- **Enhanced TNRS error handling**: Improved the retry mechanism in `check_occ_taxon()` with proper error catching using `tryCatch()` instead of `try()`. The function now provides informative error messages and gracefully handles network failures when the TNRS API is unreachable.
- **Added LazyData compression**: Added `LazyDataCompression: gzip` to DESCRIPTION to reduce package size and meet CRAN requirements.

## Bug Fixes

- **Fixed `check_occ_taxon()` retry logic crash**: Resolved an issue where TNRS API failures caused the function to hang indefinitely. Changed initialization from `NULL` to empty `data.frame()` and added proper error handling to ensure `nrow()` operations work correctly during retry attempts.

## Documentation

- **Standardized DOI citation format**: Updated all R documentation files to use `\doi{}` macro instead of `\url{https://doi.org/...}` for academic reference formatting across `UltraGBIF-package.R`, `import_records.R`, `check_occ_taxon.R`, `refine_records.R`, `plot_richness.R`, and `data.R`.
- **Updated README.md**: Refreshed the README with the new four-stage workflow diagram, updated installation instructions, and refined descriptions of all modules.
- **Complete tutorial restructuring**: Rewrote `Tutorial_of_UltraGBIF.Rmd` following a 4-stage, 8-module structure with academic English, clear organization, and comprehensive workflow explanations. Added summary section for core modules with statistics table explaining data reduction process.

# UltraGBIF 3.2.7

## Major Improvements

### Dependency Restructuring

- **Removed dependency on rWCVP and rWCVPdata**: UltraGBIF now fully relies on the Taxonomic Name Resolution Service (TNRS) for taxonomic name resolution instead of the discontinued rWCVP packages. This critical change enables UltraGBIF to meet CRAN submission requirements, as packages published on CRAN may only depend on other CRAN-hosted packages. Users can now install UltraGBIF with a single `install.packages("UltraGBIF")` call.
- **Streamlined taxonomic databases**: The required WCVP databases are now bundled within the package, eliminating external data dependencies and ensuring consistent behavior across installations.

### Taxonomic Name Resolution

- **Integrated TNRS (Taxonomic Name Resolution Service)**: Implemented a more mature and widely adopted name correction scheme that fully replaces the original complex scripts. The TNRS queries the World Checklist of Vascular Plants (WCVP) to resolve synonyms, correct misspellings, and standardize plant scientific names.
- **Enhanced taxonomic workflow**: The `check_occ_taxon()` function now provides detailed TNRS workflow documentation, including the four-step resolution process (Parse → Match → Correct → Select Best Match), making the taxonomic standardization process transparent and understandable for users.

### Performance Optimization

- **Vectorized Set Digital Voucher**: For the most time-consuming step in the "Set Digital Voucher" stage—the "Process taxonomic information for groupable records" phase—vectorization techniques have been fully leveraged, resulting in a further 40% speedup of the `set_digital_voucher()` function.
- **Optimized richness calculation**: Deeply integrated and optimized the richness calculation and heatmap plotting functionality inspired by `lets.presab.points` and `plot.PresenceAbsence` from the letsR package (Vilela & Villalobos, 2015). The implementation fully leverages vectorized `terra` operations to avoid explicit looping when filling large presence-absence matrices, achieving nearly a hundredfold speedup over traditional approaches.
- **Efficient collection event key generation**: Optimized the algorithm for generating collection event keys, reducing computational overhead in the `set_collection_mark()` function.

### Functionality Enhancements

- **Refactored collector name standardization**: Completely restructured the collector name normalization and collection event mark generation functionality. The new `check_collectors()` function simplifies the workflow by using `tokenizers::tokenize_words()` for robust word tokenization, replacing the previous complex string splitting logic with multiple parameters.

- **New S3 class system**: Introduced R's S3 class system for UltraGBIF objects, providing a clearer workflow structure with well-defined return types:

  - `UltraGBIF_import` class for `import_records()` output
  - `UltraGBIF_taxa_checked` class for `check_occ_taxon()` output
  - `UltraGBIF_collection_key` class for `set_collection_mark()` output
  - `UltraGBIF_voucher` class for `set_digital_voucher()` output
  - `UltraGBIF_refined` class for `refine_records()` output

- **Deleted deprecated ref_dictionary data**: Removed the built-in collector name reference dictionary (`ref_dictionary`) and related functions, reducing package size and simplifying dependencies.

## Bug Fixes

- **Fixed `plot_richness.R` raster value extraction error**: Resolved an intermittent error (`invalid name(s)`) in the `terra::values()` operation by adding cell ID validation and using direct raster object access instead of the unstable layer name accessor (`ras_richness$richness`).

## Documentation

- **Comprehensive roxygen2 documentation**: Systematically optimized and enriched help documentation across all 8 R modules. Every exported function now includes:

  - Structured `@description` with workflow explanation using `\itemize`
  - Detailed `@param` specifications with type and default value information
  - Multi-section `@details` with `\strong` subsection headers
  - Comprehensive `@return` descriptions
  - Academic references where applicable

- **Package-level documentation**: Added complete package-level documentation in `UltraGBIF-package.R`, providing:

  - Three-stage workflow overview (Data Acquisition → Duplicate Removal → Refine Records)
  - Eight-module function reference with cross-links
  - Quick start example code demonstrating the complete workflow
  - Performance optimization technical details (C/C++ backend integration, vectorization, SIMD exploitation, memory-efficient design, chunk-based parallelization)
  - Numbered reference list for all cited literature

- **Updated README.md**: Refreshed the README with the new four-stage workflow diagram, updated installation instructions, and refined descriptions of all modules.

- **Unified reference formatting**: Standardized all citations across documentation files to use `\enumerate` for numbered reference lists.

## Code Quality

- **Cleaned code formatting**: Removed redundant imports and standardized code style across all R files.
- **Removed deprecated functions**: Deleted obsolete functions including `check_occ_name()`, `prepare_collectors_dictionary()`, `generate_collection_mark()`, and `usecores()`, replacing them with their more streamlined successors.
