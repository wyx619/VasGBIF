# Print an `occ_taxa` object

Displays a summary of a taxonomic resolution result based on
`occ_taxa_checked`: the number of records, the number of distinct
`scientificName` values, a table of distinct name counts
(`scientificName`, `Accepted_name`, `Accepted_species`), the `Source`
breakdown, and the top three `Accepted_name` values by record count,
followed by the elapsed runtime. The records themselves are not shown;
use [`head()`](https://rdrr.io/r/utils/head.html) or
[`View()`](https://rdrr.io/r/utils/View.html) to inspect them.

## Usage

``` r
# S3 method for class 'occ_taxa'
print(x, ...)
```

## Arguments

- x:

  An object of class `"occ_taxa"` returned by
  [`check_taxon()`](https://wyx619.github.io/VasGBIF/reference/check_taxon.md).

- ...:

  Additional arguments (unused, retained for S3 compatibility).

## Value

Invisibly returns `x`.
