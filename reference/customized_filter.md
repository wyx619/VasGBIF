# Apply custom quality filters to occurrence records

Joins the outputs of the VasGBIF import and taxonomic-resolution steps
into a single occurrence table, then progressively removes records
according to a user-selected set of quality rules.

## Usage

``` r
customized_filter(
  occ_import = NA,
  taxa_checked = NA,
  filter_countryCode = TRUE,
  filter_coordinateUncertainty = 10000,
  filter_date = FALSE,
  filter_identifiedBy = FALSE,
  filter_recordedBy = FALSE,
  filter_gbif_issues_max = 5
)
```

## Arguments

- occ_import:

  An `"import"` `data.table` returned by
  [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md).
  `gbifID` and `issue` are always required; every other column is
  required only by the rule that reads it, so a column backing a
  disabled rule may be absent. The columns are `decimalLatitude` and
  `countryCode` for `filter_countryCode`,
  `coordinateUncertaintyInMeters` for `filter_coordinateUncertainty`,
  `eventDate`, `month`, `year`, and `day` for `filter_date`,
  `identifiedBy`, and `recordedBy`.

- taxa_checked:

  An `"occ_taxa"` object returned by
  [`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md).

- filter_countryCode:

  Logical scalar. If `TRUE` (default), removes records with no usable
  geographic information: `decimalLatitude` is `NA` **and**
  `countryCode` is `NA` or empty. Records with either a coordinate or a
  country code are kept. When enabled, a `filter_countryCode` logical
  column is added to `occ_marked`; see *Per-rule verdict columns*.

- filter_coordinateUncertainty:

  Non-negative numeric scalar. Removes records whose
  `coordinateUncertaintyInMeters` is strictly greater than the
  threshold. Defaults to `10000`. Records with `NA` or empty
  `coordinateUncertaintyInMeters` are always kept - they do not
  participate in this rule. Pass `NULL`, `NA`, or `''` to disable the
  rule. The value is validated when the function is called, before any
  work is done. When the rule is enabled, a
  `filter_coordinateUncertainty` logical column is added to
  `occ_marked`.

- filter_date:

  Logical scalar. If `TRUE`, removes records for which all four date
  components (`eventDate`, `month`, `year`, `day`) are missing or empty.
  Defaults to `FALSE`.

- filter_identifiedBy:

  Logical scalar. If `TRUE`, removes records whose `identifiedBy` is
  missing or contains no named identifier (see *Collector junk
  detection*). Defaults to `FALSE`.

- filter_recordedBy:

  Logical scalar. If `TRUE`, removes records whose `recordedBy` is
  missing or contains no named collector. Defaults to `FALSE`.

- filter_gbif_issues_max:

  Non-negative numeric scalar. Removes records flagged with more GBIF
  issues than the threshold (`gbif_issues > filter_gbif_issues_max`).
  Defaults to `5`. Pass `NULL`, `NA`, or `''` to disable the rule. The
  value is validated when the function is called, before any work is
  done.

  Each of `filter_date`, `filter_identifiedBy`, `filter_recordedBy`, and
  `filter_gbif_issues_max` adds a logical column named after the
  argument to `occ_marked` when it is enabled; see *Per-rule verdict
  columns*.

## Value

An object of class `"customFiltered"`, implemented as a named list with
three elements:

- `occ_filtered`: the records that passed every applied test, as a
  `data.table` with the occurrence and joined columns only - no verdict
  columns.

- `summary`: a `data.table` with columns `rule`, `dropped`, `remaining`,
  `failed`, and `only_failed_here`, giving for each applied step (the
  `taxon_resolved` join plus each enabled rule) how many records it
  removed, how many remained, and how many it rejects under the
  independent and exclusive readings described in *Per-rule verdict
  columns*.

- `occ_marked`: the records excluded by at least one applied test,
  reduced to `gbifID` and one verdict column per applied test (see
  *Per-rule verdict columns*). Every such record fails at least one of
  them, so its verdict columns contain at least one `FALSE`. Together
  with `occ_filtered`, this table accounts for every record in
  `occ_import`.

A [`print()`](https://rdrr.io/r/base/print.html) method for class
`"customFiltered"` displays how many records were kept and excluded, and
the per-rule summary.

## Details

### Joining the inputs

The two inputs are joined by `gbifID`. For memory efficiency the joins
are performed **in place** on a single defensive copy of `occ_import`:
[`copy()`](https://rdrr.io/pkg/data.table/man/copy.html) is made once
and each join adds columns via `:=`, instead of materialising a fresh
full-width table per join. The caller's `occ_import` is never modified.
Rows are not deleted during the join or the rules; every criterion
accumulates into a logical mask and a single row subset is applied at
the end. Peak memory is therefore close to the input plus one working
copy, regardless of how many rules are enabled.

[`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md)
already removes records that fail the `accuracy` threshold, whose
`Taxonomic_status` is neither `"Accepted"` nor `"Synonym"`, or that
resolve to a genus-level or unranked accepted name, so
`occ_taxa_checked` contains only fully resolved records. Rows absent
from `occ_taxa_checked` are dropped via the keep mask instead of
carrying `NA` taxonomy through the rest of the pipeline. The number
removed is recorded in `summary` under the rule name `taxon_resolved`.

[`extract_issues()`](https://wyx619.github.io/VasGBIF/reference/extract_issues.md)
is called internally on `occ_import` and returns exactly one row per
imported record, so the issue join is one-to-one and cannot change the
row count. The function verifies this and stops if any record lacks an
issue count. The raw `issue` column is removed from `occ_import` and
replaced by `gbif_issues`, the per-record issue count.

### Filter rules

Every applied test inspects the full table on its own terms rather than
only the records left by the preceding tests, and its verdict is stored
as a logical column named after the test. `TRUE` means the record passed
that test. By default `countryCode`, `coordinateUncertainty`, and
`gbif_issues_max` are enabled; `date`, `identifiedBy`, and `recordedBy`
are disabled. Numeric thresholds are validated before any work is done,
so an invalid value fails immediately.

The always-on `taxon_resolved` test is the first one applied. It is not
a selectable rule:
[`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md)
only retains records whose name resolved, so records absent from
`taxa_checked$occ_taxa_checked` receive `NA` `Accepted_name` at the join
and fail this test. It always contributes a `filter_taxon_resolved`
column.

- `countryCode`: drop records with `NA` latitude **and** `NA`/empty
  `countryCode`.

- `coordinateUncertainty`: drop records with
  `coordinateUncertaintyInMeters > threshold`; records with `NA` or
  empty uncertainty are kept.

- `date`: drop records with `eventDate`, `month`, `year`, **and** `day`
  all missing.

- `identifiedBy` / `recordedBy`: drop records whose value is junk (see
  below).

- `gbif_issues_max`: drop records with `gbif_issues > threshold`. The
  one-to-one issue join guarantees every record carries an issue count,
  so no record is exempt from this rule.

### Per-rule verdict columns

Each applied test contributes a logical column named after it:
`filter_taxon_resolved` (always) plus `filter_countryCode`,
`filter_coordinateUncertainty`, `filter_date`, `filter_identifiedBy`,
`filter_recordedBy`, and `filter_gbif_issues_max` for the selected
rules. `TRUE` marks a record that passed that test. A disabled rule
contributes no column, so the output width depends on which rules were
selected. The columns are carried by `occ_marked`, where they identify
which tests rejected each excluded record; `occ_filtered` holds only
occurrence and joined columns.

Because each rule is evaluated independently, one record can fail
several tests at once and is then counted by each of them. The `summary`
table makes this explicit:

- `failed` is the number of records that test rejects on its own terms;
  these counts overlap and sum to more than the number of records
  removed.

- `only_failed_here` is the number of records that test rejects and no
  other test does; these counts are disjoint but incomplete, since a
  record failing several tests is credited to none of them.

- `dropped` and `remaining` remain the sequential attribution: each
  removed record is credited to the first enabled test that rejected it,
  so `dropped` sums exactly to the number of records removed.

The split of the output reflects the same distinction. `occ_filtered`
holds the records that passed every applied test, with their occurrence
and joined columns and no verdict columns; `occ_marked` holds the rest,
reduced to `gbifID` and the verdict columns. Because every applied test
has a column, each marked record carries at least one `FALSE` and shows
exactly which tests rejected it - a record excluded only because its
taxon name did not resolve has `FALSE` in `filter_taxon_resolved` alone.

### Collector junk detection

The `identifiedBy` and `recordedBy` rules are identical in strictness. A
value is treated as junk - and the record removed - when it is missing
or empty, or when it matches a curated set of "no named person" patterns
while containing **no name separator**.

The keyword list covers English (`unknown`, `anonymous`, `unnamed`,
`unidentified`, `unrecorded`, `incognito`), other languages
(`desconocido`, `desconhecido`, `anonimo` and its accented Spanish and
Portuguese variants, `sin nombre`, `sem nome`, `inconnu`, `anonyme`,
`unbekannt`, `anonym`, and four Chinese terms meaning "unknown",
"unnamed", "anonymous" and "no details"), and whole-value patterns such
as `s.n.`, `n/a`, `et al.`, and `no collector`.

Name separators (`,`, `;`, `&`, `+`, `and`, plus the full-width comma,
full-width semicolon, and ideographic enumeration comma used in CJK
text) protect values that mix a keyword with a real name, e.g.
`"Unknown; Jongmans WJ"` or `"Collector(s): Eric Sundell, unknown"` are
kept because a named person is present.

Word-boundary matching means the Chinese keywords only match standalone
values; a longer phrase that merely begins with one of them (for
instance the Chinese for "unknown collector") is not removed. This is
deliberately conservative: without boundaries, a real name that happens
to contain a keyword could be wrongly dropped.

## See also

- [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md)
  and
  [`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md)
  for the two inputs.

- [`extract_issues()`](https://wyx619.github.io/VasGBIF/reference/extract_issues.md)
  for the issue count behind the `gbif_issues_max` rule.

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

filtered <- customized_filter(
  occ_import = occ,
  taxa_checked = taxa_checked,
  filter_date = TRUE,
  filter_identifiedBy = TRUE,
  filter_recordedBy = TRUE
)
filtered
filtered$summary

# The kept records carry the occurrence and joined columns only:
names(filtered$occ_filtered)

# The excluded records carry `gbifID` and one verdict column per applied
# test, so each shows exactly which tests rejected it:
names(filtered$occ_marked)
head(filtered$occ_marked)

# Disable the coordinate-uncertainty rule (NULL / NA / '' all work). The
# rule contributes no verdict column:
filtered_loose <- customized_filter(
  occ_import = occ,
  taxa_checked = taxa_checked,
  filter_coordinateUncertainty = NULL
)
"filter_coordinateUncertainty" %in% names(filtered_loose$occ_marked)
}
```
