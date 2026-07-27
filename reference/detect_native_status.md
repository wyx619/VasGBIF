# Detect native status from WGSRPD distributions

Assigns a native status classification to each occurrence record by
matching validated coordinates to WCVP distribution data via WGSRPD
Level 3 polygons.

Native status is determined in two stages, working one taxon at a time.

**Stage 1 — classify WGSRPD areas.** The internal `Distributions`
dataset links each WGSRPD Level 3 area code to WCVP flags (`introduced`,
`extinct`, `location_doubtful`). These flags are resolved into a single
status label with the following priority:

1.  If `location_doubtful == 1`, the area is classified as
    `"location_doubtful"` regardless of other flags.

2.  Otherwise, if `introduced == 1`, the area is `"introduced"`.

3.  Otherwise, if `extinct == 1`, the area is `"extinct"`.

4.  If all three flags are `0`, the area is `"native"`.

5.  Any remaining case defaults to `"unknown"`.

**Stage 2 — spatial intersection.** For each taxon, the validated
occurrence points are overlaid on the WGSRPD Level 3 polygon map (via
[`terra::extract()`](https://rspatial.github.io/terra/reference/extract.html))
to assign an area code to each record. That area code is then looked up
in the classified distribution table. Records falling outside any
documented area, or whose taxon has no entry in `Distributions`, are
labelled `"unknown"`.

## Usage

``` r
detect_native_status(CoordinateCleaned)
```

## Arguments

- CoordinateCleaned:

  A `data.table` of records that passed coordinate validation,
  containing at minimum `gbifID`, `VasGBIF_decimalLongitude`,
  `VasGBIF_decimalLatitude`, and `VasGBIF_wcvp_taxon_name`.

## Value

A `data.table` with columns:

- `gbifID`: the record identifier

- `LEVEL3_COD`: the assigned WGSRPD Level 3 area code, or `NA` if the
  taxon has no distribution data

- `native_status`: one of `"native"`, `"introduced"`, `"extinct"`,
  `"location_doubtful"`, or `"unknown"`
