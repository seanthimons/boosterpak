.rescue <- function(root = ".", dry_run = FALSE, verbose = NULL) {
  check_verbose(verbose)
  if (!is.logical(dry_run) || length(dry_run) != 1 || is.na(dry_run)) {
    cli::cli_abort("{.arg dry_run} must be {.code TRUE} or {.code FALSE}.", call = NULL)
  }

  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  if (!file.exists(boosters_file(root))) {
    cli::cli_abort(
      c(
        "{.file boosters.toml} does not exist; {.code boosterpak:::.rescue()} repairs existing boosterpak projects only.",
        "i" = "Use {.code boosterpak::init()} for a new project, or restore {.file boosters.toml} before running rescue."
      ),
      call = NULL
    )
  }

  report <- .rescue_report(root, dry_run)
  repositories <- .rescue_repositories(dry_run, verbose)
  report <- .rescue_merge_report(report, repositories$report)
  report$repository_changes <- repositories$changes

  config <- .rescue_config(root)
  report <- .rescue_merge_report(report, config$report)

  report <- .rescue_rprofile(
    root,
    repository_lines = repositories$lines,
    dry_run = dry_run,
    report = report
  )
  report <- .rescue_core_assets(
    root,
    config = config$config,
    config_valid = config$valid,
    dry_run = dry_run,
    report = report
  )
  report <- .rescue_attach(
    root,
    config_valid = config$valid,
    dry_run = dry_run,
    report = report
  )
  report <- .rescue_workflow_packages(root, dry_run, report)

  .rescue_emit_report(report, verbose)
  invisible(report)
}

.rescue_report <- function(root, dry_run) {
  list(
    root = root,
    dry_run = dry_run,
    actions = character(),
    skipped = character(),
    warnings = character(),
    paths = character(),
    repository_changes = character()
  )
}

.rescue_merge_report <- function(report, other) {
  for (field in c("actions", "skipped", "warnings", "paths")) {
    report[[field]] <- unique(c(report[[field]], other[[field]]))
  }
  report
}

.rescue_add <- function(report, field, values) {
  report[[field]] <- unique(c(report[[field]], values))
  report
}

.rescue_add_path <- function(report, path) {
  .rescue_add(
    report,
    "paths",
    normalizePath(path, winslash = "/", mustWork = FALSE)
  )
}

.rescue_repositories <- function(dry_run, verbose) {
  report <- .rescue_report(root = "", dry_run = dry_run)

  if (isTRUE(dry_run)) {
    old_repos <- getOption("repos")
    old_renv_repos <- getOption("renv.config.repos.override")
    changes <- configure_boosterpak_repositories(verbose = FALSE)
    lines <- boosterpak_repository_lines_for_session(changes)
    options(repos = old_repos)
    options(renv.config.repos.override = old_renv_repos)
  } else {
    changes <- configure_boosterpak_repositories(verbose = should_emit(verbose))
    lines <- boosterpak_repository_lines_for_session(changes)
  }

  if (!should_configure_repositories()) {
    report <- .rescue_add(report, "skipped", "repository configuration skipped: disabled by option or environment.")
  } else if (length(changes) > 0) {
    report <- .rescue_add(
      report,
      "actions",
      if (isTRUE(dry_run)) "would configure boosterpak package repositories." else "configured boosterpak package repositories."
    )
  } else {
    report <- .rescue_add(report, "skipped", "repository configuration already set or intentionally custom.")
  }

  list(report = report, lines = lines, changes = changes)
}

.rescue_config <- function(root) {
  report <- .rescue_report(root, dry_run = FALSE)
  config <- tryCatch(
    read_config(root),
    error = function(err) {
      report <<- .rescue_add(
        report,
        "warnings",
        sprintf("boosters.toml could not be read: %s", conditionMessage(err))
      )
      NULL
    }
  )
  if (is.null(config)) {
    return(list(config = NULL, valid = FALSE, report = report))
  }

  valid <- tryCatch(
    {
      validate_config(config, root)
      TRUE
    },
    error = function(err) {
      report <<- .rescue_add(
        report,
        "warnings",
        sprintf("boosters.toml is not valid for config-dependent repairs: %s", conditionMessage(err))
      )
      FALSE
    }
  )
  list(config = config, valid = valid, report = report)
}

.rescue_rprofile <- function(root, repository_lines, dry_run, report) {
  path <- file.path(root, ".Rprofile")
  existing <- if (file.exists(path)) readLines(path, warn = FALSE) else character()
  planned <- .rescue_rprofile_lines(existing, repository_lines)

  if (!planned$changed) {
    return(.rescue_add(report, "skipped", ".Rprofile startup setup already matches rescue requirements."))
  }

  report <- .rescue_add_path(report, path)
  report <- .rescue_add(
    report,
    "actions",
    if (isTRUE(dry_run)) "would repair .Rprofile startup setup." else "repaired .Rprofile startup setup."
  )
  if (!isTRUE(dry_run)) {
    writeLines(planned$lines, path, useBytes = TRUE)
  }
  report
}

.rescue_rprofile_lines <- function(lines, repository_lines = character()) {
  original <- lines
  lines <- lines[lines != legacy_rprofile_line()]
  lines <- lines[lines != rprofile_line()]

  if (length(repository_lines) > 0) {
    lines <- .rescue_remove_rprofile_repository_block(lines)
    lines <- insert_before_renv_activation(lines, repository_lines)
  }

  lines <- insert_after_renv_activation(lines, rprofile_line())
  list(lines = lines, changed = !identical(original, lines))
}

.rescue_remove_rprofile_repository_block <- function(lines) {
  marker <- rprofile_repository_marker()
  marker_idx <- which(lines == marker)
  if (length(marker_idx) == 0) {
    return(lines)
  }

  keep <- rep(TRUE, length(lines))
  for (idx in marker_idx) {
    keep[[idx]] <- FALSE
    cursor <- idx + 1L
    if (cursor <= length(lines) && grepl("^options\\(repos\\s*=\\s*c\\(", trimws(lines[[cursor]]))) {
      keep[[cursor]] <- FALSE
      cursor <- cursor + 1L
    }
    if (
      cursor <= length(lines) &&
        grepl("^options\\(renv\\.config\\.repos\\.override\\s*=", trimws(lines[[cursor]]))
    ) {
      keep[[cursor]] <- FALSE
    }
  }
  lines[keep]
}

.rescue_core_assets <- function(root, config, config_valid, dry_run, report) {
  report <- .rescue_builtin_pack("core", root, dry_run, report)
  if (!isTRUE(config_valid)) {
    return(.rescue_add(report, "skipped", "declared pack materialization skipped because boosters.toml is invalid."))
  }

  if (isTRUE(dry_run)) {
    return(report)
  }

  before <- .rescue_project_pack_files(root)
  ok <- tryCatch(
    {
      materialize_config_packs(config, root)
      TRUE
    },
    error = function(err) {
      report <<- .rescue_add(
        report,
        "warnings",
        sprintf("declared pack materialization skipped: %s", conditionMessage(err))
      )
      FALSE
    }
  )
  if (!isTRUE(ok)) {
    return(report)
  }

  touched <- setdiff(.rescue_project_pack_files(root), before)
  if (length(touched) > 0) {
    report <- .rescue_add(report, "actions", "materialized declared project pack files.")
    for (path in touched) {
      report <- .rescue_add_path(report, path)
    }
  } else {
    report <- .rescue_add(report, "skipped", "declared project pack files already materialized.")
  }
  report
}

.rescue_builtin_pack <- function(name, root, dry_run, report) {
  source <- system.file("packs", sprintf("%s.toml", name), package = "boosterpak")
  target <- file.path(project_packs_dir(root), sprintf("%s.toml", name))

  if (!nzchar(source)) {
    return(.rescue_add(report, "warnings", sprintf("built-in pack '%s' is unavailable.", name)))
  }
  if (file.exists(target)) {
    return(.rescue_add(report, "skipped", sprintf("built-in pack '%s' already materialized.", name)))
  }

  report <- .rescue_add_path(report, target)
  report <- .rescue_add(
    report,
    "actions",
    if (isTRUE(dry_run)) {
      sprintf("would materialize built-in pack '%s'.", name)
    } else {
      sprintf("materialized built-in pack '%s'.", name)
    }
  )
  if (!isTRUE(dry_run)) {
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    copied <- file.copy(source, target, overwrite = FALSE)
    if (!isTRUE(copied)) {
      cli::cli_abort("Failed to write built-in pack {.val {name}} to {.file {target}}.", call = NULL)
    }
  }
  report
}

.rescue_project_pack_files <- function(root) {
  dir <- project_packs_dir(root)
  if (!dir.exists(dir)) {
    return(character())
  }
  normalizePath(
    list.files(dir, recursive = TRUE, full.names = TRUE),
    winslash = "/",
    mustWork = FALSE
  )
}

.rescue_attach <- function(root, config_valid, dry_run, report) {
  path <- attach_file(root)
  if (!isTRUE(config_valid)) {
    return(.rescue_add(report, "skipped", "attach file rewrite skipped because boosters.toml is invalid."))
  }

  report <- .rescue_add_path(report, path)
  report <- .rescue_add(
    report,
    "actions",
    if (isTRUE(dry_run)) "would rewrite managed boosters/attach.R." else "rewrote managed boosters/attach.R."
  )
  if (!isTRUE(dry_run)) {
    write_attach(root, verbose = FALSE)
  }
  report
}

.rescue_workflow_packages <- function(root, dry_run, report) {
  packages <- c("renv", "pak", "boosterpak")

  if (!has_project_renv(root)) {
    return(.rescue_add(
      report,
      "skipped",
      "workflow package repair skipped: no project renv found; run boosterpak::init(renv = 'yes') to initialize one."
    ))
  }

  if (!is_project_renv_active(root)) {
    if (isTRUE(dry_run)) {
      report <- .rescue_add(report, "actions", "would load project renv.")
    } else {
      loaded <- tryCatch(
        {
          call_renv_load(root)
          TRUE
        },
        error = function(err) {
          report <<- .rescue_add(
            report,
            "warnings",
            sprintf("workflow package repair skipped: project renv could not be loaded: %s", conditionMessage(err))
          )
          FALSE
        }
      )
      if (!isTRUE(loaded)) {
        return(report)
      }
      report <- .rescue_add(report, "actions", "loaded project renv.")
    }
  }

  missing <- tryCatch(
    missing_packages(packages, root),
    error = function(err) {
      report <<- .rescue_add(
        report,
        "warnings",
        sprintf("workflow package repair skipped: project renv library could not be inspected: %s", conditionMessage(err))
      )
      NULL
    }
  )
  if (is.null(missing)) {
    return(report)
  }

  if (isTRUE(dry_run)) {
    if (length(missing) > 0) {
      report <- .rescue_add(
        report,
        "actions",
        sprintf("would install missing workflow packages: %s.", paste(missing, collapse = ", "))
      )
    } else {
      report <- .rescue_add(report, "skipped", "workflow packages already installed.")
    }
    report <- .rescue_add_path(report, file.path(root, "renv.lock"))
    return(.rescue_add(report, "actions", "would snapshot workflow packages with update = TRUE."))
  }

  if (length(missing) > 0) {
    .rescue_install_workflow_packages(root, packages)
    report <- .rescue_add(
      report,
      "actions",
      sprintf("installed missing workflow packages: %s.", paste(missing, collapse = ", "))
    )
  } else {
    report <- .rescue_add(report, "skipped", "workflow packages already installed.")
  }

  report <- .rescue_add_path(report, file.path(root, "renv.lock"))
  call_renv_snapshot(root, packages = packages, update = TRUE)
  .rescue_add(report, "actions", "snapshotted workflow packages with update = TRUE.")
}

.rescue_install_workflow_packages <- function(root, packages) {
  install_specs <- c(
    renv = "renv",
    pak = "pak",
    boosterpak = self_install_spec()
  )
  missing <- missing_packages(packages, root)
  hydrate_via_renv(intersect(missing, c("renv", "pak")), root)
  missing <- missing_packages(packages, root)
  if ("pak" %in% missing) {
    install_pak_via_renv(root)
    missing <- missing_packages(packages, root)
  }
  install_via(unname(install_specs[missing]), root)
  invisible(packages)
}

.rescue_emit_report <- function(report, verbose) {
  if (!should_emit(verbose)) {
    return(invisible(report))
  }

  title <- if (isTRUE(report$dry_run)) "boosterpak rescue dry run" else "boosterpak rescue"
  cli::cli_h1(title)
  for (action in report$actions) {
    cli::cli_alert_success(action)
  }
  for (skipped in report$skipped) {
    cli::cli_alert_info(skipped)
  }
  for (warning in report$warnings) {
    cli::cli_alert_warning(warning)
  }
  invisible(report)
}
