.rescue <- function(root = ".", dry_run = FALSE, verbose = NULL) {
  .rescue_check_verbose(verbose)
  if (!is.logical(dry_run) || length(dry_run) != 1 || is.na(dry_run)) {
    .rescue_stop("dry_run must be TRUE or FALSE.")
  }

  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  if (!file.exists(boosters_file(root))) {
    .rescue_stop(
      c(
        "boosters.toml does not exist; boosterpak:::.rescue() repairs existing boosterpak projects only.",
        "Use boosterpak::init() for a new project, or restore boosters.toml before running rescue."
      )
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

.rescue_check_verbose <- function(verbose) {
  if (!is.null(verbose) && !isTRUE(verbose) && !identical(verbose, FALSE)) {
    .rescue_stop("verbose must be NULL, TRUE, or FALSE.")
  }
  invisible(TRUE)
}

.rescue_stop <- function(message) {
  stop(paste(unname(message), collapse = "\n"), call. = FALSE)
}

.rescue_has_package <- function(package) {
  requireNamespace(package, quietly = TRUE)
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
    old_install_policy <- lapply(
      names(boosterpak_install_policy_options()),
      getOption
    )
    names(old_install_policy) <- names(boosterpak_install_policy_options())
    changes <- configure_boosterpak_repositories(verbose = FALSE)
    install_policy_changes <- configure_boosterpak_install_policy(verbose = FALSE)
    lines <- boosterpak_rprofile_setup_lines(changes, install_policy_changes)
    options(repos = old_repos)
    options(renv.config.repos.override = old_renv_repos)
    options(old_install_policy)
  } else {
    changes <- configure_boosterpak_repositories(verbose = FALSE)
    install_policy_changes <- configure_boosterpak_install_policy(verbose = FALSE)
    lines <- boosterpak_rprofile_setup_lines(changes, install_policy_changes)
  }

  if (!should_configure_repositories()) {
    report <- .rescue_add(report, "skipped", "repository configuration skipped: disabled by option or environment.")
  } else if (length(changes) > 0) {
    report <- .rescue_add(
      report,
      "actions",
      if (isTRUE(dry_run)) {
        "would configure boosterpak package repositories."
      } else {
        "configured boosterpak package repositories."
      }
    )
  } else {
    report <- .rescue_add(report, "skipped", "repository configuration already set or intentionally custom.")
  }

  if (!should_configure_install_policy()) {
    report <- .rescue_add(report, "skipped", "package install policy skipped: disabled by option or environment.")
  } else if (length(install_policy_changes) > 0) {
    report <- .rescue_add(
      report,
      "actions",
      if (isTRUE(dry_run)) {
        "would configure boosterpak package install policy."
      } else {
        "configured boosterpak package install policy."
      }
    )
  } else {
    report <- .rescue_add(report, "skipped", "package install policy already set.")
  }

  list(report = report, lines = lines, changes = changes, install_policy_changes = install_policy_changes)
}

.rescue_config <- function(root) {
  report <- .rescue_report(root, dry_run = FALSE)
  config <- tryCatch(
    .rescue_read_config(root),
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
      .rescue_validate_config(config)
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

.rescue_read_config <- function(root) {
  path <- boosters_file(root)
  if (!file.exists(path)) {
    .rescue_stop("boosters.toml does not exist.")
  }
  data <- tryCatch(
    RcppTOML::parseTOML(path),
    error = function(err) {
      .rescue_stop(c(
        sprintf("%s is not valid TOML.", path),
        conditionMessage(err)
      ))
    }
  )
  normalize_toml_arrays(data)
}

.rescue_validate_config <- function(config) {
  .rescue_character_array(config$packs$declared %||% character(), "[packs].declared")
  .rescue_character_array(config$extras$declared %||% character(), "[extras].declared")
  .rescue_character_array(config$exclude$declared %||% character(), "[exclude].declared")

  attach <- config$attach %||% list()
  if (!is.null(attach$enabled) && (!is.logical(attach$enabled) || length(attach$enabled) != 1)) {
    .rescue_stop("[attach].enabled must be true or false.")
  }
  .rescue_character_array(attach$declared %||% character(), "[attach].declared")
  .rescue_character_array(attach$exclude %||% character(), "[attach].exclude")

  settings <- config$settings %||% list()
  if (!is.null(settings$air_toml) && (!is.logical(settings$air_toml) || length(settings$air_toml) != 1)) {
    .rescue_stop("[settings].air_toml must be true or false.")
  }
  if (
    !is.null(settings$auto_snapshot) &&
      (!is.logical(settings$auto_snapshot) || length(settings$auto_snapshot) != 1)
  ) {
    .rescue_stop("[settings].auto_snapshot must be true or false.")
  }
  invisible(TRUE)
}

.rescue_character_array <- function(value, field) {
  if (is.list(value) && length(value) == 0) {
    return(character())
  }
  if (!is.character(value)) {
    .rescue_stop(sprintf("%s must be a string array.", field))
  }
  value
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
    lines <- remove_rprofile_boosterpak_setup_blocks(lines)
    lines <- insert_before_renv_activation(lines, repository_lines)
  }

  lines <- insert_after_renv_activation(lines, rprofile_line())
  list(lines = lines, changed = !identical(original, lines))
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
      .rescue_stop(sprintf("Failed to write built-in pack '%s' to %s.", name, target))
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

  if (isTRUE(dry_run)) {
    report <- .rescue_add_path(report, path)
    return(.rescue_add(report, "actions", "would rewrite managed boosters/attach.R."))
  }

  ok <- tryCatch(
    {
      write_attach(root, verbose = FALSE)
      TRUE
    },
    error = function(err) {
      report <<- .rescue_add(
        report,
        "warnings",
        sprintf("attach file rewrite skipped: %s", conditionMessage(err))
      )
      FALSE
    }
  )
  if (!isTRUE(ok)) {
    return(report)
  }
  report <- .rescue_add_path(report, path)
  report <- .rescue_add(report, "actions", "rewrote managed boosters/attach.R.")
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
  if (!.rescue_has_package("renv")) {
    return(.rescue_add(
      report,
      "skipped",
      "workflow package repair skipped: renv is unavailable; install renv and rerun boosterpak:::.rescue() to repair workflow packages."
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
      repo_changes <- configure_boosterpak_repositories(verbose = FALSE)
      install_policy_changes <- configure_boosterpak_install_policy(verbose = FALSE)
      if (length(repo_changes) > 0) {
        report <- .rescue_add(
          report,
          "actions",
          "reapplied boosterpak package repositories after loading project renv."
        )
      }
      if (length(install_policy_changes) > 0) {
        report <- .rescue_add(
          report,
          "actions",
          "reapplied boosterpak package install policy after loading project renv."
        )
      }
    }
  }

  missing <- tryCatch(
    missing_packages(packages, root),
    error = function(err) {
      report <<- .rescue_add(
        report,
        "warnings",
        sprintf(
          "workflow package repair skipped: project renv library could not be inspected: %s",
          conditionMessage(err)
        )
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
    installed <- tryCatch(
      {
        .rescue_install_workflow_packages(root, packages)
        TRUE
      },
      error = function(err) {
        report <<- .rescue_add(
          report,
          "warnings",
          sprintf(
            "workflow package install skipped: %s",
            conditionMessage(err)
          )
        )
        FALSE
      }
    )
    if (!isTRUE(installed)) {
      return(report)
    }
    report <- .rescue_add(
      report,
      "actions",
      sprintf("installed missing workflow packages: %s.", paste(missing, collapse = ", "))
    )
  } else {
    report <- .rescue_add(report, "skipped", "workflow packages already installed.")
  }

  report <- .rescue_add_path(report, file.path(root, "renv.lock"))
  snapshotted <- tryCatch(
    {
      call_renv_snapshot(root, packages = packages, update = TRUE)
      TRUE
    },
    error = function(err) {
      report <<- .rescue_add(
        report,
        "warnings",
        sprintf(
          "workflow package snapshot skipped: %s",
          conditionMessage(err)
        )
      )
      FALSE
    }
  )
  if (!isTRUE(snapshotted)) {
    return(report)
  }
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
  message(title)
  for (action in report$actions) {
    message("OK: ", action)
  }
  for (skipped in report$skipped) {
    message("INFO: ", skipped)
  }
  for (warning in report$warnings) {
    message("WARNING: ", warning)
  }
  invisible(report)
}
