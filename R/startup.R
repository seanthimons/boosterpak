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
#' @return A named list of package installation option values.
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
      "i" = "boosterpak is configuring package installs to prefer pak and avoid source compilation when binaries are available.",
      " " = "renv pak backend: {getOption('renv.config.pak.enabled')}",
      " " = "compile from source: {getOption('install.packages.compile.from.source')}"
    ))
  }

  invisible(changed)
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
    "@CRAN@",
    "https://cloud.r-project.org",
    "https://cran.rstudio.com",
    "https://cran.r-project.org",
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
  any(
    grepl("packagemanager\\.(posit|rstudio)\\.co", unname(repos)),
    na.rm = TRUE
  )
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
  lines
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
#' @return A character vector of repository setup lines, or an empty vector when
#'   repository configuration is disabled or Posit Package Manager is unused.
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
  rprofile_repository_lines(repos, include_renv = include_renv)
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
