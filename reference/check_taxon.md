# Resolve taxon names via the Taxonomic Name Resolution Service

Submits plant scientific names from a GBIF occurrence table to the
Taxonomic Name Resolution Service ('TNRS') and resolves them against the
World Checklist of Vascular Plants ('WCVP') or World Flora Online
('WFO'), depending on `sources` (default `"wcvp"`). Spelling errors are
corrected, variant spellings are standardised, and synonyms are
converted to their currently accepted names. Only records that meet the
`accuracy` threshold, have an accepted or synonym `Taxonomic_status`,
and resolve to an accepted name at species rank or below are returned in
`occ_taxa_checked`.

## Usage

``` r
check_taxon(
  occ_import = NA,
  accuracy = 0.85,
  sources = "wcvp",
  timeout_minutes = 20
)
```

## Arguments

- occ_import:

  An `"import"` `data.table` returned by
  [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md),
  containing at least the columns `gbifID`, `scientificName`, and
  `taxonRank`.

- accuracy:

  Numeric scalar between `0` and `1`. Minimum 'TNRS' match score for a
  resolution to be accepted. Defaults to `0.85`. Records whose
  `Overall_score` falls below this threshold are excluded from
  `occ_taxa_checked`. Passed directly to
  [`TNRS::TNRS()`](https://rdrr.io/pkg/TNRS/man/TNRS.html).

- sources:

  Character vector naming the taxonomic sources to resolve against.
  Defaults to `"wcvp"` (World Checklist of Vascular Plants). `"wfo"`
  (World Flora Online) is also accepted. Multiple sources can be
  combined, e.g. `c("wcvp", "wfo")`; the 'TNRS' API then returns the
  best match across all selected sources and the `Source` column records
  which source provided it. Passed directly to
  [`TNRS::TNRS()`](https://rdrr.io/pkg/TNRS/man/TNRS.html).

- timeout_minutes:

  Numeric scalar. Timeout per 'TNRS' chunk attempt in minutes. Defaults
  to `20`. If an attempt exceeds the timeout it is abandoned and
  retried.

## Value

An object of class `"occ_taxa"`, implemented as a named list with three
elements:

- `occ_taxa_checked`: a `data.table` of occurrence records that passed
  the `accuracy` threshold and have an `"Accepted"` or `"Synonym"`
  `Taxonomic_status`. Columns from `occ_import` (`gbifID`,
  `scientificName`) are joined with the following 'TNRS' result columns:
  `Overall_score`, `Taxonomic_status`, `Accepted_name`,
  `Accepted_species`, `Accepted_name_id`, `Accepted_name_rank`,
  `Accepted_family`, `Source`.

- `summary`: a `data.table` of unique 'TNRS' resolution results (one row
  per submitted name), useful for reviewing match quality and
  identifying names that require manual attention. `scientificName`
  holds the string as submitted, while `Name_submitted` holds the
  possibly rewritten form echoed by 'TNRS'; comparing the two exposes
  names the API altered.

- `runtime`: a `difftime` object recording the total elapsed time.

## Details

### Taxon rank filtering

Only records whose `taxonRank` is one of `"SPECIES"`, `"VARIETY"`,
`"SUBSPECIES"`, or `"FORM"` are submitted to 'TNRS'. Records at genus
rank or above are excluded from the query and are absent from both
`summary` and `occ_taxa_checked`.

This check filters on the `taxonRank` reported by GBIF for the submitted
record. It is distinct from the output-side check on
`Accepted_name_rank` described under "Output filtering", which filters
on the rank of the *resolved* accepted name returned by 'TNRS'.

### Chunked submission

Unique names are submitted in chunks of up to 4,000 to respect 'TNRS'
API limits. Each name is assigned a row identifier before chunking, so
the identifiers stay unique across the whole query. Results from all
chunks are combined with
[`data.table::rbindlist()`](https://rdrr.io/pkg/data.table/man/rbindlist.html)
and then de-duplicated by `ID`, guarding against occasional duplicate
rows returned by the API.

### Joining results back to occurrences

'TNRS' does not echo submitted names verbatim: commas are replaced by
spaces and diacritics are normalised, so `Name_submitted` in the
response may differ from the string that was sent. Results are therefore
joined back to the occurrence table through the row identifier echoed in
the `ID` column, which maps each result to the exact `scientificName`
submitted.

### Output filtering

After merging 'TNRS' results back into the occurrence table, only
records satisfying **all** of the following conditions are kept in
`occ_taxa_checked`:

- `Overall_score >= accuracy`

- `Taxonomic_status` is `"Accepted"` or `"Synonym"`

- `Accepted_name_rank` is neither empty nor `"genus"`

The rank condition excludes records whose best match only reached a
genus-level or unranked accepted name, even when the score and status
would pass. Records that fail any condition (unresolved names,
low-confidence matches, names with uncertain status, or genus-level
resolutions) are present in `summary` for manual review but absent from
`occ_taxa_checked`.

### Retry logic

Each chunk is attempted up to three times. An attempt that exceeds
`timeout_minutes` or that returns no rows is abandoned and retried, with
a five-second pause between attempts, guarding against transient network
failures. If all attempts fail for a chunk, the function stops with an
informative error.

## References

Boyle, B. et al. (2013). The taxonomic name resolution service: an
online tool for automated standardisation of plant names. *BMC
Bioinformatics*, 14, 16.
[doi:10.1186/1471-2105-14-16](https://doi.org/10.1186/1471-2105-14-16)

Govaerts, R. et al. (2021). The World Checklist of Vascular Plants, a
continuously updated resource for exploring global plant diversity.
*Scientific Data*, 8, 215.
[doi:10.1038/s41597-021-00997-6](https://doi.org/10.1038/s41597-021-00997-6)

## See also

- [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md)
  for the first step that produces the `occ_import` input.

- [`extract_gbif_issues()`](https://wyx619.github.io/VasGBIF/reference/extract_gbif_issues.md)
  for the parallel step that processes issue flags.

- [`TNRS::TNRS()`](https://rdrr.io/pkg/TNRS/man/TNRS.html) for the
  underlying name resolution function.

- [`print.occ_taxa()`](https://wyx619.github.io/VasGBIF/reference/print.occ_taxa.md)
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
taxa_checked <- check_taxon(occ_import = occ, accuracy = 0.85)
head(taxa_checked$summary, 10)
nrow(taxa_checked$occ_taxa_checked)
}
```
