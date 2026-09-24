# Package index

## Package overview

- [`VasGBIF`](https://wyx619.github.io/VasGBIF/reference/VasGBIF.md) :
  Fast and Easy Compilation of Vascular Plants Occurrence Records from
  GBIF

## Step 1 — Import Records

- [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md)
  : Import GBIF occurrence records

## Step 2 — Check Taxon Name

- [`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md)
  : Resolve taxon names via the Taxonomic Name Resolution Service

## Step 3 — Customized Filter

- [`customized_filter()`](https://wyx619.github.io/VasGBIF/reference/customized_filter.md)
  : Apply custom quality filters to occurrence records

## Step 4 — Clean Coordinates

- [`par_clean_coordinates()`](https://wyx619.github.io/VasGBIF/reference/par_clean_coordinates.md)
  : Validate coordinates of filtered occurrence records

## Step 5 — Detect Native Status

- [`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md)
  : Detect native status from WGSRPD distributions
- [`detect_native_country()`](https://wyx619.github.io/VasGBIF/reference/detect_native_country.md)
  : Detect native status from country codes

## Step 6 — Map Records

- [`map_records()`](https://wyx619.github.io/VasGBIF/reference/map_records.md)
  : Visualize refined records on interactive maps

## Step 7 — Export Records

- [`export_records()`](https://wyx619.github.io/VasGBIF/reference/export_records.md)
  : Export classified records to compressed CSV files

## Print methods

- [`print(`*`<import>`*`)`](https://wyx619.github.io/VasGBIF/reference/print.import.md)
  :

  Print an `import` object

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
  : Enumeration of GBIF occurrence issues
- [`Level3maping`](https://wyx619.github.io/VasGBIF/reference/Level3maping.md)
  : WGSRPD Level 3 area codes, names and country concordance
- [`WGSRPD3`](https://wyx619.github.io/VasGBIF/reference/wgsrpd3.md) :
  Biodiversity Information Standards (TDWG) World Geographical Scheme
  for Recording Plant Distributions (WGSRPD)
- [`WorldLandMap`](https://wyx619.github.io/VasGBIF/reference/WorldLandMap.md)
  : A simple features object of the world land map
