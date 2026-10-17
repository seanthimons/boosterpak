# Upgrading an existing project

This vignette covers projects that were created or last repaired with an
older boosterpak.
[`upgrade_project()`](https://seanthimons.github.io/boosterpak/reference/upgrade_project.md)
brings them up to the installed version. It repairs the managed
`.Rprofile` startup lines and `boosters/attach.R`, installs missing
workflow packages into the project library, and records the result in
`renv.lock`. It does not change your pack declarations, your
`boosters.toml` settings, or your helper functions. The only
`boosters.toml` change is the `boosters_version` record.

## Who needs it

A project needs an upgrade when it was last migrated with an older
boosterpak. `boosters.toml` records that version in
`[project].boosters_version`:

``` toml
[project]
name = "my-project"
# boosters_version is the boosterpak version this project was last migrated
# with. init() and the upgrade path refresh it; sync() does not. It is not a
# lock. When it is older than the installed boosterpak, run
# boosterpak::upgrade_project() to bring the project up to date.
boosters_version = "0.9.2"
```

[`status()`](https://seanthimons.github.io/boosterpak/reference/status.md)
warns when the recorded version is older than the installed boosterpak.
A missing record is reported as “no version recorded” without a warning,
and `upgrade_needed` is still `TRUE`. You do not need to know which
layout a project has. The dry run below shows what would change.

[`sync()`](https://seanthimons.github.io/boosterpak/reference/sync.md)
does not update the recorded version. A project that only ran
[`sync()`](https://seanthimons.github.io/boosterpak/reference/sync.md)
after an upgrade of boosterpak still needs
[`upgrade_project()`](https://seanthimons.github.io/boosterpak/reference/upgrade_project.md).

## Before you start

- Commit or stash your work, so that the upgrade shows up as its own
  diff.
- Run the upgrade from the R version the project should pin. The
  lockfile records the R version that runs the upgrade.
- Have a GitHub token ready if the install step may run. See “GitHub
  rate limits” below.

## The recipe

The order matters. Run the dry run before the real upgrade, and review
the diff before you commit.

``` mermaid
flowchart TD
  A([Commit or stash your work]) --> B(["Install the new boosterpak into the project library"])
  B --> C(["Restart R in the project"])
  C --> D(["upgrade_project(dry_run = TRUE)"])
  D --> E["Read the preview: R version, CRAN URL, packages, files"]
  E --> F(["upgrade_project()"])
  F --> G(["git diff"])
  G --> H([Commit])
  G --> I(["Revert the files under Files touched"])

  classDef userAction fill:#e8f3ff,stroke:#1f6feb,color:#0b1f3a;
  classDef packageAction fill:#f6f8fa,stroke:#6e7781,color:#24292f;
  class A,B,C,D,E,F,G,H,I userAction;
```

### 1. Install the new boosterpak

Update the copy in the project library, so that `renv.lock` can record
the new version:

``` r

renv::install("seanthimons/boosterpak")
```

Then restart R in the project, so the new version is the one that loads.

[`upgrade_project()`](https://seanthimons.github.io/boosterpak/reference/upgrade_project.md)
installs workflow packages only when they are missing from the project
library. It does not update a copy that is already there, so this step
is the one that moves the project’s boosterpak forward.

### 2. Run a dry run

``` r

boosterpak::upgrade_project(dry_run = TRUE)
```

A dry run changes no files, installs no packages, and restores the
session options it touched. It prints the planned actions and the
report. When `verbose` is left at its default, a dry run always prints.

### 3. Read the preview

The report ends with a `Lockfile preview (renv.lock)` section and a
`Files a real run would touch` list. The preview has three parts:

- `R version`, the version recorded in `renv.lock` and the version that
  is running the upgrade. A change here means the lockfile will pin a
  different R version. Start R at the version you want before
  continuing.
- `CRAN repository`, the URL recorded in the lockfile and the URL in use
  now.
- The workflow packages (`renv`, `pak`, `boosterpak`) and their
  dependencies whose locked version differs from the installed version,
  one per line in the form `package: locked -> installed`.

The preview is an estimate. renv writes the final records when the
snapshot runs.

### 4. Run the upgrade

``` r

boosterpak::upgrade_project()
```

In an interactive session the report prints by default. In a script,
pass `verbose = TRUE` to see it.

To leave `renv.lock` alone, pass `snapshot = FALSE`. The upgrade still
repairs the project files and installs missing workflow packages, but it
does not write the lockfile. Run
[`upgrade_project()`](https://seanthimons.github.io/boosterpak/reference/upgrade_project.md)
again without that argument before you commit, or the lockfile keeps its
old records.

### 5. Review and commit or revert

``` sh
git diff
```

Commit when the diff matches the preview. To undo the upgrade:

1.  Restore each tracked file listed under “Files touched” with
    `git restore`.
2.  For each new file the upgrade created, such as
    `boosters/packs/core.toml`, check the path first with
    `git clean -n -- <path>`, then remove it with
    `git clean -f -- <path>`. Use only the paths the report lists.
3.  Restart R.

Packages installed into `renv/library/` are not tracked by git. Remove
them with
[`renv::remove()`](https://rstudio.github.io/renv/reference/remove.html)
if you do not want them.

## Files the upgrade touches

Each file is touched only when the condition in the middle column holds.
`.Rprofile`, `boosters/packs/core.toml`, and the declared pack files are
reported as skipped when they are already current. `boosters/attach.R`
and `renv.lock` are rewritten or re-snapshotted on every run where they
apply, so they are listed under “Files touched” even when nothing
changed.

| File | When it is touched | Why |
|----|----|----|
| `.Rprofile` | The managed startup block or the repository lines differ from the current layout | Replaces an older hook block, removes historical hook lines, and adds the Linux binary lines. Other lines are kept. |
| `boosters/attach.R` | Every run where `boosters.toml` is valid | Rewritten in the current guarded format. When `[attach].enabled = false`, a managed file is removed instead. |
| `boosters/packs/core.toml` | Only when missing | Materializes the built-in `core` pack manifest. |
| `boosters/packs/` | Only for declared packs whose files are not yet present | Copies pack manifests and nested helper sidecars. Existing files are not overwritten. |
| `renv.lock` | Unless `snapshot = FALSE` | Records `renv`, `pak`, `boosterpak`, and their hard dependencies, along with the R version and the CRAN URL. Other packages keep their records. |
| `renv/activate.R` | Only when the renv version changes during the snapshot | renv rewrites its activation script when it records a new renv version. |
| `boosters.toml` | Only when `[project].boosters_version` is missing or older than the installed boosterpak, and the run reports no warnings | Sets `boosters_version` to the installed version. No other field changes. A dry run only lists the file. |

`boosters/fn_*.R` helper files are not rewritten. Your local edits to
them are kept.

## What changes in renv.lock

- **R version.** The `R` record is set to the R version that runs the
  upgrade.
- **CRAN repository.** The lockfile records the generic Package Manager
  URL, such as `https://packagemanager.posit.co/cran/latest`, even on
  glibc Linux, where the session uses a manylinux binary URL. The
  upgrade’s snapshot passes the generic URL to renv, so the
  `__linux__/manylinux_2_28` segment does not reach `renv.lock`. A
  manual
  [`renv::snapshot()`](https://rstudio.github.io/renv/reference/snapshot.html)
  does not get that handling; renv strips the segment only while its own
  Package Manager handling is on. See “Linux binary packages” in
  [`vignette("getting-started", package = "boosterpak")`](https://seanthimons.github.io/boosterpak/articles/getting-started.md).
- **Package records.** `renv`, `pak`, `boosterpak`, and their hard
  dependencies are recorded at their installed versions.
- **`Repository` and `Platform` fields.** Packages installed from
  Package Manager binaries can carry `Repository: RSPM` and a `Platform`
  field. renv’s restore does not read `Platform`. `RSPM` is only a
  preference, so restore falls back to the repository URLs in
  `renv.lock`. Those URLs are the generic Package Manager URLs, which
  also serve Windows and macOS binaries. A lockfile written on Linux
  should therefore restore elsewhere. Check each platform after its
  first restore.

## The managed .Rprofile block over time

The startup lines have changed in each release.
[`upgrade_project()`](https://seanthimons.github.io/boosterpak/reference/upgrade_project.md)
replaces the older forms with the current one.

| Layout | What the `.Rprofile` contains |
|----|----|
| 0.5.x | One line that sources the `boosters/fn_*.R` files. No attachment. |
| 0.6.1 to 0.7.0 | One line that sources `boosters/attach.R`, then the `fn_*.R` files. No markers. |
| 0.8.0 to 0.9.2 | The same line wrapped in a managed block, `# BEGIN boosterpak managed startup` to `# END boosterpak managed startup`, inside [`try()`](https://rdrr.io/r/base/try.html). The repository and install-policy lines sit around the activation line. 0.9.2 also adds the early Linux binary line (manylinux). |
| Current source (next release) | The block sources `boosters/attach.R` and each `fn_*.R` file in its own [`try()`](https://rdrr.io/r/base/try.html), so one failure does not stop the rest. The Linux binary lines are also repeated after the renv activation line. |

The reason for the last change is that `attach.R` loads packages. In the
0.8.0 to 0.9.2 layout, a missing package made `attach.R` fail, and that
stopped the helper files that came after it. In the current layout,
`attach.R` attaches each package on its own, so a missing package is
reported and the rest still attach.

The post-activation Linux lines matter because `renv/activate.R` calls
[`renv::load()`](https://rstudio.github.io/renv/reference/load.html).
That resets `repos` to the lockfile URLs and undoes the manylinux
rewrite made before activation. The lines repeat the rewrite right after
activation, and only while renv’s Package Manager handling is on. They
keep the lockfile URL generic. See “Linux binary packages” in
[`vignette("getting-started", package = "boosterpak")`](https://seanthimons.github.io/boosterpak/articles/getting-started.md).

A rerun is safe. On a second run the `.Rprofile` lines are not
rewritten, because they already match, and the report lists `.Rprofile`
and the pack files as skipped. `boosters/attach.R` is regenerated with
the same content, and `renv.lock` is re-snapshotted. Both stay listed
under “Files touched”, so check them with `git diff`. `boosters.toml` is
listed only when its `boosters_version` changes. On a rerun that finds
the version current, the report says so as a skipped step.

## GitHub rate limits

The install step runs only when a workflow package is missing from the
project library. boosterpak is installed from GitHub only when it is the
missing package. Anonymous GitHub requests are limited, so that install
can fail with a rate limit. When it does,
[`upgrade_project()`](https://seanthimons.github.io/boosterpak/reference/upgrade_project.md)
does not stop. It reports a `WARNING: workflow package install skipped`
line, with a hint that names the token options appended to it. The run
then writes no `renv.lock` and does not record `boosters_version`. Set a
token and rerun. The first step of this recipe,
`renv::install("seanthimons/boosterpak")`, also talks to GitHub, but
renv reports its own errors, so no boosterpak hint is added there.

Set a token before you run either step. From a shell where the GitHub
CLI is logged in:

``` sh
GITHUB_PAT=$(gh auth token) Rscript -e 'boosterpak::upgrade_project(".")'
```

The substitution passes the token to that one command. The token is not
written to a file, and boosterpak never prints its value. For the other
ways to supply a token, and what to keep out of the project, see “GitHub
rate limits” in
[`vignette("restoring-a-project", package = "boosterpak")`](https://seanthimons.github.io/boosterpak/articles/restoring-a-project.md).

## Troubleshooting

The report prefixes each line with `OK:`, `INFO:`, or `WARNING:`. `INFO`
lines are skips, which do not stop the run. `WARNING` lines are
problems. A run with any warning does not record `boosters_version`.
Most entries below quote a report line. The first entry is an error that
stops the run.

**`boosters.toml does not exist`.** The directory is not a boosterpak
project, or `boosters.toml` was deleted.
[`upgrade_project()`](https://seanthimons.github.io/boosterpak/reference/upgrade_project.md)
repairs existing projects only. Use
[`init()`](https://seanthimons.github.io/boosterpak/reference/init.md)
for a new project, or restore the file from git.

**`workflow package repair skipped: no project renv found`.** The
project has no project-local renv. The `.Rprofile` and `attach.R`
repairs still run, but the workflow packages are not installed or
snapshotted. Run `boosterpak::init(renv = "yes")` to create one, then
upgrade again.

**`workflow package repair skipped: renv is unavailable`.** renv is not
installed, so the workflow packages are not repaired or snapshotted. The
report also carries a `WARNING: workflow package repair incomplete`
line, so the run does not record `boosters_version`. Install renv into
your user library and rerun.

**`WARNING: workflow package repair skipped: project renv could not be loaded`.**
The upgrade could not activate the project’s renv. Fix the error it
reports, then rerun. Nothing is written to `renv.lock` on this path.

**`boosters.toml is not valid for config-dependent repairs`.** The file
parses, but a field the upgrade needs is the wrong type. The message
names the field. Fix it and rerun. Pack materialization and `attach.R`
are skipped until then, but the `.Rprofile` repair still runs.

**`WARNING: workflow package install skipped`, with a GitHub hint.** The
install failed, most often with a GitHub rate limit. The `.Rprofile` and
`attach.R` repairs are already done, but the run writes no `renv.lock`
and does not record `boosters_version`. Set a token as shown above, then
rerun.

**`WARNING: workflow package snapshot skipped`.** The packages are
installed, but the dependency check or
[`renv::snapshot()`](https://rstudio.github.io/renv/reference/snapshot.html)
failed. The message carries renv’s error. Fix it and rerun.

**`boosters_version not recorded: the upgrade reported warnings`.** This
is an `INFO` line. The version is recorded only after a run with no
warnings, so fix the warnings above and rerun. A
`WARNING: boosters_version not recorded: <reason>` line means the record
itself could not be written. The message gives the reason.

**`lockfile preview unavailable`.** The dry run could not read
`renv.lock`. The rest of the report is still valid. Check that the file
parses, for example with
[`jsonlite::validate()`](https://jeroen.r-universe.dev/jsonlite/reference/validate.html).

**`repository configuration skipped: disabled by option or environment`.**
Repository setup is off, because
`BOOSTERPAK_CONFIGURE_REPOSITORIES=false` or the
`boosterpak.configure_repositories` option is set. This is an `INFO`
line. If install-policy setup is still on, the rerun removes the managed
repository lines from `.Rprofile`, because boosterpak has no repository
setup to write back. The install-policy lines are kept. If
install-policy setup is off as well,
`BOOSTERPAK_CONFIGURE_INSTALL_POLICY=false` or the
`boosterpak.configure_install_policy` option is `FALSE`, no setup lines
are written, and the existing repository and install-policy lines are
not changed.

**`repository configuration already set or intentionally custom`.** This
is information, not a problem. boosterpak leaves a custom CRAN
repository alone.

**`attach file rewrite skipped`.** The message gives the reason. The
other repairs still run.
