#' Initialize a boosterpak project
#'
#' @param root Project root.
#' @param renv Whether to initialize project-local renv: `"ask"`, `"yes"`, or `"no"`.
#' @param rprofile Whether to add the helper auto-source line to `.Rprofile`.
#' @param verbose Whether to print routine summaries.
#' @return Project setup paths, invisibly.
#' @export
init <- function(root = ".", renv = c("ask", "yes", "no"), rprofile = c("ask", "yes", "no"), verbose = NULL) {
  check_verbose(verbose)
  renv <- match.arg(renv)
  rprofile <- match.arg(rprofile)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)

  dir.create(project_packs_dir(root), recursive = TRUE, showWarnings = FALSE)

  config_path <- boosters_file(root)
  wrote_config <- FALSE
  if (!file.exists(config_path)) {
    write_default_config(root)
    wrote_config <- TRUE
  } else {
    repair_self_extra(config_path)
  }

  config <- read_config(root)

  if (isTRUE(config$settings$air_toml) && !file.exists(file.path(root, "air.toml"))) {
    writeLines(c("# air formatter configuration", ""), file.path(root, "air.toml"), useBytes = TRUE)
  }
  materialize_config_packs(config, root)

  if (identical(renv, "no")) {
    renv_ready <- FALSE
  } else if (!is_project_renv_active(root)) {
    renv_ready <- handle_renv_init(root, renv)
  } else {
    renv_ready <- TRUE
  }
  if (isTRUE(renv_ready)) {
    bootstrap_project_renv(root, config)
  }

  changed_rprofile <- ensure_rprofile_line(root, rprofile)

  if (should_emit(verbose)) {
    if (wrote_config) cli::cli_alert_success("Wrote {.file boosters.toml}.")
    if (isTRUE(changed_rprofile)) cli::cli_alert_success("Updated {.file .Rprofile}.")
  }

  invisible(list(config = config_path, rprofile_changed = changed_rprofile))
}

repair_self_extra <- function(path) {
  lines <- readLines(path, warn = FALSE)
  extras_start <- grep("^\\s*\\[extras\\]\\s*(#.*)?$", lines)
  if (length(extras_start) == 0) {
    return(invisible(FALSE))
  }

  start <- extras_start[[1]]
  next_section <- grep("^\\s*\\[[^]]+\\]\\s*(#.*)?$", lines)
  next_section <- next_section[next_section > start]
  end <- if (length(next_section) > 0) next_section[[1]] - 1L else length(lines)
  section <- lines[start:end]
  declared_rel <- grep("^\\s*declared\\s*=", section)
  if (length(declared_rel) != 1) {
    return(invisible(FALSE))
  }

  declared_idx <- start + declared_rel[[1]] - 1L
  declared_line <- lines[[declared_idx]]
  array_match <- regexec("^(\\s*declared\\s*=\\s*)\\[(.*)\\](\\s*(#.*)?)$", declared_line)
  parts <- regmatches(declared_line, array_match)[[1]]
  if (length(parts) == 0) {
    cli::cli_alert_info("Leaving existing {.file boosters.toml} unchanged; [extras].declared is not a generated single-line array.")
    return(invisible(FALSE))
  }

  existing <- parse_toml_string_array_literal(parts[[3]])
  if (is.null(existing)) {
    cli::cli_alert_info("Leaving existing {.file boosters.toml} unchanged; [extras].declared is custom TOML.")
    return(invisible(FALSE))
  }
  if ("boosterpak" %in% vapply(existing, package_name_from_spec, character(1), USE.NAMES = FALSE)) {
    return(invisible(FALSE))
  }

  next_values <- c(existing, self_install_spec())
  rendered <- paste(sprintf('"%s"', vapply(next_values, escape_toml_string, character(1))), collapse = ", ")
  lines[[declared_idx]] <- sprintf("%s[%s]%s", parts[[2]], rendered, parts[[4]])
  writeLines(lines, path, useBytes = TRUE)
  invisible(TRUE)
}

parse_toml_string_array_literal <- function(x) {
  x <- trimws(x)
  if (!nzchar(x)) {
    return(character())
  }
  parsed <- tryCatch(toml::parse_toml(paste0("declared = [", x, "]"))$declared, error = function(err) NULL)
  if (is.null(parsed) || !is.character(parsed)) {
    return(NULL)
  }
  parsed
}

handle_renv_init <- function(root, renv) {
  if (identical(renv, "no")) {
    return(invisible(FALSE))
  }
  if (identical(renv, "ask")) {
    if (!interactive()) {
      cli::cli_alert_info("No project-local renv found. Use {.code renv = 'yes'} to initialize one.")
      return(invisible(FALSE))
    }
    answer <- utils::menu(c("Yes", "No"), title = "Initialize project-local renv now?")
    if (!identical(answer, 1L)) {
      return(invisible(FALSE))
    }
  }
  if (has_project_renv(root)) {
    call_renv_load(root)
  } else {
    call_renv_init(root)
  }
  invisible(TRUE)
}

bootstrap_project_renv <- function(root, config) {
  package_names <- c("pak", "renv", "boosterpak")
  install_specs <- c("pak", "renv", self_install_spec())
  names(install_specs) <- package_names

  missing <- missing_packages(package_names, root)
  install_via(unname(install_specs[missing]), root)

  if (isTRUE(config$settings$auto_snapshot %||% TRUE)) {
    call_renv_snapshot(root, package_names)
  }

  invisible(package_names)
}
