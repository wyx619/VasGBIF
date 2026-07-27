# Normalize the number of worker threads

Converts either an absolute thread count or a proportion of available
CPU cores into an integer number of worker threads. The number of
available cores is determined by
[`parallel::detectCores()`](https://rdrr.io/r/parallel/detectCores.html).

## Usage

``` r
set_threads(x)
```

## Arguments

- x:

  A numeric scalar. Values greater than or equal to `1` specify an
  absolute number of threads and are rounded to the nearest integer.
  Values strictly between `0` and `1` specify a proportion of available
  cores; the resulting number of threads is also rounded to the nearest
  integer.

## Value

An integer-like numeric scalar giving the normalized number of worker
threads. A message reports the selected and available thread counts.

## Details

Absolute thread counts exceeding the number of cores reported by
[`parallel::detectCores()`](https://rdrr.io/r/parallel/detectCores.html)
are silently capped to that limit with a message. Values less than or
equal to zero and non-numeric inputs produce an error.

During `R CMD check` (when the environment variable
`_R_CHECK_LIMIT_CORES_` is set to `"TRUE"`), threads are capped to a
maximum of 2 to comply with the check environment limit on parallel
processes.

This function is also used by
[`refine_records()`](https://wyx619.github.io/VasGBIF/reference/refine_records.md)
to normalize its `threads` argument.

## See also

[`parallel::detectCores()`](https://rdrr.io/r/parallel/detectCores.html),
[`refine_records()`](https://wyx619.github.io/VasGBIF/reference/refine_records.md)

## Examples

``` r
set_threads(1)
#> 1/4 threads used
#> [1] 1
set_threads(0.5)
#> 2/4 threads used
#> [1] 2
```
