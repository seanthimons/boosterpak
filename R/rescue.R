#' Rescue an existing boosterpak project
#'
#' @param root Project root containing an existing `boosters.toml` file.
#' @param dry_run Whether to report repairs without modifying files or the
#'   active R session.
#' @param verbose Whether to print the rescue report.
#' @param snapshot Whether to write workflow packages to `renv.lock`.
#' @return A rescue report, invisibly.
#' @noRd
.rescue <- function(root = ".", dry_run = FALSE, verbose = NULL, snapshot = TRUE) {
  .rescue_check_verbose(verbose)
  if (!is.logical(dry_run) || length(dry_run) != 1 || is.na(dry_run)) {
    .rescue_stop("dry_run must be TRUE or FALSE.")
  }
  if (!is.logical(snapshot) || length(snapshot) != 1 || is.na(snapshot)) {
    .rescue_stop("snapshot must be TRUE or FALSE.")
  }

  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  if (!file.exists(boosters_file(root))) {
    .rescue_stop(
      c(
        "boosters.toml does not exist; upgrade_project() repairs existing boosterpak projects only.",
        "Use boosterpak::init() for a new project, or restore boosters.toml before running upgrade_project()."
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
  # Captured before the workflow step, which may load renv and rewrite
  # renv/activate.R; the change is reported on every path out of that step.
  activate <- file.path(root, "renv", "activate.R")
  activate_before <- .rescue_read_lines(activate)
  report <- .rescue_workflow_packages(
    root,
    dry_run,
    report,
    snapshot = snapshot,
    repos = repositories$repos
  )
  report <- .rescue_note_activate_change(report, activate, activate_before)
  report <- .rescue_record_version(root, dry_run, report)

  .rescue_emit_report(report, verbose)
  invisible(report)
}

#' Record the installed boosterpak version after a completed upgrade
#'
#' `[project].boosters_version` marks the boosterpak version a project was last
#' migrated with, so it is refreshed only when the upgrade finished without
#' warnings. A dry run reports the change on a scratch copy and writes nothing.
#'
#' @param root Normalized project root.
#' @param dry_run Whether the upgrade is a dry run.
#' @param report Rescue report to update.
#' @return The updated rescue report.
#' @noRd
.rescue_record_version <- function(root, dry_run, report) {
  if (length(report$warnings) > 0) {
    return(.rescue_add(
      report,
      "skipped",
      "boosters_version not recorded: the upgrade reported warnings. Fix them and rerun upgrade_project()."
    ))
  }

  path <- boosters_file(root)
  changed <- tryCatch(
    {
      if (isTRUE(dry_run)) {
        .rescue_version_would_change(path)
      } else {
        set_boosters_version(root)
      }
    },
    error = function(err) {
      report <<- .rescue_add(
        report,
        "warnings",
        sprintf("boosters_version not recorded: %s", conditionMessage(err))
      )
      NULL
    }
  )
  if (is.null(changed)) {
    return(report)
  }
  if (!isTRUE(changed)) {
    return(.rescue_add(report, "skipped", "boosters_version already matches the installed boosterpak."))
  }

  report <- .rescue_add_path(report, path)
  .rescue_add(
    report,
    "actions",
    if (isTRUE(dry_run)) {
      "would record the installed boosterpak version in boosters.toml."
    } else {
      "recorded the installed boosterpak version in boosters.toml."
    }
  )
}

#' Check whether recording the boosterpak version would change boosters.toml
#'
#' @param path Path to the project's `boosters.toml`.
#' @return `TRUE` when `set_boosters_version()` would change the file, otherwise
#'   `FALSE`. The project file is not modified.
#' @noRd
.rescue_version_would_change <- function(path) {
  scratch <- tempfile("boosterpak-version-")
  dir.create(scratch)
  on.exit(unlink(scratch, recursive = TRUE, force = TRUE), add = TRUE)
  file.copy(path, file.path(scratch, "boosters.toml"))
  isTRUE(set_boosters_version(scratch))
}

#' Validate rescue verbosity
#'
#' @param verbose Verbosity value to validate.
#' @return `TRUE`, invisibly, or an error if `verbose` is invalid.
#' @noRd
.rescue_check_verbose <- function(verbose) {
  if (!is.null(verbose) && !isTRUE(verbose) && !identical(verbose, FALSE)) {
    .rescue_stop("verbose must be NULL, TRUE, or FALSE.")
  }
  invisible(TRUE)
}

#' Signal a rescue error
#'
#' @param message Character vector of error message lines.
#' @return This function does not return; it signals an error.
#' @noRd
.rescue_stop <- function(message) {
  stop(paste(unname(message), collapse = "\n"), call. = FALSE)
}

#' Check whether a package is available during rescue
#'
#' @param package Package name.
#' @return A logical scalar indicating whether the package namespace is
#'   available.
#' @noRd
.rescue_has_package <- function(package) {
  requireNamespace(package, quietly = TRUE)
}

#' Create an empty rescue report
#'
#' @param root Project root recorded in the report.
#' @param dry_run Whether the report describes a dry run.
#' @return A rescue report list with empty result fields.
#' @noRd
.rescue_report <- function(root, dry_run) {
  list(
    root = root,
    dry_run = dry_run,
    actions = character(),
    skipped = character(),
    warnings = character(),
    paths = character(),
    repository_changes = character(),
    preview = character()
  )
}

#' Merge rescue report fields
#'
#' @param report Rescue report to update.
#' @param other Rescue report whose result fields are merged into `report`.
#' @return The updated rescue report.
#' @noRd
.rescue_merge_report <- function(report, other) {
  for (field in c("actions", "skipped", "warnings", "paths")) {
    report[[field]] <- unique(c(report[[field]], other[[field]]))
  }
  report
}

#' Add unique values to a rescue report field
#'
#' @param report Rescue report to update.
#' @param field Name of the report field to update.
#' @param values Values to add.
#' @return The updated rescue report.
#' @noRd
.rescue_add <- function(report, field, values) {
  report[[field]] <- unique(c(report[[field]], values))
  report
}

#' Add a normalized path to a rescue report
#'
#' @param report Rescue report to update.
#' @param path File path to record.
#' @return The updated rescue report.
#' @noRd
.rescue_add_path <- function(report, path) {
  .rescue_add(
    report,
    "paths",
    normalizePath(path, winslash = "/", mustWork = FALSE)
  )
}

#' Repair repository and install-policy options
#'
#' @param dry_run Whether to restore session options after calculating changes.
#' @param verbose Verbosity value accepted for interface consistency;
#'   repository configuration is always run quietly.
#' @return A list containing the rescue report, `.Rprofile` setup lines,
#'   repository changes, and install-policy changes.
#' @noRd
.rescue_repositories <- function(dry_run, verbose) {
  report <- .rescue_report(root = "", dry_run = dry_run)

  if (isTRUE(dry_run)) {
    old_repos <- getOption("repos")
    old_renv_repos <- getOption("renv.config.repos.override")
    old_user_agent <- getOption("HTTPUserAgent")
    old_download_extra <- getOption("download.file.extra")
    old_install_policy <- lapply(
      names(boosterpak_install_policy_options()),
      getOption
    )
    names(old_install_policy) <- names(boosterpak_install_policy_options())
    changes <- configure_boosterpak_repositories(verbose = FALSE)
    install_policy_changes <- configure_boosterpak_install_policy(verbose = FALSE)
    lines <- boosterpak_rprofile_setup_lines(changes, install_policy_changes)
    repos <- getOption("repos")
    options(repos = old_repos)
    options(renv.config.repos.override = old_renv_repos)
    options(HTTPUserAgent = old_user_agent)
    options(download.file.extra = old_download_extra)
    options(old_install_policy)
  } else {
    changes <- configure_boosterpak_repositories(verbose = FALSE)
    install_policy_changes <- configure_boosterpak_install_policy(verbose = FALSE)
    lines <- boosterpak_rprofile_setup_lines(changes, install_policy_changes)
    repos <- getOption("repos")
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

  list(
    report = report,
    lines = lines,
    changes = changes,
    install_policy_changes = install_policy_changes,
    repos = repos
  )
}

#' Read and validate the rescue configuration
#'
#' @param root Project root.
#' @return A list containing the parsed configuration, its validity, and a
#'   rescue report containing any warnings.
#' @noRd
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

#' Read a configuration for rescue
#'
#' @param root Project root.
#' @return The parsed configuration with TOML arrays normalized.
#' @noRd
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

#' Validate configuration fields needed by rescue
#'
#' @param config Parsed boosterpak configuration.
#' @return `TRUE`, invisibly, or an error if a required field is invalid.
#' @noRd
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

#' Validate a rescue configuration string array
#'
#' @param value Configuration value to validate.
#' @param field Configuration field name used in error messages.
#' @return The character vector, with an empty list normalized to
#'   `character()`.
#' @noRd
.rescue_character_array <- function(value, field) {
  if (is.list(value) && length(value) == 0) {
    return(character())
  }
  if (!is.character(value)) {
    .rescue_stop(sprintf("%s must be a string array.", field))
  }
  value
}

#' Repair the project startup profile
#'
#' @param root Project root.
#' @param repository_lines Repository and install-policy setup lines to insert.
#' @param dry_run Whether to report the repair without writing the file.
#' @param report Rescue report to update.
#' @return The updated rescue report.
#' @noRd
.rescue_rprofile <- function(root, repository_lines, dry_run, report) {
  path <- file.path(root, ".Rprofile")
  existing <- if (file.exists(path)) readLines(path, warn = FALSE) else character()
  planned <- .rescue_rprofile_lines(existing, repository_lines)

  if (!planned$changed) {
    return(.rescue_add(report, "skipped", ".Rprofile startup setup already matches upgrade requirements."))
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

#' Plan rescued startup profile lines
#'
#' @param lines Existing `.Rprofile` lines.
#' @param repository_lines Repository and install-policy setup lines to insert.
#' @return A list containing the planned `lines` and a logical `changed` flag.
#' @noRd
.rescue_rprofile_lines <- function(lines, repository_lines = character()) {
  original <- lines
  lines <- lines[lines != legacy_rprofile_line()]
  lines <- lines[lines != rprofile_line()]

  if (length(repository_lines) > 0) {
    lines <- remove_rprofile_boosterpak_setup_blocks(lines)
  }

  # The hook goes after the activation line and after any post-activation
  # repository lines, so the order is activation, repository re-apply, hook.
  if (!has_rprofile_startup_block(lines)) {
    # Drop a block from an earlier version so exactly one current block remains.
    lines <- remove_rprofile_startup_blocks(lines)$lines
    lines <- insert_startup_block(lines, rprofile_startup_block())
  }

  if (length(repository_lines) > 0) {
    lines <- insert_repository_lines(lines, repository_lines)
  }
  list(lines = lines, changed = !identical(original, lines))
}

#' Repair core and declared pack assets
#'
#' @param root Project root.
#' @param config Parsed boosterpak configuration.
#' @param config_valid Whether `config` passed rescue validation.
#' @param dry_run Whether to report repairs without writing files.
#' @param report Rescue report to update.
#' @return The updated rescue report.
#' @noRd
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

#' Repair a built-in pack manifest
#'
#' @param name Built-in pack name.
#' @param root Project root.
#' @param dry_run Whether to report the repair without writing the manifest.
#' @param report Rescue report to update.
#' @return The updated rescue report.
#' @noRd
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

#' List materialized project pack files
#'
#' @param root Project root.
#' @return A character vector of normalized project pack file paths.
#' @noRd
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

#' Repair the managed attach file
#'
#' @param root Project root.
#' @param config_valid Whether the project configuration passed validation.
#' @param dry_run Whether to report the repair without writing the file.
#' @param report Rescue report to update.
#' @return The updated rescue report.
#' @noRd
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

#' Repair workflow packages in the project library
#'
#' @param root Project root.
#' @param dry_run Whether to report package repairs without applying them.
#' @param report Rescue report to update.
#' @param snapshot Whether to write the workflow packages to `renv.lock`.
#' @param repos Repository option the run will use; used for the dry-run
#'   lockfile preview.
#' @return The updated rescue report.
#' @noRd
.rescue_workflow_packages <- function(
  root,
  dry_run,
  report,
  snapshot = TRUE,
  repos = getOption("repos")
) {
  packages <- c("renv", "pak", "boosterpak")

  if (!has_project_renv(root)) {
    return(.rescue_add(
      report,
      "skipped",
      "workflow package repair skipped: no project renv found; run boosterpak::init(renv = 'yes') to initialize one."
    ))
  }
  if (!.rescue_has_package("renv")) {
    # The upgrade is incomplete without renv, so it is reported as a warning
    # and boosters_version is not recorded (see .rescue_record_version()).
    report <- .rescue_add(
      report,
      "skipped",
      "workflow package repair skipped: renv is unavailable; install renv and rerun upgrade_project() to repair workflow packages."
    )
    return(.rescue_add(
      report,
      "warnings",
      "workflow package repair incomplete: renv is unavailable. Install renv and rerun upgrade_project()."
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
    if (!isTRUE(snapshot)) {
      return(.rescue_add(report, "skipped", "renv.lock would not be written: snapshot = FALSE."))
    }

    preview <- tryCatch(
      workflow_lockfile_preview(root, packages, repos),
      error = function(err) {
        list(
          lines = sprintf("lockfile preview unavailable: %s", conditionMessage(err)),
          renv_changed = FALSE
        )
      }
    )
    report$preview <- preview$lines
    report <- .rescue_add_path(report, file.path(root, "renv.lock"))
    report <- .rescue_add(report, "actions", "would snapshot workflow packages with update = TRUE.")
    if (isTRUE(preview$renv_changed) && file.exists(file.path(root, "renv", "activate.R"))) {
      report <- .rescue_add_path(report, file.path(root, "renv", "activate.R"))
      report <- .rescue_add(
        report,
        "actions",
        "would rewrite renv/activate.R when renv::snapshot() records the new renv version."
      )
    }
    return(report)
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

  snapshotted <- tryCatch(
    {
      ensure_dependency_closure(packages, root)
      if (isTRUE(snapshot)) {
        call_renv_snapshot(root, packages = packages, update = TRUE)
      }
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
  if (!isTRUE(snapshot)) {
    return(.rescue_add(
      report,
      "skipped",
      "renv.lock not written: snapshot = FALSE. Run upgrade_project() without snapshot = FALSE to pin workflow packages."
    ))
  }

  report <- .rescue_add_path(report, file.path(root, "renv.lock"))
  report <- .rescue_add(report, "actions", "snapshotted workflow packages with update = TRUE.")
  report
}

#' Read a text file for rescue comparisons
#'
#' @param path File path.
#' @return The lines of `path`, or `NULL` when the file does not exist.
#' @noRd
.rescue_read_lines <- function(path) {
  if (!file.exists(path)) {
    return(NULL)
  }
  readLines(path, warn = FALSE)
}

#' Report a change to renv/activate.R made during the workflow step
#'
#' Loading or snapshotting renv can rewrite `renv/activate.R`. Reporting the
#' change lets the user see it under files touched.
#'
#' @param report Rescue report to update.
#' @param activate Path to `renv/activate.R`.
#' @param before Lines of `renv/activate.R` captured before the workflow step,
#'   or `NULL` when the file was absent.
#' @return The updated rescue report.
#' @noRd
.rescue_note_activate_change <- function(report, activate, before) {
  if (identical(before, .rescue_read_lines(activate))) {
    return(report)
  }
  report <- .rescue_add_path(report, activate)
  .rescue_add(report, "actions", "updated renv/activate.R while loading or snapshotting renv.")
}

#' Install missing rescue workflow packages
#'
#' @param root Project root.
#' @param packages Workflow package names to ensure are installed.
#' @return `packages`, invisibly.
#' @noRd
.rescue_install_workflow_packages <- function(root, packages) {
  tryCatch(
    {
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
    },
    error = rethrow_github_rate_limit
  )
  invisible(packages)
}

#' Emit a rescue report
#'
#' @param report Rescue report to emit.
#' @param verbose Verbosity value controlling whether messages are emitted.
#' @return `report`, invisibly.
#' @noRd
.rescue_emit_report <- function(report, verbose) {
  if (!should_emit(verbose)) {
    return(invisible(report))
  }

  title <- if (isTRUE(report$dry_run)) "boosterpak upgrade dry run" else "boosterpak upgrade"
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
  if (length(report$preview) > 0) {
    message("Lockfile preview (renv.lock):")
    for (line in report$preview) {
      message("  ", line)
    }
  }
  files <- .rescue_display_paths(report$paths, report$root)
  if (length(files) > 0) {
    message(if (isTRUE(report$dry_run)) "Files a real run would touch:" else "Files touched:")
    for (path in files) {
      message("  ", path)
    }
    message("Review these changes with git diff (or your version control) before committing.")
  }
  invisible(report)
}

#' Show rescue paths relative to the project root
#'
#' @param paths Normalized file paths recorded in a rescue report.
#' @param root Normalized project root.
#' @return A character vector of display paths.
#' @noRd
.rescue_display_paths <- function(paths, root) {
  prefix <- paste0(root, "/")
  inside <- startsWith(paths, prefix)
  paths[inside] <- substring(paths[inside], nchar(prefix) + 1L)
  paths
}
