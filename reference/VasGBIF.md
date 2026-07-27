# Fast and Easy Compilation of Vascular Plants Occurrence Records from GBIF

GBIF hosts over 500 million tracheophyte (vascular plant) occurrence
records, but processing them typically involves complex workflows and
substantial computational overhead. **VasGBIF** is a fast,
plant-optimised R package that parses, validates, and consolidates GBIF
occurrence records into analysis-ready datasets.

VasGBIF integrates taxonomic resolution via the
[TNRS](https://rdrr.io/pkg/TNRS/man/TNRS.html), spatial validation via
[CoordinateCleaner](https://ropensci.github.io/CoordinateCleaner/reference/CoordinateCleaner-package.html),
duplicate consolidation, and native-range annotation against WCVP and
WGSRPD within a single high-performance pipeline. Its vectorised design
and selective parallelisation let it process one million records on a
laptop in under 15 minutes without specialised hardware.

## Details

### Pipeline overview

VasGBIF provides a reproducible workflow organised into four sequential
stages built around seven core functions. The core pipeline typically
retains approximately 35% of input records as high-quality,
non-redundant data.

#### Stage 1 — Import and taxonomic standardisation

- [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md):
  loads a GBIF occurrence download ZIP, extracts the occurrence table,
  and parses GBIF issue flags.

- [`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md):
  submits species- and infraspecific-rank names to the Taxonomic Name
  Resolution Service (TNRS; Boyle et al. 2013) for resolution against
  the World Checklist of Vascular Plants (WCVP). Synonyms are resolved
  to accepted names; names that cannot be matched are flagged for
  review.

#### Stage 2 — Duplicate detection via collection-event keys

- [`get_collections()`](https://wyx619.github.io/VasGBIF/reference/get_collections.md):
  builds a composite key for each record from its accepted taxon name,
  collection date, and rounded coordinates. Records sharing the same key
  are treated as potential duplicates from a single gathering event.

- [`set_vouchers()`](https://wyx619.github.io/VasGBIF/reference/set_vouchers.md):
  scores each record on metadata completeness (nine fields) and
  geospatial quality (GBIF issue flags) and selects the highest-scoring
  record in each duplicate group as the master digital voucher. Records
  with incomplete keys are kept as independent vouchers.

#### Stage 3 — Coordinate validation and native-status annotation

- [`refine_records()`](https://wyx619.github.io/VasGBIF/reference/refine_records.md):
  restores missing metadata from duplicate records via
  [`restore_duplicates()`](https://wyx619.github.io/VasGBIF/reference/restore_duplicates.md),
  then validates coordinates with
  [`CoordinateCleaner::clean_coordinates()`](https://ropensci.github.io/CoordinateCleaner/reference/clean_coordinates.html)
  (Zizka et al. 2019) to flag spatial errors such as centroids,
  capitals, marine coordinates, and zero coordinates. Matches validated
  coordinates to [WGSRPD Level
  3](https://wyx619.github.io/VasGBIF/reference/wgsrpd3.md) and [WCVP
  distribution](https://wyx619.github.io/VasGBIF/reference/Distributions.md)
  data via
  [`detect_native_status()`](https://wyx619.github.io/VasGBIF/reference/detect_native_status.md)
  to classify each record as native, introduced, extinct,
  location_doubtful, or unknown.

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

    # Step 2: Resolve taxon names against WCVP
    taxa_checked <- check_taxon(occ_import = occ_import, accuracy = 0.9)

    # Step 3: Build collection-event keys
    collection_keys <- get_collections(
      occ_import = occ_import,
      taxa_checked = taxa_checked,
      precision = 2L
    )

    # Step 4: Select digital vouchers
    voucher <- set_vouchers(
      occ_import = occ_import,
      taxa_checked = taxa_checked,
      collection_keys = collection_keys
    )

    # Step 5: Validate coordinates and annotate native status
    refined_records <- refine_records(
      voucher = voucher,
      threads = 4
    )

    # Step 6: Export records
    export_records(refined_records = refined_records,
      export_path = getwd())

    # Optional: visualise on an interactive map
    map_records(refined_records = refined_records, precision = 3,
      cex = 3)

### Performance

VasGBIF achieves its speed through several architectural choices:

- **C/C++ backends**: core operations are delegated to
  [data.table](https://rdrr.io/pkg/data.table/man/data.table.html),
  [stringi](https://rdrr.io/pkg/stringi/man/stringi-package.html), and
  [terra](https://rspatial.github.io/terra/reference/terra-package.html)
  — packages written in C/C++ that bypass R's per-iteration interpretive
  overhead.

- **Vectorisation over explicit loops**: functions such as
  [`set_vouchers()`](https://wyx619.github.io/VasGBIF/reference/set_vouchers.md)
  use vectorised string matching
  [`stri_detect_fixed()`](https://rdrr.io/pkg/stringi/man/stri_detect.html)
  and conditional assignment
  [`fcase()`](https://rdrr.io/pkg/data.table/man/fcase.html) to process
  entire columns in a single compiled call rather than iterating in R.

- **SIMD exploitation**: vectorised routines in
  [stringi](https://rdrr.io/pkg/stringi/man/stringi-package.html) and
  [`terra::extract()`](https://rspatial.github.io/terra/reference/extract.html)
  allow the compiler to emit SIMD instructions (AVX, AVX-512) that
  process multiple data elements per CPU cycle.

- **Memory-efficient design**:
  [data.table](https://rdrr.io/pkg/data.table/man/data.table.html)'s
  in-place modification `:=`,
  [`set()`](https://rdrr.io/pkg/data.table/man/assign.html)) avoids
  unnecessary copies, and contiguous memory access patterns improve CPU
  cache utilisation.

- **Selective parallelisation**:
  [`refine_records()`](https://wyx619.github.io/VasGBIF/reference/refine_records.md)
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

4.  De Melo, Pablo Hendrigo Alves, Nadia Bystriakova, Eve Lucas, and
    Alexandre K. Monro. 2024. "A New R Package to Parse Plant Species
    Occurrence Records into Unique Collection Events Efficiently Reduces
    Data Redundancy." *Scientific Reports* 14 (1): 5450.
    [doi:10.1038/s41598-024-56158-3](https://doi.org/10.1038/s41598-024-56158-3)
    .

5.  Vilela, Bruno, and Fabricio Villalobos. 2015. "letsR: A New R
    Package for Data Handling and Analysis in Macroecology." Edited by
    Timothée Poisot. *Methods in Ecology and Evolution* 6 (10): 1229-34.
    [doi:10.1111/2041-210x.12401](https://doi.org/10.1111/2041-210x.12401)
    .

6.  Zizka, Alexander, Daniele Silvestro, Tobias Andermann, Josue
    Azevedo, Camila Duarte Ritter, Daniel Edler, Harith Farooq, et
    al. 2019. "CoordinateCleaner: Standardized Cleaning of Occurrence
    Records from Biological Collection Databases." Edited by Tiago
    Quental. *Methods in Ecology and Evolution* 10 (5): 744-51.
    [doi:10.1111/2041-210X.13152](https://doi.org/10.1111/2041-210X.13152)
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
