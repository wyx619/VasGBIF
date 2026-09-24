# Count GBIF issue flags per record

Counts, for every occurrence record, how many of the issue codes defined
in
[`EnumOccurrenceIssue`](https://wyx619.github.io/VasGBIF/reference/EnumOccurrenceIssue.md)
are flagged in the record's `issue` field. This is the second step in
the VasGBIF import workflow, taking the `data.table` returned by
[`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md)
as input.

The function is internal:
[`customized_filter()`](https://wyx619.github.io/VasGBIF/reference/customized_filter.md)
calls it directly, so users never invoke it themselves.

## Usage

``` r
extract_issues(occ = NA)
```

## Arguments

- occ:

  An `"import"` `data.table` returned by
  [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md),
  containing at least the columns `gbifID` and `issue`. The `issue`
  column must hold raw GBIF issue codes as present in a GBIF SIMPLE_CSV
  download. Defaults to `NA`.

## Value

A `data.table` with one row per record in `occ` and two columns:

- `gbifID`: copied from `occ` to allow joining back to the original
  records.

- `issue_count`: the number of issue codes flagged for that record.

## Details

The set of recognised issue codes is taken from the package dataset
[`EnumOccurrenceIssue`](https://wyx619.github.io/VasGBIF/reference/EnumOccurrenceIssue.md).
Each code is searched for in the record's `issue` string, and
`issue_count` is how many of them are found. Codes not present in the
dataset are ignored.

## See also

- [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md)
  for the preceding step that produces the `occ` input.

- [`customized_filter()`](https://wyx619.github.io/VasGBIF/reference/customized_filter.md)
  for the consumer of the issue count.

- [`EnumOccurrenceIssue`](https://wyx619.github.io/VasGBIF/reference/EnumOccurrenceIssue.md)
  for the full list of recognised GBIF issue codes.

## Examples

``` r
if (FALSE) { # interactive()
gbif_file <- system.file(
  "extdata",
  "0003386-260721160103020.zip",
  package = "VasGBIF"
)
occ <- import_records(path = gbif_file)
head(extract_issues(occ))
}
```
