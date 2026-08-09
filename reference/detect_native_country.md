# Detect native status from country codes

Assigns a native status classification to occurrence records that lack
usable coordinates by matching their `countryCode` against WCVP
distribution data (the internal `Distributions` dataset) via WGSRPD
Level 3 areas. `countryCode` is mapped to candidate Level 3 areas by the
`Level3maping` table; no geometry is used. The same flag priority as
[`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md)
applies:

1.  If `location_doubtful == 1`, the area is classified as
    `"location_doubtful"` regardless of other flags.

2.  Otherwise, if `introduced == 1`, the area is `"introduced"`.

3.  Otherwise, if `extinct == 1`, the area is `"extinct"`.

4.  If all three flags are `0`, the area is `"native"`.

5.  Any remaining case defaults to `"unknown"`.

Only records missing longitude **or** latitude —
`custom_filtered$occ_filtered[is.na(decimalLatitude) | is.na(decimalLongitude)]`
— are classified. Records with complete coordinates are not part of the
result; classify them with
[`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md)
instead.

## Usage

``` r
detect_native_country(custom_filtered = NA)
```

## Arguments

- custom_filtered:

  A `customFiltered` object returned by
  [`custom_filter()`](https://wyx619.github.io/VasGBIF/reference/custom_filter.md).
  Only records missing longitude or latitude are classified; records
  with complete coordinates are dropped from the result.

## Value

A `nativeDetected` object — a `data.table` subclass with one row per
coordinateless record (every row of
`custom_filtered$occ_filtered[is.na(decimalLatitude) | is.na(decimalLongitude)]`),
keyed by `gbifID`. Every column of the input records is retained
unchanged, with four classification columns appended:

- `LEVEL3_COD`: the assigned WGSRPD Level 3 area code, or `NA` if the
  record could not be matched

- `native_status`: one of `"native"`, `"introduced"`, `"extinct"`,
  `"location_doubtful"`, or `"unknown"`

- `native_status_source`: `"country_code"` for a mapped hit;
  `"country_code_no_entry"` when the country mapped to areas but the
  taxon had no distribution entry there; `"unmatched"` when the record
  had no usable country code.

- `buffered`: always `FALSE`; no geometry is used.

The intermediate matching columns used internally (taxon keys, candidate
areas, match ranks) are not returned.

## Details

`L3 ISOcode` in `Level3maping` is reproduced as published and is **not**
a complete or one-to-one concordance. A single ISO code usually maps to
several Level 3 units (for example `CN` maps to eight), so a country
code identifies a *set* of candidate areas; a record is assigned the
most preferred status among the areas its taxon occurs in (`"native"`
first). Records whose country code is missing or empty, or maps to no
Level 3 area, stay `"unmatched"`; records whose country maps to areas
but whose taxon has no distribution entry there are
`"country_code_no_entry"`.

## See also

[`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md)
for records with validated coordinates,
[`print.nativeDetected()`](https://wyx619.github.io/VasGBIF/reference/print.nativeDetected.md)
for a compact summary of the result.

## Examples

``` r
if (FALSE) { # interactive() && exists("filtered")
# Classify the coordinate-less records. `filtered` comes from
# `custom_filter()`, whose example creates it when run first.
native_country <- detect_native_country(custom_filtered = filtered)
native_country
}
```
