# Select master digital vouchers from duplicate groups via quality scoring

Identifies and selects the best representative record (the *digital
voucher*) from each group of duplicate occurrence records that share the
same collection event key. Records are scored across two quality
dimensions, and the highest-scoring record in each group is retained.

## Usage

``` r
set_vouchers(occ_import = NA, taxa_checked = NA, collection_keys = NA)
```

## Arguments

- occ_import:

  An `import` object returned by
  [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md).
  Used for the `occ_issue` table containing GBIF geospatial issue flags.

- taxa_checked:

  An `occ_taxa` object returned by
  [`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md).
  Used for the WCVP taxonomic resolution of each record.

- collection_keys:

  A `collections` object returned by
  [`get_collections()`](https://wyx619.github.io/VasGBIF/reference/get_collections.md).
  Used for the `collection_key` that groups records into collection
  events.

## Value

A list of class `"vouchers"` with three elements:

- `occ_digital_voucher`: a `data.table` with all occurrence records and
  their quality scores, voucher status, grouping flags, taxonomic
  assignments, and final classification. Key columns include
  `moreInformativeRecord`, `VasGBIF_digital_voucher`,
  `VasGBIF_duplicates`, `VasGBIF_dataset_result`, and
  `VasGBIF_duplicates_grouping_status`.

- `occ_results`: a `data.table` with only the quality-assessment and
  result columns, keyed by `gbifID`.

- `runtime`: the elapsed execution time.

## Details

### How the collection key identifies duplicates

The `collection_key` from
[`get_collections()`](https://wyx619.github.io/VasGBIF/reference/get_collections.md)
has the form `taxon|eventDate|latitude|longitude`. Records that share
the **same, complete** key are considered potential duplicates from a
single gathering event and are processed as a group. Records whose key
is missing or contains `NA` in any component cannot be grouped and are
each treated as an independent voucher.

### Quality scoring system

Each record receives a total quality score (`moreInformativeRecord`)
computed as the sum of two sub-scores:

`moreInformativeRecord = verbatim_quality + geospatial_quality`

#### `verbatim_quality` — record completeness (0–9)

One point for each of these nine fields that is present and non-empty:
`recordedBy`, `recordNumber`, `year`, `institutionCode`,
`catalogNumber`, `locality`, `stateProvince`, `countryCode` (via
`COUNTRY_INVALID`), and `identifiedBy`. A record with all nine fields
scores 9; one with none scores 0.

#### `geospatial_quality` — coordinate issue penalty (0 to −9)

Derived from the GBIF issue flags catalogued in `EnumOccurrenceIssue`:

- `0`: no known geospatial issues.

- `−1`: at least one severity-1 (cosmetic) issue, e.g.
  `COORDINATE_ROUNDED`.

- `−3`: at least one severity-2 (potential) issue, e.g.
  `COUNTRY_COORDINATE_MISMATCH`.

- `−9`: at least one severity-3 (exclusion) issue, e.g.
  `ZERO_COORDINATE`, or coordinates are missing entirely.

#### Worked example

Suppose three records share the collection key
`Saxifraga oppositifolia|17095|30.45|79.07`:

|  |  |  |  |  |  |  |  |
|----|----|----|----|----|----|----|----|
| Record | `recordedBy` | `year` | ... | `verbatim_quality` | GBIF issues | `geospatial_quality` | `moreInformativeRecord` |
| A (complete, no issues) | ✓ | ✓ | ... | 7 | none | 0 | **7** |
| B (sparse, minor issue) | ✗ | ✗ | ... | 3 | `COORDINATE_ROUNDED` | −1 | 2 |
| C (missing coordinates) | ✓ | ✓ | ... | 6 | `ZERO_COORDINATE` | −9 | −3 |

Record A has the highest `moreInformativeRecord` (7) and becomes the
digital voucher. Its coordinates are propagated to B and C. Records B
and C are classified as `"duplicate"`.

#### Tie-breaking

If two records tie for the highest score, the one appearing first in the
data (smallest row index) is chosen. This is deterministic but
arbitrary; users concerned about a specific tie should inspect those
groups directly.

### Voucher selection

Within each group, the record with the highest `moreInformativeRecord`
is marked `VasGBIF_digital_voucher = TRUE`. Its coordinates
(prioritising validated coordinates from the voucher itself) are
assigned to all members of the group via `VasGBIF_decimalLatitude` and
`VasGBIF_decimalLongitude`.

### Taxonomic consensus

For groupable records, the most frequent accepted taxon name (from WCVP)
in the group is assigned to all members. Groups are classified as:

- `"identified"`: a single accepted name dominates.

- `"divergent identifications"`: multiple accepted names appear.

- `"unidentified"`: no accepted name is present.

Non-groupable records take their taxon identity directly from their own
WCVP resolution.

### Final dataset classification

`VasGBIF_dataset_result` assigns one of three labels:

- `"usable"`: digital voucher, taxonomically identified, and spatially
  useful (has validated coordinates).

- `"duplicate"`: not the digital voucher of its group.

- `"unusable"`: digital voucher but either unidentified, lacking
  validated coordinates, or both.

## References

De Melo, Pablo Hendrigo Alves, Nadia Bystriakova, Eve Lucas, and
Alexandre K. Monro. 2024. "A New R Package to Parse Plant Species
Occurrence Records into Unique Collection Events Efficiently Reduces
Data Redundancy." *Scientific Reports* 14 (1): 5450.
doi:10.1038/s41598-024-56158-3.

## Examples

``` r
if (FALSE) { # interactive()
taxa_checked <- check_taxon(occ_import = occ_import, accuracy = 0.9)

collection_keys <- get_collections(
  occ_import = occ_import,
  taxa_checked = taxa_checked,
  precision = 2L
)

voucher <- set_vouchers(
  occ_import = occ_import,
  taxa_checked = taxa_checked,
  collection_keys = collection_keys
)
}
```
