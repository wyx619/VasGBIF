# VasGBIF 3.7.1

*Internal-consistency release. The documented workflow shrinks from eight steps to seven: issue counting becomes an internal detail of `customized_filter()`, and the coordinate stage is renamed `par_clean_coordinates()`. The two native-status detectors stop demanding a `CoordinateRefined` object and become plain table functions with explicit column-name arguments, and their classification columns are simplified.*

## Breaking Changes

### Function renames

- **`clean_coordinates()` is renamed `par_clean_coordinates()`.** The old name collided with `CoordinateCleaner::clean_coordinates()`, which the function calls, and said nothing about how it works. The new name records that the CoordinateCleaner tests are distributed across `threads` workers through `foreach` / `doParallel`. The signature changes from `clean_coordinates(customized_filtered, threads = 4, tests = ...)` to `par_clean_coordinates(input = NA, species = "Accepted_name_id", longitude = "decimalLongitude", latitude = "decimalLatitude", threads = 4, tests = ...)`. The first argument is renamed and the three column-name arguments are new; see *Improvements*.
- **`extract_gbif_issues()` is renamed `extract_issues()` and is no longer exported.** Issue counting was never a decision the user had to make: it only feeds the `gbif_issues_max` rule of `customized_filter()`, which now calls it internally. The `"issue"` class and its `print.issue()` method are gone with the export.

### `detect_native_coord()` and `detect_native_country()` now take a table

- **Both functions accept any table-like object instead of a `CoordinateRefined` object.** `detect_native_coord(cleaned_coordinates = NA, buffer_km = 10, buffer_chunk_size = 2000)` becomes `detect_native_coord(input = NA, species = "Accepted_name", longitude = "decimalLongitude", latitude = "decimalLatitude", buffer_km = 10, buffer_chunk_size = 2000)`, and `detect_native_country(cleaned_coordinates = NA)` becomes `detect_native_country(input = NA, species = "Accepted_name", country = "countryCode")`. Anything `data.table::as.data.table()` can convert is accepted, so the `inherits()` check on the input class is gone. Pass the concrete table, for example `par_clean_coordinates(...)$CoordinateCleaned`, rather than the wrapper object.
- **The species and coordinate columns no longer have to carry GBIF field names.** They are named by the `species`, `longitude`, `latitude` and `country` arguments, which default to the GBIF names. A column that happens to share a name with one of the arguments (a `species` column, say) does not interfere: the column vectors are extracted before the internal `data.table` expression is evaluated.
- **`detect_native_country()` no longer requires coordinates and no longer inspects `CoordinateProblematic`.** It classifies every record handed to it through `countryCode`, so it also works on records that do have coordinates but are better classified without geometry.
- **A missing `gbifID` is filled in.** Both functions previously relied on it as a join key; an input without one now gets a character sequence number instead of failing.

### Classification columns

- **`native_status_source` values renamed.** In the spatial result, `spatial` and `spatial_buffered` become `exact` and `buffered`. In the country-code result, `country_code` and `country_code_no_entry` become `country` and `no_entry`. The `unmatched` value is unchanged in both.
- **The `buffered` logical column has been removed.** It was fully implied by `native_status_source == "buffered"`, and was always `FALSE` in the country-code result, so it carried no information of its own. Both results now append exactly three classification columns: `LEVEL3_COD`, `native_status`, `native_status_source`.

### Other signature changes

- **`customized_filter()` no longer takes `gbif_issue`.** The argument had to be filled with the output of `extract_gbif_issues()`, which is now called internally, so the signature drops to `customized_filter(occ_import, taxa_checked, filter_countryCode = TRUE, filter_coordinateUncertainty = 10000, filter_date = FALSE, filter_identifiedBy = FALSE, filter_recordedBy = FALSE, filter_gbif_issues_max = 5)`.
- **`export_records()` gains a `native_detected_country` argument and renames its output files.** The signature becomes `export_records(native_detected_coord = NA, native_detected_country = NA, export_path = NA)`. Each classification supplied is written as its own pair - `all_records_coord.csv.gz` / `native_records_coord.csv.gz` and `all_records_country.csv.gz` / `native_records_country.csv.gz` - replacing `all_records.csv.gz` / `native_records.csv.gz`. The two sets are never bound into a combined table.
- **`map_records()` gains a `species` argument.** The signature becomes `map_records(native_detected_coord = NA, species = "all", precision = 3, cex = 3)`, so a single species can be mapped without subsetting the table by hand. A name that selects nothing stops with an error rather than rendering an empty map.
- **`import_records()` accepts an already-extracted occurrence table, and `remove_tempfile` defaults to `TRUE`.** The default was `NULL`, which resolved to `TRUE` for an auto-created directory but `FALSE` for a user-supplied one; it is now a plain `TRUE`. The extension check on `path` is gone: a non-ZIP file is no longer rejected on its suffix but probed for a `gbifID` first column, which rejects non-GBIF files including comma-separated ones whose header would otherwise arrive as a single column.

### Dependency and documentation

- **The `rnaturalearthdata` dependency has been removed.** The `seas` test is evaluated against the bundled `WorldLandMap` object, which is passed explicitly as `seas_ref`, so the package was never imported at run time.
- **The documented workflow is now seven steps:** `import_records()` -\> `check_taxon()` -\> `customized_filter()` -\> `par_clean_coordinates()` -\> `detect_native_coord()` / `detect_native_country()` -\> `map_records()` -\> `export_records()`. Every step number was decremented after the removal of the issue-extraction step.

## Bug Fixes

- **`par_clean_coordinates()` returned different results for a `data.table` and a `data.frame`.** `CoordinateCleaner::clean_coordinates()` behaves differently on the two: inside `cc_outl()` it subsets with `k[, c(species, lon, lat)]`, which on a `data.table` returns a three-element character vector rather than the columns, silently changing which records are flagged as outliers. The table is now converted with `as.data.frame()` before it is handed over, so the same input always yields the same output. This was a reproducibility defect: the result depended on the class of the caller's object rather than on its contents.
- **`import_records()` could delete a directory the caller supplied.** Cleanup ran `unlink(ex_path, recursive = TRUE)` unconditionally when `tempdir` was given, so a user-supplied directory was removed in full even though it may have held unrelated files. An auto-created directory is still removed whole, but a caller-supplied one now has only the extracted members unlinked.
- **`set_threads()` stopped with `"illegal !!!"`.** A non-positive `x` now stops with `` `x` must be a single positive number. `` instead of an unexplained exclamation.
- **`par_clean_coordinates()` rejects a whole `customFiltered` object with a usable message.** Passing the object rather than the table it contains previously failed deep inside the coordinate tests; it now stops with `` `input` is a `customFiltered` object, not a table. Pass the table it contains, for example `par_clean_coordinates(filtered$occ_filtered)`. `` The guard tests for the class, so an ordinary list or `data.frame` input is unaffected.

## Improvements

- **`par_clean_coordinates()` names its columns and chunks by species.** The `species`, `longitude` and `latitude` arguments free the input from GBIF field names, and the parallel split runs per species so a chunk never straddles a taxon boundary. The `seas` test is evaluated against the bundled `WorldLandMap` land polygons buffered by 5 km.
- **`customized_filter()` reports per-rule verdicts.** Each rule now evaluates the whole table and stores a logical `filter_*` column, so one record can be audited against several rules at once. `occ_filtered` carries no verdict columns; the verdicts are returned separately in `occ_marked`, one column per applied rule. `summary` gains `failed` (records the rule rejects on its own terms) and `only_failed_here` (records it rejects and no other rule does) alongside the existing sequential `dropped` / `remaining`, whose sums differ on overlapping rules.
- **`extract_issues()` returns one tidy table.** The previous `"issue"` object bundled a wide logical matrix with a per-code summary; the internal function returns a single `data.table` of `gbifID` and a numeric `issue_count`, which is all the `gbif_issues_max` rule needs.
- **`export_records()` validates and documents both channels.** The coordinate channel requires `gbifID`, `native_status`, `decimalLongitude` and `decimalLatitude`, and rejects a record with a missing coordinate; the country-code channel requires only `gbifID` and `native_status`. Supplying one argument leaves the files of the other untouched.
- **The country-code stage keeps every record.** A `countryCode` that is blank, `NA`, or maps to no WGSRPD Level 3 area is retained as `unknown` / `unmatched` rather than dropped, and a country that maps but has no distribution entry for the taxon is `unknown` / `no_entry`. The two are distinct in `native_status_source`, so a genuinely absent country is never confused with a taxon that has no record there.

## Documentation

- Package-level documentation, README, `Example.Rmd`, and `Application.Rmd` rewritten for the seven-step workflow, the renamed functions, and the new column contracts.
- Every `clean_coordinates()`, `refine_coordinates()`, `custom_filter()` and `extract_gbif_issues()` reference has been updated across `R/`, README, and the vignettes. References to the internal `extract_gbif_issues()` are cross-links to the unexported `extract_issues()`.
- `_pkgdown.yml` step headings renumbered to match, and the removed `print.issue` method dropped from the reference index.
- Rd files regenerated for the renamed and updated functions.

## Testing

- `test-custom_filter.R` rewritten for the verdict-column contract: the `gbif_issue` argument is gone, raw pipe-separated `issue` strings are built in the fixtures, and the `failed` / `only_failed_here` semantics are pinned against overlapping and disjoint rules.
- `test-detect_native_coord.R` and `test-detect_native_country.R` rewritten for the table input, the auto-generated `gbifID`, and the renamed classification values; both add a regression test that a column named `species` does not shadow the `species` argument.
- `test-par_clean_coordinates.R` added, replacing `test-refine_coordinates.R`. It covers the renamed argument, table-like inputs, the `customFiltered` guard, and a thread-independence check that `threads = 1` and `threads = 2` return `identical()` results.
- `test-extract_issues.R` added, replacing `test-extract_gbif_issues.R`. It asserts the new return contract and that the function stays internal with no `print.issue` method.
- `test-export_records.R` extended to the country-code channel and the renamed files; the fixtures now create their own temporary directories.
- `test-import_records.R`, `test-map_records.R`, and `test-set_threads.R` updated for the new `tempdir` semantics, the header probe error, the `species` argument, and the reworded thread error. The `set_threads` snapshot was re-recorded.

# VasGBIF 3.7.0

## Breaking Changes

- **`detect_native_country()` now requires a `CoordinateRefined` object.** The function signature has changed from `detect_native_country(customized_filtered)` to `detect_native_country(cleaned_coordinates)`. It now takes the output of `clean_coordinates()` instead of `customized_filter()`, processing all records from `CoordinateProblematic` (both coordinateless records and those that failed coordinate validation tests).

## Improvements

- **`clean_coordinates()` now includes coordinateless records in `CoordinateProblematic`.** Records missing longitude or latitude are no longer silently excluded but are added to `CoordinateProblematic` alongside records that failed coordinate validation tests. This ensures all problematic records are captured in one place for downstream processing.
- **`detect_native_country()` processes all `CoordinateProblematic` records.** The function now classifies both coordinateless records and records with coordinates that failed validation tests, providing comprehensive country-code-based classification for all records that cannot be spatially matched.

## Documentation

- **Pipeline workflow updated in package documentation.** The step 6 description in `VasGBIF-package.R` now accurately reflects that `detect_native_coord()` processes `CoordinateCleaned` while `detect_native_country()` processes all `CoordinateProblematic` records. The "Precise native-status detection system" section has been revised to clarify the division of labor between the two functions.
- **Example code updated.** Quick start examples in package documentation now correctly pass `cleaned_coordinates` to `detect_native_country()` instead of the previous `customized_filtered` argument.
- **Function names corrected throughout.** All references to `custom_filter()` and `refine_coordinates()` have been updated to `customized_filter()` and `clean_coordinates()` respectively across package documentation, ensuring consistency with actual function names.

## Testing

- **`test-detect_native_country.R` updated for new input type.** All 40 tests rewritten to create `CoordinateRefined` objects instead of `customFiltered` objects. New tests verify that records with complete coordinates (those that failed validation) are correctly processed alongside coordinateless records.
- **`test-refine_coordinates.R` updated for `CoordinateProblematic` behavior.** All 32 tests updated to reflect that `CoordinateProblematic` now includes both validation-failed records and coordinateless records, with tests confirming the correct categorization of each record type.
