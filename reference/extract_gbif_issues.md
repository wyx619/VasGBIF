# Extract GBIF issue flags into logical columns

Parses the pipe-separated `issue` field from a GBIF occurrence
`data.table` and expands it into one logical indicator column per issue
code defined in
[`EnumOccurrenceIssue`](https://wyx619.github.io/VasGBIF/reference/EnumOccurrenceIssue.md).
This is the second step in the VasGBIF import workflow, taking the
`data.table` returned by
[`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md)
as input.

## Usage

``` r
extract_gbif_issues(occ = NA)
```

## Arguments

- occ:

  An `"import"` `data.table` returned by
  [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md),
  containing at least the columns `gbifID` and `issue`. The `issue`
  column must hold raw pipe-separated GBIF issue codes as present in a
  GBIF SIMPLE_CSV download. Defaults to `NA`.

## Value

An object of class `"issue"`, implemented as a named list with two
elements:

- `occ_issue`: A `data.table` with one logical column per issue code in
  [`EnumOccurrenceIssue`](https://wyx619.github.io/VasGBIF/reference/EnumOccurrenceIssue.md),
  plus `gbifID` for linking to `occ` and `issue_count` with the total
  number of flags per record.

- `summary`: A `data.table` with columns `issue_keys` and `N`, giving
  the number of records flagged with each issue code, ordered by
  decreasing `N`.

## Details

The set of recognised issue codes is taken from the package dataset
[`EnumOccurrenceIssue`](https://wyx619.github.io/VasGBIF/reference/EnumOccurrenceIssue.md).
For each code a logical column is created that is `TRUE` when the code
appears anywhere in the record's `issue` string and `FALSE` otherwise.
Codes not present in the dataset are ignored.

Two further columns are appended to the per-code columns:

- `gbifID`: copied from `occ` to allow joining back to the original
  records.

- `issue_count`: the number of issue flags that are `TRUE` for each
  record.

The companion `summary` table ranks the issue codes by how many records
they flag, which is useful for spotting data-quality problems at a
glance.

## See also

- [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md)
  for the preceding step that produces the `occ` input.

- [`EnumOccurrenceIssue`](https://wyx619.github.io/VasGBIF/reference/EnumOccurrenceIssue.md)
  for the full list of recognised GBIF issue codes.

- [`print.issue()`](https://wyx619.github.io/VasGBIF/reference/print.issue.md)
  for a compact summary of the result.

## Examples

``` r
if (FALSE) { # interactive()
gbif_file <- system.file(
  "extdata",
  "0003386-260721160103020.zip",
  package = "VasGBIF"
)
occ <- import_records(path = gbif_file)
gbif_issue <- extract_gbif_issues(occ)
head(gbif_issue$summary, 10)
gbif_issue$occ_issue[, .(gbifID, issue_count)] |> head()
}
```
