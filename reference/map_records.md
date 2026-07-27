# Visualize refined records on interactive maps

Renders refined occurrence records on interactive maps for spatial
exploration and quality assessment. Records are deduplicated with
geohashes and color-coded by their native status.

## Usage

``` r
map_records(refined_records = NA, precision = 3, cex = 3)
```

## Arguments

- refined_records:

  A `refined` object returned by
  [`refine_records()`](https://wyx619.github.io/VasGBIF/reference/refine_records.md).

- precision:

  Positive integer controlling the spatial resolution of geohash-based
  deduplication. Higher values produce finer-grained cells. For
  reference, precision values of 4, 3, and 2 represent approximately 20
  km, 156 km, and 1,250 km resolution, respectively. Defaults to `3`.

- cex:

  Numeric value controlling the point size of occurrence records on the
  map. Defaults to `3`.

## Value

A `mapview` interactive map object displaying refined occurrence records
color-coded by `native_status`. The map contains a native-status legend,
three switchable basemap layers, and clickable popups with record
metadata.

## Details

The workflow has four stages:

- **Record aggregation:** Combines native and non-native refined records
  that passed spatial validation
  (`VasGBIF_useful_for_spatial_analysis = TRUE`).

- **Geohash deduplication:** Encodes coordinates at the requested
  precision and retains one representative record per species, geohash
  cell, and native status.

- **Interactive visualization:** Builds a multi-layer map with records
  color-coded by `native_status`.

- **Basemap selection:** Provides OpenStreetMap, Esri World Imagery, and
  Stadia Stamen Watercolor basemaps.

### Geohash deduplication

Geohash encoding converts latitude-longitude pairs into alphanumeric
strings representing grid cells of varying sizes. The function groups
records by species name, geohash cell, and native status, then retains
the first record from each group. This reduces visual overplotting while
preserving the broad spatial distribution pattern, which is useful for
densely sampled regions.

### Map layers and interactivity

The generated map includes:

- A color-coded legend based on `native_status` categories.

- Popups displaying record attributes such as GBIF ID, collection key,
  and taxon name.

- Toggleable basemap layers for different visualization contexts.

- Point transparency set to `alpha.regions = 0.6` to improve density
  perception.

### Record selection

Records are included only when
`VasGBIF_useful_for_spatial_analysis = TRUE`. For non-native records,
`native_status` must also differ from `"unknown"`. Records with missing
longitude or latitude are removed before geohash deduplication.

## See also

[`gh_encode()`](https://rdrr.io/pkg/geohashTools/man/gh_encode.html) for
geohash encoding and
[`mapView()`](https://r-spatial.github.io/mapview/reference/mapView.html)
for interactive map construction.

## Examples

``` r
if (FALSE) { # interactive() && exists("refined_records")
map_records(refined_records = refined_records, precision = 3, cex = 3)
}
```
