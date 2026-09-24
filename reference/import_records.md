# Import GBIF occurrence records

Reads a GBIF occurrence download and returns a `data.table` of the
fields required by the 'VasGBIF' workflow.

## Usage

``` r
import_records(path = "", tempdir = NULL, remove_tempfile = TRUE)
```

## Arguments

- path:

  Character scalar. Path to a GBIF occurrence download: either a
  'SIMPLE_CSV' or 'DWCA' ZIP archive, or an extracted tab-separated
  occurrence table. An archive must contain a tab-separated occurrence
  data file, named `occurrence.txt` when the archive contains more than
  one member (as in a Darwin Core Archive).

- tempdir:

  Character scalar or `NULL`. Directory into which the ZIP archive is
  extracted. Ignored when `path` is not a ZIP file.

  - `NULL` (default): a unique subdirectory is created inside the system
    temporary directory via
    [`base::tempfile()`](https://rdrr.io/r/base/tempfile.html), and it
    is deleted on exit unless `remove_tempfile = FALSE`.

  - A user-supplied path: if the directory does not exist it is created
    (recursively). If it already exists and contains files, a warning is
    issued because those files may be overwritten. The directory is
    never deleted; on exit only the extracted occurrence file is
    unlinked, and even that is skipped when `remove_tempfile = FALSE`.

- remove_tempfile:

  Logical scalar. Controls whether the files this call produced are
  deleted when the function exits (including after an error). Defaults
  to `TRUE`.

  - With `tempdir = NULL`, the extraction directory is created by this
    call and holds nothing else, so the directory is removed whole.

  - With a user-supplied `tempdir`, only the extracted occurrence file
    is unlinked. The directory itself and every unrelated file in it are
    left untouched.

  - `FALSE` keeps the extracted file in `ex_path` and reports its
    location.

## Value

A `data.table` of class `"import"` containing the selected occurrence
fields with Darwin Core / GBIF column names. The `gbifID` column is
always character.

## Details

Two kinds of input are accepted, chosen by the file extension:

- A ZIP archive in 'SIMPLE_CSV' or Darwin Core Archive ('DWCA') format.
  The occurrence data file is extracted and read from there.

- An already extracted occurrence table in any other file, e.g. `.csv`,
  `.txt` or `.tsv`. The extension is not used to infer the format: the
  file must be tab-separated regardless.

In both cases the first column must be named `gbifID`; anything else
stops with an error. This also catches comma-separated files, whose
header then arrives as a single column.

An archive is extracted into a dedicated directory rather than next to
the ZIP file, so a ZIP stored in `inst/extdata` is never modified.

The function performs the following steps:

- Validates that `path` is a non-empty single character string.

- Resolves the file to read. For a `.zip` path the archive members are
  listed: a 'SIMPLE_CSV' download holds a single data file which is
  extracted by name, while a 'DWCA' holds several members (typically
  `meta.xml`, `occurrence.txt`, and extension files) and its
  `occurrence.txt` core file is assumed. For any other path the file
  itself is read directly.

- Reads the header of the resolved file with
  [`data.table::fread()`](https://rdrr.io/pkg/data.table/man/fread.html)
  using `nrows = 0`, and requires its first column to be named `gbifID`.
  Only the header is parsed, so this check is nearly free and rejects
  unusable files before the full read.

- Reads the tab-separated, UTF-8 occurrence file with
  [`data.table::fread()`](https://rdrr.io/pkg/data.table/man/fread.html),
  selecting only the GBIF fields used by VasGBIF.

- Coerces `gbifID` to character.

## References

GBIF.org (23 July 2026) GBIF Occurrence Download
[doi:10.15468/dl.nt5exp](https://doi.org/10.15468/dl.nt5exp)

## See also

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

# An already extracted occurrence table is read directly. The extension is
# irrelevant; the file must be tab-separated and start with a `gbifID`
# column.
# occ <- import_records(path = "~/downloads/occurrence.txt")

# Extract into a directory of your own; the extracted file is removed on
# exit, but the directory and its other contents are kept.
# occ <- import_records(path = gbif_file, tempdir = "~/gbif_extracted")

# Keep the extracted file as well.
# occ <- import_records(
#   path = gbif_file, tempdir = "~/gbif_extracted", remove_tempfile = FALSE
# )
}
```
