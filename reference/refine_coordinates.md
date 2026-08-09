# Validate coordinates of filtered occurrence records

Validates the coordinates of filtered occurrence records with
CoordinateCleaner and splits them into coordinate-clean and problematic
tables.

[CoordinateCleaner::clean_coordinates](https://ropensci.github.io/CoordinateCleaner/reference/clean_coordinates.html)
checks run in parallel to flag common spatial issues such as centroids,
capitals, and marine records.

Records that pass all requested tests are returned in
`CoordinateCleaned`; records that fail one or more tests are returned in
`CoordinateProblematic`. Native-status classification is a separate
step:
[`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md)
classifies the records with validated coordinates, and
[`detect_native_country()`](https://wyx619.github.io/VasGBIF/reference/detect_native_country.md)
the coordinate-less records (taken directly from `custom_filtered`).

## Usage

``` r
refine_coordinates(
  custom_filtered = NA,
  threads = 4,
  tests = c("capitals", "centroids", "equal", "gbif", "institutions", "outliers", "seas",
    "zeros")
)
```

## Arguments

- custom_filtered:

  A `customFiltered` object returned by
  [`custom_filter()`](https://wyx619.github.io/VasGBIF/reference/custom_filter.md).

- threads:

  Number of threads to use for coordinate validation, passed to
  [`set_threads()`](https://wyx619.github.io/VasGBIF/reference/set_threads.md).
  Use an integer `>= 1` for an absolute count, or a value between `0`
  and `1` for a proportion of available cores. The default is `4`.

- tests:

  Character vector of CoordinateCleaner validation tests to apply.
  Choose one or more of `"capitals"`, `"centroids"`, `"equal"`,
  `"gbif"`, `"institutions"`, `"outliers"`, `"seas"`, and `"zeros"`. The
  default uses all tests.

## Value

A `CoordinateRefined` object (list) with three elements:

- `CoordinateCleaned`: a `data.table` of records that passed all
  requested coordinate tests

- `CoordinateProblematic`: a `data.table` of records that failed one or
  more tests, retaining the CoordinateCleaner flag columns (e.g.
  `.summary`) so the failing tests can be inspected

- `runtime`: the elapsed execution time

Use
[`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md)
to classify the records with validated coordinates, and
[`detect_native_country()`](https://wyx619.github.io/VasGBIF/reference/detect_native_country.md)
for the coordinate-less records.

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

### Parallel processing

Records with complete coordinates are chunked across the requested
number of workers and validated with `foreach` and `doParallel`. The
worker count is capped to the number of records to avoid idle cluster
nodes.

### Empty input

If no records have complete coordinates, validation is skipped and empty
`CoordinateCleaned` and `CoordinateProblematic` tables are returned.

## References

- Zizka, A., Silvestro, D., Andermann, T., Azevedo, J., Duarte Ritter,
  C., Edler, D., Farooq, H., Herdean, A., Ariza, M., Scharn, R.,
  Svantesson, S., Wengstrom, N., Vitecek, S., & Antonelli, A. (2019).
  CoordinateCleaner: Standardized cleaning of occurrence records from
  biological collection databases. *Methods in Ecology and Evolution*,
  10(5), 744-751.
  [doi:10.1111/2041-210X.13152](https://doi.org/10.1111/2041-210X.13152)

## See also

[`clean_coordinates()`](https://ropensci.github.io/CoordinateCleaner/reference/clean_coordinates.html),
[`custom_filter()`](https://wyx619.github.io/VasGBIF/reference/custom_filter.md),
[`detect_native_coord()`](https://wyx619.github.io/VasGBIF/reference/detect_native_coord.md),
[`detect_native_country()`](https://wyx619.github.io/VasGBIF/reference/detect_native_country.md),
[`export_records()`](https://wyx619.github.io/VasGBIF/reference/export_records.md),
[`print.CoordinateRefined()`](https://wyx619.github.io/VasGBIF/reference/print.CoordinateRefined.md),
[`set_threads()`](https://wyx619.github.io/VasGBIF/reference/set_threads.md)

## Examples

``` r
if (FALSE) { # interactive() && exists("filtered")
refined_coordinates <- refine_coordinates(custom_filtered = filtered, threads = 4)
}
```
