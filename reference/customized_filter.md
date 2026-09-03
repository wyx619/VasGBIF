# Apply custom quality filters to occurrence records

Joins the outputs of the VasGBIF import, taxonomic-resolution, and
GBIF-issue steps into a single occurrence table, then progressively
removes records according to a user-selected set of quality rules.

## Usage

``` r
customized_filter(
  occ_import = NA,
  taxa_checked = NA,
  gbif_issue = NA,
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
  [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md),
  containing at least the columns `issue`, `decimalLatitude`,
  `countryCode`, `coordinateUncertaintyInMeters`, `eventDate`, `month`,
  `year`, `day`, `identifiedBy`, and `recordedBy`.

- taxa_checked:

  An `"occ_taxa"` object returned by
  [`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md).

- gbif_issue:

  An `"issue"` object returned by
  [`extract_gbif_issues()`](https://wyx619.github.io/VasGBIF/reference/extract_gbif_issues.md).

- filter_countryCode:

  Logical scalar. If `TRUE` (default), removes records with no usable
  geographic information: `decimalLatitude` is `NA` **and**
  `countryCode` is `NA` or empty. Records with either a coordinate or a
  country code are kept.

- filter_coordinateUncertainty:

  Non-negative numeric scalar. Removes records whose
  `coordinateUncertaintyInMeters` is strictly greater than the
  threshold. Defaults to `10000`. Records with `NA` or empty
  `coordinateUncertaintyInMeters` are always kept - they do not
  participate in this rule. Pass `NULL`, `NA`, or `''` to disable the
  rule.

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
  Defaults to `5`. Pass `NULL`, `NA`, or `''` to disable the rule.

## Value

An object of class `"customFiltered"`, implemented as a named list with
two elements:

- `occ_filtered`: the filtered `data.table` with all occurrence and
  joined columns.

- `summary`: a `data.table` with columns `rule`, `dropped`, and
  `remaining` giving, for each applied step (the `taxon_resolved` join
  plus each enabled rule), how many records were removed and how many
  remained.

A [`print()`](https://rdrr.io/r/base/print.html) method for class
`"customFiltered"` displays the record counts and the per-rule summary.

## Details

### Joining the inputs

The three inputs are joined by `gbifID`. For memory efficiency the joins
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

[`extract_gbif_issues()`](https://wyx619.github.io/VasGBIF/reference/extract_gbif_issues.md)
returns exactly one row per imported record, so the issue join is
one-to-one and cannot change the row count. The function verifies this
and stops if any record lacks an issue count. The raw `issue` column is
removed from `occ_import` and replaced by `gbif_issues`, the per-record
issue count computed by
[`extract_gbif_issues()`](https://wyx619.github.io/VasGBIF/reference/extract_gbif_issues.md).

### Filter rules

Enabled rules are applied in sequence. By default `countryCode`,
`coordinateUncertainty`, and `gbif_issues_max` are enabled; `date`,
`identifiedBy`, and `recordedBy` are disabled.

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

- [`import_records()`](https://wyx619.github.io/VasGBIF/reference/import_records.md),
  [`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md),
  [`extract_gbif_issues()`](https://wyx619.github.io/VasGBIF/reference/extract_gbif_issues.md)
  for the three inputs.

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
taxa_checked <- check_taxon(occ_import = occ, accuracy = 0.85)

filtered <- customized_filter(
  occ_import = occ,
  taxa_checked = taxa_checked,
  gbif_issue = gbif_issue,
  filter_date = TRUE,
  filter_identifiedBy = TRUE,
  filter_recordedBy = TRUE
)
filtered

# Disable the coordinate-uncertainty rule (NULL / NA / '' all work):
filtered_loose <- customized_filter(
  occ_import = occ,
  taxa_checked = taxa_checked,
  gbif_issue = gbif_issue,
  filter_coordinateUncertainty = NULL
)
filtered_loose
}
```
