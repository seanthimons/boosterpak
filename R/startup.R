posit_package_manager_repo <- function() {
  Sys.getenv(
    "BOOSTERPAK_PPM_REPO",
    unset = "https://packagemanager.posit.co/cran/latest"
  )
}

should_configure_repositories <- function() {
  env <- Sys.getenv("BOOSTERPAK_CONFIGURE_REPOSITORIES", unset = NA_character_)
  if (!is.na(env)) {
    return(!tolower(env) %in% c("0", "false", "no", "off"))
  }
  isTRUE(getOption("boosterpak.configure_repositories", TRUE))
}

should_configure_install_policy <- function() {
  env <- Sys.getenv("BOOSTERPAK_CONFIGURE_INSTALL_POLICY", unset = NA_character_)
  if (!is.na(env)) {
    return(!tolower(env) %in% c("0", "false", "no", "off"))
  }
  isTRUE(getOption("boosterpak.configure_install_policy", TRUE))
}

boosterpak_install_policy_options <- function() {
  list(
    renv.config.pak.enabled = TRUE,
    renv.config.ppm.enabled = TRUE,
    install.packages.compile.from.source = "never",
    install.packages.check.source = "no"
  )
}

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

normalize_cran_mirror <- function(x) {
  x <- trimws(x)
  x <- sub("/+$", "", x)
  url <- !is.na(x) & grepl("^[A-Za-z][A-Za-z0-9+.-]*://", x)
  x[url] <- vapply(x[url], function(mirror) {
    parts <- regexec("^([A-Za-z][A-Za-z0-9+.-]*://)([^/?#]*)(.*)$", mirror)
    matches <- regmatches(mirror, parts)[[1]]
    if (length(matches) == 0) {
      return(mirror)
    }
    paste0(tolower(matches[[2]]), tolower(matches[[3]]), matches[[4]])
  }, character(1))
  x
}

is_default_cran_mirror <- function(repo) {
  if (length(repo) != 1 || is.na(repo) || !nzchar(repo)) {
    return(FALSE)
  }
  normalize_cran_mirror(repo) %in%
    normalize_cran_mirror(default_cran_mirrors())
}

uses_default_cran_repo <- function(repos) {
  if (is.null(repos) || length(repos) == 0) {
    return(TRUE)
  }
  if (!"CRAN" %in% names(repos)) {
    return(FALSE)
  }
  is_default_cran_mirror(unname(repos[["CRAN"]]))
}

uses_posit_package_manager <- function(repos) {
  if (is.null(repos) || length(repos) == 0) {
    return(FALSE)
  }
  any(
    grepl("packagemanager\\.(posit|rstudio)\\.co", unname(repos)),
    na.rm = TRUE
  )
}

repo_names_missing <- function(repos) {
  repo_names <- names(repos)
  is.null(repo_names) || any(is.na(repo_names) | !nzchar(repo_names))
}

renv_repos_override_is_unset <- function() {
  is.null(getOption("renv.config.repos.override")) &&
    !nzchar(Sys.getenv("RENV_CONFIG_REPOS_OVERRIDE", unset = ""))
}

format_repos_override <- function(repos) {
  if (repo_names_missing(repos)) {
    return(unname(repos[[1]]))
  }
  paste(sprintf("%s=%s", names(repos), unname(repos)), collapse = ";")
}

escape_r_string <- function(x) {
  x <- gsub("\\\\", "\\\\\\\\", x)
  gsub('"', '\\"', x, fixed = TRUE)
}

rprofile_repo_name <- function(name) {
  escaped <- escape_r_string(name)
  if (identical(make.names(name), name)) {
    return(escaped)
  }
  sprintf('"%s"', escaped)
}

rprofile_repository_marker <- function() {
  "# Configure boosterpak package repositories."
}

rprofile_install_policy_marker <- function() {
  "# Configure boosterpak package installation."
}

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

rprofile_repository_lines <- function(repos, include_renv = TRUE) {
  lines <- c(
    rprofile_repository_marker(),
    sprintf("options(repos = c(%s))", rprofile_repos_value(repos))
  )
  if (isTRUE(include_renv)) {
    lines <- c(
      lines,
      sprintf(
        'options(renv.config.repos.override = "%s")',
        escape_r_string(format_repos_override(repos))
      )
    )
  }
  lines
}

boosterpak_install_policy_lines_for_session <- function(changes = character()) {
  if (!should_configure_install_policy()) {
    return(character())
  }
  rprofile_install_policy_lines()
}

boosterpak_repository_lines_for_session <- function(changes = character()) {
  if (!should_configure_repositories()) {
    return(character())
  }
  repos <- getOption("repos")
  if (!uses_posit_package_manager(repos)) {
    return(character())
  }
  include_renv <- "renv" %in% changes ||
    identical(
      getOption("renv.config.repos.override"),
      format_repos_override(repos)
    )
  rprofile_repository_lines(repos, include_renv = include_renv)
}

boosterpak_rprofile_setup_lines <- function(repository_changes = character(), install_policy_changes = character()) {
  c(
    boosterpak_install_policy_lines_for_session(install_policy_changes),
    boosterpak_repository_lines_for_session(repository_changes)
  )
}

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
    options(renv.config.repos.override = format_repos_override(getOption("repos")))
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
