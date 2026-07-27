# The World Checklist of Vascular Plants Distributions

A processed dataset containing the distribution data from the WCVP,
mapped to the Biodiversity Information Standards (TDWG) World
Geographical Scheme for Recording Plant Distributions (WGSRPD)

## Usage

``` r
Distributions
```

## Format

A data.table with 1,983653 rows and 6 variables:

- plant_name_id:

  World Checklist of Vascular Plants (WCVP) identifier

- taxon_name:

  Concatenation of genus with species and, where applicable,
  infraspecific epithets to make a binomial or trinomial name

- area_code_l3:

  WGSRPD Level 3 code

- introduced:

  0 if native; 1 if introduced

- extinct:

  1 if extinct; 0 if extant

- location_doubtful:

  1 if doubtful; 0 otherwise

## Source

<http://sftp.kew.org/pub/data-repositories/WCVP/wcvp.zip>

## References

Govaerts, R., Nic Lughadha, E., Black, N. et al. The World Checklist of
Vascular Plants, a continuously updated resource for exploring global
plant diversity. *Sci Data* 8, 215 (2021).
[doi:10.1038/s41597-021-00997-6](https://doi.org/10.1038/s41597-021-00997-6)
