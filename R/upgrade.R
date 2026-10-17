#' Upgrade an existing boosterpak project
#'
#' `upgrade_project()` brings a project created by an earlier boosterpak
#' version up to date. It repairs the managed `.Rprofile` startup lines,
#' rewrites the managed `boosters/attach.R`, materializes missing built-in
#' packs, installs missing workflow packages (renv, pak, and boosterpak) into
#' the project library, and snapshots those packages into `renv.lock`.
#'
#' Run a dry run first. `upgrade_project(dry_run = TRUE)` changes no files,
#' installs no packages, and restores the session options it touched. It
#' prints the planned actions, a preview of the `renv.lock` changes, and the
#' files a real run would touch.
#'
#' @details
#' The snapshot records the R version that runs the upgrade and the CRAN
#' repository URL in use, so run the upgrade from the R version the project
#' should pin. Package entries installed from Posit Package Manager binaries
#' can carry `Repository: RSPM` and a `Platform` field. renv's restore code
#' does not read `Platform`, and `RSPM` is only a preference: restore falls
#' back to the repository URLs listed in `renv.lock`, which also serve Windows
#' and macOS binaries. Use `snapshot = FALSE` to leave `renv.lock` unchanged.
#'
#' A clean real run records the installed boosterpak version in
#' `[project].boosters_version` in `boosters.toml`. A run is clean when its
#' report has no warnings. Steps that are skipped on purpose, such as
#' repository configuration disabled by an option or a project without a
#' project renv, do not make a run unclean. A missing renv does, because the
#' workflow packages cannot be repaired without it. A run that is not clean
#' repairs what it can, leaves the record as it was, and reports why. A dry run
#' changes nothing. It lists `boosters.toml` among the files a real run would
#' touch when that run would record the version.
#'
#' Review the result with `git diff` (or your version control) before
#' committing. When an install fails with a GitHub rate limit, or with an HTTP
#' 403 or 429 from GitHub that may be a rate limit, the error includes a hint
#' about supplying a GitHub token. The hint never prints a token value.
#'
#' @param root Project root containing an existing `boosters.toml` file.
#' @param dry_run Whether to report planned changes without modifying files,
#'   the project library, or the active session. Default `FALSE`.
#' @param snapshot Whether to write workflow packages to `renv.lock`. With
#'   `FALSE` the upgrade still repairs project files and installs missing
#'   workflow packages into the project library, but does not write the
#'   lockfile.
#' @param verbose Whether to print the upgrade report. `NULL` prints in
#'   interactive sessions. A dry run prints its report when `verbose` is `NULL`.
#' @return The upgrade report, invisibly. Its `actions`, `skipped`, `warnings`,
#'   `paths`, and `preview` fields list what was done, or would be done, and
#'   which files are affected.
#' @examples
#' \dontrun{
#' boosterpak::upgrade_project(dry_run = TRUE)
#' boosterpak::upgrade_project()
#' }
#' @export
upgrade_project <- function(
  root = ".",
  dry_run = FALSE,
  snapshot = TRUE,
  verbose = NULL
) {
  if (is.null(verbose) && isTRUE(dry_run)) {
    verbose <- TRUE
  }
  .rescue(
    root = root,
    dry_run = dry_run,
    verbose = verbose,
    snapshot = snapshot
  )
}

#' Describe the renv.lock changes a workflow snapshot would make
#'
#' @param root Project root.
#' @param packages Workflow package names the snapshot updates.
#' @param repos Repository option the snapshot runs with.
#' @return A list with `lines`, the preview text, and `renv_changed`, which is
#'   `TRUE` when the lockfile's renv record differs from the installed renv.
#' @noRd
workflow_lockfile_preview <- function(root, packages, repos = getOption("repos")) {
  path <- file.path(root, "renv.lock")
  if (!file.exists(path)) {
    return(list(
      lines = "renv.lock does not exist yet; the snapshot will create it.",
      renv_changed = TRUE
    ))
  }

  lock <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  db <- installed_package_db(root)
  installed_version <- function(package) {
    if (package %in% rownames(db)) {
      db[package, "Version"]
    } else {
      NA_character_
    }
  }

  lines <- c(
    lockfile_change_line(
      "R version",
      first_string(lock$R$Version),
      as.character(getRversion())
    ),
    lockfile_change_line(
      "CRAN repository",
      lockfile_cran_url(lock),
      cran_repo_url(portable_ppm_repos(repos))
    )
  )

  changes <- character()
  for (package in installed_hard_closure(packages, db)) {
    locked <- first_string(lock$Packages[[package]]$Version)
    current <- installed_version(package)
    if (is.na(locked) && is.na(current)) {
      next
    }
    if (identical(locked, current)) {
      next
    }
    changes <- c(changes, lockfile_package_change(package, locked, current))
  }

  if (length(changes) > 0) {
    lines <- c(
      lines,
      "workflow packages and dependencies the snapshot re-pins:",
      paste0("  ", changes)
    )
  } else {
    lines <- c(lines, "workflow packages and dependencies: no version changes.")
  }
  lines <- c(
    lines,
    "This preview is approximate; renv makes the final records when it snapshots."
  )

  list(
    lines = lines,
    renv_changed = !identical(
      first_string(lock$Packages$renv$Version),
      installed_version("renv")
    )
  )
}

#' Format one lockfile header change
#'
#' @param label Human-readable field name.
#' @param old Value recorded in the lockfile, or `NA`.
#' @param new Value the snapshot would record.
#' @return A one-line description.
#' @noRd
lockfile_change_line <- function(label, old, new) {
  show <- function(value) if (is.na(value)) "(none)" else value
  if (identical(old, new)) {
    return(sprintf("%s: %s (unchanged)", label, show(new)))
  }
  sprintf("%s: %s -> %s", label, show(old), show(new))
}

#' Format one package version change
#'
#' @param package Package name.
#' @param locked Version recorded in the lockfile, or `NA`.
#' @param current Installed version, or `NA` when not installed.
#' @return A one-line description.
#' @noRd
lockfile_package_change <- function(package, locked, current) {
  if (is.na(locked)) {
    return(sprintf("%s: not in lockfile -> %s", package, current))
  }
  if (is.na(current)) {
    return(sprintf("%s: %s -> (will be installed)", package, locked))
  }
  sprintf("%s: %s -> %s", package, locked, current)
}

#' Read the CRAN repository URL recorded in a lockfile
#'
#' @param lock Parsed lockfile.
#' @return The CRAN URL, or `NA` when none is recorded.
#' @noRd
lockfile_cran_url <- function(lock) {
  repos <- lock$R$Repositories %||% list()
  if (!is.null(names(repos)) && "CRAN" %in% names(repos)) {
    return(first_string(repos[["CRAN"]]))
  }
  for (repo in repos) {
    if (identical(repo$Name, "CRAN")) {
      return(first_string(repo$URL))
    }
  }
  NA_character_
}

#' Read the CRAN repository URL from a repository option
#'
#' @param repos A named repository option vector.
#' @return The CRAN URL, or `NA` when none is set.
#' @noRd
cran_repo_url <- function(repos) {
  first_string(repos[names(repos) %in% "CRAN"])
}

#' Take the first string from a parsed value
#'
#' @param value A string, a list of strings, or `NULL`.
#' @return The first string, or `NA_character_` when there is none.
#' @noRd
first_string <- function(value) {
  value <- as.character(unlist(value, use.names = FALSE))
  if (length(value) > 0) {
    value[[1]]
  } else {
    NA_character_
  }
}

#' Collect the installed hard-dependency closure of workflow packages
#'
#' Base packages are excluded because renv does not record them. Packages that
#' are not installed are kept so the preview can report them.
#'
#' @param packages Package names at the root of the closure.
#' @param db Matrix like [utils::installed.packages()].
#' @return A character vector of package names.
#' @noRd
installed_hard_closure <- function(packages, db) {
  base <- rownames(db)[db[, "Priority"] %in% "base"]
  queue <- packages
  seen <- character()
  while (length(queue) > 0) {
    package <- queue[[1]]
    queue <- queue[-1]
    if (package %in% seen || package %in% base) {
      next
    }
    seen <- c(seen, package)
    if (!package %in% rownames(db)) {
      next
    }
    deps <- parse_hard_dependencies(
      db[package, c("Depends", "Imports", "LinkingTo")]
    )
    queue <- c(queue, deps)
  }
  seen
}
