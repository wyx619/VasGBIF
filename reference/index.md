# Package index

## Package overview

- [`VasGBIF`](https://wyx619.github.io/VasGBIF/reference/VasGBIF.md) :
  Fast and Easy Compilation of Vascular Plants Occurrence Records from
  GBIF

## Stage 1 — Import and issue parsing

- [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md)
  : Import GBIF occurrence records
- [`extract_gbif_issues()`](https://wyx619.github.io/VasGBIF/reference/extract_gbif_issues.md)
  : Extract GBIF issue flags into logical columns

## Stage 2 — Taxonomic resolution and record filtering

- [`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md)
  : Resolve taxon names via the Taxonomic Name Resolution Service
- [`custom_filter()`](https://wyx619.github.io/VasGBIF/reference/custom_filter.md)
  : Apply custom quality filters to occurrence records

## Stage 3 — Coordinate validation and native-status annotation

- [`refine_coordinates()`](https://wyx619.github.io/VasGBIF/reference/refine_coordinates.md)
  : Validate coordinates of filtered occurrence records
- [`detect_native_status()`](https://wyx619.github.io/VasGBIF/reference/detect_native_status.md)
  : Detect native status from WGSRPD distributions

## Stage 4 — Export and visualisation

- [`export_records()`](https://wyx619.github.io/VasGBIF/reference/export_records.md)
  : Export refined records to compressed CSV files
- [`map_records()`](https://wyx619.github.io/VasGBIF/reference/map_records.md)
  : Visualize refined records on interactive maps

## Print methods

- [`print(`*`<import>`*`)`](https://wyx619.github.io/VasGBIF/reference/print.import.md)
  :

  Print an `import` object

- [`print(`*`<issue>`*`)`](https://wyx619.github.io/VasGBIF/reference/print.issue.md)
  :

  Print an `issue` object

- [`print(`*`<occ_taxa>`*`)`](https://wyx619.github.io/VasGBIF/reference/print.occ_taxa.md)
  :

  Print an `occ_taxa` object

- [`print(`*`<CoordinateRefined>`*`)`](https://wyx619.github.io/VasGBIF/reference/print.CoordinateRefined.md)
  :

  Print a `CoordinateRefined` object

- [`print(`*`<customFiltered>`*`)`](https://wyx619.github.io/VasGBIF/reference/print.customFiltered.md)
  :

  Print a `customFiltered` object

- [`print(`*`<nativeDetected>`*`)`](https://wyx619.github.io/VasGBIF/reference/print.nativeDetected.md)
  :

  Print a `nativeDetected` object

## Utilities

- [`set_threads()`](https://wyx619.github.io/VasGBIF/reference/set_threads.md)
  : Normalize the number of worker threads

## Internal datasets

- [`Distributions`](https://wyx619.github.io/VasGBIF/reference/Distributions.md)
  : The World Checklist of Vascular Plants Distributions
- [`EnumOccurrenceIssue`](https://wyx619.github.io/VasGBIF/reference/EnumOccurrenceIssue.md)
  : Enumeration GBIF issue
- [`Level3maping`](https://wyx619.github.io/VasGBIF/reference/Level3maping.md)
  : WGSRPD Level 3 area codes, names and country concordance
- [`WGSRPD3`](https://wyx619.github.io/VasGBIF/reference/wgsrpd3.md) :
  Biodiversity Information Standards (TDWG) World Geographical Scheme
  for Recording Plant Distributions (WGSRPD)
- [`WorldLandMap`](https://wyx619.github.io/VasGBIF/reference/WorldLandMap.md)
  : A simple features object of the world land map
