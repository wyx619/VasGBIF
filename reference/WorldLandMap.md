# A simple features object of the world land map

An integrated land map

## Usage

``` r
WorldLandMap
```

## Format

A simple features object

- featurecla:

  Land area

- scalerank:

  Scale rank of the land feature

- min_zoom:

  Minimum zoom level at which the feature is displayed

- geometry:

  Geometry unit

## Source

`rnaturalearth::ne_download(scale = 110,type = 'land',category = 'physical',returnclass = "sf")`

## See also

[`rnaturalearth::ne_download()`](https://docs.ropensci.org/rnaturalearth/reference/ne_download.html)
