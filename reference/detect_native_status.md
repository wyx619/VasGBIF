# Detect native status from WGSRPD distributions

Assigns a native status classification to each occurrence record by
matching it against WCVP distribution data (the internal `Distributions`
dataset) via WGSRPD Level 3 areas. Classification proceeds in two
stages.

**Spatial stage.** Records with validated coordinates are overlaid on
the WGSRPD Level 3 polygon map (via
[`terra::extract()`](https://rspatial.github.io/terra/reference/extract.html))
to assign an area code to each record. That area code is looked up in a
distribution table classified from the WCVP flags (`introduced`,
`extinct`, `location_doubtful`) with the following priority:

1.  If `location_doubtful == 1`, the area is classified as
    `"location_doubtful"` regardless of other flags.

2.  Otherwise, if `introduced == 1`, the area is `"introduced"`.

3.  Otherwise, if `extinct == 1`, the area is `"extinct"`.

4.  If all three flags are `0`, the area is `"native"`.

5.  Any remaining case defaults to `"unknown"`.

A record that falls in several areas at once is assigned the most
preferred status (`"native"` first). Unresolved records may be buffered
(`buffer_km`) so coastal points just outside a polygon can still be
matched; buffered hits are ranked below exact ones. Records that the
spatial stage still leaves unresolved are retried by country code (see
below).

**Country-code stage.** Records without coordinates, plus records the
spatial stage left unresolved, are matched through `countryCode` mapped
to WGSRPD Level 3 areas by the `Level3maping` table; no geometry is
used. The same status priority applies.

## Usage

``` r
detect_native_status(
  refined_coordinates = NA,
  buffer_km = 10,
  buffer_chunk_size = 2000
)
```

## Arguments

- refined_coordinates:

  A `CoordinateRefined` object (or a list with the same structure)
  containing `CoordinateCleaned` — records with validated coordinates —
  and `Coordinateless` — records without usable coordinates.

- buffer_km:

  Numeric scalar. Width of the spatial buffer in km applied to records
  the exact spatial match left unresolved. `0` disables the buffer.
  Defaults to `10`.

- buffer_chunk_size:

  Numeric scalar. Maximum number of records buffered in one chunk,
  keeping the relate matrix small. Defaults to `2000`.

## Value

A `nativeDetected` object — a `data.table` subclass with one row per
input record (all records from `CoordinateCleaned` and all from
`Coordinateless`), keyed by `gbifID`. Every column of the input records
is retained unchanged, with four classification columns appended:

- `LEVEL3_COD`: the assigned WGSRPD Level 3 area code, or `NA` if the
  record could not be matched

- `native_status`: one of `"native"`, `"introduced"`, `"extinct"`,
  `"location_doubtful"`, or `"unknown"`

- `native_status_source`: how the status was inferred. `"spatial"` /
  `"spatial_buffered"` are spatial matches, the latter via the geodesic
  buffer; `"country_code"` / `"country_code_after_spatial_miss"` are
  country-code matches; `"country_code_no_entry"` means the country
  mapped to WGSRPD areas but the taxon had no distribution entry there;
  `"unmatched"` means the record had no usable key at all.

- `buffered`: `TRUE` when the status came from a buffered spatial hit

The intermediate matching columns used internally (taxon keys, candidate
areas, match ranks) are not returned. Because the record columns are
carried through, the result holds a second copy of the input data: for
large inputs, `refined_coordinates` can be dropped once the
classification is in hand. `CoordinateProblematic` records are not
classified and do not appear in the result.

## Details

**Coordinate reference system.** Both the occurrence points and the
internal `WGSRPD3` polygons are assumed to be in longitude/latitude
(EPSG:4326); the function asserts this on the polygon side. `buffer_km`
is applied as metres via
[`terra::buffer()`](https://rspatial.github.io/terra/reference/buffer.html)'s
geodesic buffer, so it keeps the same meaning at every latitude.

## See also

[`print.nativeDetected()`](https://wyx619.github.io/VasGBIF/reference/print.nativeDetected.md)
for a compact summary of the result.
