# Read a pack setting

Looks up a setting for a pack, preferring the project-level override in
`[settings.packs.<pack>]` of `boosters.toml`, then the pack's own
`[settings]` defaults, then `default`.

## Usage

``` r
pack_setting(pack, key, default = NULL, root = ".")
```

## Arguments

- pack:

  Pack name.

- key:

  Setting key.

- default:

  Value returned when the setting is not declared anywhere.

- root:

  Project root.

## Value

The setting value.
