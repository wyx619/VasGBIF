# Validate coordinates of filtered occurrence records

Validates the coordinates of occurrence records with CoordinateCleaner
and splits them into coordinate-clean and problematic tables. Any table
with a taxon column and complete coordinate columns is accepted, so the
function does not depend on the output of
[`customized_filter()`](https://wyx619.github.io/VasGBIF/reference/customized_filter.md).

[CoordinateCleaner::clean_coordinates](https://ropensci.github.io/CoordinateCleaner/reference/clean_coordinates.html)
checks run in parallel to flag common spatial issues such as centroids,
capitals, and marine records.

Records that pass all requested tests are returned in
`CoordinateCleaned`; records that fail one or more tests, along with
records lacking coordinates, are returned in `CoordinateProblematic`.
The latter carries one logical column per test applied, so a flagged
record can be traced to the specific test(s) it failed. Native-status
classification is a separate step:
[`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md)
classifies the records with validated coordinates, and
[`detect_native_country()`](https://wyx619.github.io/VasGBIF/reference/detect_native_country.md)
the coordinate-less records (extracted from `CoordinateProblematic`).

## Usage

``` r
par_clean_coordinates(
  input = NA,
  species = "Accepted_name_id",
  longitude = "decimalLongitude",
  latitude = "decimalLatitude",
  threads = 4,
  tests = c("capitals", "centroids", "equal", "gbif", "institutions", "outliers", "seas",
    "zeros")
)
```

## Arguments

- input:

  A table of occurrence records, with coordinates that are complete,
  i.e. neither longitude nor latitude may be `NA`; records missing
  either are returned in `CoordinateProblematic` without being
  validated. Typically `filtered$occ_filtered`, the table returned by
  [`customized_filter()`](https://wyx619.github.io/VasGBIF/reference/customized_filter.md).
  If the table has no `gbifID` column, one is created as a character
  sequence number over the input rows.

- species:

  Name of the column giving the taxon each record belongs to, used to
  group records for the `outliers` test. Defaults to
  `"Accepted_name_id"`, the column produced by
  [`customized_filter()`](https://wyx619.github.io/VasGBIF/reference/customized_filter.md).

- longitude, latitude:

  Names of the longitude and latitude columns. Default to
  `"decimalLongitude"` and `"decimalLatitude"`, the names produced by
  [`customized_filter()`](https://wyx619.github.io/VasGBIF/reference/customized_filter.md).

- threads:

  Number of threads to use for coordinate validation, passed to
  [`set_threads()`](https://wyx619.github.io/VasGBIF/reference/set_threads.md).
  Use an integer `>= 1` for an absolute count, or a value between `0`
  and `1` for a proportion of available cores. The default is `4`.

- tests:

  Character vector of CoordinateCleaner validation tests to apply.
  Choose one or more of `"capitals"`, `"centroids"`, `"equal"`,
  `"gbif"`, `"institutions"`, `"outliers"`, `"seas"`, and `"zeros"`. The
  default uses all tests. Each test adds its own verdict column to
  `CoordinateProblematic`; see *Verdict columns*.

## Value

A `CoordinateRefined` object (list) with three elements:

- `CoordinateCleaned`: a `data.table` of records that passed all
  requested coordinate tests (complete data with valid coordinates)

- `CoordinateProblematic`: a `data.table` containing (1) records that
  failed one or more coordinate tests, and (2) records lacking complete
  coordinates (missing latitude or longitude). The two kinds of record
  are told apart by the verdict columns described in *Verdict columns*:
  they are all `NA` for the coordinate-less records and for the other
  records at least one is `FALSE`, the columns for the remaining tests
  being `TRUE`

- `runtime`: the elapsed execution time

Use
[`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md)
to classify the records with validated coordinates, and
[`detect_native_country()`](https://wyx619.github.io/VasGBIF/reference/detect_native_country.md)
for the coordinate-less records from `CoordinateProblematic`.

## Details

### Coordinate validation

Coordinate validation is performed with CoordinateCleaner. Available
tests are:

- `capitals`: records at country capital coordinates

- `centroids`: records at country or province centroids

- `equal`: records with identical latitude and longitude values

- `gbif`: records matching known GBIF geospatial issues

- `institutions`: records at known herbarium or museum coordinates

- `outliers`: geographic outliers within a species range

- `seas`: records located in marine areas for terrestrial species

- `zeros`: records at coordinates `(0, 0)`

The `seas` test is evaluated against the bundled `WorldLandMap` land
polygons buffered by 5 km. The buffer absorbs records that a coarse
coastline places just offshore, which would otherwise be reported as sea
records; it is applied because the map is a low-resolution outline, not
because those records are expected to be at sea.

### Parallel processing

Records with complete coordinates are chunked across the requested
number of workers and validated with `foreach` and `doParallel`. The
worker count is capped to the number of species and of records, so no
worker is left idle.

Chunks are built from species, not from consecutive rows: every record
of a species is kept in one chunk, and whole species are assigned to the
chunk that currently holds the fewest records, which keeps chunk sizes
close to equal. Records of a species must not be split across workers
because the `outliers` test judges each record against the distribution
of its own species, so splitting them would change which records are
flagged.

### Verdict columns

`CoordinateProblematic` gains one logical column per test listed in
`tests`, named after the corresponding CoordinateCleaner flag (`.cap`
for `capitals`, `.cen` for `centroids`, `.equ` for `equal`, `.gbf` for
`gbif`, `.inst` for `institutions`, `.otl` for `outliers`, `.sea` for
`seas`, and `.zer` for `zeros`). `TRUE` means the record passed that
test, `FALSE` means it failed it, and records that never reached
validation keep `NA` throughout, which is how coordinate-less records
can be told apart from flagged ones. These columns are appended after
the occurrence columns. `CoordinateCleaned` holds records that passed
every test and keeps the occurrence columns only.

### Empty input

If no records have complete coordinates, validation is skipped. An empty
`CoordinateCleaned` table is returned, while records lacking coordinates
are placed in `CoordinateProblematic`, with every verdict column set to
`NA`.

## References

- Zizka, A., Silvestro, D., Andermann, T., Azevedo, J., Duarte Ritter,
  C., Edler, D., Farooq, H., Herdean, A., Ariza, M., Scharn, R.,
  Svantesson, S., Wengstrom, N., Vitecek, S., & Antonelli, A. (2019).
  CoordinateCleaner: Standardized cleaning of occurrence records from
  biological collection databases. *Methods in Ecology and Evolution*,
  10(5), 744-751.
  [doi:10.1111/2041-210X.13152](https://doi.org/10.1111/2041-210X.13152)

## See also

[`CoordinateCleaner::clean_coordinates()`](https://ropensci.github.io/CoordinateCleaner/reference/clean_coordinates.html),
[`customized_filter()`](https://wyx619.github.io/VasGBIF/reference/customized_filter.md),
[`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md),
[`detect_native_country()`](https://wyx619.github.io/VasGBIF/reference/detect_native_country.md),
[`export_records()`](https://wyx619.github.io/VasGBIF/reference/export_records.md),
[`print.CoordinateRefined()`](https://wyx619.github.io/VasGBIF/reference/print.CoordinateRefined.md),
[`set_threads()`](https://wyx619.github.io/VasGBIF/reference/set_threads.md)

## Examples

``` r
if (FALSE) { # interactive() && exists("filtered")
cleaned_coordinates <- par_clean_coordinates(filtered$occ_filtered, threads = 4)

cleaned_coordinates
# the test each flagged record failed
cleaned_coordinates$CoordinateProblematic[.otl == FALSE]

# the column names can be mapped explicitly instead
par_clean_coordinates(
  filtered$occ_filtered,
  species = "Accepted_name_id",
  longitude = "decimalLongitude",
  latitude = "decimalLatitude"
)
}
```
