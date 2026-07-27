# Validate coordinates, restore metadata, and detect native status

Validates spatial information, restores metadata for usable vouchers,
and classifies records by geographic distribution status.

The function combines three steps:

1.  Restores missing metadata from duplicate records via
    [`restore_duplicates()`](https://wyx619.github.io/VasGBIF/reference/restore_duplicates.md).

2.  Runs
    [CoordinateCleaner::clean_coordinates](https://ropensci.github.io/CoordinateCleaner/reference/clean_coordinates.html)
    checks in parallel to flag common spatial issues such as centroids,
    capitals, institutions, and marine records.

3.  Assigns native status by matching validated coordinates to WGSRPD
    Level 3 areas and WCVP distribution data via
    [`detect_native_status()`](https://wyx619.github.io/VasGBIF/reference/detect_native_status.md).

## Usage

``` r
refine_records(
  voucher = NA,
  threads = 4,
  tests = c("capitals", "centroids", "equal", "gbif", "institutions", "outliers", "seas",
    "zeros")
)
```

## Arguments

- voucher:

  A `vouchers` object returned by
  [`set_vouchers()`](https://wyx619.github.io/VasGBIF/reference/set_vouchers.md).

- threads:

  Number of threads to use for coordinate validation. Use an integer
  `>= 1` for an absolute count, or a value between `0` and `1` for a
  proportion of available cores. The default is `4`.

- tests:

  Character vector of CoordinateCleaner validation tests to apply.
  Choose one or more of `"capitals"`, `"centroids"`, `"equal"`,
  `"gbif"`, `"institutions"`, `"outliers"`, `"seas"`, and `"zeros"`. The
  default uses all tests.

## Value

A `refined` object (list) with three elements:

- `all_records`: a `data.table` of records with validated coordinates,
  restored metadata, and native status classification

- `CoordinateProblematic`: a `data.table` of records that failed one or
  more CoordinateCleaner tests

- `runtime`: the elapsed execution time

Use
[`export_records()`](https://wyx619.github.io/VasGBIF/reference/export_records.md)
to write results to compressed CSV files.

## Details

### Metadata restoration

[`restore_duplicates()`](https://wyx619.github.io/VasGBIF/reference/restore_duplicates.md)
fills missing metadata fields in usable voucher records using values
from duplicate records that share the same collection event key.
Restored fields include `eventDate`, `year`, `month`, `day`,
`identifiedBy`, `countryCode`, `stateProvince`, and `locality`.
Candidate values longer than 10,000 characters are skipped.

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

### Native status detection

Delegated to
[`detect_native_status()`](https://wyx619.github.io/VasGBIF/reference/detect_native_status.md).
Records that pass coordinate validation are matched against WCVP
distribution data via WGSRPD Level 3 polygons using a two-stage
priority-based classification. The result is a `native_status` label for
each record: `"native"`, `"introduced"`, `"extinct"`,
`"location_doubtful"`, or `"unknown"`.

## References

- Zizka, A., Silvestro, D., Andermann, T., Azevedo, J., Duarte Ritter,
  C., Edler, D., Farooq, H., Herdean, A., Ariza, M., Scharn, R.,
  Svantesson, S., Wengstrom, N., Vitecek, S., & Antonelli, A. (2019).
  CoordinateCleaner: Standardized cleaning of occurrence records from
  biological collection databases. *Methods in Ecology and Evolution*,
  10(5), 744-751.
  [doi:10.1111/2041-210X.13152](https://doi.org/10.1111/2041-210X.13152)

- Govaerts, R., Nic Lughadha, E., Black, N. et al. The World Checklist
  of Vascular Plants, a continuously updated resource for exploring
  global plant diversity. *Scientific Data*, 8, 215 (2021).
  [doi:10.1038/s41597-021-00997-6](https://doi.org/10.1038/s41597-021-00997-6)

## See also

[`clean_coordinates()`](https://ropensci.github.io/CoordinateCleaner/reference/clean_coordinates.html),
[`export_records()`](https://wyx619.github.io/VasGBIF/reference/export_records.md)

## Examples

``` r
if (FALSE) { # interactive() && exists("voucher")

refined_records <- refine_records(
  voucher = voucher,
  threads = 4,
  tests = c(
    "capitals", "centroids", "equal", "gbif",
    "institutions", "outliers", "seas", "zeros"
  )
)
}
```
