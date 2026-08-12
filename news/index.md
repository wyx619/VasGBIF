# Changelog

## VasGBIF 3.6.4

### Improvements

- **[`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md)
  default TNRS timeout raised to 20 minutes.** `timeout_minutes` now
  defaults to `20` (previously `5`), reducing chunk-timeout retries for
  large downloads under unstable network conditions.
- **Workflow order adjusted:
  [`map_records()`](https://wyx619.github.io/VasGBIF/reference/map_records.md)
  now precedes
  [`export_records()`](https://wyx619.github.io/VasGBIF/reference/export_records.md).**
  The documented workflow — step numbering and example code in the
  package documentation, README, and vignettes — now visualises the
  records on the interactive map before writing the classified records
  to disk.
- **[`custom_filter()`](https://wyx619.github.io/VasGBIF/reference/custom_filter.md)
  peak memory reduced from 2–3× to about 2× the input size.** The two
  full-width
  [`merge()`](https://rspatial.github.io/terra/reference/merge.html)
  calls were replaced by a single defensive shallow copy of `occ_import`
  followed by in-place keyed joins (`:=` column addition), and the six
  filter rules now accumulate into a logical mask applied as a single
  row subset at the end. The output is exactly equivalent to the
  previous version — same rows, column order, row order, `gbifID` key,
  and `summary` — and the defensive copy preserves the contract that the
  caller’s input is never modified.

### Documentation

- Rd files regenerated for
  [`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md),
  [`custom_filter()`](https://wyx619.github.io/VasGBIF/reference/custom_filter.md),
  and `VasGBIF-package`.
- **Removed remaining non-ASCII characters from Rd-facing
  documentation** so the PDF manual builds on non-UTF-8 Windows locales
  (GBK), where the Rd-to-LaTeX conversion previously failed with an
  `iconv` “embedded nul” error. Em-dashes were replaced with ASCII
  hyphens, and the accented Spanish/Portuguese keyword list, the
  hybrid-marker example, and the `Timothée` author name were rewritten
  in ASCII. Rd files for `Level3maping`,
  [`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md),
  [`detect_native_country()`](https://wyx619.github.io/VasGBIF/reference/detect_native_country.md),
  [`export_records()`](https://wyx619.github.io/VasGBIF/reference/export_records.md),
  and
  [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md)
  were regenerated as part of this change.

## VasGBIF 3.6.3

Native-status detection is split into two independent functions:
[`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md)
classifies records with validated coordinates through the spatial pass,
while
[`detect_native_country()`](https://wyx619.github.io/VasGBIF/reference/detect_native_country.md)
classifies records without coordinates through their country code. The
previous “retry unresolved records by country code” mechanism is
removed, and the downstream consumers
([`export_records()`](https://wyx619.github.io/VasGBIF/reference/export_records.md),
[`map_records()`](https://wyx619.github.io/VasGBIF/reference/map_records.md))
now require and validate that their input carries coordinates.

### Breaking Changes

- **`detect_native_status()` is replaced by
  [`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md)
  and
  [`detect_native_country()`](https://wyx619.github.io/VasGBIF/reference/detect_native_country.md).**
  The combined two-pass classifier no longer exists; classification is
  split by whether a record has coordinates.
  - `detect_native_coord(refined_coordinates, buffer_km = 10, buffer_chunk_size = 2000)`
    classifies the records with validated coordinates
    (`refined_coordinates$CoordinateCleaned`) by overlaying them on the
    WGSRPD Level 3 polygon map. `native_status_source` is `spatial`
    (exact hit), `spatial_buffered` (geodesic buffer hit), or
    `unmatched`.
  - `detect_native_country(custom_filtered)` classifies the records
    missing longitude or latitude
    (`custom_filtered$occ_filtered[is.na(decimalLatitude) | is.na(decimalLongitude)]`)
    through `countryCode` mapped to Level 3 areas by `Level3maping`;
    records with complete coordinates are not part of the result.
    `native_status_source` is `country_code`, `country_code_no_entry`,
    or `unmatched`, and `buffered` is always `FALSE` because no geometry
    is used.
  - Both return a `nativeDetected` object keyed by `gbifID`; the two
    results can be combined with
    [`rbind()`](https://rdrr.io/r/base/cbind.html) for a full
    classification.
- **Records the spatial stage leaves unresolved are no longer retried by
  country code.** The migration mechanism and its
  `country_code_after_spatial_miss` source value are gone: a spatial
  miss stays `unmatched` and is never re-classified through the country
  code. Coordinateless records are classified separately with
  [`detect_native_country()`](https://wyx619.github.io/VasGBIF/reference/detect_native_country.md).
- **[`export_records()`](https://wyx619.github.io/VasGBIF/reference/export_records.md)
  and
  [`map_records()`](https://wyx619.github.io/VasGBIF/reference/map_records.md)
  now take `native_detected_coord` (renamed from `native_detected`) and
  require coordinates.** The input must be the output of
  [`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md):
  both functions stop with an error if `decimalLongitude` or
  `decimalLatitude` is missing for any record, so the output of
  [`detect_native_country()`](https://wyx619.github.io/VasGBIF/reference/detect_native_country.md)
  is rejected.
- **[`refine_coordinates()`](https://wyx619.github.io/VasGBIF/reference/refine_coordinates.md)
  no longer returns a `Coordinateless` table.** The `CoordinateRefined`
  object now has three elements (`CoordinateCleaned`,
  `CoordinateProblematic`, `runtime`). Records missing longitude or
  latitude are not carried by
  [`refine_coordinates()`](https://wyx619.github.io/VasGBIF/reference/refine_coordinates.md);
  they are classified directly from `custom_filtered` by
  [`detect_native_country()`](https://wyx619.github.io/VasGBIF/reference/detect_native_country.md).

### Bug Fixes

- **[`refine_coordinates()`](https://wyx619.github.io/VasGBIF/reference/refine_coordinates.md)
  empty-input path no longer errors.** The guard previously referenced
  an undefined `Coordinateless` variable, failing with “object
  ‘Coordinateless’ not found”; it now returns a well-formed
  `CoordinateRefined` object with empty `CoordinateCleaned` and
  `CoordinateProblematic` tables.
- **A blank `countryCode` no longer resolves to Level 3 areas.** The 42
  WGSRPD areas whose `L3 ISOcode` is stored as `""` were previously
  treated as a valid mapping, so a record with an empty country code
  could be classified from those areas; such records are now
  `unmatched`.

### Documentation

- Package-level documentation, README, `Example.Rmd`, and
  `Application.Rmd` rewritten for the two-function split; every
  `detect_native_status()` reference — including `@seealso` cross-links
  — has been removed from `R/`, `man/`, README, and the vignettes.
- Rd files regenerated for the new and updated functions.

### Testing

- `test-detect_native_status.R` replaced by `test-detect_native_coord.R`
  (spatial classification, buffer passes, hybrid-name normalisation,
  print method) and `test-detect_native_country.R` (country-code
  classification, multi-area status adjudication, blank and unknown
  country codes, empty inputs).
- `test-export_records.R` and `test-map_records.R` updated for the
  renamed argument and the new coordinate-presence check; fixtures carry
  coordinates for every record.
- `test-refine_coordinates.R` updated for the three-element
  `CoordinateRefined` contract (`Coordinateless` is no longer returned).

## VasGBIF 3.6.2

### Breaking Changes

- **`species_fallback` has been removed from `detect_native_status()`.**
  The opt-in parameter let infraspecific taxa absent from
  `Distributions` inherit their parent species’ status, but this proxy
  has been shown by research to be unreliable — a subspecies may be
  introduced where the species is native. Classification is now strictly
  by `Accepted_name`. The signature is
  `detect_native_status(refined_coordinates, buffer_km = 10, buffer_chunk_size = 2000)`,
  and the `key_rank`-based fallback machinery in the internal matching
  pipeline has been removed with it.
- **`native_status_source` values renamed.** Spatial matches are now
  `spatial` (exact) and `spatial_buffered` (buffered) instead of a
  single `accepted_name`; a country that mapped to WGSRPD areas but has
  no distribution entry for the taxon is `country_code_no_entry` instead
  of `country_code_miss`. The `accepted_species` value and the
  `_species`-suffixed country-code forms no longer exist.

## VasGBIF 3.6.1

*A follow-up release that makes the output of `detect_native_status()`
self-contained: the native-status classification now carries the input
record columns, so
[`export_records()`](https://wyx619.github.io/VasGBIF/reference/export_records.md)
and
[`map_records()`](https://wyx619.github.io/VasGBIF/reference/map_records.md)
no longer need a separate `refined_coordinates` object.*

### Breaking Changes

- **`detect_native_status()` now returns the record columns alongside
  the classification.** A `nativeDetected` object retains every column
  of the input records (`CoordinateCleaned` + `Coordinateless`) and
  appends `LEVEL3_COD`, `native_status`, `native_status_source`, and
  `buffered`. The result is keyed by `gbifID` and can be passed straight
  to
  [`export_records()`](https://wyx619.github.io/VasGBIF/reference/export_records.md)
  /
  [`map_records()`](https://wyx619.github.io/VasGBIF/reference/map_records.md)
  without joining back to `refined_coordinates`. The intermediate
  matching columns used internally (taxon keys, candidate areas, match
  ranks) are no longer returned. Because the record columns are carried
  through, the result holds a second copy of the input data;
  `refined_coordinates` can be dropped once the classification is in
  hand.
- **[`export_records()`](https://wyx619.github.io/VasGBIF/reference/export_records.md)
  signature simplified to
  `export_records(native_detected, export_path)`.** The
  `refined_coordinates` argument is removed, and the
  `CoordinateProblematic_records.csv.gz` file is no longer written — two
  files are produced (`all_records.csv.gz`, `native_records.csv.gz`).
  Records that failed coordinate validation are never classified and are
  inspected through
  [`refine_coordinates()`](https://wyx619.github.io/VasGBIF/reference/refine_coordinates.md)
  instead.
- **[`map_records()`](https://wyx619.github.io/VasGBIF/reference/map_records.md)
  signature simplified to
  `map_records(native_detected, precision = 3, cex = 3)`.** The
  `refined_coordinates` argument is removed: both the coordinates and
  the classification now come from `native_detected`, so the previous
  join by `gbifID` is gone.

### Improvements

- **Runtime reporting across the pipeline.**
  [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md),
  [`extract_gbif_issues()`](https://wyx619.github.io/VasGBIF/reference/extract_gbif_issues.md),
  and
  [`custom_filter()`](https://wyx619.github.io/VasGBIF/reference/custom_filter.md)
  now print the elapsed time in a `used` message when they finish,
  matching the timing already reported by
  [`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md)
  and
  [`refine_coordinates()`](https://wyx619.github.io/VasGBIF/reference/refine_coordinates.md).
- **Column-clash guard in `detect_native_status()`.** Passing an
  already-classified table back in (one that already contains
  `LEVEL3_COD`, `native_status`, `native_status_source`, or `buffered`)
  now stops with a clear error instead of producing `.x` / `.y` suffixed
  columns in the final join.
- **Row-count assertion in `detect_native_status()`.** Reattaching the
  record columns is asserted to be one-to-one: a duplicated `gbifID`
  across the input tables would inflate the result and now fails loudly
  rather than silently doubling rows.
- **[`export_records()`](https://wyx619.github.io/VasGBIF/reference/export_records.md)
  writes `all_records.csv.gz` straight from `native_detected`.** No join
  and no column selection are performed, so the exported table carries
  every record column in addition to the classification.
- **[`map_records()`](https://wyx619.github.io/VasGBIF/reference/map_records.md)
  popup columns are unchanged.** Although `native_detected` now carries
  all record columns, only the informative fields (GBIF ID, issues,
  taxon names, status, coordinates) are passed to the map popups; the
  `nativeDetected` class is stripped from the display subset so the
  print method is not misapplied.

### Documentation

- Package-level documentation, README, `Example.Rmd`, and
  `Application.Rmd` updated for the new output structure and simplified
  signatures. The `nativeDetected` description in `Application.Rmd` no
  longer instructs users to join back to `refined_coordinates`.
- Rd files regenerated for `detect_native_status()`,
  [`export_records()`](https://wyx619.github.io/VasGBIF/reference/export_records.md),
  and
  [`map_records()`](https://wyx619.github.io/VasGBIF/reference/map_records.md).

### Testing

- `test-export_records.R` rewritten: the fixture no longer builds a
  `refined_coordinates` object, and a new assertion checks that the
  `CoordinateProblematic_records.csv.gz` file is no longer produced.
- `test-map_records.R` rewritten: the fixture builds a `nativeDetected`
  table that carries the record columns directly, and the
  `CoordinateCleaned` inner-join behaviour test is replaced by a
  coordinateless-dropping test.
- `test-detect_native_status.R` updated: the output-column contract test
  now expects the record columns to be preserved, with new tests for the
  column-clash guard and for unchanged record columns in the result.

## VasGBIF 3.6.0

*Major release: the package has been completely redesigned. The
duplicate-detection and voucher-selection pipeline that VasGBIF
inherited from UltraGBIF has been removed and replaced by a new
eight-function, four-stage workflow built around two new systems: a
precise two-pass native-status detector and a fluent, fully auditable
record filter.*

### Breaking Changes

#### The new pipeline

The workflow is now:

[`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md)
→
[`extract_gbif_issues()`](https://wyx619.github.io/VasGBIF/reference/extract_gbif_issues.md)
→
[`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md)
→
[`custom_filter()`](https://wyx619.github.io/VasGBIF/reference/custom_filter.md)
→
[`refine_coordinates()`](https://wyx619.github.io/VasGBIF/reference/refine_coordinates.md)
→ `detect_native_status()` →
[`export_records()`](https://wyx619.github.io/VasGBIF/reference/export_records.md)
/
[`map_records()`](https://wyx619.github.io/VasGBIF/reference/map_records.md)

#### Removed functions

- **`get_collections()`, `set_vouchers()`, and `restore_duplicates()`
  have been removed**, together with the entire collection-event key /
  digital-voucher / metadata-restoration stage. Deduplication by
  composite `taxon|date|latitude|longitude` keys, the
  metadata-completeness and geospatial-penalty scoring system,
  `moreInformativeRecord`, the `usable` / `duplicate` / `unusable`
  classification, and the `VasGBIF_dataset_result` column no longer
  exist. Records are now selected by explicit, individually auditable
  quality rules in
  [`custom_filter()`](https://wyx619.github.io/VasGBIF/reference/custom_filter.md)
  instead of by an implicit voucher-quality ranking.
- **`refine_records()` has been replaced by
  [`refine_coordinates()`](https://wyx619.github.io/VasGBIF/reference/refine_coordinates.md).**
  The old function bundled three unrelated jobs — metadata restoration,
  coordinate validation, and native-status detection — behind one call.
  Coordinate validation and native-status detection are now separate,
  independently callable steps.

#### Function signature and return-value changes

- `refine_coordinates(custom_filtered, threads = 4, tests = ...)` takes
  a `customFiltered` object and returns a `CoordinateRefined` object
  with **four** elements: `CoordinateCleaned`, `CoordinateProblematic`,
  `Coordinateless`, and `runtime`. The new `Coordinateless` table means
  records missing longitude or latitude are no longer silently lost —
  they are carried forward and still receive a native status.
- `detect_native_status(refined_coordinates, species_fallback = FALSE, buffer_km = 10, buffer_chunk_size = 2000)`
  is now exported as a pipeline stage in its own right and returns a
  `nativeDetected` object.
- `export_records(refined_coordinates, native_detected, export_path)`
  and
  `map_records(native_detected, refined_coordinates, precision = 3, cex = 3)`
  now take the coordinate and native-status objects explicitly rather
  than deriving them from a single bundled result, and both validate
  their inputs by class.
- `extract_gbif_issue()` has been **renamed to
  [`extract_gbif_issues()`](https://wyx619.github.io/VasGBIF/reference/extract_gbif_issues.md)**.
- All object classes have been renamed: `import`, `issue`, `occ_taxa`,
  `customFiltered`, `CoordinateRefined`, and `nativeDetected`.

### New and Rewritten Functions

#### `detect_native_status()`: precise native-status detection

Newly exported as a pipeline stage and rewritten from scratch, this is
the analytical core of VasGBIF. It assigns `native`, `introduced`,
`extinct`, `location_doubtful`, or `unknown` to **every** record by
matching identification and position against WCVP distribution data
organised by WGSRPD Level 3 areas. Classification runs in two passes so
the most precise available evidence always wins:

- **Spatial pass.** Records with validated coordinates are overlaid on
  the WGSRPD Level 3 polygon map with a single vectorised
  [`terra::extract()`](https://rspatial.github.io/terra/reference/extract.html)
  call. Each area code is looked up in a distribution table classified
  from the WCVP flags with a fixed priority: `location_doubtful` \>
  `introduced` \> `extinct` \> `native` \> `unknown`. Records falling in
  several areas receive the most preferred status, never an arbitrary
  one.
- **Country-code pass.** Records without coordinates, and records the
  spatial pass left unresolved, are retried through `countryCode` mapped
  to Level 3 areas by the new `Level3maping` table. No geometry is used,
  so this pass is nearly free.

Precision improvements over the previous implementation:

- **Geodesic buffering.** Coastal points just outside a polygon are
  matched through
  [`terra::buffer()`](https://rspatial.github.io/terra/reference/buffer.html)
  in metres, so `buffer_km` has the same meaning at every latitude.
  Buffered hits are always ranked below exact ones and flagged in the
  returned `buffered` column. Buffering is chunked (`buffer_chunk_size`)
  to keep the relate matrix small.
- **Hybrid-name normalisation.** Taxon keys are canonicalised so
  `Alnus x pubescens` matches `Alnus × pubescens` in `Distributions`.
- **Opt-in species fallback.** With `species_fallback = TRUE`,
  infraspecific taxa absent from `Distributions` inherit their parent
  species’ status. This is off by default because it is a deliberate
  loss of precision — a subspecies may be introduced where the species
  is native.
- **Full auditability.** The new `native_status_source` column records
  *how* each status was obtained (`accepted_name`, `accepted_species`,
  `country_code`, `country_code_after_spatial_miss`,
  `country_code_miss`, `unmatched`, with a `_species` suffix where the
  fallback was used), so no classification is a black box.
- **CRS assertion.** The function verifies that the `WGSRPD3` polygons
  are in a longitude/latitude CRS, so a future data change cannot
  silently break the overlay.

#### `custom_filter()`: flexible and fluent filtering

Replaces the implicit voucher-quality ranking with an explicit,
user-controlled filter pipeline. It joins the three preceding outputs by
`gbifID` and then applies a selected set of quality rules, one
vectorised `data.table` pass per rule:

- **Fluent rule control.** Each rule is an independently toggleable
  argument. Three are on by default (`filter_countryCode`,
  `filter_coordinateUncertainty = 10000`, `filter_gbif_issues_max = 5`);
  `filter_date`, `filter_identifiedBy`, and `filter_recordedBy` are
  opt-in, so no information is discarded without an explicit choice.
  Numeric thresholds share one uniform “off” convention — `NULL`, `NA`,
  or `''` — so any rule can be disabled without restructuring the call.
- **Auditable pipeline.** Every step, including the `taxon_resolved`
  join, is logged in the returned `summary` table (`rule`, `dropped`,
  `remaining`).
- **Strict joins.** The taxonomic join is an inner join, so unresolved
  records are dropped at a single visible point instead of carrying `NA`
  taxonomy through the rest of the workflow. The issue join is verified
  to be one-to-one and the function stops if any record lacks an issue
  count.
- **Careful collector and identifier detection.** The `identifiedBy` and
  `recordedBy` rules remove only values containing no named person,
  using a curated multilingual keyword list (English, Spanish,
  Portuguese, French, German, Chinese) plus whole-value patterns such as
  `s.n.`, `n/a`, and `no collector`. Name separators protect values that
  mix a keyword with a real name (`"Unknown; Jongmans WJ"` is kept), and
  word-boundary matching keeps CJK keywords from splitting genuine
  names.

#### `refine_coordinates()`

Coordinate validation, now a standalone step. It splits filtered records
into those with complete coordinates and those without, then runs
[`CoordinateCleaner::clean_coordinates()`](https://ropensci.github.io/CoordinateCleaner/reference/clean_coordinates.html)
checks in parallel over chunked records, with the worker count capped to
the number of records. `CoordinateProblematic` retains the
CoordinateCleaner flag columns so the failing tests can be inspected. If
no record has complete coordinates, validation is skipped rather than
failing.

#### Print methods

Six S3 [`print()`](https://rdrr.io/r/base/print.html) methods have been
added so every pipeline object gives an informative summary at the
console instead of dumping a list:
[`print.import()`](https://wyx619.github.io/VasGBIF/reference/print.import.md),
[`print.issue()`](https://wyx619.github.io/VasGBIF/reference/print.issue.md),
[`print.occ_taxa()`](https://wyx619.github.io/VasGBIF/reference/print.occ_taxa.md),
[`print.customFiltered()`](https://wyx619.github.io/VasGBIF/reference/print.customFiltered.md),
[`print.CoordinateRefined()`](https://wyx619.github.io/VasGBIF/reference/print.CoordinateRefined.md),
and
[`print.nativeDetected()`](https://wyx619.github.io/VasGBIF/reference/print.nativeDetected.md).

### Improvements

- **[`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md)
  now supports Darwin Core Archive downloads** in addition to
  `SIMPLE_CSV`. Archives with more than one member are treated as a DWCA
  and their `occurrence.txt` core file is read. The archive is extracted
  into a dedicated directory rather than next to the ZIP, so a ZIP
  stored in `inst/extdata` is never modified. `tempdir` and
  `remove_tempfile` now have coordinated defaults: an auto-created
  directory is cleaned up on exit, a user-supplied one is kept, and
  either default can be overridden. The return value is a single
  `"import"` `data.table` rather than a list.
- **[`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md)**
  now returns `Accepted_species` and `Accepted_name_rank` alongside the
  existing TNRS columns, and `occ_taxa_checked` is filtered on three
  conditions rather than two: `Overall_score >= accuracy`,
  `Taxonomic_status` in `Accepted`/`Synonym`, and an
  `Accepted_name_rank` that is neither empty nor `genus`. Genus-level
  and unranked matches therefore no longer reach the distribution
  lookup, where they cannot be resolved.
- **[`export_records()`](https://wyx619.github.io/VasGBIF/reference/export_records.md)**
  writes `all_records.csv.gz`, `native_records.csv.gz`, and
  `CoordinateProblematic_records.csv.gz`, with `all_records.csv.gz` now
  covering records both with and without coordinates, each joined to its
  native status. `export_path` is validated before any file is written.

### Bug Fixes

- **[`extract_gbif_issues()`](https://wyx619.github.io/VasGBIF/reference/extract_gbif_issues.md):
  fixed the single-record case.** Building the issue matrix with
  [`sapply()`](https://rdrr.io/r/base/lapply.html)/[`vapply()`](https://rdrr.io/r/base/lapply.html)
  dropped dimensions when the input held one record, producing a
  malformed result. The matrix is now built with
  [`lapply()`](https://rdrr.io/r/base/lapply.html) +
  `do.call(cbind, ...)`, which preserves the expected dimensions for any
  number of records.

### New Data

- **`Level3maping`**: the tabular component of the WGSRPD standard — 369
  Level 3 units with code, name, parent Level 2 region, and ISO 3166-1
  alpha-2 concordance — used by the country-code pass of
  `detect_native_status()`. Its documentation states plainly that the
  published `L3 ISOcode` column is neither complete nor one-to-one: one
  ISO code usually maps to several areas (`US` to 51, `RU` to 21), 42
  areas carry no ISO code at all (including mainland France, Italy,
  Spain, Austria, Belgium, Ireland, Ukraine, and Korea, so a naive
  lookup silently returns only their offshore units), and Belarus is
  listed under `RU`, reflecting the standard’s 2001 vintage.
- **`Distributions`** has been rebuilt and now holds 1,647,045 rows
  (previously reported as 1,983,653), reducing the installed data size.

### Dependency Changes

- Added [`tools::file_ext()`](https://rdrr.io/r/tools/fileutils.html)
  and [`utils::unzip()`](https://rdrr.io/r/utils/unzip.html) to
  NAMESPACE for the new ZIP handling in
  [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md).
- Removed the now-unused NAMESPACE imports
  [`dplyr::case_when()`](https://dplyr.tidyverse.org/reference/case-and-replace-when.html),
  [`dplyr::if_else()`](https://dplyr.tidyverse.org/reference/if_else.html),
  `lubridate::as_date()`, `lubridate::parse_date_time()`,
  [`stringi::stri_length()`](https://rdrr.io/pkg/stringi/man/stri_length.html),
  [`stringi::stri_replace_all_regex()`](https://rdrr.io/pkg/stringi/man/stri_replace.html),
  [`stringi::stri_trans_toupper()`](https://rdrr.io/pkg/stringi/man/stri_trans_casemap.html),
  [`terra::extract()`](https://rspatial.github.io/terra/reference/extract.html),
  [`terra::merge()`](https://rspatial.github.io/terra/reference/merge.html),
  [`terra::vect()`](https://rspatial.github.io/terra/reference/vect.html),
  and [`utils::head()`](https://rdrr.io/r/utils/head.html). The date
  parsing and string-length scoring they supported belonged to the
  removed voucher pipeline; the remaining `stringi` and `terra` calls
  are covered by `@import stringi` and by explicit `terra::`
  qualification.

### Documentation

- **Package-level documentation rewritten.** `VasGBIF-package.R` now
  documents the four-stage, eight-function workflow and leads with the
  two new systems, the native-status detector and the custom filter.
- **README rewritten** in its Workflow, Minimal Complete Example, and
  Performance sections, with a new **Key Points** section describing the
  native-status detection and custom filter systems.
- **`Example.Rmd` completely rewritten** against the current pipeline,
  reporting per-stage record counts from a real 228,494-record download:
  205,527 after TNRS resolution, 145,366 after
  [`custom_filter()`](https://wyx619.github.io/VasGBIF/reference/custom_filter.md),
  then 65,081 coordinate-clean, 8,554 coordinate-problematic, and 71,731
  coordinateless records, ending at 110,706 native, 354 introduced, 81
  extinct, 2 location_doubtful, and 25,669 unknown. The description of
  the bundled example dataset has also been corrected.
- **`_pkgdown.yml` reference index reorganised** into the four pipeline
  stages, with new sections for the print methods and for the
  `Level3maping` dataset.
- DESCRIPTION `Title` and `Description` now quote ‘GBIF’, ‘VasGBIF’, and
  ‘R’ and give the GBIF URL, as CRAN requires.

### Testing

- Test suites for the removed functions (`set_vouchers()`,
  `get_collections()`, `restore_duplicates()`, `refine_records()`) have
  been deleted, along with the stale
  [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md)
  snapshots.
- New and rewritten suites cover
  [`custom_filter()`](https://wyx619.github.io/VasGBIF/reference/custom_filter.md),
  [`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md),
  [`extract_gbif_issues()`](https://wyx619.github.io/VasGBIF/reference/extract_gbif_issues.md),
  [`refine_coordinates()`](https://wyx619.github.io/VasGBIF/reference/refine_coordinates.md),
  [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md),
  [`export_records()`](https://wyx619.github.io/VasGBIF/reference/export_records.md),
  `detect_native_status()`, and
  [`map_records()`](https://wyx619.github.io/VasGBIF/reference/map_records.md),
  testing the new object classes, the per-rule filter summary, the
  two-pass status priority, buffered matching, and input validation for
  every exported function.

## VasGBIF 3.5.2

### Website

- **Added search and dark/light mode toggle** to the pkgdown navbar.
- **Simplified navbar labels**: “Get started” → “Start”, “Reference” →
  “Functions”, “Articles” → “Manuals”.
- Reorganized reference index: `detect_native_status()` and
  `restore_duplicates()` moved under Utilities.
- Workflow diagram converted from JPG to PNG.

### Documentation

- **Fixed Unicode characters in `set_vouchers()` documentation** (`✓`,
  `✗`, `−`) that caused the PDF manual to fail building under LaTeX.
- Updated `Distributions` data source URL from `http` to `https`.
- Added `@seealso` reference in `WorldLandMap` documentation.
- README: updated codecov and R-CMD-check badge links, added GBIF DOI
  citation, rephrased performance statement.
- Vignette `Example.Rmd`: all code chunks set to `eval = FALSE` to avoid
  network-dependent failures during `R CMD check`.
- Vignette `Application.Rmd`: fixed citation format and added missing
  letsR reference.
- Vignette `GetRecords.Rmd`: fixed table column alignment.
- Reported retention rate updated from ~35% to ~30% across package docs
  and vignettes.

### Testing

- Added testthat snapshot files for
  [`set_threads()`](https://wyx619.github.io/VasGBIF/reference/set_threads.md)
  and
  [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md)
  error messages.
- **Added comprehensive test suite across five core functions** (81 new
  tests, 177 total):
  - `set_vouchers()` (54 tests): return structure, `verbatim_quality`
    scoring (0–9), `geospatial_quality` scoring (0 to -9),
    `moreInformativeRecord` calculation, non-groupable record handling,
    voucher selection, tie-breaking, coordinate propagation, taxonomic
    consensus (identified / divergent / unidentified), and final
    classification (usable / duplicate / unusable).
  - `get_collections()` (26 tests): return structure, key format
    `taxon|date|lat|lon`, precision-controlled coordinate rounding,
    complete vs. incomplete key counting, precision parameter
    validation, and eventDate parsing (full dates, dates with time,
    year-month only).
  - `restore_duplicates()` (26 tests): return structure, restoration of
    all eight metadata fields (`eventDate`, `year`, `month`, `day`,
    `identifiedBy`, `countryCode`, `stateProvince`, `locality`), integer
    coercion for `year`/`month`/`day`, `"NA"` string treated as missing,
    skipping of values \>10,000 characters, special character stripping,
    and first-available-duplicate selection.
  - `detect_native_status()` (14 tests): return structure, unknown
    status for taxa absent from `Distributions`, known-native
    classification (e.g. *Rosa canina* in Denmark), independent
    multi-taxon processing, and verification of the `fcase` priority
    logic (location_doubtful \> introduced \> extinct \> native \>
    unknown).
  - `refine_records()` (15 tests): return structure, `native_status`
    column integration, valid coordinate pass-through, zero-coordinate
    flagging by the `"zeros"` test, equal lat/lon flagging by `"equal"`,
    empty `tests` parameter behaviour, and exclusion of `"unusable"`
    records by `restore_duplicates()`.

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
- **`refine_records()`: removed erroneous pre-filter before
  `restore_duplicates()`.** The call
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
  `get_collections()`.
- `check_occ_taxon()` replaced by
  [`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md).
- `set_collection_mark()` replaced by `get_collections()`.
- `set_digital_voucher()` replaced by `set_vouchers()`.

#### Removed Data

- `occ_import`, `ref_wcvp_names`, `seas_ref`, and `wcvp_distributions`
  datasets have been removed from the package. The internal datasets
  `Distributions`, `WGSRPD3`, `WorldLandMap`, and `EnumOccurrenceIssue`
  remain available.

#### Function Signature Changes

- [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md):
  parameter `GBIF_file` renamed to `path`; `only_PRESERVED_SPECIMEN`
  removed; new `remove_tempfile` parameter.
- `refine_records()`: parameter `export_path` removed (use
  [`export_records()`](https://wyx619.github.io/VasGBIF/reference/export_records.md)
  instead); `save_path` removed; return value is now a `refined` object
  with elements `all_records`, `CoordinateProblematic`, and `runtime`.
- [`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md)
  replaces `check_occ_taxon()`: default `sources` changed from
  `c("wcvp", "wfo")` to `"wcvp"` only.

### New Functions

- `detect_native_status()` detects native status by matching validated
  coordinates to WGSRPD Level 3 polygons and WCVP distribution data.
  Classification uses a priority-based scheme: location_doubtful \>
  introduced \> extinct \> native \> unknown.
- [`export_records()`](https://wyx619.github.io/VasGBIF/reference/export_records.md)
  writes refined records to disk as three gzip-compressed CSV files: all
  usable records, the native subset, and records that failed coordinate
  validation.
- `restore_duplicates()` is a new internal helper that fills missing
  metadata fields (`eventDate`, `year`, `month`, `day`, `identifiedBy`,
  `countryCode`, `stateProvince`, `locality`) in usable voucher records
  using data from duplicate records sharing the same collection key.

### Improvements

- **Simplified pipeline**: The workflow has been reduced from 8 modules
  (with collector checking) to 7 core functions across 4 stages. The
  collector name standardization stage has been removed entirely;
  duplicate detection now uses composite keys of
  `taxon_name|eventDate|latitude|longitude` via `get_collections()`.
- `refine_records()` has been modularised into a three-step internal
  pipeline: `restore_duplicates()` → CoordinateCleaner →
  `detect_native_status()`.
- `get_collections()` builds collection-event keys from resolved taxon
  names, event dates, and rounded coordinates, with user-controlled
  spatial precision.
- `set_vouchers()` implements a refined quality scoring system (metadata
  completeness + geospatial penalty) and returns a `vouchers` object.
- `restore_duplicates()` now restores `month` and `day` in addition to
  the previously restored fields.
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
  - `VasGBIF_refined` class for `refine_records()` output

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
