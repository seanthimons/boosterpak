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

uses_default_cran_repo <- function(repos) {
  if (is.null(repos) || length(repos) == 0) {
    return(TRUE)
  }
  if (!"CRAN" %in% names(repos)) {
    return(FALSE)
  }
  identical(unname(repos[["CRAN"]]), "@CRAN@")
}

uses_posit_package_manager <- function(repos) {
  if (is.null(repos) || length(repos) == 0) {
    return(FALSE)
  }
  any(grepl("packagemanager\\.(posit|rstudio)\\.co", unname(repos)))
}

renv_repos_override_is_unset <- function() {
  is.null(getOption("renv.config.repos.override")) &&
    !nzchar(Sys.getenv("RENV_CONFIG_REPOS_OVERRIDE", unset = ""))
}

format_repos_override <- function(repos) {
  if (is.null(names(repos)) || any(!nzchar(names(repos)))) {
    return(unname(repos[[1]]))
  }
  paste(sprintf("%s=%s", names(repos), unname(repos)), collapse = ";")
}

escape_r_string <- function(x) {
  x <- gsub("\\\\", "\\\\\\\\", x)
  gsub('"', '\\"', x, fixed = TRUE)
}

rprofile_repository_marker <- function() {
  "# Configure boosterpak package repositories."
}

rprofile_repos_value <- function(repos) {
  repo_names <- names(repos)
  if (is.null(repo_names) || any(!nzchar(repo_names))) {
    return(paste(
      sprintf(
        '"%s"',
        vapply(unname(repos), escape_r_string, character(1))
      ),
      collapse = ", "
    ))
  }
  paste(
    sprintf(
      '"%s" = "%s"',
      vapply(repo_names, escape_r_string, character(1)),
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
