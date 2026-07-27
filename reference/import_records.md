# Import GBIF occurrence records

Imports occurrence records from a GBIF ZIP download and prepares the
result for subsequent VasGBIF processing. The function reads the
occurrence data file in the archive, retains the fields required by the
package, expands GBIF issue codes into record-level logical indicators,
and creates an issue-count summary.

## Usage

``` r
import_records(path = "", remove_tempfile = TRUE)
```

## Arguments

- path:

  Character scalar giving the path to a GBIF ZIP file. The archive must
  contain exactly one tab-separated occurrence data file.

- remove_tempfile:

  Logical scalar. If `TRUE`, the temporary extraction directory is
  removed when the function exits, including after an error. If `FALSE`,
  the extracted directory is retained and its path is reported. Defaults
  to `TRUE`.

## Value

An object of class `import`, implemented as a list with four elements:

- `occ`: A `data.table` containing the selected occurrence fields. Its
  columns retain the Darwin Core/GBIF field names.

- `occ_issue`: A `data.table` containing one logical column for each
  issue code in
  [`EnumOccurrenceIssue`](https://wyx619.github.io/VasGBIF/reference/EnumOccurrenceIssue.md),
  plus `gbifID` for linking the indicators to `occ`.

- `summary`: A `data.table` with columns `issue_keys` and `N`, giving
  the number of records associated with each issue; rows are ordered by
  decreasing `N`.

- `runtime`: The elapsed time reported for the import operation.

## Details

The input archive is extracted into a temporary directory rather than
next to the ZIP file. This also prevents a ZIP stored in a package's
`inst/extdata` directory from being modified during import.

The function performs the following steps:

- Checks that `path` is a character path with a `.zip` extension.

- Checks that the archive contains exactly one member and extracts that
  member to a unique temporary directory.

- Reads the tab-separated, UTF-8 occurrence file with
  [`data.table::fread()`](https://rdrr.io/pkg/data.table/man/fread.html)
  and selects the GBIF fields used by the VasGBIF workflow.

- Coerces `gbifID` to character.

- Parses the pipe-separated `issue` field. For each issue code in
  [`EnumOccurrenceIssue`](https://wyx619.github.io/VasGBIF/reference/EnumOccurrenceIssue.md),
  it creates a logical column indicating whether that issue occurs in
  each record, then counts the flagged records by issue code.

The function does not filter records by basis of record, taxon,
geography, or issue status. It also does not correct or remove records
flagged by GBIF; it only imports the selected fields and creates
diagnostic indicators.

The `occ_issue` component uses the `gbifID` column to link issue
indicators back to `occ`. The available issue columns are determined by
the package dataset
[`EnumOccurrenceIssue`](https://wyx619.github.io/VasGBIF/reference/EnumOccurrenceIssue.md);
they can therefore change if that dataset is updated.

When `remove_tempfile = FALSE`, the function leaves the extracted file
in a system temporary directory. The caller is responsible for removing
the retained directory after inspecting it.

## References

GBIF.org (23 July 2026) GBIF Occurrence Download
[doi:10.15468/dl.nt5exp](https://doi.org/10.15468/dl.nt5exp)

## See also

- [`unzip()`](https://rdrr.io/r/utils/unzip.html) for listing or
  extracting ZIP archives.

- [`data.table::fread()`](https://rdrr.io/pkg/data.table/man/fread.html)
  for delimited-file import.

## Examples

``` r
if (FALSE) { # interactive()
gbif_file <- system.file(
  "extdata",
  "0003386-260721160103020.zip",
  package = "VasGBIF"
)
occ_import <- import_records(path = gbif_file)
head(occ_import$summary, 5)

# Or choose another GBIF ZIP file interactively.
# occ_import <- import_records(path = file.choose())
}
```
