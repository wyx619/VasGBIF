# Generate collection event keys from taxon name, date, and coordinates

Builds a composite key for each occurrence record by combining the
accepted taxon name from
[`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md),
the collection date, and the rounded geographic coordinates. Records
sharing the same key are likely to represent the same collection event
and can be treated as duplicates.

## Usage

``` r
get_collections(occ_import = NA, taxa_checked = NA, precision = 2L)
```

## Arguments

- occ_import:

  An `import` object returned by
  [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md).

- taxa_checked:

  A `occ_taxa` object returned by
  [`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md),
  used to supply the accepted taxon name for each record.

- precision:

  Integer number of decimal places used to round latitude and longitude
  when constructing the spatial portion of the key. This indirectly
  controls the spatial tolerance for treating two records as the same
  collection event. Typical choices:

  - `1`: ~10 km

  - `2`: ~1 km (default)

  - `3`: ~100 m

  - `4`: ~10 m

  The default of `2` balances the fact that GBIF coordinates are often
  recorded to 5 decimal places (~1 m) whereas the accompanying
  `coordinateUncertaintyInMeters` is commonly around 500 m, making
  sub-100 m grouping unreliable without additional filtering.

## Value

A list of class `"collections"` with four elements:

- `occ_key`: a `data.table` of the occurrence records with an added
  `collection_key` column.

- `complete_keys`: the number of distinct complete keys.

- `incomplete_keys`: the number of distinct incomplete keys (those with
  at least one `NA` component).

- `runtime`: the elapsed execution time.

## Details

### Key construction

The collection key is a pipe-delimited string with four components:

    wcvp_taxon_name | eventDate_numeric | rounded_latitude | rounded_longitude

- `wcvp_taxon_name`: the accepted taxon name from `taxa_checked`.

- `eventDate_numeric`: the `eventDate` field with time-of-day and ISO
  separators removed, parsed as a date with
  [`lubridate::parse_date_time()`](https://lubridate.tidyverse.org/reference/parse_date_time.html)
  (accepting truncated `ymd` orders), and converted to a numeric value.

- `rounded_latitude` and `rounded_longitude`: `decimalLatitude` and
  `decimalLongitude` rounded to `precision` decimal places.

Any component that ends up as `NA` produces an incomplete key.

### Choosing precision

GBIF occurrence records often carry coordinates at 5 decimal places (~1
m at the equator) alongside a `coordinateUncertaintyInMeters` field that
typically ranges from tens to hundreds of metres. Rounding coordinates
via `precision` lets you define a spatial tolerance appropriate for your
data quality expectations, effectively deciding how close two records
must be to share a key.

### Key classification

Keys are considered **complete** when all four components are
non-missing. Keys containing `NA` in at least one position (detected by
the pattern `(^|\\|)NA(\\||$)`) are counted as **incomplete**.

## See also

[`set_vouchers()`](https://wyx619.github.io/VasGBIF/reference/set_vouchers.md),
which consumes the output of this function.

## Examples

``` r
if (FALSE) { # interactive()
collection_keys <- get_collections(
  occ_import = occ_import,
  taxa_checked = taxa_checked,
  precision = 2
)
}
```
