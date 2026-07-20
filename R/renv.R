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

has_project_renv <- function(root = ".") {
  renv_dir <- file.path(root, "renv")
  activate <- file.path(renv_dir, "activate.R")
  dir.exists(renv_dir) && file.exists(activate)
}

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

ensure_package_library <- function(root = ".", library = "renv") {
  library <- resolve_library_strategy(library)
  if (identical(library, "renv")) {
    ensure_project_renv(root)
  } else {
    active_package_library()
  }
  invisible(TRUE)
}

call_renv_init <- function(root = ".") {
  old <- setwd(root)
  on.exit(setwd(old), add = TRUE)
  renv::init(project = root, bare = TRUE, load = TRUE, restart = FALSE)
}

call_renv_load <- function(root = ".") {
  renv::load(project = root, quiet = TRUE)
}

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

call_renv_restore <- function(root = ".") {
  old <- setwd(root)
  on.exit(setwd(old), add = TRUE)
  configure_boosterpak_repositories(verbose = FALSE)
  configure_boosterpak_install_policy(verbose = FALSE)
  renv::restore(project = root, prompt = FALSE)
}

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

install_pak_via_renv <- function(root = ".") {
  old <- setwd(root)
  on.exit(setwd(old), add = TRUE)
  configure_boosterpak_repositories(verbose = FALSE)
  configure_boosterpak_install_policy(verbose = FALSE)
  renv::install("pak", prompt = FALSE)
  invisible("pak")
}

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

plain_missing_packages <- function(packages, install_specs, missing) {
  missing_specs <- install_specs[packages %in% missing]
  missing_packages <- packages[packages %in% missing]
  missing_packages[missing_specs == missing_packages]
}

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
