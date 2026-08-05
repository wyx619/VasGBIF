# Fast and Easy Compilation of Vascular Plants Occurrence Records from GBIF

GBIF hosts over 500 million tracheophyte (vascular plant) occurrence
records, but processing them typically involves complex workflows and
substantial computational overhead. **VasGBIF** is a fast,
plant-optimised R package that parses, validates, and consolidates GBIF
occurrence records into analysis-ready datasets.

VasGBIF integrates taxonomic resolution via the
[TNRS](https://rdrr.io/pkg/TNRS/man/TNRS.html), spatial validation via
[CoordinateCleaner](https://ropensci.github.io/CoordinateCleaner/reference/CoordinateCleaner-package.html),
and native-range annotation against WCVP and WGSRPD within a single
high-performance pipeline. Its vectorised design and selective
parallelisation let it process one million records on a laptop in under
15 minutes without specialised hardware.

## Details

### Pipeline overview

VasGBIF provides a reproducible workflow organised into four sequential
stages built around eight core functions.

#### Stage 1 — Import and issue parsing

- [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md):
  loads a GBIF occurrence download ZIP ('SIMPLE_CSV' or Darwin Core
  Archive), extracts the occurrence table, and returns an `"import"`
  data.table of the fields required by the workflow.

- [`extract_gbif_issues()`](https://wyx619.github.io/VasGBIF/reference/extract_gbif_issues.md):
  expands the raw pipe-separated `issue` column into one logical
  indicator column per GBIF issue code, plus a companion summary ranking
  issues by how many records they flag.

#### Stage 2 — Taxonomic resolution and record filtering

- [`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md):
  submits species- and infraspecific-rank names to the Taxonomic Name
  Resolution Service (TNRS; Boyle et al. 2013) for resolution against
  the World Checklist of Vascular Plants (WCVP) or World Flora Online
  (WFO). Synonyms are resolved to accepted names; names that cannot be
  matched are flagged for review.

- [`custom_filter()`](https://wyx619.github.io/VasGBIF/reference/custom_filter.md):
  joins the imported records with the resolved taxonomy and the parsed
  issue flags, then applies the enabled filter rules (country code,
  coordinate uncertainty, GBIF issue count, event date, collector and
  identifier fields) to retain only high-quality records (see *Flexible
  and fluent custom filter system*).

#### Stage 3 — Coordinate validation and native-status annotation

- [`refine_coordinates()`](https://wyx619.github.io/VasGBIF/reference/refine_coordinates.md):
  validates coordinates with
  [`CoordinateCleaner::clean_coordinates()`](https://ropensci.github.io/CoordinateCleaner/reference/clean_coordinates.html)
  (Zizka et al. 2019) to flag spatial errors such as centroids,
  capitals, marine coordinates, and zero coordinates, splitting records
  into cleaned, problematic, and coordinate-less tables.

- [`detect_native_status()`](https://wyx619.github.io/VasGBIF/reference/detect_native_status.md):
  matches each record against WCVP distribution data (the internal
  `Distributions` dataset) via WGSRPD Level 3 areas to classify it as
  native, introduced, extinct, location_doubtful, or unknown (see
  *Precise native-status detection system*).

#### Stage 4 — Export and visualisation

- [`export_records()`](https://wyx619.github.io/VasGBIF/reference/export_records.md):
  writes the refined records to disk as three gzip-compressed CSV files:
  all usable records, the native subset, and records that failed
  coordinate validation.

- [`map_records()`](https://wyx619.github.io/VasGBIF/reference/map_records.md):
  renders refined records on interactive maps via
  [`mapView()`](https://r-spatial.github.io/mapview/reference/mapView.html),
  with geohash-based decluttering and colour-coding by native status.
  Supports multiple basemap layers (OpenStreetMap, Esri World Imagery,
  and others).

### Precise native-status detection system

[`detect_native_status()`](https://wyx619.github.io/VasGBIF/reference/detect_native_status.md)
is the analytical core of VasGBIF: it assigns a native, introduced,
extinct, location_doubtful, or unknown classification to every
occurrence by matching the record's identification and position against
authoritative WCVP distribution data (the internal `Distributions`
dataset) organised by WGSRPD Level 3 areas. Classification runs in two
passes so that the most precise available evidence always wins.

**Spatial pass.** Records with validated coordinates are overlaid on the
WGSRPD Level 3 polygon map with
[`terra::extract()`](https://rspatial.github.io/terra/reference/extract.html)
— a single vectorised call that assigns every point its area code in
compiled code. Each area code is looked up in a distribution table
classified from the WCVP flags (`introduced`, `extinct`,
`location_doubtful`) with a fixed priority:

1.  `location_doubtful` wins over every other flag;

2.  otherwise `introduced`;

3.  otherwise `extinct`;

4.  otherwise, when no flag is set, the area is `native`;

5.  any remaining case is `unknown`.

A record that falls in several areas at once receives the most preferred
status (`native` first), never an arbitrary one. Coastal points that
fall just outside a polygon are still matched through a geodesic buffer
(`buffer_km`, applied in metres by
[`terra::buffer()`](https://rspatial.github.io/terra/reference/buffer.html)
so its meaning is identical at every latitude); buffered hits always
rank below exact ones, so a genuine in-polygon match is never displaced
by a buffered candidate.

**Country-code pass.** Records without coordinates, and records the
spatial pass left unresolved, are retried through `countryCode` mapped
to WGSRPD Level 3 areas by the `Level3maping` table. No geometry is
used, so this pass is nearly free, and buffering is chunked
(`buffer_chunk_size`) to keep the relate matrix small.

Every classification records how it was obtained in
`native_status_source` — `accepted_name` / `accepted_species` for
spatial matches, `country_code` / `country_code_after_spatial_miss` for
country-code matches (with a `_species` suffix when fallback was used),
`country_code_miss` when the country mapped but the taxon has no
distribution entry there, and `unmatched` when no usable key exists — so
the entire decision chain is auditable.

**Precision without a speed penalty.** Infraspecific taxa inherit their
parent species' status only when `species_fallback = TRUE`, an explicit
and documented loss of precision; hybrid markers are normalised so
`Alnus x pubescens` matches the `Alnus × pubescens` recorded in the
distributions; and neither the spatial overlay nor the distribution
lookup ever iterates record-by-record in R. The result is a
`nativeDetected` table keyed by `gbifID` (`gbifID`, `LEVEL3_COD`,
`native_status`, `native_status_source`, `buffered`) that feeds directly
into
[`export_records()`](https://wyx619.github.io/VasGBIF/reference/export_records.md)
and
[`map_records()`](https://wyx619.github.io/VasGBIF/reference/map_records.md).

### Flexible and fluent custom filter system

[`custom_filter()`](https://wyx619.github.io/VasGBIF/reference/custom_filter.md)
turns the raw download into an analysis-ready occurrence table. It joins
the three preceding outputs (`occ_import`, `taxa_checked`, `gbif_issue`)
into one table, then walks a user-selected set of quality rules — one
vectorised
[data.table](https://rdrr.io/pkg/data.table/man/data.table.html) pass
per rule — with every step audited.

**Fluent rule control.** Each rule is an independently toggleable
argument. Three rules are on by default (`countryCode`,
`coordinateUncertainty <= 10000` m, `gbif_issues_max <= 5`), giving
sensible out-of-the-box behaviour; `date`, `identifiedBy`, and
`recordedBy` are opt-in, so no information is discarded without an
explicit choice. Numeric thresholds share one uniform "off" convention —
`NULL`, `NA`, or `''` — so any rule can be disabled without
restructuring the call.

**Auditable pipeline.** Every step — the `taxon_resolved` join as well
as each enabled rule — is logged in the returned `summary` table
(`rule`, `dropped`, `remaining`), making the effect of each decision
visible and reproducible. The joins are deliberately strict: the
taxonomic join drops unresolved names instead of carrying `NA` taxonomy
forward, and the one-to-one issue join is verified at runtime, stopping
if any record lacks an issue count.

**Careful collector and identifier detection.** The `identifiedBy` and
`recordedBy` rules remove only values that contain no named person:
missing or empty values, a curated multilingual keyword list (`unknown`,
`anonymous`, `desconocido`, `inconnu`, `unbekannt`, plus Chinese terms
for "unknown", "unnamed", "anonymous" and "no details"), and whole-value
patterns such as `s.n.` and `n/a`. Name separators (`,`, `;`, `&`, `+`,
`and`, and their full-width CJK equivalents) protect values that mix a
keyword with a real name, and word-boundary matching keeps the CJK
keywords from splitting genuine names — deliberately conservative so
that real records are never dropped.

The output `customFiltered` object carries every downstream column in
`occ_filtered` and a per-rule `summary` that exposes the whole filtering
decision chain at a glance.

### Quick start

The built-in example dataset lets you run the full pipeline without a
GBIF download:

    library(VasGBIF)

    # Step 1: Import (built-in example, or use your own ZIP)
    gbif_file <- system.file(
      "extdata", "0003386-260721160103020.zip",
      package = "VasGBIF"
    )
    occ_import <- import_records(path = gbif_file)

    # Step 2: Parse GBIF issue flags
    gbif_issue <- extract_gbif_issues(occ_import)

    # Step 3: Resolve taxon names against WCVP
    taxa_checked <- check_taxon(occ_import = occ_import, accuracy = 0.85)

    # Step 4: Filter records by quality rules
    filtered <- custom_filter(
      occ_import = occ_import,
      taxa_checked = taxa_checked,
      gbif_issue = gbif_issue
    )

    # Step 5: Validate coordinates and annotate native status
    refined_coordinates <- refine_coordinates(
      custom_filtered = filtered,
      threads = 4
    )
    native_detected <- detect_native_status(
      refined_coordinates = refined_coordinates
    )

    # Step 6: Export and visualise
    export_records(
      refined_coordinates = refined_coordinates,
      native_detected = native_detected,
      export_path = tempdir()
    )
    map_records(
      native_detected = native_detected,
      refined_coordinates = refined_coordinates,
      precision = 3,
      cex = 3
    )

### Performance

VasGBIF achieves its speed through several architectural choices:

- **C/C++ backends**: core operations are delegated to
  [data.table](https://rdrr.io/pkg/data.table/man/data.table.html),
  [stringi](https://rdrr.io/pkg/stringi/man/stringi-package.html), and
  [terra](https://rspatial.github.io/terra/reference/terra-package.html)
  — packages written in C/C++ that bypass R's per-iteration interpretive
  overhead.

- **Vectorisation over explicit loops**: operations such as issue-flag
  detection in
  [`extract_gbif_issues()`](https://wyx619.github.io/VasGBIF/reference/extract_gbif_issues.md)
  and native-status lookups in
  [`detect_native_status()`](https://wyx619.github.io/VasGBIF/reference/detect_native_status.md)
  process entire columns in compiled calls rather than iterating in R.

- **SIMD exploitation**: vectorised routines in
  [stringi](https://rdrr.io/pkg/stringi/man/stringi-package.html) and
  [`terra::extract()`](https://rspatial.github.io/terra/reference/extract.html)
  allow the compiler to emit SIMD instructions (AVX, AVX-512) that
  process multiple data elements per CPU cycle.

- **Memory-efficient design**:
  [data.table](https://rdrr.io/pkg/data.table/man/data.table.html)'s
  in-place modification `:=` avoids unnecessary copies, and contiguous
  memory access patterns improve CPU cache utilisation.

- **Selective parallelisation**:
  [`refine_coordinates()`](https://wyx619.github.io/VasGBIF/reference/refine_coordinates.md)
  partitions the dataset into chunks and distributes
  [CoordinateCleaner](https://ropensci.github.io/CoordinateCleaner/reference/CoordinateCleaner-package.html)
  validation across workers via
  [foreach](https://rdrr.io/pkg/foreach/man/foreach.html) and
  [doParallel](https://rdrr.io/pkg/doParallel/man/doParallel-package.html),
  combining vectorised processing within each chunk with parallel
  execution across chunks.

On a standard laptop, VasGBIF compiles one million occurrence records
within 15 minutes.

## References

1.  Appelhans, Tim, Florian Detsch, Christoph Reudenbach, and Stefan
    Woellauer. 2023. "Mapview: Interactive Viewing of Spatial Data in
    R." <https://CRAN.R-project.org/package=mapview>.

2.  Boyle, Brad, Nicole Hopkins, Zhenyuan Lu, Juan Antonio Raygoza
    Garay, Dmitry Mozzherin, Tony Rees, Naim Matasci, et al. 2013. "The
    Taxonomic Name Resolution Service: An Online Tool for Automated
    Standardization of Plant Names." *BMC Bioinformatics* 14 (1): 16.
    [doi:10.1186/1471-2105-14-16](https://doi.org/10.1186/1471-2105-14-16)
    .

3.  Chirico, Michael. 2023. "geohashTools: Tools for Working with
    Geohashes." <https://CRAN.R-project.org/package=geohashTools>.

4.  Govaerts, R. et al. (2021). The World Checklist of Vascular Plants,
    a continuously updated resource for exploring global plant
    diversity. *Scientific Data*, 8, 215.
    [doi:10.1038/s41597-021-00997-6](https://doi.org/10.1038/s41597-021-00997-6)

5.  Zizka, Alexander, Daniele Silvestro, Tobias Andermann, Josue
    Azevedo, Camila Duarte Ritter, Daniel Edler, Harith Farooq, et
    al. 2019. "CoordinateCleaner: Standardized Cleaning of Occurrence
    Records from Biological Collection Databases." Edited by Tiago
    Quental. *Methods in Ecology and Evolution* 10 (5): 744-51.
    [doi:10.1111/2041-210X.13152](https://doi.org/10.1111/2041-210X.13152)
    .

6.  Vilela, Bruno, and Fabricio Villalobos. 2015. "letsR: A New R
    Package for Data Handling and Analysis in Macroecology." Edited by
    Timothée Poisot. *Methods in Ecology and Evolution* 6 (10): 1229-34.
    [doi:10.1111/2041-210x.12401](https://doi.org/10.1111/2041-210x.12401)
    .

## Examples

``` r
if (FALSE) { # interactive()
# Three vignettes walk through the entire VasGBIF workflow, from
# data acquisition to final export:
vignette("GetRecords",   package = "VasGBIF")  # search & download GBIF data
vignette("Example",      package = "VasGBIF")  # quick-start with built-in data
vignette("Application",  package = "VasGBIF")  # real-world full-pipeline walk-through
}
```
