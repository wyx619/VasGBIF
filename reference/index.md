# Package index

## Package overview

- [`VasGBIF`](https://wyx619.github.io/VasGBIF/reference/VasGBIF.md) :
  Fast and Easy Compilation of Vascular Plants Occurrence Records from
  GBIF

## Stage 1 — Import and taxonomic standardisation

- [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md)
  : Import GBIF occurrence records
- [`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md)
  : Resolve taxon names via the Taxonomic Name Resolution Service

## Stage 2 — Duplicate detection via collection-event keys

- [`get_collections()`](https://wyx619.github.io/VasGBIF/reference/get_collections.md)
  : Generate collection event keys from taxon name, date, and
  coordinates
- [`set_vouchers()`](https://wyx619.github.io/VasGBIF/reference/set_vouchers.md)
  : Select master digital vouchers from duplicate groups via quality
  scoring

## Stage 3 — Coordinate validation and native-status annotation

- [`refine_records()`](https://wyx619.github.io/VasGBIF/reference/refine_records.md)
  : Validate coordinates, restore metadata, and detect native status
- [`detect_native_status()`](https://wyx619.github.io/VasGBIF/reference/detect_native_status.md)
  : Detect native status from WGSRPD distributions
- [`restore_duplicates()`](https://wyx619.github.io/VasGBIF/reference/restore_duplicates.md)
  : Restore missing metadata from duplicate records

## Stage 4 — Export and visualisation

- [`export_records()`](https://wyx619.github.io/VasGBIF/reference/export_records.md)
  : Export refined records to compressed CSV files
- [`map_records()`](https://wyx619.github.io/VasGBIF/reference/map_records.md)
  : Visualize refined records on interactive maps

## Utilities

- [`set_threads()`](https://wyx619.github.io/VasGBIF/reference/set_threads.md)
  : Normalize the number of worker threads

## Internal datasets

- [`Distributions`](https://wyx619.github.io/VasGBIF/reference/Distributions.md)
  : The World Checklist of Vascular Plants Distributions
- [`EnumOccurrenceIssue`](https://wyx619.github.io/VasGBIF/reference/EnumOccurrenceIssue.md)
  : Enumeration GBIF issue
- [`WGSRPD3`](https://wyx619.github.io/VasGBIF/reference/wgsrpd3.md) :
  Biodiversity Information Standards (TDWG) World Geographical Scheme
  for Recording Plant Distributions (WGSRPD)
- [`WorldLandMap`](https://wyx619.github.io/VasGBIF/reference/WorldLandMap.md)
  : A simple features object of the world land map
