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

#' Check whether renv's Package Manager handling is on
#'
#' Uses the internal `renv:::renv_ppm_enabled()`, which is not a public API.
#' Any failure reads as "off", so the caller falls back to the generic URL.
#'
#' @return A single logical value.
#' @noRd
renv_ppm_handling_enabled <- function() {
  isTRUE(tryCatch(
    utils::getFromNamespace("renv_ppm_enabled", "renv")(),
    error = function(err) FALSE
  ))
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
  # On glibc Linux the session repos point at the manylinux binary URL. With
  # renv's Package Manager handling on, renv strips that segment from the
  # lockfile's repository URL itself and keeps each package's repository as a
  # name such as "CRAN". Passing the generic URL instead makes renv record the
  # manylinux URL on every package record, because it no longer matches the
  # URL the package was installed from. Only when that handling is off does
  # renv write the URL as given, so pass the generic one then.
  repos <- getOption("repos")
  if (!is.null(repos) && !renv_ppm_handling_enabled()) {
    repos <- portable_ppm_repos(repos)
  }
  result <- renv::snapshot(
    project = root,
    packages = packages,
    repos = repos,
    prompt = FALSE,
    update = update
  )
  tryCatch(
    normalize_lockfile_platform(root),
    error = function(err) {
      cli::cli_warn(c(
        "Could not remove Linux-specific data from {.file renv.lock}.",
        "i" = conditionMessage(err)
      ))
    }
  )
  invisible(result)
}

#' Remove Linux-Specific Data from Lockfile Package Records
#'
#' A lockfile written on Linux should restore on Windows and macOS like one
#' written elsewhere. Packages installed from portable Linux binaries can carry
#' a `Platform` tag, and a record's `Repository` can be a manylinux URL instead
#' of a repository name. This drops the Linux `Platform` tag and maps a
#' `Repository` URL back to the name of the matching lockfile repository, or to
#' the generic Package Manager URL when no repository matches. The lockfile is
#' rewritten only when a record changes.
#'
#' @param root Project root.
#' @return The number of package records that changed, invisibly.
#' @noRd
normalize_lockfile_platform <- function(root = ".") {
  path <- file.path(root, "renv.lock")
  if (!file.exists(path)) {
    return(invisible(0L))
  }
  lock <- renv::lockfile_read(file = path, project = root)
  repositories <- lock$R$Repositories %||% list()
  # renv reads the repositories as a list named by repository.
  repo_names <- names(repositories) %||% character()
  repo_urls <- vapply(repositories, function(url) as.character(url)[[1]], character(1))
  repo_urls <- sub("/+$", "", portable_ppm_repos(repo_urls))

  changed <- 0L
  for (name in names(lock$Packages)) {
    record <- lock$Packages[[name]]
    before <- record

    platform <- record$Platform
    if (is.character(platform) && length(platform) == 1 && grepl("linux", platform, ignore.case = TRUE)) {
      record$Platform <- NULL
    }

    repository <- record$Repository
    if (is.character(repository) && length(repository) == 1 && grepl("^https?://", repository)) {
      generic <- portable_ppm_repos(repository)
      matched <- match(sub("/+$", "", generic), repo_urls)
      record$Repository <- if (!is.na(matched) && nzchar(repo_names[[matched]])) {
        repo_names[[matched]]
      } else {
        generic
      }
    }

    if (!identical(record, before)) {
      lock$Packages[[name]] <- record
      changed <- changed + 1L
    }
  }

  if (changed > 0L) {
    old_options <- options(renv.verbose = FALSE)
    on.exit(options(old_options), add = TRUE)
    renv::lockfile_write(lock, file = path, project = root)
  }
  invisible(changed)
}

#' Read installed package metadata for dependency checks
#'
#' @param root Project root.
#' @param library Package library strategy, either `"renv"` or `"active"`.
#' @return A matrix like [utils::installed.packages()].
#' @noRd
installed_package_db <- function(root = ".", library = "renv") {
  lib <- package_library(root, library)
  lib_loc <- unique(c(lib, .Library, .Library.site))
  utils::installed.packages(
    lib.loc = lib_loc[file.exists(lib_loc)],
    fields = c("Depends", "Imports", "LinkingTo")
  )
}

#' Find missing hard dependencies for installed packages
#'
#' @param packages Character vector of package names to validate.
#' @param root Project root.
#' @param library Package library strategy, either `"renv"` or `"active"`.
#' @return Character vector of missing hard dependency package names.
#' @noRd
missing_hard_dependencies <- function(packages, root = ".", library = "renv") {
  if (length(packages) == 0) {
    return(character())
  }
  db <- installed_package_db(root, library)
  present <- intersect(packages, rownames(db))
  if (length(present) == 0) {
    return(character())
  }
  seen <- character()
  queue <- present
  missing <- character()

  while (length(queue) > 0) {
    package <- queue[[1]]
    queue <- queue[-1]
    if (package %in% seen || !package %in% rownames(db)) {
      next
    }
    seen <- c(seen, package)
    deps <- parse_hard_dependencies(db[package, c("Depends", "Imports", "LinkingTo")])
    missing <- union(missing, setdiff(deps, rownames(db)))
    queue <- c(queue, intersect(deps, rownames(db)))
  }

  missing
}

#' Parse hard dependency package names from DESCRIPTION fields
#'
#' @param fields Character vector of DESCRIPTION fields.
#' @return Character vector of package names excluding `R`.
#' @noRd
parse_hard_dependencies <- function(fields) {
  fields <- fields[!is.na(fields) & nzchar(fields)]
  if (length(fields) == 0) {
    return(character())
  }
  deps <- trimws(unlist(strsplit(fields, ",", fixed = TRUE), use.names = FALSE))
  deps <- sub("\\s*\\(.*$", "", deps)
  deps <- deps[nzchar(deps) & deps != "R"]
  unique(deps)
}

#' Ensure installed packages have a complete hard dependency closure
#'
#' @param packages Character vector of package names to validate.
#' @param root Project root.
#' @param library Package library strategy, either `"renv"` or `"active"`.
#' @return Newly installed dependency package names, invisibly.
#' @noRd
ensure_dependency_closure <- function(packages, root = ".", library = "renv") {
  missing <- missing_hard_dependencies(packages, root, library)
  if (length(missing) == 0) {
    return(invisible(character()))
  }
  install_via(missing, root, library)
  remaining <- missing_hard_dependencies(packages, root, library)
  if (length(remaining) > 0) {
    cli::cli_abort(
      "Required package dependencies are still missing after install: {remaining}.",
      call = NULL
    )
  }
  invisible(missing)
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
  scope_windows_native_tar()
  lockfile <- renv::lockfile_read(project = ".")
  lockfile$Packages <- pin_github_commits(lockfile$Packages)
  lockfile$Packages <- repair_unreachable_index_urls(lockfile$Packages)
  renv::restore(project = root, lockfile = lockfile, prompt = FALSE)
}

#' Make GitHub Package Records Restore at Their Locked Commit
#'
#' renv's pak restore path installs `RemotePkgRef` when a record has one, which
#' for a GitHub package is the branch (`user/repo@branch`) and silently
#' discards the locked `RemoteSha`. Dropping `RemotePkgRef` from GitHub records
#' that have a commit makes renv build the reference from the host, repo,
#' subdirectory and `RemoteSha` instead. The lockfile on disk is not changed.
#'
#' @param records The `Packages` element of a lockfile.
#' @return `records`, with `RemotePkgRef` removed from GitHub records that have
#'   a `RemoteSha`.
#' @noRd
pin_github_commits <- function(records) {
  for (name in names(records)) {
    record <- records[[name]]
    sha <- record$RemoteSha
    if (identical(record$RemoteType, "github") && is.character(sha) && length(sha) == 1 && nzchar(sha)) {
      records[[name]]$RemotePkgRef <- NULL
    }
  }
  records
}

#' Route Around Index Entries That Point at Missing Directories
#'
#' Posit Package Manager's Windows binary index lists some packages (the
#' recommended ones, e.g. `foreign`) a second time with a `Path:` directory
#' that does not exist, and pak can pick that entry, which 404s the restore.
#' For each locked repository package, this looks at the index entries for its
#' locked version and probes the `Path:` directories they use. If one is
#' missing, the record is rewritten to the entry's working URL (same version),
#' or dropped from the lockfile object when no entry works. The lockfile on disk
#' is not changed, and any failure to look up the index leaves `records`
#' untouched.
#'
#' @param records The `Packages` element of a lockfile.
#' @param meta Function returning pak's index metadata for package names.
#' @param url_ok Function returning whether a URL can be opened.
#' @param repos Repository URLs; the first is probed to detect being offline.
#' @return `records`, with affected records rewritten to `url` records or
#'   removed.
#' @noRd
repair_unreachable_index_urls <- function(
  records,
  meta = function(packages) {
    rows <- pak::meta_list(packages)
    if (nrow(rows) == 0) {
      pak::meta_update()
      rows <- pak::meta_list(packages)
    }
    rows
  },
  url_ok = url_reachable,
  repos = getOption("repos")
) {
  from_repo <- vapply(records, function(record) identical(record$Source, "Repository"), logical(1))
  # Offline, a failed probe would look like a missing directory; and pak's
  # index update has no timeout, so check the first repository before asking.
  repos <- repos[nzchar(repos) & !grepl("@CRAN@", repos, fixed = TRUE)]
  if (!any(from_repo) || length(repos) == 0 || !url_ok(paste0(repos[[1]], "/src/contrib/PACKAGES"))) {
    return(records)
  }
  rows <- tryCatch(meta(names(records)[from_repo]), error = function(error) NULL)
  if (is.null(rows) || nrow(rows) == 0) {
    return(records)
  }
  rows <- rows[rows$platform != "source", , drop = FALSE]
  urls <- vapply(rows$sources, function(source) source[[1]], character(1))
  # Only entries filed under an extra `Path:` directory can point nowhere.
  nested <- dirname(rows$target) != rows$repodir
  dirs <- unique(dirname(urls[nested]))
  dir_ok <- vapply(dirs, function(dir) url_ok(paste0(dir, "/PACKAGES")), logical(1))
  broken <- nested & !dirname(urls) %in% dirs[dir_ok]

  repaired <- character()
  dropped <- character()
  for (name in names(records)[from_repo]) {
    same <- rows$package == name & rows$version == records[[name]]$Version
    if (!any(broken & same)) {
      next
    }
    candidates <- urls[same & !broken]
    working <- Find(url_ok, candidates)
    if (is.null(working)) {
      records[[name]] <- NULL
      dropped <- c(dropped, name)
    } else {
      records[[name]] <- list(
        Package = name,
        Version = records[[name]]$Version,
        Source = "URL",
        RemoteType = "url",
        RemoteUrl = working
      )
      repaired <- c(repaired, name)
    }
  }
  if (length(repaired)) {
    cli::cli_inform(c(
      "i" = "Restoring {.pkg {repaired}} from direct URLs: the repository index lists them at a missing directory."
    ))
  }
  if (length(dropped)) {
    cli::cli_warn(c(
      "Skipping {.pkg {dropped}}: the repository index lists them only at a missing directory.",
      i = "Install them separately, or restore again once the repository index is fixed."
    ))
  }
  records
}

#' Check Whether a URL Can Be Opened
#'
#' @param url URL to open.
#' @return `TRUE` if the server answers with a success status.
#' @noRd
url_reachable <- function(url) {
  old <- options(timeout = 10)
  on.exit(options(old), add = TRUE)
  tryCatch(
    {
      connection <- suppressWarnings(url(url, "rb"))
      close(connection)
      TRUE
    },
    error = function(error) FALSE
  )
}

#' Prefer Windows' Native tar for Pak
#'
#' On Windows with Rtools on the PATH, pak's subprocesses run Rtools' GNU tar,
#' which reads a `C:/` archive path as a remote host and fails. pkgdepends then
#' falls back to starting an R process per archive, with no cap. Pointing `TAR`
#' at the built-in `tar.exe` avoids that. renv sets `TAR` to `"internal"` when
#' it is unset, which pkgdepends cannot run, so that counts as unset. Any other
#' `TAR` the user set is left alone, and the prior value is restored on exit.
#' pak reuses its subprocess, so this only helps if it runs before pak starts.
#'
#' @param envir Frame whose exit restores `TAR`.
#' @return The tar path used, or `NULL` when nothing was changed, invisibly.
#' @noRd
scope_windows_native_tar <- function(envir = parent.frame()) {
  old <- Sys.getenv("TAR")
  if (.Platform$OS.type != "windows" || !old %in% c("", "internal")) {
    return(invisible(NULL))
  }
  tar <- file.path(Sys.getenv("SystemRoot", "C:/Windows"), "System32", "tar.exe")
  if (!file.exists(tar)) {
    return(invisible(NULL))
  }
  Sys.setenv(TAR = tar)
  restore <- bquote(if (nzchar(.(old))) Sys.setenv(TAR = .(old)) else Sys.unsetenv("TAR"))
  do.call(on.exit, list(restore, add = TRUE), envir = envir)
  invisible(tar)
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
  tryCatch(
    pak_install_packages(packages, package_library(root, library)),
    error = rethrow_github_rate_limit
  )
  invisible(packages)
}

#' Install Packages with Pak into One Library
#'
#' @param packages Character vector of package specifications to install.
#' @param lib Library path to install into.
#' @return The pak installation result, invisibly.
#' @noRd
pak_install_packages <- function(packages, lib) {
  scope_windows_native_tar()
  invisible(pak::pkg_install(packages, lib = lib, upgrade = FALSE))
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
