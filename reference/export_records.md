# Export classified records to compressed CSV files

Writes the results of
[`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md)
and/or
[`detect_native_country()`](https://wyx619.github.io/VasGBIF/reference/detect_native_country.md)
to disk as gzip-compressed CSV files. Each classification supplied
produces two files: all of its classified records and the native subset.

## Usage

``` r
export_records(
  native_detected_coord = NA,
  native_detected_country = NA,
  export_path = NA
)
```

## Arguments

- native_detected_coord:

  A `nativeDetected` object returned by
  [`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md),
  containing records with validated coordinates. It must carry `gbifID`,
  `native_status`, `decimalLongitude` and `decimalLatitude`, and none of
  its coordinates may be missing. Optional, but at least one of
  `native_detected_coord` and `native_detected_country` must be
  supplied.

- native_detected_country:

  A `nativeDetected` object returned by
  [`detect_native_country()`](https://wyx619.github.io/VasGBIF/reference/detect_native_country.md),
  containing the records classified through their `countryCode`. It must
  carry `gbifID` and `native_status`; missing coordinates are allowed.
  Optional, but at least one of the two classification arguments must be
  supplied.

- export_path:

  Directory where the compressed CSV files should be written.

## Value

Called for its side effect of writing files to `export_path`. Returns
`NULL` invisibly.

## Details

Each classification supplied is written as its own pair of files, so the
two sets never overwrite each other:

- `all_records_coord.csv.gz`: every record classified by
  [`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md),
  with all its columns and its native status

- `native_records_coord.csv.gz`: the subset of those records classified
  as `"native"`

- `all_records_country.csv.gz`: every record classified by
  [`detect_native_country()`](https://wyx619.github.io/VasGBIF/reference/detect_native_country.md),
  with all its columns and its native status

- `native_records_country.csv.gz`: the subset of those records
  classified as `"native"`

Only the pair belonging to a supplied argument is written, so supplying
one argument leaves the files of the other untouched. The two sets are
exported separately rather than bound together: this function never
writes a combined table.

The two `all_records_*` files are likewise not a partition of a single
input and cannot be row-bound with each other. They carry different
columns - the coordinate result comes from `CoordinateCleaned`, whereas
the country-code result comes from `CoordinateProblematic`, which keeps
its per-test verdict columns - and
[`detect_native_country()`](https://wyx619.github.io/VasGBIF/reference/detect_native_country.md)
classifies only the records it receives with a usable `countryCode`.

Both arguments already carry every column of the input records, so no
join is performed here: each table is written straight from the object.

`native_detected_coord` must carry coordinates for every record: it is
the spatial output of
[`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md),
which only classifies records with validated coordinates. The function
stops if `decimalLongitude` or `decimalLatitude` is missing for any of
its records, which catches the two arguments being swapped.
`native_detected_country` carries no such requirement, because
[`detect_native_country()`](https://wyx619.github.io/VasGBIF/reference/detect_native_country.md)
classifies the records that failed coordinate validation - including
records whose coordinates are entirely absent.

Files are written with `fwrite(encoding = "UTF-8")`. `export_path` is
validated before writing: if it is not a single character path or exists
as a file (not a directory), the function stops with an error; if it
does not exist, a warning is emitted and the directory is created
automatically.

## See also

[`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md),
[`detect_native_country()`](https://wyx619.github.io/VasGBIF/reference/detect_native_country.md),
[`par_clean_coordinates()`](https://wyx619.github.io/VasGBIF/reference/par_clean_coordinates.md)
