# Export classified records to compressed CSV files

Writes the results of
[`detect_native_status()`](https://wyx619.github.io/VasGBIF/reference/detect_native_status.md)
to disk as gzip-compressed CSV files. Two files are exported: all
classified records and the native subset.

## Usage

``` r
export_records(native_detected = NA, export_path = NA)
```

## Arguments

- native_detected:

  A `nativeDetected` object returned by
  [`detect_native_status()`](https://wyx619.github.io/VasGBIF/reference/detect_native_status.md).

- export_path:

  Directory where the compressed CSV files should be written.

## Value

Called for its side effect of writing files to `export_path`. Returns
`NULL` invisibly.

## Details

The following files are written:

- `all_records.csv.gz`: every classified record — those with validated
  coordinates and those without — with all its columns and its native
  status

- `native_records.csv.gz`: the subset classified as `"native"`

`native_detected` already carries every column of the input records, so
no join is performed here: `all_records.csv.gz` is written straight from
it. Records that failed coordinate validation are never classified and
therefore do not appear in the output; use
[`refine_coordinates()`](https://wyx619.github.io/VasGBIF/reference/refine_coordinates.md)
to inspect them.

Files are written with `fwrite(encoding = "UTF-8")`. `export_path` is
validated before writing: if it is not a single character path or exists
as a file (not a directory), the function stops with an error; if it
does not exist, a warning is emitted and the directory is created
automatically.

## See also

[`detect_native_status()`](https://wyx619.github.io/VasGBIF/reference/detect_native_status.md),
[`refine_coordinates()`](https://wyx619.github.io/VasGBIF/reference/refine_coordinates.md)
