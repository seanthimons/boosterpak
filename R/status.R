#' Report boosterpak project status
#'
#' @param root Project root.
#' @param verbose Whether to print routine summaries.
#' @return A list describing project status, invisibly. Includes config
#'   validity, declared and resolved packs, package and missing-package counts,
#'   attach state, materialized function drift/missing counts, pack catalog
#'   counts, selected package-library strategy and path, renv state, lockfile
#'   presence, and `.Rprofile` hook state.
#'
#'   The attach fields are `attach_enabled`; `attach_packages`, the names of
#'   every attached package, and `attach_package_count`, its length; and
#'   `attach_every_start_count`, the number of those packages attached on every
#'   R start, including workers. `attach_interactive_packages` names the packages
#'   attached only in interactive sessions (`attach_mode = "interactive"` packs).
#'   `attach_sources` is a data frame with one row per attached package and
#'   columns `package`, `pack`, and `interactive`. `pack` names the packs that
#'   requested the package, or `"[attach].declared"` for packages listed in
#'   `boosters.toml`. `interactive` is `TRUE` for interactive-only packages.
#'
#'   `upgrade_needed` is `TRUE` when `boosters.toml` exists and its
#'   `boosters_version` record is missing, unreadable, or older than the
#'   installed boosterpak. Only an older or unreadable record, or an earlier
#'   `.Rprofile` layout, prints a warning. A missing record is reported as
#'   "no version recorded" and prints no warning, because a project created
#'   with `init(rprofile = "no")` has none. A `.Rprofile` with no boosterpak
#'   hook is informational, not a warning. Run `upgrade_project(dry_run = TRUE)`
#'   before `upgrade_project()` when a warning asks for it.
#'
#'   `github_token_visible` is `NA` unless the project declares GitHub sources
#'   (`owner/repo` specifications from `[extras].declared` or from pack
#'   `sources`). Then it is `TRUE` when a token is visible through the
#'   `GITHUB_PAT` or `GITHUB_TOKEN` environment variables or, when the gitcreds
#'   package is installed, through its credential store. The token value is
#'   never returned or printed.
#' @export
status <- function(root = ".", verbose = NULL) {
  check_verbose(verbose)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  config_exists <- file.exists(boosters_file(root))
  valid <- FALSE
  packages <- character()
  packs <- character()
  resolved_packs <- character()
  extras <- character()
  exclude <- character()
  functions <- character()
  function_status <- function_status_frame()
  attach_enabled <- TRUE
  attach_sources <- attach_origin_rows(character(), character())
  library_strategy <- "renv"
  github_token_visible <- NA
  parse_error <- NULL
  if (config_exists) {
    config <- tryCatch(
      read_config(root),
      error = function(err) {
        parse_error <<- conditionMessage(err)
        NULL
      }
    )
    valid <- !is.null(config) &&
      tryCatch(
        {
          validate_config(config, root)
          TRUE
        },
        error = function(err) {
          parse_error <<- conditionMessage(err)
          FALSE
        }
      )
    if (isTRUE(valid)) {
      packages <- resolve_config_packages(config, root)
      packs <- config$packs$declared %||% character()
      resolved_packs <- resolve_config_pack_names(config, root)
      extras <- toml_string_array(
        config$extras$declared %||% character(),
        "[extras].declared"
      )
      exclude <- toml_string_array(
        config$exclude$declared %||% character(),
        "[exclude].declared"
      )
      functions <- installed_functions(config)
      function_status <- collect_function_status(functions, root)
      attach_enabled <- !identical((config$attach %||% list())$enabled, FALSE)
      attach_sources <- resolve_config_attach_sources(config, root)
      library_strategy <- resolve_library_strategy(config = config)
      if (length(github_source_specs(resolve_config_install_specs(config, root))) > 0) {
        github_token_visible <- github_token_is_visible()
      }
    }
  }
  attach_packages <- attach_sources$package
  attach_interactive_packages <- attach_sources$package[attach_sources$interactive]
  upgrade_needed <- project_needs_upgrade(root)
  pack_catalog <- available_packs(root)
  missing <- missing_packages(packages, root, library_strategy)
  out <- list(
    config_exists = config_exists,
    config_valid = valid,
    packs = packs,
    resolved_packs = resolved_packs,
    extras = extras,
    exclude = exclude,
    packages = packages,
    package_count = length(packages),
    missing_packages = missing,
    missing_package_count = length(missing),
    functions = functions,
    function_status = function_status,
    function_count = length(functions),
    function_missing_count = sum(!function_status$exists),
    function_drift_count = sum(
      function_status$exists & !function_status$matches
    ),
    attach_enabled = attach_enabled,
    attach_packages = attach_packages,
    attach_package_count = length(attach_packages),
    attach_every_start_count = sum(!attach_sources$interactive),
    attach_interactive_packages = attach_interactive_packages,
    attach_sources = attach_sources,
    attach_file_exists = file.exists(attach_file(root)),
    upgrade_needed = upgrade_needed,
    github_token_visible = github_token_visible,
    pack_catalog = pack_catalog,
    pack_counts = stats::setNames(
      vapply(
        c("project", "user", "builtin"),
        function(scope) sum(pack_catalog$scope == scope),
        integer(1)
      ),
      c("project", "user", "builtin")
    ),
    library_strategy = library_strategy,
    library_path = package_library(root, library_strategy),
    renv_active = is_project_renv_active(root),
    lockfile_exists = file.exists(file.path(root, "renv.lock")),
    rprofile_hook = has_rprofile_line(root),
    config_error = parse_error
  )
  if (should_emit(verbose)) {
    cli::cli_h1("boosterpak status")
    version_state <- if (isTRUE(out$config_valid)) {
      boosters_version_state(root)
    }
    if (isTRUE(out$config_valid)) {
      # Only an older or unreadable record, or an earlier .Rprofile layout,
      # is a warning. A missing record is reported calmly below.
      reasons <- c(
        if (identical(version_state, "older")) {
          "boosterpak is newer than this project's boosters_version record."
        },
        if (identical(version_state, "invalid")) {
          "boosters.toml has an unreadable boosters_version record."
        },
        if (rprofile_layout_is_old(root)) {
          "The .Rprofile startup hook is from an earlier boosterpak layout."
        }
      )
      if (length(reasons) > 0) {
        cli::cli_alert_warning(paste(
          paste(reasons, collapse = " "),
          "Run {.code boosterpak::upgrade_project(dry_run = TRUE)} first, then {.code boosterpak::upgrade_project()}."
        ))
      }
    }
    cli::cli_li(
      "boosters.toml: {if (out$config_exists) 'present' else 'missing'}"
    )
    cli::cli_li("config valid: {out$config_valid}")
    if (isTRUE(out$config_valid)) {
      version_label <- c(
        current = "matches the installed boosterpak",
        newer = "newer than the installed boosterpak",
        older = "older than the installed boosterpak",
        missing = "no version recorded",
        invalid = "unreadable"
      )[[version_state]]
      cli::cli_li("boosters_version: {version_label}")
    }
    cli::cli_li("renv active: {out$renv_active}")
    cli::cli_li(
      "package library: {out$library_strategy} ({out$library_path})"
    )
    cli::cli_li(
      "renv.lock: {if (out$lockfile_exists) 'present' else 'missing'}"
    )
    cli::cli_li(".Rprofile hook: {out$rprofile_hook}")
    cli::cli_li("declared packs: {format_status_values(out$packs)}")
    cli::cli_li(
      "resolved packages: {out$package_count} ({out$missing_package_count} missing)"
    )
    cli::cli_li(
      "materialized functions: {out$function_count} ({out$function_missing_count} missing, {out$function_drift_count} drifted)"
    )
    if (isTRUE(out$config_valid)) {
      cli::cli_li(
        "startup attach: {out$attach_enabled}, {out$attach_every_start_count} package{?s} on every start, file {if (out$attach_file_exists) 'present' else 'missing'}"
      )
    }
    cli::cli_li(
      "pack catalog: {out$pack_counts[['project']]} project, {out$pack_counts[['user']]} user, {out$pack_counts[['builtin']]} built-in"
    )
    if (isTRUE(out$config_valid) && isTRUE(out$attach_enabled)) {
      every_start <- out$attach_sources[!out$attach_sources$interactive, , drop = FALSE]
      cli::cli_li(
        "attached on every R start (including workers): {out$attach_every_start_count} package{?s}"
      )
      for (i in seq_len(nrow(every_start))) {
        cli::cli_li(
          "{.pkg {every_start$package[[i]]}} from {every_start$pack[[i]]}"
        )
      }
      interactive_count <- length(out$attach_interactive_packages)
      if (interactive_count > 0) {
        interactive_rows <- out$attach_sources[out$attach_sources$interactive, , drop = FALSE]
        cli::cli_li("{interactive_count} more only in interactive sessions")
        for (i in seq_len(nrow(interactive_rows))) {
          cli::cli_li(
            "{.pkg {interactive_rows$package[[i]]}} from {interactive_rows$pack[[i]]}"
          )
        }
      }
      if (!isTRUE(out$rprofile_hook)) {
        # rprofile = "no" is a valid choice, so this is information, not a warning.
        cli::cli_alert_info(
          "No .Rprofile hook is set, so boosters/attach.R is not sourced at startup. init(rprofile = \"yes\") adds it; rprofile = \"no\" is a valid choice."
        )
      }
    } else if (isTRUE(out$config_valid)) {
      cli::cli_li("attached on every R start: disabled ([attach].enabled = false)")
    }
    if (!is.na(out$github_token_visible)) {
      cli::cli_li(
        "GitHub token visible: {out$github_token_visible} (GITHUB_PAT, GITHUB_TOKEN, or gitcreds)"
      )
    }
    if (is_glibc_linux() && isTRUE(out$lockfile_exists)) {
      cli::cli_alert_info(
        'On Linux, check that renv.lock pins have binary packages: {.code boosterpak::check_binary_repos(lockfile = "renv.lock")}'
      )
    }
  }
  invisible(out)
}

#' Find GitHub source specifications
#'
#' GitHub sources are `owner/repo` install specifications, as used in
#' `[extras].declared` and pack `sources`.
#'
#' Only `owner/repo` specifications count, optionally with a `/subdir` and an
#' `@ref`. Other remote prefixes such as `gitlab::`, `bioc::`, or `local::`, URLs,
#' and relative paths are not GitHub sources.
#'
#' @param specs Install specifications for the resolved packages.
#' @return The subset of `specs` that name a GitHub repository.
#' @noRd
github_source_specs <- function(specs) {
  specs[grepl(
    "^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9_.-]+(/[^@]+)?(@.+)?$",
    specs
  )]
}

#' Check whether a GitHub token is visible to this session
#'
#' Checks the `GITHUB_PAT` and `GITHUB_TOKEN` environment variables, then the
#' gitcreds credential store when that package is installed. The token value
#' is never returned.
#'
#' @return `TRUE` or `FALSE`.
#' @noRd
github_token_is_visible <- function() {
  if (nzchar(Sys.getenv("GITHUB_PAT")) || nzchar(Sys.getenv("GITHUB_TOKEN"))) {
    return(TRUE)
  }
  gitcreds_token_is_visible()
}

#' Check the gitcreds credential store for a GitHub token
#'
#' Queries gitcreds with terminal prompting disabled, so the check never asks
#' for credentials. Errors, including a missing package or missing git, count
#' as no token.
#'
#' @return `TRUE` when gitcreds returns a password for github.com, otherwise
#'   `FALSE`.
#' @noRd
gitcreds_token_is_visible <- function() {
  if (!requireNamespace("gitcreds", quietly = TRUE)) {
    return(FALSE)
  }
  old_prompt <- Sys.getenv("GIT_TERMINAL_PROMPT", unset = NA)
  Sys.setenv(GIT_TERMINAL_PROMPT = "0")
  on.exit(
    if (is.na(old_prompt)) {
      Sys.unsetenv("GIT_TERMINAL_PROMPT")
    } else {
      Sys.setenv(GIT_TERMINAL_PROMPT = old_prompt)
    },
    add = TRUE
  )
  creds <- tryCatch(gitcreds_lookup(), error = function(err) NULL)
  is.list(creds) && nzchar(creds[["password"]] %||% "")
}

#' Look up the github.com credential through gitcreds
#'
#' This is the only place that runs `git credential fill`. The test suite
#' replaces it, so no test depends on the developer's credential setup.
#'
#' @return The gitcreds credential list, or `NULL`.
#' @noRd
gitcreds_lookup <- function() {
  gitcreds_get <- utils::getFromNamespace("gitcreds_get", "gitcreds")
  gitcreds_get(url = "https://github.com", use_cache = TRUE, set_cache = FALSE)
}

#' Create an empty function status table
#'
#' @return An empty data frame with function status columns.
#' @noRd
function_status_frame <- function() {
  data.frame(
    name = character(),
    path = character(),
    exists = logical(),
    matches = logical(),
    stringsAsFactors = FALSE
  )
}

#' Collect project function status
#'
#' @param functions Character vector of installed function names.
#' @param root Project root.
#' @return A data frame describing each function's path, existence, and drift.
#' @noRd
collect_function_status <- function(functions, root) {
  rows <- lapply(functions, function(name) {
    local <- function_file(name, root)
    package <- catalog_function_file(name, root)
    exists <- file.exists(local)
    matches <- exists &&
      identical(
        readLines(local, warn = FALSE),
        readLines(package, warn = FALSE)
      )
    data.frame(
      name = name,
      path = local,
      exists = exists,
      matches = matches,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows) %||% function_status_frame()
}

#' Format values for status output
#'
#' @param values Character vector of values to display.
#' @return A comma-separated string, or `"(none)"` for no values.
#' @noRd
format_status_values <- function(values) {
  if (length(values) == 0) {
    "(none)"
  } else {
    paste(values, collapse = ", ")
  }
}
