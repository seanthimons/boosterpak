# Create a new pack from declared intent

`create_pack()` writes a pack manifest from package specs you provide.
It does not add the pack to `boosters.toml`, install packages, sync
`renv`, or copy functions into the project.

## Usage

``` r
create_pack(
  name,
  packages = character(),
  root = ".",
  scope = "project",
  description = NULL,
  extends = NULL,
  attach = c("ask", "all", "some", "none"),
  function_template = c("ask", "yes", "no"),
  overwrite = FALSE,
  verbose = NULL
)
```

## Arguments

- name:

  Pack name to write. The name is also used as the TOML `name` and file
  name.

- packages:

  Character vector of package specs. Plain package names are written to
  `packages`; source-specific specs are preserved in `[sources]`.

- root:

  Project root.

- scope:

  Destination scope: `"project"` or `"user"`.

- description:

  Optional pack description.

- extends:

  Optional character vector of known pack names to extend.

- attach:

  Attach intent: `"ask"`, `"all"`, `"some"`, `"none"`, or a character
  vector of package names to attach.

- function_template:

  Whether to create a nested function sidecar template: `"ask"`,
  `"yes"`, or `"no"`.

- overwrite:

  Whether to replace an existing pack file or template.

- verbose:

  Whether to print routine summaries.

## Value

Path to the created pack, invisibly.
