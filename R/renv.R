#' Check Whether the Project Renv Is Active
#'
#' @param root Project root.
#' @return `TRUE` if the project has renv infrastructure and its library is on
#'   the active library paths.
#' @noRd
is_project_renv_active <- function(root = ".") {
  renv_dir <- file.path(root, "renv")
  activate <- file.path(renv_dir, "activate.R")
  if (!dir.exists(renv_dir) || !file.exists(activate)) {
    return(FALSE)
  }
  lib <- renv::paths$library(project = root)
  any(
    normalizePath(.libPaths(), winslash = "/", mustWork = FALSE) ==
      normalizePath(lib, winslash = "/", mustWork = FALSE)
  )
}

#' Check Whether the Project Has Renv Infrastructure
#'
#' @param root Project root.
#' @return `TRUE` if the project has the `renv` directory and its activation
#'   script.
#' @noRd
has_project_renv <- function(root = ".") {
  renv_dir <- file.path(root, "renv")
  activate <- file.path(renv_dir, "activate.R")
  dir.exists(renv_dir) && file.exists(activate)
}

#' Require an Active Project Renv
#'
#' @param root Project root.
#' @return `TRUE`, invisibly.
#' @noRd
ensure_project_renv <- function(root = ".") {
  if (!is_project_renv_active(root)) {
    cli::cli_abort(
      c(
        "No active project-local renv library was found.",
        "i" = "Run {.code boosterpak::init(renv = 'yes')} to bootstrap the project renv, or run {.code renv::init()} and restart R in the project."
      ),
      call = NULL
    )
  }
  invisible(TRUE)
}

#' Resolve the Package Library Strategy
#'
#' @param library Optional package library strategy.
#' @param config Optional parsed project configuration.
#' @return One of `"renv"` or `"active"`.
#' @noRd
resolve_library_strategy <- function(library = NULL, config = NULL) {
  configured <- (config$settings %||% list())$library %||% "renv"
  strategy <- library %||% configured
  if (!is.character(strategy) || length(strategy) != 1 || is.na(strategy)) {
    cli::cli_abort(
      "{.arg library} must be one of {.val renv} or {.val active}.",
      call = NULL
    )
  }
  match.arg(strategy, c("renv", "active"))
}

#' Find the Active Writable Package Library
#'
#' @return The normalized path to the first writable active package library.
#' @noRd
active_package_library <- function() {
  libraries <- .libPaths()
  writable <- libraries[file.access(libraries, mode = 2) == 0]
  if (length(writable) == 0) {
    cli::cli_abort(
      "No writable library was found in {.code .libPaths()}.",
      call = NULL
    )
  }
  normalizePath(writable[[1]], winslash = "/", mustWork = TRUE)
}

#' Resolve the Package Library Path
#'
#' @param root Project root.
#' @param library Package library strategy, either `"renv"` or `"active"`.
#' @return The normalized package library path.
#' @noRd
package_library <- function(root = ".", library = "renv") {
  library <- resolve_library_strategy(library)
  if (identical(library, "active")) {
    active_package_library()
  } else {
    normalizePath(
      renv::paths$library(project = root),
      winslash = "/",
      mustWork = FALSE
    )
  }
}

#' Ensure the Selected Package Library Is Available
#'
#' @param root Project root.
#' @param library Package library strategy, either `"renv"` or `"active"`.
#' @return `TRUE`, invisibly.
#' @noRd
ensure_package_library <- function(root = ".", library = "renv") {
  library <- resolve_library_strategy(library)
  if (identical(library, "renv")) {
    ensure_project_renv(root)
  } else {
    active_package_library()
  }
  invisible(TRUE)
}

#' Initialize Project Renv
#'
#' @param root Project root.
#' @return The project path, invisibly.
#' @noRd
call_renv_init <- function(root = ".") {
  old <- setwd(root)
  on.exit(setwd(old), add = TRUE)
  renv::init(project = root, bare = TRUE, load = TRUE, restart = FALSE)
}

#' Load Project Renv
#'
#' @param root Project root.
#' @return The project path, invisibly.
#' @noRd
call_renv_load <- function(root = ".") {
  renv::load(project = root, quiet = TRUE)
}

#' Snapshot the Project Renv Lockfile
#'
#' @param root Project root.
#' @param packages Optional character vector of package names to snapshot.
#' @param update Whether to update package records in the lockfile.
#' @return The lockfile data, invisibly.
#' @noRd
call_renv_snapshot <- function(root = ".", packages = NULL, update = FALSE) {
  old <- setwd(root)
  on.exit(setwd(old), add = TRUE)
  renv::snapshot(
    project = root,
    packages = packages,
    prompt = FALSE,
    update = update
  )
}

#' Restore the Project Renv Library
#'
#' @param root Project root.
#' @return The restored package records, invisibly.
#' @noRd
call_renv_restore <- function(root = ".") {
  old <- setwd(root)
  on.exit(setwd(old), add = TRUE)
  configure_boosterpak_repositories(verbose = FALSE)
  configure_boosterpak_install_policy(verbose = FALSE)
  renv::restore(project = root, prompt = FALSE)
}

#' Install Packages with Pak
#'
#' @param packages Character vector of package specifications to install.
#' @param root Project root.
#' @param library Package library strategy, either `"renv"` or `"active"`.
#' @return `packages`, invisibly.
#' @noRd
install_via <- function(packages, root = ".", library = "renv") {
  if (length(packages) == 0) {
    return(invisible(character()))
  }
  old <- setwd(root)
  on.exit(setwd(old), add = TRUE)
  configure_boosterpak_install_policy(verbose = FALSE)
  pak::pkg_install(
    packages,
    lib = package_library(root, library),
    upgrade = FALSE
  )
  invisible(packages)
}

#' Install Pak with Renv
#'
#' @param root Project root.
#' @return `"pak"`, invisibly.
#' @noRd
install_pak_via_renv <- function(root = ".") {
  old <- setwd(root)
  on.exit(setwd(old), add = TRUE)
  configure_boosterpak_repositories(verbose = FALSE)
  configure_boosterpak_install_policy(verbose = FALSE)
  renv::install("pak", prompt = FALSE)
  invisible("pak")
}

#' Hydrate Packages into the Project Renv Library
#'
#' @param packages Character vector of package names to hydrate.
#' @param root Project root.
#' @return `packages`, invisibly.
#' @noRd
hydrate_via_renv <- function(packages, root = ".") {
  if (length(packages) == 0) {
    return(invisible(character()))
  }
  renv::hydrate(
    project = root,
    packages = packages,
    library = renv::paths$library(project = root),
    prompt = FALSE,
    report = FALSE
  )
  invisible(packages)
}

#' Select Missing Packages with Plain Install Specifications
#'
#' @param packages Character vector of package names.
#' @param install_specs Character vector of corresponding install
#'   specifications.
#' @param missing Character vector of missing package names.
#' @return The missing package names whose install specifications are plain
#'   package names.
#' @noRd
plain_missing_packages <- function(packages, install_specs, missing) {
  missing_specs <- install_specs[packages %in% missing]
  missing_packages <- packages[packages %in% missing]
  missing_packages[missing_specs == missing_packages]
}

#' Find Missing Packages
#'
#' @param packages Character vector of package names.
#' @param root Project root.
#' @param library Package library strategy, either `"renv"` or `"active"`.
#' @return A character vector of packages absent from the selected library.
#' @noRd
missing_packages <- function(packages, root = ".", library = "renv") {
  lib <- package_library(root, library)
  installed <- vapply(
    packages,
    function(package) {
      file.exists(file.path(lib, package, "DESCRIPTION"))
    },
    logical(1),
    USE.NAMES = FALSE
  )
  packages[!installed]
}
