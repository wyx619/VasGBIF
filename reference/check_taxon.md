# Resolve taxon names via the Taxonomic Name Resolution Service

Submits plant scientific names to the Taxonomic Name Resolution Service
(TNRS) and resolves them against the World Checklist of Vascular Plants
(WCVP). The TNRS corrects spelling errors, standardises variant
spellings, and converts synonyms to their currently accepted names.

The function works in three phases:

1.  Extracts unique names at species-level ranks (species, subspecies,
    variety, form) and submits them to the TNRS in chunks of up to 4,000
    names.

2.  Post-processes the TNRS response into a structured `data.table` with
    WCVP identifiers, accepted names, taxonomic status, and a resolution
    outcome label.

3.  Merges the results back into the full occurrence table. Records
    above species rank are not submitted and retain `NA` in all WCVP
    fields.

## Usage

``` r
check_taxon(occ_import = NA, accuracy = 0.9, sources = c("wcvp", "wfo"))
```

## Arguments

- occ_import:

  An `import` object returned by
  [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md).

- accuracy:

  Numeric threshold between `0` and `1` controlling the minimum match
  score for a name to be considered resolved. The default is `0.9`.
  Passed to [`TNRS::TNRS()`](https://rdrr.io/pkg/TNRS/man/TNRS.html).

- sources:

  Character vector of taxonomic sources. The effective default is
  `"wcvp"`. `"wfo"` is also accepted.

## Value

A list of class `"occ_taxa"` with three elements:

- `occ_taxa_checked`: a `data.table` of all occurrence records (one row
  per `gbifID`) with WCVP taxonomic columns appended. Key columns
  include `wcvp_searchedName` (the original submitted name),
  `wcvp_taxon_name` (the accepted name), `wcvp_plant_name_id`,
  `wcvp_family`, `wcvp_taxon_rank`, `wcvp_searchNotes`, and
  `wcvp_reviewed`.

- `summary`: a `data.table` of unique resolution outcomes (one row per
  submitted name), suitable for reviewing results and identifying names
  that require manual attention.

- `runtime`: the elapsed execution time.

## Details

### Taxon rank filtering

Only records whose `taxonRank` is one of `"SPECIES"`, `"VARIETY"`,
`"SUBSPECIES"`, or `"FORM"` are submitted to the TNRS. Records at genus
rank or above are retained in the output but receive `NA` for all WCVP
fields and are not part of the resolution process.

### Handling of unresolved and uncertain names

All records are **retained** in the output — none are removed. Names
that cannot be resolved are identifiable through the `wcvp_searchNotes`
column:

- `"Accepted"`: the submitted name is already an accepted name in WCVP.

- `"Updated"`: the submitted name is a synonym and has been resolved to
  its accepted name. The accepted name appears in `wcvp_taxon_name` and
  its WCVP identifier in `wcvp_plant_name_id`.

- `"Not found"`: the TNRS could not match the name to any WCVP entry, or
  the match has no accepted name. All WCVP fields (`wcvp_taxon_name`,
  `wcvp_plant_name_id`, `wcvp_family`, etc.) are `NA` for these records.

Names with uncertain taxonomic status in WCVP — including *unplaced*,
*unresolved*, *illegitimate*, and *invalid* names — typically receive no
accepted name from the TNRS and are therefore classified as
`"Not found"`. They remain in the dataset with `NA` WCVP fields so that
users can inspect and manually curate them.

Names that the TNRS resolves only to genus level are also reclassified
as `"Not found"`, since a genus-level identification is too coarse to be
useful for the duplicate-detection and native-status workflows that
consume this output.

### Review flag

The `wcvp_reviewed` column is `"N"` for every name that received an
accepted WCVP match (i.e. `wcvp_searchNotes` is `"Accepted"` or
`"Updated"`). It is `NA` for names classified as `"Not found"`. Users
can manually set it to `"Y"` after verifying a resolution, or fill it
for unresolved names after manual curation.

### Retry logic

Each TNRS chunk query is attempted up to 3 times with a 5-second wait
between attempts and a 20-minute timeout per attempt. This guards
against transient network failures and API timeouts.

## References

- Boyle, B. et al. (2013). The taxonomic name resolution service: an
  online tool for automated standardisation of plant names. *BMC
  Bioinformatics*, 14, 16. doi:10.1186/1471-2105-14-16

- Govaerts, R. et al. (2021). The World Checklist of Vascular Plants, a
  continuously updated resource for exploring global plant diversity.
  *Scientific Data*, 8, 215. doi:10.1038/s41597-021-00997-6

## See also

[`TNRS()`](https://rdrr.io/pkg/TNRS/man/TNRS.html)

## Examples

``` r
if (FALSE) { # interactive()
taxa_checked <- check_taxon(occ_import = occ_import, accuracy = 0.9)
}
```
