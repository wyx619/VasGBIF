# Example

## Overview

VasGBIF is a high-performance R package that compiles, validates, and
standardizes tracheophyte occurrence records from GBIF into
analysis-ready datasets. This basic example demonstrates the complete
workflow using the built-in example dataset.

The VasGBIF pipeline consists of **4 stages** with **7 core functions**:

| Stage | Functions |
|----|----|
| **Stage 1:** Import and taxonomic standardisation | [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md), [`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md) |
| **Stage 2:** Duplicate detection via collection-event keys | [`get_collections()`](https://wyx619.github.io/VasGBIF/reference/get_collections.md), [`set_vouchers()`](https://wyx619.github.io/VasGBIF/reference/set_vouchers.md) |
| **Stage 3:** Coordinate validation and native-status annotation | [`refine_records()`](https://wyx619.github.io/VasGBIF/reference/refine_records.md) |
| **Stage 4:** Export and visualisation | [`export_records()`](https://wyx619.github.io/VasGBIF/reference/export_records.md), [`map_records()`](https://wyx619.github.io/VasGBIF/reference/map_records.md) |

After all, approximately 30% of the initial records are retained as
high-quality, non-redundant data.

``` r

library(VasGBIF)
library(data.table)
VasGBIF_summary <- list()
```

## Stage 1: Import and Taxonomic Standardisation

### Import Records

[`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md)
reads a GBIF occurrence download ZIP, extracts the occurrence table, and
parses GBIF issue flags into record-level logical indicators.

The built-in example dataset is a GBIF download of *Medicago sativa*
(preserved specimens with coordinates, obtained 23 July 2026):
<https://doi.org/10.15468/dl.nt5exp>.

``` r

gbif_file <- system.file(
  "extdata", "0003386-260721160103020.zip",
  package = "VasGBIF"
)
occ_import <- import_records(path = gbif_file)
VasGBIF_summary$initial_records <- nrow(occ_import$occ)
VasGBIF_summary$initial_taxa <- occ_import$occ[, uniqueN(scientificName)]
```

The `import` object contains:

- `occ`: the occurrence records with core GBIF fields
- `occ_issue`: a binary matrix of GBIF issue flags per record
- `summary`: frequency table of detected issues
- `runtime`: execution time

### Check Taxon Name

[`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md)
resolves species- and infraspecific-rank names against the World
Checklist of Vascular Plants (WCVP) via the Taxonomic Name Resolution
Service (TNRS).

``` r

taxa_checked <- check_taxon(occ_import = occ_import, accuracy = 0.9)
```

The `occ_taxa` object contains:

- `occ_taxa_checked`: records with resolved WCVP taxonomy
- `summary`: resolution statistics by taxon rank
- `runtime`: execution time

## Stage 2: Duplicate Detection via Collection-Event Keys

### Generate Collection-Event Keys

[`get_collections()`](https://wyx619.github.io/VasGBIF/reference/get_collections.md)
builds a composite key from the accepted taxon name, event date, and
rounded coordinates (format:
`wcvp_taxon_name|eventDate|latitude|longitude`). Records sharing the
same key are treated as potential duplicates from a single gathering
event.

``` r

collection_keys <- get_collections(
  occ_import = occ_import,
  taxa_checked = taxa_checked,
  precision = 2L
)
VasGBIF_summary$complete_keys <- collection_keys$complete_keys
VasGBIF_summary$incomplete_keys <- collection_keys$incomplete_keys
```

The `collections` object contains:

- `occ_key`: the occurrence table with collection-event keys
- `complete_keys`: count of records with complete keys
- `incomplete_keys`: count of records with incomplete keys
- `runtime`: execution time

### Select Digital Vouchers

[`set_vouchers()`](https://wyx619.github.io/VasGBIF/reference/set_vouchers.md)
scores each record on metadata completeness (9 fields) and geospatial
quality (GBIF issue flags). The highest-scoring record in each duplicate
group is designated the master digital voucher.

``` r

voucher <- set_vouchers(
  occ_import = occ_import,
  taxa_checked = taxa_checked,
  collection_keys = collection_keys
)
VasGBIF_summary$usable <- voucher$occ_digital_voucher[
  VasGBIF_dataset_result == "usable", .N
]
VasGBIF_summary$duplicate <- voucher$occ_digital_voucher[
  VasGBIF_dataset_result == "duplicate", .N
]
```

The `vouchers` object contains:

- `occ_digital_voucher`: records with quality scores, grouping
  information, and `VasGBIF_dataset_result` (usable / duplicate)
- `occ_results`: quality assessment fields
- `runtime`: execution time

## Stage 3: Coordinate Validation and Native-Status Annotation

[`refine_records()`](https://wyx619.github.io/VasGBIF/reference/refine_records.md)
performs three internal steps: restores missing metadata from
duplicates, validates coordinates with CoordinateCleaner, and assigns
native status by matching validated coordinates to WGSRPD Level 3 areas
and WCVP distribution data.

``` r

refined_records <- refine_records(voucher = voucher, threads = 4)
VasGBIF_summary$all_refined <- nrow(refined_records$all_records)
VasGBIF_summary$native <- refined_records$all_records[
  native_status == "native", .N
]
VasGBIF_summary$introduced <- refined_records$all_records[
  native_status == "introduced", .N
]
VasGBIF_summary$coordinate_problematic <- nrow(
  refined_records$CoordinateProblematic
)
VasGBIF_summary$final_taxa <- refined_records$all_records[
  , uniqueN(VasGBIF_wcvp_taxon_name)
]
```

The `refined` object contains:

- `all_records`: records with validated coordinates, restored metadata,
  and native status
- `CoordinateProblematic`: records that failed one or more
  CoordinateCleaner tests
- `runtime`: execution time

## Stage 4: Export and Visualisation

### Export Records

[`export_records()`](https://wyx619.github.io/VasGBIF/reference/export_records.md)
writes the refined records to disk as gzip-compressed CSV files.

``` r

export_records(
  refined_records = refined_records,
  export_path = getwd()
)
```

Three files are written:

- `usable_refined_records.csv.gz`: all records with validated
  coordinates
- `native_refined_records.csv.gz`: native subset
- `CoordinateProblematic_records.csv.gz`: records failing coordinate
  validation

### Map Records

[`map_records()`](https://wyx619.github.io/VasGBIF/reference/map_records.md)
renders an interactive map via `mapview`, with geohash-based
decluttering and colour-coding by native status.

``` r

map_records(refined_records = refined_records, precision = 3, cex = 3)
```

## Summary

The summary statistics provide a quantitative overview of data reduction
through the pipeline:

``` r

VasGBIF_summary |>
  as.data.frame() |>
  t()
```

``` r

##                         [,1]
## initial_records        12362
## initial_taxa              15
## taxa_submitted         12362
## taxa_resolved          12362
## complete_keys           9445
## incomplete_keys          722
## usable                 10443
## duplicate               1849
## all_refined             9055
## native                   431
## introduced              8224
## coordinate_problematic  1388
## final_taxa                 5
```

| Statistic | Description |
|----|----|
| `initial_records` | Total GBIF occurrence records imported |
| `initial_taxa` | Unique scientific names before resolution |
| `complete_keys` | Records with complete collection-event keys |
| `incomplete_keys` | Records with incomplete keys |
| `usable` | Records classified as usable after voucher selection |
| `duplicate` | Records classified as duplicates |
| `all_refined` | Records retained after coordinate validation |
| `native` | Records classified as native |
| `introduced` | Records classified as introduced |
| `coordinate_problematic` | Records failing coordinate validation |
| `final_taxa` | Unique accepted taxon names in final dataset |

The workflow progressively filters the dataset through taxonomy
resolution, duplicate grouping, quality scoring, and coordinate
validation. The drop from `initial_records` to `all_refined` reflects
the removal of duplicates and records with spatial issues. The
transition from `initial_taxa` to `final_taxa` reflects synonym
resolution and the removal of unresolvable names.

## Performance

VasGBIF achieves its speed through:

- **C/C++ backends**: core operations delegated to `data.table`,
  `stringi`, and `terra`
- **Vectorisation**: entire columns processed in single compiled calls
  via [`fcase()`](https://rdrr.io/pkg/data.table/man/fcase.html),
  [`stri_detect_fixed()`](https://rdrr.io/pkg/stringi/man/stri_detect.html)
- **Memory-efficient design**: in-place modification (`:=`,
  [`set()`](https://rdrr.io/pkg/data.table/man/assign.html)) avoids
  unnecessary copies
- **Selective parallelisation**: CoordinateCleaner validation
  distributed across threads

On a standard laptop, VasGBIF compiles one million occurrence records
within 15 minutes.

## References

GBIF.org (23 July 2026) GBIF Occurrence Download
<https://doi.org/10.15468/dl.nt5exp>
