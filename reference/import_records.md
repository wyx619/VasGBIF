# Import GBIF occurrence records

Reads a GBIF occurrence download in 'SIMPLE_CSV' or Darwin Core Archive
('DWCA') format from a ZIP file, extracts the occurrence data file, and
returns a `data.table` of the fields required by the 'VasGBIF' workflow.
The returned table is the direct input to
[`extract_gbif_issues()`](https://wyx619.github.io/VasGBIF/reference/extract_gbif_issues.md).

## Usage

``` r
import_records(path = "", tempdir = NULL, remove_tempfile = NULL)
```

## Arguments

- path:

  Character scalar. Path to a GBIF occurrence ZIP download in
  'SIMPLE_CSV' or 'DWCA' format. The archive must contain a
  tab-separated occurrence data file, named `occurrence.txt` when the
  archive contains more than one member (as in a Darwin Core Archive).

- tempdir:

  Character scalar or `NULL`. Directory into which the ZIP archive is
  extracted.

  - `NULL` (default): a unique subdirectory is created inside the system
    temporary directory via
    [`base::tempfile()`](https://rdrr.io/r/base/tempfile.html), and it
    is deleted on exit unless `remove_tempfile = FALSE`.

  - A user-supplied path: if the directory does not exist it is created
    (recursively). If it already exists and contains files, a warning is
    issued because those files may be overwritten. The directory is
    **not** deleted on exit by default; set `remove_tempfile = TRUE` to
    override.

- remove_tempfile:

  Logical scalar or `NULL`. Controls whether the extraction directory is
  deleted when the function exits (including after an error).

  - `NULL` (default): behaves as `TRUE` when `tempdir = NULL` (auto
    directory is cleaned up), and as `FALSE` when the user supplies a
    `tempdir` (the directory is kept).

  - `TRUE` or `FALSE`: override the default in either direction.

## Value

A `data.table` of class `"import"` containing the selected occurrence
fields with Darwin Core / GBIF column names. The `gbifID` column is
always character. The `issue` column contains raw pipe-separated GBIF
issue codes and is consumed by
[`extract_gbif_issues()`](https://wyx619.github.io/VasGBIF/reference/extract_gbif_issues.md).

## Details

The archive is extracted into a dedicated directory rather than next to
the ZIP file, so a ZIP stored in `inst/extdata` is never modified.

The function performs the following steps:

- Validates that `path` is a non-empty character string with a `.zip`
  extension.

- Lists the archive members; a 'SIMPLE_CSV' download holds a single data
  file which is extracted by name, while a 'DWCA' holds several members
  (typically `meta.xml`, `occurrence.txt`, and extension files) and its
  `occurrence.txt` core file is assumed.

- Reads the tab-separated, UTF-8 occurrence file with
  [`data.table::fread()`](https://rdrr.io/pkg/data.table/man/fread.html),
  selecting only the GBIF fields used by VasGBIF.

- Coerces `gbifID` to character.

No records are filtered, corrected, or removed at this stage. All
diagnostic fields - including the raw `issue` column - are preserved so
that
[`extract_gbif_issues()`](https://wyx619.github.io/VasGBIF/reference/extract_gbif_issues.md)
can parse them in the next step.

## References

GBIF.org (23 July 2026) GBIF Occurrence Download
[doi:10.15468/dl.nt5exp](https://doi.org/10.15468/dl.nt5exp)

## See also

- [`extract_gbif_issues()`](https://wyx619.github.io/VasGBIF/reference/extract_gbif_issues.md)
  for the next step: parsing the `issue` column into logical indicator
  columns.

- [`print.import()`](https://wyx619.github.io/VasGBIF/reference/print.import.md)
  for a one-line record count.

- [`data.table::fread()`](https://rdrr.io/pkg/data.table/man/fread.html)
  for delimited-file import.

- [`unzip()`](https://rdrr.io/r/utils/unzip.html) for ZIP archive
  handling.

- [GBIF download
  formats](https://techdocs.gbif.org/en/data-use/download-formats) for
  the difference between 'SIMPLE_CSV' and 'DWCA' downloads.

## Examples

``` r
if (FALSE) { # interactive()
gbif_file <- system.file(
  "extdata",
  "0003386-260721160103020.zip",
  package = "VasGBIF"
)
occ <- import_records(path = gbif_file)
occ_import <- extract_gbif_issues(occ)
head(occ_import$summary, 5)

# Extract to a specific directory and keep it afterwards.
# occ <- import_records(path = gbif_file, tempdir = "~/gbif_extracted")
}
```
