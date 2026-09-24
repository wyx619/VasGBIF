# Detect native status from country codes

Assigns a native status classification to occurrence records by matching
their country code against WCVP distribution data (the internal
`Distributions` dataset) via WGSRPD Level 3 areas. The country code is
mapped to candidate Level 3 areas by the `Level3maping` table; no
geometry is used. The same flag priority as
[`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md)
applies:

1.  If `location_doubtful == 1`, the area is classified as
    `"location_doubtful"` regardless of other flags.

2.  Otherwise, if `introduced == 1`, the area is `"introduced"`.

3.  Otherwise, if `extinct == 1`, the area is `"extinct"`.

4.  If all three flags are `0`, the area is `"native"`.

5.  Any remaining case defaults to `"unknown"`.

This stage needs no geometry, so it classifies every record handed to
it, including records that lack coordinates entirely. Records with
validated coordinates are better classified with
[`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md),
whose spatial match is more precise.

## Usage

``` r
detect_native_country(
  input = NA,
  species = "Accepted_name",
  country = "countryCode"
)
```

## Arguments

- input:

  A table holding one occurrence record per row, with the species and
  country-code columns named by `species` and `country`. Anything
  [`data.table::as.data.table()`](https://rdrr.io/pkg/data.table/man/as.data.table.html)
  can convert is accepted. Typically the `CoordinateProblematic` table
  of a `CoordinateRefined` object returned by
  [`par_clean_coordinates()`](https://wyx619.github.io/VasGBIF/reference/par_clean_coordinates.md).
  Missing coordinates are allowed: no geometry is used.

- species, country:

  Names of the columns in `input` holding the species name and the
  country code. Default to the GBIF field names `"Accepted_name"` and
  `"countryCode"`.

## Value

A `nativeDetected` object - a `data.table` subclass with one row per
input record (every row of `input`), keyed by `gbifID`. Every column of
the input records is retained unchanged, with three classification
columns appended:

- `LEVEL3_COD`: the assigned WGSRPD Level 3 area code, or `NA` if the
  record could not be matched

- `native_status`: one of `"native"`, `"introduced"`, `"extinct"`,
  `"location_doubtful"`, or `"unknown"`

- `native_status_source`: `"country"` for a mapped hit; `"no_entry"`
  when the country mapped to areas but the taxon had no distribution
  entry there; `"unmatched"` when the record had no usable country code.

The intermediate matching columns used internally (taxon keys, candidate
areas, match ranks) are not returned.

## Details

`L3 ISOcode` in `Level3maping` is reproduced as published and is **not**
a complete or one-to-one concordance. A single ISO code usually maps to
several Level 3 units (for example `CN` maps to eight), so a country
code identifies a *set* of candidate areas; a record is assigned the
most preferred status among the areas its taxon occurs in (`"native"`
first).

Every input record is returned. A record whose country code is missing
or empty, or maps to no Level 3 area, is kept with
`native_status_source = "unmatched"`; a record whose country maps to
areas but whose taxon has no distribution entry there is `"no_entry"`.

**Input.** Any table-like object that
[`data.table::as.data.table()`](https://rdrr.io/pkg/data.table/man/as.data.table.html)
can convert is accepted - a `data.frame`, a `data.table`, a tibble, or a
list of equal-length columns - provided it carries the species and
country-code columns named by `species` and `country`. No coordinate
column is required. Pass the problematic-coordinate table (for example
`refined_coordinates$CoordinateProblematic`). If `input` has no
`gbifID`, one is created as a character sequence number. The column-name
arguments are independent of the data: a column that happens to share a
name with one of them (for example a `species` column) does not
interfere, and `species = "species"` is a valid way to select it.

## See also

[`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md)
for records with validated coordinates,
[`print.nativeDetected()`](https://wyx619.github.io/VasGBIF/reference/print.nativeDetected.md)
for a compact summary of the result.

## Examples

``` r
if (FALSE) { # interactive() && exists("refined_coordinates")
# Classify the records that failed coordinate validation. `refined_coordinates`
# comes from `par_clean_coordinates()`, whose example creates it when run
# first.
native_country <- detect_native_country(
  refined_coordinates$CoordinateProblematic
)
native_country
}
```
