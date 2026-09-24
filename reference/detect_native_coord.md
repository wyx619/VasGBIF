# Detect native status from WGSRPD distributions

Assigns a native status classification to each occurrence record by
matching it against WCVP distribution data (the internal `Distributions`
dataset) via WGSRPD Level 3 areas. Classification uses only the spatial
stage: the records in `input` are overlaid on the WGSRPD Level 3 polygon
map (via
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
matched; buffered hits are ranked below exact ones.

Every record must carry a usable coordinate. Records without one are
**not** classified here; classify them with
[`detect_native_country()`](https://wyx619.github.io/VasGBIF/reference/detect_native_country.md),
which matches them through their `countryCode` without using geometry.

## Usage

``` r
detect_native_coord(
  input = NA,
  species = "Accepted_name",
  longitude = "decimalLongitude",
  latitude = "decimalLatitude",
  buffer_km = 10,
  buffer_chunk_size = 2000
)
```

## Arguments

- input:

  A table holding one occurrence record per row, with the species and
  coordinate columns named by `species`, `longitude` and `latitude`.
  Anything
  [`data.table::as.data.table()`](https://rdrr.io/pkg/data.table/man/as.data.table.html)
  can convert is accepted, so a `data.frame`, `data.table`, tibble or
  list of equal-length columns all work. Typically the
  `CoordinateCleaned` table of a `CoordinateRefined` object returned by
  [`par_clean_coordinates()`](https://wyx619.github.io/VasGBIF/reference/par_clean_coordinates.md).
  Every record must carry a non-missing coordinate.

- species, longitude, latitude:

  Names of the columns in `input` holding the species name and the
  coordinates. Default to the GBIF field names `"Accepted_name"`,
  `"decimalLongitude"` and `"decimalLatitude"`.

- buffer_km:

  Numeric scalar. Width of the spatial buffer in km applied to records
  the exact spatial match left unresolved. `0` disables the buffer.
  Defaults to `10`.

- buffer_chunk_size:

  Numeric scalar. Maximum number of records buffered in one chunk,
  keeping the relate matrix small. Defaults to `2000`.

## Value

A `nativeDetected` object - a `data.table` subclass with one row per
input record (every row of `input`), keyed by `gbifID`. Every column of
the input records is retained unchanged, with three classification
columns appended:

- `LEVEL3_COD`: the assigned WGSRPD Level 3 area code, or `NA` if the
  record could not be matched

- `native_status`: one of `"native"`, `"introduced"`, `"extinct"`,
  `"location_doubtful"`, or `"unknown"`

- `native_status_source`: how the status was inferred. `"exact"` is a
  direct spatial match, `"buffered"` a match obtained through the
  geodesic buffer, and `"unmatched"` a record that matched no area at
  all.

The intermediate matching columns used internally (taxon keys, candidate
areas, match ranks) are not returned. Because the record columns are
carried through, the result holds a second copy of the input data: for
large inputs, the input table can be dropped once the classification is
in hand.

## Details

**Coordinate reference system.** Both the occurrence points and the
internal `WGSRPD3` polygons are assumed to be in longitude/latitude
(EPSG:4326); the function asserts this on the polygon side. `buffer_km`
is applied as metres via
[`terra::buffer()`](https://rspatial.github.io/terra/reference/buffer.html)'s
geodesic buffer, so it keeps the same meaning at every latitude.

**Input.** Any table-like object that
[`data.table::as.data.table()`](https://rdrr.io/pkg/data.table/man/as.data.table.html)
can convert is accepted - a `data.frame`, a `data.table`, a tibble, or a
list of equal-length columns - provided it carries the species and
coordinate columns named by `species`, `longitude` and `latitude`. It
does not have to come from
[`par_clean_coordinates()`](https://wyx619.github.io/VasGBIF/reference/par_clean_coordinates.md).
Pass the validated-coordinate table (for example
`refined_coordinates$CoordinateCleaned`) so the records that failed
coordinate validation are left to
[`detect_native_country()`](https://wyx619.github.io/VasGBIF/reference/detect_native_country.md)
instead of being classified by geometry. If `input` has no `gbifID`, one
is created as a character sequence number. The column-name arguments are
independent of the data: a column that happens to share a name with one
of them (for example a `species` column) does not interfere, and
`species = "species"` is a valid way to select it.

## See also

[`detect_native_country()`](https://wyx619.github.io/VasGBIF/reference/detect_native_country.md)
for records without coordinates,
[`print.nativeDetected()`](https://wyx619.github.io/VasGBIF/reference/print.nativeDetected.md)
for a compact summary of the result.

## Examples

``` r
if (FALSE) { # interactive() && exists("refined_coordinates")
# Classify the records with validated coordinates. `refined_coordinates`
# comes from `par_clean_coordinates()`, whose example creates it when run
# first.
native_coord <- detect_native_coord(refined_coordinates$CoordinateCleaned)
native_coord
}
```
