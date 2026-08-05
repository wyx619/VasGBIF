# Export refined records to compressed CSV files

Writes the results of
[`refine_coordinates()`](https://wyx619.github.io/VasGBIF/reference/refine_coordinates.md)
and
[`detect_native_status()`](https://wyx619.github.io/VasGBIF/reference/detect_native_status.md)
to disk as gzip-compressed CSV files. Three files are exported: all
refined records joined with their native status, the native subset, and
records that failed coordinate validation.

## Usage

``` r
export_records(
  refined_coordinates = NA,
  native_detected = NA,
  export_path = NA
)
```

## Arguments

- refined_coordinates:

  A `CoordinateRefined` object returned by
  [`refine_coordinates()`](https://wyx619.github.io/VasGBIF/reference/refine_coordinates.md).

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

- `all_records.csv.gz`: all refined records — those with validated
  coordinates and those without — joined with their native status by
  `gbifID`

- `native_records.csv.gz`: the subset classified as `"native"`

- `CoordinateProblematic_records.csv.gz`: records that failed one or
  more CoordinateCleaner tests

Files are written with `fwrite(encoding = "UTF-8")`. `export_path` is
validated before writing: if it is not a single character path or exists
as a file (not a directory), the function stops with an error; if it
does not exist, a warning is emitted and the directory is created
automatically.

The data inputs are validated first: `refined_coordinates` must be a
`CoordinateRefined` object whose `CoordinateCleaned` and
`Coordinateless` tables share identical columns and contain `gbifID`;
`native_detected` must be a `nativeDetected` object with `gbifID` and
`native_status`.

## See also

[`refine_coordinates()`](https://wyx619.github.io/VasGBIF/reference/refine_coordinates.md),
[`detect_native_status()`](https://wyx619.github.io/VasGBIF/reference/detect_native_status.md)
