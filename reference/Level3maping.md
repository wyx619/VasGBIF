# WGSRPD Level 3 area codes, names and country concordance

The tabular component of the Biodiversity Information Standards (TDWG)
World Geographical Scheme for Recording Plant Distributions (WGSRPD):
one row per Level 3 unit ("Botanical Country"), giving its code, name,
parent Level 2 region, and — where the source standard supplies one —
the ISO 3166-1 alpha-2 code of the country it belongs to.

## Usage

``` r
Level3maping
```

## Format

A data.table with 369 rows and 6 variables:

- L3 code:

  Three-letter WGSRPD Level 3 code, e.g. `"AGE"`. Unique; joins to
  `LEVEL3_COD` in
  [WGSRPD3](https://wyx619.github.io/VasGBIF/reference/wgsrpd3.md) and
  to `area_code_l3` in
  [Distributions](https://wyx619.github.io/VasGBIF/reference/Distributions.md).

- L3 area:

  Name of the Level 3 unit, e.g. `"Argentina Northeast"`. Boundaries
  follow political borders or coastlines, but the units are botanical
  rather than political: large countries are subdivided, and small ones
  may be grouped.

- L2 code:

  Code of the parent Level 2 (regional) unit. Stored as text with a
  comma decimal mark, e.g. `"85,00"`, as in the source file.

- L3 ISOcode:

  ISO 3166-1 alpha-2 country code, or `""` when the source standard
  gives none. See Details before using this column to map country codes
  onto areas.

- Ed2status:

  Amendment flag carried over verbatim from the source table. Empty for
  366 areas; `"N"` for Belarus (BLR) and Suriname (SUR), `"T"` for the
  Chagos Archipelago (CGS). The source standard should be consulted for
  the meaning of these codes.

- Notes:

  Free-text note from the source table. Populated for three areas only:
  alternative spellings for Belarus and Suriname, and a Level 2 code
  remark for the Chagos Archipelago.

## Source

- [tblLevel3.txt](https://github.com/tdwg/wgsrpd/blob/master/109-488-1-ED/2nd%20Edition/tblLevel3.txt)

- [World Geographical Scheme for Recording Plant Distributions
  (WGSRPD)](http://www.tdwg.org/standards/109)

## Details

Level 3 is the level at which the World Checklist of Vascular Plants
records distributions, so `L3 code` is the key shared with
[Distributions](https://wyx619.github.io/VasGBIF/reference/Distributions.md)
and with the polygon map in
[WGSRPD3](https://wyx619.github.io/VasGBIF/reference/wgsrpd3.md). All
369 codes are present in `WGSRPD3`.

`L3 ISOcode` is reproduced as published and is **not** a complete or
one-to-one concordance. Three properties matter when using it to
translate an occurrence record's `countryCode` into candidate Level 3
areas:

- **Many areas share one country code.** A single ISO code usually maps
  to several Level 3 units: `US` to 51, `RU` to 21, `CA` to 13, `CN` and
  `AU` to 8 each. Only 138 of the represented countries map to exactly
  one area, so an ISO code generally identifies a *set* of areas, not
  one area.

- **42 areas carry no ISO code at all**, among them the mainland units
  for France (FRA), Italy (ITA), Spain (SPA), Austria (AUT), Belgium
  (BGM), Ireland (IRE), Ukraine (UKR) and Korea (KOR). Because some
  offshore units of the same countries *do* carry a code, a naive lookup
  silently returns the islands alone: `"FR"` resolves to Corse, `"IT"`
  to Sardegna, and `"ES"` to the Baleares and Canary Islands. This
  yields a plausible but wrong area rather than no answer.

- **One code is inconsistent with current usage.** Belarus (BLR) is
  listed under ISO `RU`, reflecting the standard's 2001 vintage; records
  coded `BY` therefore find no area, and records coded `RU` gain Belarus
  as a candidate.

## References

R. K. Brummitt. 2001. World Geographical Scheme for Recording Plant
Distributions, Edition 2. Hunt Institute for Botanical Documentation,
Carnegie Mellon University (Pittsburgh).
<http://rs.tdwg.org/wgsrpd/doc/data/>

## See also

[WGSRPD3](https://wyx619.github.io/VasGBIF/reference/wgsrpd3.md) for the
matching polygons,
[Distributions](https://wyx619.github.io/VasGBIF/reference/Distributions.md)
for the distribution records keyed on these codes.
