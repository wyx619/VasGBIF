# Export refined records to compressed CSV files

Writes the output of
[`refine_records()`](https://wyx619.github.io/VasGBIF/reference/refine_records.md)
to disk as gzip-compressed CSV files. Three files are exported: all
usable records, the native subset, and records that failed coordinate
validation.

## Usage

``` r
export_records(refined_records = NA, export_path = NA)
```

## Arguments

- refined_records:

  A `refined` object returned by
  [`refine_records()`](https://wyx619.github.io/VasGBIF/reference/refine_records.md).

- export_path:

  Directory where the compressed CSV files should be written.

## Value

Called for its side effect of writing files to `export_path`. Returns
`NULL` invisibly.

## Details

The following files are written:

- `usable_refined_records.csv.gz`: all records with validated
  coordinates and assigned native status

- `native_refined_records.csv.gz`: the subset classified as native

- `CoordinateProblematic_records.csv.gz`: records that failed one or
  more CoordinateCleaner tests

Files are written with `fwrite(encoding = "UTF-8")`. `export_path` is
validated before writing: if it exists as a file (not a directory) or is
`NA`, the function stops with an error; if it does not exist, a warning
is emitted and the directory is created automatically.

## See also

[`refine_records()`](https://wyx619.github.io/VasGBIF/reference/refine_records.md)
