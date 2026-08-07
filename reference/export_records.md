# Export classified records to compressed CSV files

Writes the results of
[`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md)
to disk as gzip-compressed CSV files. Two files are exported: all
classified records and the native subset.

## Usage

``` r
export_records(native_detected_coord = NA, export_path = NA)
```

## Arguments

- native_detected_coord:

  A `nativeDetected` object returned by
  [`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md),
  containing records with validated coordinates.

- export_path:

  Directory where the compressed CSV files should be written.

## Value

Called for its side effect of writing files to `export_path`. Returns
`NULL` invisibly.

## Details

The following files are written:

- `all_records.csv.gz`: every classified record with validated
  coordinates, with all its columns and its native status

- `native_records.csv.gz`: the subset classified as `"native"`

`native_detected_coord` already carries every column of the input
records, so no join is performed here: `all_records.csv.gz` is written
straight from it.

`native_detected_coord` must carry coordinates for every record: it is
the spatial output of
[`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md),
which only classifies records with validated coordinates. The function
stops if `decimalLongitude` or `decimalLatitude` is missing for any
record — the output of
[`detect_native_country()`](https://wyx619.github.io/VasGBIF/reference/detect_native_country.md)
would be rejected this way. Records without coordinates are classified
separately by
[`detect_native_country()`](https://wyx619.github.io/VasGBIF/reference/detect_native_country.md);
to export both sets together, bind the two results before calling this
function.

Files are written with `fwrite(encoding = "UTF-8")`. `export_path` is
validated before writing: if it is not a single character path or exists
as a file (not a directory), the function stops with an error; if it
does not exist, a warning is emitted and the directory is created
automatically.

## See also

[`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md),
[`detect_native_country()`](https://wyx619.github.io/VasGBIF/reference/detect_native_country.md),
[`refine_coordinates()`](https://wyx619.github.io/VasGBIF/reference/refine_coordinates.md)
