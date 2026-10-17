#' Get the Posit Package Manager Repository
#'
#' @return The configured Posit Package Manager repository URL.
#' @noRd
posit_package_manager_repo <- function() {
  Sys.getenv(
    "BOOSTERPAK_PPM_REPO",
    unset = "https://packagemanager.posit.co/cran/latest"
  )
}

#' Check for a glibc Linux R Build
#'
#' @return `TRUE` when R runs on glibc Linux, where Posit Package Manager's
#'   manylinux binaries apply.
#' @noRd
is_glibc_linux <- function() {
  identical(R.version$os, "linux-gnu")
}

#' Get the Default Posit Package Manager Hosts
#'
#' @return A character vector of public Posit Package Manager host names.
#' @noRd
ppm_default_hosts <- function() {
  c("packagemanager.posit.co", "packagemanager.rstudio.com", "p3m.dev")
}

#' Normalize a Package Manager Host
#'
#' @param x A character vector of hosts or URLs.
#' @return `x` lowercased, with any scheme, credentials, and path removed.
#'   Entries that are not a host name with an optional port become `NA`.
#' @noRd
normalize_ppm_host <- function(x) {
  x <- tolower(trimws(x))
  x <- sub("^[a-z][a-z0-9+.-]*://", "", x)
  x <- sub("[/?#].*$", "", x)
  x <- sub("^.*@", "", x)
  x[!grepl("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:[0-9]+)?$", x)] <- NA_character_
  x
}

# Invalid host entries already reported, so each warns once per session.
ppm_state <- new.env(parent = emptyenv())

#' Get Additional Package Manager Hosts
#'
#' Combines the host of `BOOSTERPAK_PPM_REPO` with the hosts listed in
#' `options(boosterpak.ppm_hosts = c(...))` and `BOOSTERPAK_PPM_HOSTS`
#' (separated by commas, semicolons, or whitespace).
#'
#' @return A character vector of normalized host names.
#' @noRd
ppm_extra_hosts <- function() {
  listed <- c(
    getOption("boosterpak.ppm_hosts", character()),
    strsplit(Sys.getenv("BOOSTERPAK_PPM_HOSTS", unset = ""), "[,;[:space:]]+")[[1]]
  )
  listed <- as.character(listed)
  listed <- listed[!is.na(listed) & nzchar(listed)]
  hosts <- normalize_ppm_host(listed)
  invalid <- setdiff(listed[is.na(hosts)], ppm_state$warned)
  if (length(invalid) > 0) {
    ppm_state$warned <- c(ppm_state$warned, invalid)
    cli::cli_warn(c(
      "Ignoring invalid Package Manager host{?s}: {.val {invalid}}.",
      "i" = "Use host names such as {.val ppm.example.com} or {.val ppm.example.com:8080}."
    ))
  }
  repo_host <- normalize_ppm_host(Sys.getenv("BOOSTERPAK_PPM_REPO", unset = ""))
  hosts <- c(hosts, repo_host)
  unique(hosts[!is.na(hosts)])
}

#' Get All Recognized Package Manager Hosts
#'
#' @return A character vector of public and user-configured host names.
#' @noRd
ppm_hosts <- function() {
  unique(c(ppm_default_hosts(), ppm_extra_hosts()))
}

#' Build the Package Manager Host Pattern
#'
#' Every host is a literal, so the pattern is a flat alternation with no
#' capture groups. The generated `.Rprofile` line inlines the result because it
#' runs before boosterpak loads.
#'
#' @return A regular expression alternation matching any recognized host.
#' @noRd
ppm_host_pattern <- function() {
  paste(escape_regex(ppm_hosts()), collapse = "|")
}

#' Check Whether Repositories Are Package Manager Repositories
#'
#' @param repos A character vector of repository URLs.
#' @return A logical vector the length of `repos`.
#' @noRd
is_ppm_repo <- function(repos) {
  grepl(
    sprintf("^https?://(%s)(/|$)", ppm_host_pattern()),
    unname(repos),
    ignore.case = TRUE
  )
}

#' Build the Package Manager Snapshot URL Pattern
#'
#' Matches `<host>/<repo>/<latest|YYYY-MM-DD>`. Distro-specific URLs such as
#' `<host>/cran/__linux__/noble/latest` have more path segments and do not
#' match. Group 1 is the repository URL and group 3 is the snapshot.
#'
#' @return A regular expression.
#' @noRd
ppm_snapshot_pattern <- function() {
  sprintf(
    "^(https?://(%s)/[^/]+)/(latest|[0-9]{4}-[0-9]{2}-[0-9]{2})$",
    ppm_host_pattern()
  )
}

#' Build the Package Manager Binary URL Pattern
#'
#' @return A regular expression matching the manylinux repository prefix.
#' @noRd
ppm_manylinux_pattern <- function() {
  sprintf(
    "^(https?://(%s)/[^/]+)/__linux__/manylinux_2_28/",
    ppm_host_pattern()
  )
}

#' Build the Linux Binary Repository Options Call
#'
#' The generic Posit Package Manager URL only serves Linux binaries on distros
#' it recognizes, so on glibc Linux the `<repo>/<snapshot>` URLs are rewritten
#' to the manylinux binary URL and the R user agent Package Manager requires is
#' set. The persisted repository URLs stay generic so a shared `.Rprofile`
#' works on every platform.
#'
#' @param include_renv Whether to rewrite the renv repository override.
#' @return A character scalar containing an R `options()` call.
#' @noRd
ppm_linux_binary_options_code <- function(include_renv = TRUE) {
  # ponytail: manylinux_2_28 for every glibc distro; per-distro URLs (as pak
  # picks) would need Package Manager's platform list at startup.
  rewrite <- function(option) {
    sprintf(
      'sub("%s", "%s", getOption("%s"), ignore.case = TRUE)',
      escape_r_string(ppm_snapshot_pattern()),
      escape_r_string("\\1/__linux__/manylinux_2_28/\\3"),
      option
    )
  }
  args <- c(
    sprintf("repos = %s", rewrite("repos")),
    if (isTRUE(include_renv)) {
      sprintf(
        "renv.config.repos.override = %s",
        rewrite("renv.config.repos.override")
      )
    },
    sprintf(
      'HTTPUserAgent = sprintf("R/%%s R (%%s)", getRversion(), %s)',
      ppm_platform_code()
    ),
    ppm_download_extra_code()
  )
  sprintf("options(%s)", paste(args, collapse = ", "))
}

#' Build the R Platform String Code
#'
#' @return R code evaluating to the platform description Package Manager
#'   expects in the `User-Agent` header.
#' @noRd
ppm_platform_code <- function() {
  "paste(getRversion(), R.version$platform, R.version$arch, R.version$os)"
}

#' Build the `download.file.extra` Option Code
#'
#' The `curl` and `wget` download methods ignore `HTTPUserAgent`, so Package
#' Manager only sees the R user agent if it is passed as a header. The header
#' is appended to any existing `download.file.extra` value and skipped when a
#' user agent is already set, so it is never duplicated or overwritten. For
#' every other download method the option keeps its current value.
#'
#' @return A character scalar containing the `download.file.extra` argument for
#'   an R `options()` call.
#' @noRd
ppm_download_extra_code <- function() {
  paste0(
    'download.file.extra = if (isTRUE(getOption("download.file.method") ',
    '%in% c("curl", "wget")) && !any(grepl("user-agent", ',
    'getOption("download.file.extra"), ignore.case = TRUE))) ',
    'paste(c(getOption("download.file.extra"), ',
    "sprintf('--header \"User-Agent: R (%s)\"', ",
    ppm_platform_code(),
    ')), collapse = " ") else getOption("download.file.extra")'
  )
}

#' Build the Repository Opt-Out Guard
#'
#' @return R code that is `TRUE` unless `BOOSTERPAK_CONFIGURE_REPOSITORIES`
#'   turns repository setup off.
#' @noRd
rprofile_repositories_enabled_code <- function() {
  '!tolower(Sys.getenv("BOOSTERPAK_CONFIGURE_REPOSITORIES", "true")) %in% c("0", "false", "no", "off")'
}

#' Build the Linux Binary Repository R Profile Line
#'
#' The line is guarded to glibc Linux and honors
#' `BOOSTERPAK_CONFIGURE_REPOSITORIES=false`, so the opt-out also works for
#' projects whose `.Rprofile` already contains it.
#'
#' When `renv_ppm` is `TRUE`, the line also requires renv's Package Manager
#' handling to be on. Then `renv::snapshot()` strips the `__linux__` segment
#' again. With it off, snapshot would write the manylinux URL into `renv.lock`.
#' The check calls renv's own resolver, which also reads project settings and
#' environment variables. It sits inside `tryCatch()` because this line runs
#' from `.Rprofile`, where a missing or changed renv must not abort startup.
#'
#' `renv:::renv_ppm_enabled()` is an internal renv function, not a public API.
#' If a future renv removes or renames it, the lookup errors, `tryCatch()`
#' returns `FALSE`, and the rewrite is skipped. That fails closed, so the
#' lockfile stays generic. The `isNamespaceLoaded("renv")` check runs first so
#' the line never loads renv from the user library as a side effect; renv is
#' already loaded by then because `renv/activate.R` has run.
#'
#' @param include_renv Whether to rewrite the renv repository override.
#' @param renv_ppm Whether to require renv's Package Manager handling to be on.
#' @return A character scalar containing the guarded `.Rprofile` line.
#' @noRd
rprofile_ppm_linux_binary_line <- function(include_renv = TRUE, renv_ppm = FALSE) {
  guards <- c(
    'identical(R.version$os, "linux-gnu")',
    if (isTRUE(renv_ppm)) {
      'isNamespaceLoaded("renv") && isTRUE(tryCatch(renv:::renv_ppm_enabled(), error = function(e) FALSE))'
    },
    rprofile_repositories_enabled_code()
  )
  paste0(
    "if (",
    paste(guards, collapse = " && "),
    ") ",
    ppm_linux_binary_options_code(include_renv)
  )
}

#' Use Posit Package Manager Linux Binaries in the Current Session
#'
#' @return `TRUE` invisibly when options were applied, otherwise `FALSE`.
#' @noRd
use_ppm_linux_binaries <- function() {
  if (!is_glibc_linux() || !uses_posit_package_manager(getOption("repos"))) {
    return(invisible(FALSE))
  }
  include_renv <- !is.null(getOption("renv.config.repos.override"))
  eval(str2lang(ppm_linux_binary_options_code(include_renv)), baseenv())
  invisible(TRUE)
}

#' Convert Linux Binary Repository URLs to Generic URLs
#'
#' @param repos A character vector of repository values.
#' @return `repos` with manylinux Posit Package Manager URLs made generic.
#' @noRd
portable_ppm_repos <- function(repos) {
  sub(ppm_manylinux_pattern(), "\\1/", repos, ignore.case = TRUE)
}

#' Check Whether to Configure Repositories
#'
#' @return `TRUE` if boosterpak should configure package repositories.
#' @noRd
should_configure_repositories <- function() {
  env <- Sys.getenv("BOOSTERPAK_CONFIGURE_REPOSITORIES", unset = NA_character_)
  if (!is.na(env)) {
    return(!tolower(env) %in% c("0", "false", "no", "off"))
  }
  isTRUE(getOption("boosterpak.configure_repositories", TRUE))
}

#' Check Whether to Configure the Install Policy
#'
#' @return `TRUE` if boosterpak should configure package installation options.
#' @noRd
should_configure_install_policy <- function() {
  env <- Sys.getenv(
    "BOOSTERPAK_CONFIGURE_INSTALL_POLICY",
    unset = NA_character_
  )
  if (!is.na(env)) {
    return(!tolower(env) %in% c("0", "false", "no", "off"))
  }
  isTRUE(getOption("boosterpak.configure_install_policy", TRUE))
}

#' Get Boosterpak Install Policy Options
#'
#' @return A named list of package installation option values. Setting
#'   `install.packages.compile.from.source` only matters when
#'   `install.packages()` runs with `type = "both"` (the default on Windows and
#'   macOS). R's default `pkgType` on Linux is `"source"`, so the option has no
#'   effect there.
#' @noRd
boosterpak_install_policy_options <- function() {
  list(
    renv.config.pak.enabled = TRUE,
    renv.config.ppm.enabled = TRUE,
    install.packages.compile.from.source = "never",
    install.packages.check.source = "no"
  )
}

#' Configure the Boosterpak Install Policy
#'
#' @param verbose Whether to report changed options.
#' @return A character vector of changed option names, invisibly.
#' @noRd
configure_boosterpak_install_policy <- function(verbose = TRUE) {
  if (!should_configure_install_policy()) {
    return(invisible(character()))
  }

  desired <- boosterpak_install_policy_options()
  changed <- character()
  for (name in names(desired)) {
    if (!identical(getOption(name), desired[[name]])) {
      options(structure(list(desired[[name]]), names = name))
      changed <- c(changed, name)
    }
  }

  if (isTRUE(verbose) && length(changed) > 0) {
    cli::cli_inform(c(
      "i" = "boosterpak is configuring package installs to prefer pak. On Windows and macOS, it also avoids compiling from source when binaries are available.",
      " " = "renv pak backend: {getOption('renv.config.pak.enabled')}",
      " " = "compile from source: {getOption('install.packages.compile.from.source')}"
    ))
  }

  invisible(changed)
}

#' Get the Built-In Default CRAN Mirrors
#'
#' These are the mirror values R and RStudio write by default. They are
#' literals, so the generated `.Rprofile` line can embed exactly this list.
#'
#' @return A character vector of built-in default CRAN mirror values.
#' @noRd
built_in_cran_mirrors <- function() {
  c(
    "@CRAN@",
    "https://cloud.r-project.org",
    "https://cran.rstudio.com",
    "https://cran.r-project.org"
  )
}

#' Get Default-Like CRAN Mirrors
#'
#' @return A character vector of repository values treated as default CRAN
#'   mirrors.
#' @noRd
default_cran_mirrors <- function() {
  env <- Sys.getenv("BOOSTERPAK_DEFAULT_CRAN_MIRRORS", unset = "")
  env_mirrors <- if (nzchar(env)) {
    trimws(strsplit(env, ";", fixed = TRUE)[[1]])
  } else {
    character()
  }
  mirrors <- c(
    built_in_cran_mirrors(),
    getOption("boosterpak.default_cran_mirrors", character()),
    env_mirrors
  )
  mirrors[!is.na(mirrors) & nzchar(mirrors)]
}

#' Normalize CRAN Mirror Values
#'
#' @param x Character vector of repository values.
#' @return A character vector with trailing slashes removed and URL schemes and
#'   hosts normalized to lowercase.
#' @noRd
normalize_cran_mirror <- function(x) {
  x <- trimws(x)
  x <- sub("/+$", "", x)
  url <- !is.na(x) & grepl("^[A-Za-z][A-Za-z0-9+.-]*://", x)
  x[url] <- vapply(
    x[url],
    function(mirror) {
      parts <- regexec("^([A-Za-z][A-Za-z0-9+.-]*://)([^/?#]*)(.*)$", mirror)
      matches <- regmatches(mirror, parts)[[1]]
      if (length(matches) == 0) {
        return(mirror)
      }
      paste0(tolower(matches[[2]]), tolower(matches[[3]]), matches[[4]])
    },
    character(1)
  )
  x
}

#' Check for a Default CRAN Mirror
#'
#' @param repo A single repository value.
#' @return `TRUE` if `repo` is a recognized default CRAN mirror.
#' @noRd
is_default_cran_mirror <- function(repo) {
  if (length(repo) != 1 || is.na(repo) || !nzchar(repo)) {
    return(FALSE)
  }
  normalize_cran_mirror(repo) %in%
    normalize_cran_mirror(default_cran_mirrors())
}

#' Check Whether Repositories Use the Default CRAN Mirror
#'
#' @param repos A named character vector of repositories, or `NULL`.
#' @return `TRUE` if the CRAN repository is unset or uses a recognized default.
#' @noRd
uses_default_cran_repo <- function(repos) {
  if (is.null(repos) || length(repos) == 0) {
    return(TRUE)
  }
  if (!"CRAN" %in% names(repos)) {
    return(FALSE)
  }
  is_default_cran_mirror(unname(repos[["CRAN"]]))
}

#' Check Whether Repositories Use Posit Package Manager
#'
#' @param repos A character vector of repositories, or `NULL`.
#' @return `TRUE` if any repository uses a Posit Package Manager host.
#' @noRd
uses_posit_package_manager <- function(repos) {
  if (is.null(repos) || length(repos) == 0) {
    return(FALSE)
  }
  any(is_ppm_repo(repos), na.rm = TRUE)
}

#' Check for Missing Repository Names
#'
#' @param repos A repository vector.
#' @return `TRUE` if repository names are absent, missing, or empty.
#' @noRd
repo_names_missing <- function(repos) {
  repo_names <- names(repos)
  is.null(repo_names) || any(is.na(repo_names) | !nzchar(repo_names))
}

#' Check Whether the Renv Repository Override Is Unset
#'
#' @return `TRUE` if neither the option nor environment variable sets a
#'   repository override for renv.
#' @noRd
renv_repos_override_is_unset <- function() {
  is.null(getOption("renv.config.repos.override")) &&
    !nzchar(Sys.getenv("RENV_CONFIG_REPOS_OVERRIDE", unset = ""))
}

#' Escape Text for an R String Literal
#'
#' @param x Character vector to escape.
#' @return The escaped character vector.
#' @noRd
escape_r_string <- function(x) {
  x <- gsub("\\\\", "\\\\\\\\", x)
  gsub('"', '\\"', x, fixed = TRUE)
}

#' Escape Text for a Regular Expression
#'
#' @param x Character vector to escape.
#' @return `x` with every regular expression metacharacter escaped.
#' @noRd
escape_regex <- function(x) {
  gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", x)
}

#' Format a Repository Name for an R Profile
#'
#' @param name A single repository name.
#' @return The escaped name, quoted when it is not syntactic.
#' @noRd
rprofile_repo_name <- function(name) {
  escaped <- escape_r_string(name)
  if (identical(make.names(name), name)) {
    return(escaped)
  }
  sprintf('"%s"', escaped)
}

#' Get the Repository Setup Marker
#'
#' @return The repository setup marker line.
#' @noRd
rprofile_repository_marker <- function() {
  "# Configure boosterpak package repositories."
}

#' Get the Install Policy Marker
#'
#' @return The install policy marker line.
#' @noRd
rprofile_install_policy_marker <- function() {
  "# Configure boosterpak package installation."
}

#' Format an R Profile Option Value
#'
#' @param value A scalar logical or character option value.
#' @return A character scalar containing R code for `value`.
#' @noRd
rprofile_option_value <- function(value) {
  if (identical(value, TRUE)) {
    return("TRUE")
  }
  if (identical(value, FALSE)) {
    return("FALSE")
  }
  if (is.character(value) && length(value) == 1) {
    return(sprintf('"%s"', escape_r_string(value)))
  }
  stop("Unsupported .Rprofile option value.", call. = FALSE)
}

#' Build Install Policy R Profile Lines
#'
#' @return A character vector of install policy setup lines.
#' @noRd
rprofile_install_policy_lines <- function() {
  options <- boosterpak_install_policy_options()
  c(
    rprofile_install_policy_marker(),
    sprintf(
      "options(%s = %s)",
      names(options),
      vapply(options, rprofile_option_value, character(1))
    )
  )
}

#' Format Repositories for an R Profile
#'
#' @param repos A character vector of repository values, optionally named.
#' @return A character scalar containing the entries for an R `c()` call.
#' @noRd
rprofile_repos_value <- function(repos) {
  if (repo_names_missing(repos)) {
    return(paste(
      sprintf(
        '"%s"',
        vapply(unname(repos), escape_r_string, character(1))
      ),
      collapse = ", "
    ))
  }
  repo_names <- names(repos)
  paste(
    sprintf(
      '%s = "%s"',
      vapply(repo_names, rprofile_repo_name, character(1)),
      vapply(unname(repos), escape_r_string, character(1))
    ),
    collapse = ", "
  )
}

#' Build Repository R Profile Lines
#'
#' @param repos A character vector of repository values, optionally named.
#' @param include_renv Whether to include the renv repository override option.
#' @return A character vector of repository setup lines.
#' @noRd
rprofile_repository_lines <- function(repos, include_renv = TRUE) {
  repos <- portable_ppm_repos(repos)
  lines <- c(
    rprofile_repository_marker(),
    sprintf("options(repos = c(%s))", rprofile_repos_value(repos))
  )
  if (isTRUE(include_renv)) {
    lines <- c(
      lines,
      sprintf(
        "options(renv.config.repos.override = c(%s))",
        rprofile_repos_value(repos)
      )
    )
  }
  c(lines, rprofile_ppm_linux_binary_line(include_renv))
}

#' Get the Post-Activation Linux Binary Marker
#'
#' @return The marker line that precedes the re-applied Linux binary rewrite.
#' @noRd
rprofile_repository_reapply_marker <- function() {
  "# Re-apply boosterpak Linux binary repositories after renv activation."
}

#' Get the Package Manager CRAN URL to Restore After Activation
#'
#' Matches the `CRAN` value the early repository line writes, so a dated or
#' custom Package Manager URL is restored as it was configured.
#'
#' @param repos A character vector of repository URLs, optionally named.
#' @return The generic `CRAN` URL the early line writes, or `NULL` when `CRAN`
#'   is missing or is not a Package Manager URL.
#' @noRd
ppm_cran_replacement <- function(repos) {
  repos <- portable_ppm_repos(repos)
  if (!"CRAN" %in% names(repos)) {
    return(NULL)
  }
  cran <- unname(repos[["CRAN"]])
  if (is.na(cran) || !is_ppm_repo(cran)) {
    return(NULL)
  }
  cran
}

#' Build the Post-Activation CRAN Default Mirror R Profile Line
#'
#' `renv::load()` can reset a `CRAN` entry to a default mirror such as
#' `https://cran.rstudio.com`. This line puts the Package Manager URL back. It
#' runs on every OS, because the lockfile would otherwise flip between mirrors
#' on different machines. Only the built-in default mirrors are replaced, so a
#' custom mirror or a non-CRAN repository is left alone. The check tolerates a
#' missing `CRAN` name and a trailing slash, and it ignores case, so it matches
#' `is_default_cran_mirror()` for the built-in mirrors. The line runs in
#' `local()` so it leaves no variables in the global environment.
#'
#' @param cran_url The Package Manager URL to restore.
#' @param include_renv Whether to restore the renv repository override too.
#' @return A character scalar containing the guarded `.Rprofile` line.
#' @noRd
rprofile_cran_default_line <- function(cran_url, include_renv = TRUE) {
  options_names <- c(
    "repos",
    if (isTRUE(include_renv)) "renv.config.repos.override"
  )
  guards <- c(
    'isNamespaceLoaded("renv") && isTRUE(tryCatch(renv:::renv_ppm_enabled(), error = function(e) FALSE))',
    rprofile_repositories_enabled_code()
  )
  sprintf(
    paste0(
      "if (%s) local({ for (option in c(%s)) { r <- getOption(option); ",
      'if ("CRAN" %%in%% names(r) && tolower(sub("/+$", "", r[["CRAN"]])) %%in%% c(%s)) { ',
      'r[["CRAN"]] <- "%s"; options(structure(list(r), names = option)) } } })'
    ),
    paste(guards, collapse = " && "),
    paste(sprintf('"%s"', options_names), collapse = ", "),
    paste(sprintf('"%s"', tolower(built_in_cran_mirrors())), collapse = ", "),
    escape_r_string(cran_url)
  )
}

#' Build Post-Activation Linux Binary R Profile Lines
#'
#' `renv/activate.R` calls `renv::load()`, which resets `repos` to the lockfile
#' URLs and undoes the manylinux rewrite made before activation. These lines
#' repeat the rewrite directly after the activation line, but only while renv's
#' Package Manager handling is on. Then `renv::snapshot()` keeps the lockfile
#' URL generic. See `rprofile_ppm_linux_binary_line()`.
#'
#' When `cran_url` is given, a line before the Linux binary line restores it
#' over a default CRAN mirror on every OS. See `rprofile_cran_default_line()`.
#' The Linux line runs second, so it rewrites the restored URL.
#'
#' @param include_renv Whether to rewrite the renv repository override.
#' @param cran_url The Package Manager URL to restore over a default CRAN
#'   mirror, or `NULL` to omit that line.
#' @return A character vector: the marker followed by the guarded `.Rprofile`
#'   lines.
#' @noRd
rprofile_repository_reapply_lines <- function(include_renv = TRUE, cran_url = NULL) {
  c(
    rprofile_repository_reapply_marker(),
    if (!is.null(cran_url)) rprofile_cran_default_line(cran_url, include_renv),
    rprofile_ppm_linux_binary_line(include_renv, renv_ppm = TRUE)
  )
}

#' Build Install Policy Lines for the Current Session
#'
#' @param changes Character vector of options changed in the current session.
#'   Currently unused.
#' @return A character vector of install policy setup lines, or an empty vector
#'   when configuration is disabled.
#' @noRd
boosterpak_install_policy_lines_for_session <- function(changes = character()) {
  if (!should_configure_install_policy()) {
    return(character())
  }
  rprofile_install_policy_lines()
}

#' Build Repository Lines for the Current Session
#'
#' @param changes Character vector identifying repository settings changed in
#'   the current session.
#' @return A character vector of repository setup lines (early lines followed
#'   by the post-activation lines), or an empty vector when repository
#'   configuration is disabled or Posit Package Manager is unused.
#' @noRd
boosterpak_repository_lines_for_session <- function(changes = character()) {
  if (!should_configure_repositories()) {
    return(character())
  }
  repos <- getOption("repos")
  if (!uses_posit_package_manager(repos)) {
    return(character())
  }
  include_renv <- "renv" %in%
    changes ||
    identical(getOption("renv.config.repos.override"), repos)
  c(
    rprofile_repository_lines(repos, include_renv = include_renv),
    rprofile_repository_reapply_lines(
      include_renv = include_renv,
      cran_url = ppm_cran_replacement(repos)
    )
  )
}

#' Build Boosterpak R Profile Setup Lines
#'
#' @param repository_changes Character vector identifying repository settings
#'   changed in the current session.
#' @param install_policy_changes Character vector of install policy options
#'   changed in the current session.
#' @return A character vector of boosterpak setup lines for an R profile.
#' @noRd
boosterpak_rprofile_setup_lines <- function(
  repository_changes = character(),
  install_policy_changes = character()
) {
  c(
    boosterpak_install_policy_lines_for_session(install_policy_changes),
    boosterpak_repository_lines_for_session(repository_changes)
  )
}

#' Configure Boosterpak Repositories
#'
#' @param verbose Whether to report repository changes.
#' @return A character vector identifying changed repository settings,
#'   invisibly.
#' @noRd
configure_boosterpak_repositories <- function(verbose = TRUE) {
  if (!should_configure_repositories()) {
    return(invisible(character()))
  }

  repo <- posit_package_manager_repo()
  repos <- getOption("repos")
  changed <- character()

  if (uses_default_cran_repo(repos)) {
    repos <- repos %||% character()
    repos[["CRAN"]] <- repo
    options(repos = repos)
    changed <- c(changed, "repos")
  }

  if (
    renv_repos_override_is_unset() &&
      (uses_default_cran_repo(getOption("repos")) ||
        uses_posit_package_manager(getOption("repos")))
  ) {
    options(renv.config.repos.override = getOption("repos"))
    changed <- c(changed, "renv")
  }

  use_ppm_linux_binaries()

  if (isTRUE(verbose) && length(changed) > 0) {
    message <- c(
      "i" = "boosterpak is using Posit Package Manager for faster binary package installs when available.",
      " " = "CRAN: {getOption('repos')[['CRAN']]}"
    )
    if (!is.null(getOption("renv.config.repos.override"))) {
      message <- c(
        message,
        " " = "renv restores: {getOption('renv.config.repos.override')}"
      )
    }
    cli::cli_inform(message)
  }

  invisible(changed)
}
