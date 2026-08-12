#' Safely deinitialize a boosterpak project
#'
#' Removes selected project-local boosterpak and renv artifacts while
#' preserving unrelated project files and user-level configuration. An
#' interactive call with all component arguments omitted offers the actionable
#' components, preselects all of them, and then confirms the exact cleanup plan.
#' Supplying any component argument skips the picker but still confirms the
#' plan. Non-interactive cleanup requires `force = TRUE`; genuine no-op calls do
#' not prompt or require `force`.
#'
#' `air.toml` is removed only when its complete line sequence matches a known
#' boosterpak-generated format. `.Rprofile` is never deleted: only recognized
#' managed startup, repository, and install-policy content is removed, along
#' with a whole-line renv activation expression when both `renv` and `rprofile`
#' are `TRUE`. Malformed startup markers and all unrelated profile lines are
#' preserved.
#'
#' @param root Existing project root.
#' @param renv Whether to remove the project-local `renv/` directory.
#' @param boosters Whether to remove `boosters.toml` and `boosters/`.
#' @param rprofile Whether to remove boosterpak-managed `.Rprofile` content.
#' @param lockfile Whether to remove `renv.lock`.
#' @param air Whether to remove an unchanged boosterpak-generated `air.toml`.
#' @param force Whether to skip interactive selection and confirmation.
#' @param verbose Whether to print routine summaries.
#' @return An invisible list with normalized `root`, actionable `selected`
#'   components, successfully `removed` relative paths, `rprofile_changed`,
#'   named `preserved` reasons, `restart_required`, and `cancelled`.
#' @seealso [init()]
#' @export
deinit <- function(
  root = ".",
  renv = TRUE,
  boosters = TRUE,
  rprofile = TRUE,
  lockfile = TRUE,
  air = TRUE,
  force = FALSE,
  verbose = NULL
) {
  all_components_missing <- missing(renv) &&
    missing(boosters) &&
    missing(rprofile) &&
    missing(lockfile) &&
    missing(air)

  root <- .deinit_root(root)
  check_verbose(verbose)
  args <- list(
    renv = renv,
    boosters = boosters,
    rprofile = rprofile,
    lockfile = lockfile,
    air = air,
    force = force
  )
  for (name in names(args)) {
    .deinit_check_logical(args[[name]], name)
  }

  selectors <- c(
    boosters = boosters,
    renv = renv,
    rprofile = rprofile,
    lockfile = lockfile,
    air = air
  )
  preview <- .deinit_preview(root, selectors)
  if (isTRUE(preview$rprofile$malformed_startup)) {
    cli::cli_warn(
      paste(
        "Preserving malformed or unmatched boosterpak startup markers in",
        "{.file .Rprofile}; remove them manually after review."
      ),
      call = NULL
    )
  }
  selected <- preview$actionable

  if (length(selected) == 0) {
    .deinit_report_preserved(preview$preserved, verbose)
    return(invisible(.deinit_result(root, preserved = preview$preserved)))
  }

  if (!isTRUE(force)) {
    if (!.deinit_is_interactive()) {
      cli::cli_abort(
        c(
          "Project cleanup requires confirmation in a non-interactive session.",
          "i" = "Use {.code force = TRUE} to run the planned cleanup."
        ),
        call = NULL
      )
    }
    if (isTRUE(all_components_missing)) {
      selected <- .deinit_select_components(selected)
      if (length(selected) == 0) {
        return(invisible(.deinit_result(
          root,
          preserved = preview$preserved,
          cancelled = TRUE
        )))
      }
    }
  }

  plan <- .deinit_plan(root, selected, preview)
  .deinit_check_user_config_overlap(plan$deletions$path)

  if (!isTRUE(force) && !.deinit_confirm(plan)) {
    return(invisible(.deinit_result(
      root,
      selected = selected,
      preserved = preview$preserved,
      cancelled = TRUE
    )))
  }

  restart_required <- "renv" %in% selected && is_project_renv_active(root)
  rprofile_changed <- FALSE
  if ("rprofile" %in% selected && isTRUE(plan$rprofile$changed)) {
    writeLines(plan$rprofile$lines, plan$rprofile$path, useBytes = TRUE)
    rprofile_changed <- TRUE
  }
  removed <- character()
  remaining <- character()
  for (idx in seq_len(nrow(plan$deletions))) {
    target <- plan$deletions[idx, , drop = FALSE]
    .deinit_unlink(target$path)
    if (.deinit_path_exists(target$path)) {
      remaining <- c(remaining, target$label)
    } else {
      removed <- c(removed, target$label)
    }
  }

  if (length(remaining) > 0) {
    guidance <- if (isTRUE(restart_required)) {
      "Restart R, close processes using the project library, and rerun deinit()."
    } else {
      "Close processes using these paths and rerun deinit()."
    }
    cli::cli_abort(
      c(
        "Failed to remove selected project artifact{?s}: {remaining}.",
        "i" = if (length(removed) > 0) {
          "Successfully removed: {removed}."
        } else {
          "No selected project paths were removed."
        },
        "i" = guidance
      ),
      call = NULL
    )
  }

  if (should_emit(verbose)) {
    if (length(removed) > 0) {
      cli::cli_alert_success(
        "Removed project artifact{?s}: {removed}."
      )
    }
    if (isTRUE(rprofile_changed)) {
      cli::cli_alert_success("Updated {.file .Rprofile}.")
    }
  }
  .deinit_report_preserved(preview$preserved, verbose)
  if (isTRUE(restart_required)) {
    cli::cli_alert_warning(
      "The removed renv library is active; restart R before continuing."
    )
  }

  invisible(.deinit_result(
    root,
    selected = selected,
    removed = removed,
    rprofile_changed = rprofile_changed,
    preserved = preview$preserved,
    restart_required = restart_required
  ))
}

#' Normalize and validate a deinitialization root
#'
#' @param root Project root.
#' @return The normalized root.
#' @noRd
.deinit_root <- function(root) {
  if (
    !is.character(root) ||
      length(root) != 1L ||
      is.na(root) ||
      !dir.exists(root)
  ) {
    cli::cli_abort("{.arg root} must be an existing directory.", call = NULL)
  }
  normalizePath(root, winslash = "/", mustWork = TRUE)
}

#' Validate a deinitialization logical argument
#'
#' @param value Value to validate.
#' @param name Argument name.
#' @return `TRUE`, invisibly.
#' @noRd
.deinit_check_logical <- function(value, name) {
  if (!is.logical(value) || length(value) != 1L || is.na(value)) {
    cli::cli_abort(
      "{.arg {name}} must be {.code TRUE} or {.code FALSE}.",
      call = NULL
    )
  }
  invisible(TRUE)
}

#' Preview actionable deinitialization components
#'
#' @param root Normalized project root.
#' @param selectors Named logical component selectors.
#' @return A preview list.
#' @noRd
.deinit_preview <- function(root, selectors) {
  paths <- data.frame(
    component = c("boosters", "boosters", "renv", "lockfile", "air"),
    label = c("boosters.toml", "boosters/", "renv/", "renv.lock", "air.toml"),
    path = file.path(
      root,
      c("boosters.toml", "boosters", "renv", "renv.lock", "air.toml")
    ),
    stringsAsFactors = FALSE
  )
  exists <- vapply(paths$path, .deinit_path_exists, logical(1))
  owned_air <- !exists[[5]] || .deinit_air_is_owned(paths$path[[5]])
  deletable <- exists & selectors[paths$component]
  deletable[[5]] <- deletable[[5]] && owned_air
  deletions <- paths[deletable, , drop = FALSE]
  rprofile <- .deinit_rprofile_preview(
    root,
    selected = isTRUE(selectors[["rprofile"]]),
    remove_renv = isTRUE(selectors[["renv"]])
  )
  actionable <- c("boosters", "renv", "rprofile", "lockfile", "air")
  actionable_components <- unique(deletions$component)
  if (isTRUE(rprofile$changed)) {
    actionable_components <- c(actionable_components, "rprofile")
  }
  actionable <- actionable[
    selectors[actionable] & actionable %in% actionable_components
  ]
  preserved <- character()
  if (isTRUE(selectors[["air"]]) && exists[[5]] && !owned_air) {
    preserved <- stats::setNames(
      "modified or ownership unknown",
      "air.toml"
    )
  }
  if (
    isTRUE(selectors[["renv"]]) &&
      !isTRUE(selectors[["rprofile"]]) &&
      isTRUE(rprofile$renv_activation_present)
  ) {
    preserved <- c(
      preserved,
      stats::setNames("renv activation preserved by request", ".Rprofile")
    )
  }
  list(
    actionable = unname(actionable),
    deletions = deletions,
    rprofile = rprofile,
    preserved = preserved
  )
}

#' Preview managed R profile cleanup
#'
#' @param root Normalized project root.
#' @param selected Whether profile cleanup is selected.
#' @param remove_renv Whether renv activation should be removed.
#' @return An R profile cleanup preview.
#' @noRd
.deinit_rprofile_preview <- function(root, selected, remove_renv) {
  path <- file.path(root, ".Rprofile")
  if (!file.exists(path)) {
    return(list(
      path = path,
      lines = character(),
      changed = FALSE,
      malformed_startup = FALSE,
      renv_activation_present = FALSE
    ))
  }
  lines <- readLines(path, warn = FALSE)
  renv_activation_present <- any(is_rprofile_renv_activation(lines))
  transformed <- remove_rprofile_managed_lines(lines, renv = remove_renv)
  list(
    path = path,
    lines = transformed$lines,
    changed = isTRUE(selected) && transformed$changed,
    malformed_startup = isTRUE(selected) && transformed$malformed_startup,
    renv_activation_present = renv_activation_present
  )
}

#' Build an immutable deinitialization plan
#'
#' @param root Normalized project root.
#' @param selected Selected component names.
#' @param preview Deinitialization preview.
#' @return A cleanup plan.
#' @noRd
.deinit_plan <- function(root, selected, preview) {
  rprofile <- preview$rprofile
  if (!"rprofile" %in% selected) {
    rprofile$changed <- FALSE
  }
  list(
    root = root,
    selected = selected,
    deletions = preview$deletions[
      preview$deletions$component %in% selected,
      ,
      drop = FALSE
    ],
    rprofile = rprofile
  )
}

#' Test whether an exact cleanup path exists
#'
#' @param path Exact path.
#' @return A logical scalar.
#' @noRd
.deinit_path_exists <- function(path) {
  file.exists(path) || dir.exists(path)
}

#' Test whether Air content is known generated content
#'
#' @param path Path to `air.toml`.
#' @return A logical scalar.
#' @noRd
.deinit_air_is_owned <- function(path) {
  lines <- tryCatch(
    suppressWarnings(readLines(path, warn = FALSE)),
    error = function(err) NULL
  )
  !is.null(lines) && is_generated_air_config(lines)
}

#' Report preserved project artifacts
#'
#' @param preserved Named preservation reasons.
#' @param verbose Whether to print routine summaries.
#' @return `TRUE`, invisibly.
#' @noRd
.deinit_report_preserved <- function(preserved, verbose) {
  if (length(preserved) > 0 && should_emit(verbose)) {
    for (idx in seq_along(preserved)) {
      path <- names(preserved)[[idx]]
      reason <- unname(preserved[[idx]])
      cli::cli_alert_info("Preserved {.file {path}}: {reason}.")
    }
  }
  invisible(TRUE)
}

#' Resolve whether deinitialization is interactive
#'
#' @return A logical scalar.
#' @noRd
.deinit_is_interactive <- function() {
  interactive()
}

#' Select actionable deinitialization components
#'
#' @param components Actionable component names.
#' @return Selected component names.
#' @noRd
.deinit_select_components <- function(components) {
  utils::select.list(
    components,
    preselect = components,
    multiple = TRUE,
    title = "Select project components to remove",
    graphics = FALSE
  )
}

#' Confirm an exact deinitialization plan
#'
#' @param plan Cleanup plan.
#' @return A logical scalar.
#' @noRd
.deinit_confirm <- function(plan) {
  changes <- plan$deletions$path
  if (isTRUE(plan$rprofile$changed)) {
    changes <- c(
      changes,
      paste0(plan$rprofile$path, " (remove managed profile lines)")
    )
  }
  answer <- utils::menu(
    c("Yes", "No"),
    title = paste(
      "Remove these project artifacts?",
      paste(changes, collapse = "\n"),
      sep = "\n"
    )
  )
  identical(answer, 1L)
}

#' Remove one exact deinitialization target
#'
#' @param path Exact project-child path.
#' @return The unlink status, invisibly.
#' @noRd
.deinit_unlink <- function(path) {
  unlink(path, recursive = TRUE, force = TRUE, expand = FALSE)
}

#' Abort when cleanup overlaps user pack configuration
#'
#' @param paths Exact selected deletion paths.
#' @return `TRUE`, invisibly.
#' @noRd
.deinit_check_user_config_overlap <- function(paths) {
  user_path <- user_packs_dir()
  overlaps <- vapply(
    paths,
    .deinit_paths_overlap,
    logical(1),
    other = user_path
  )
  if (any(overlaps)) {
    cli::cli_abort(
      c(
        "Refusing project cleanup because a selected path overlaps user pack configuration.",
        "x" = "Selected path: {paths[which(overlaps)[[1]]]}",
        "i" = "User packs: {user_path}"
      ),
      call = NULL
    )
  }
  invisible(TRUE)
}

#' Test whether two paths contain or overlap each other
#'
#' @param path First path.
#' @param other Second path.
#' @return A logical scalar.
#' @noRd
.deinit_paths_overlap <- function(path, other) {
  paths <- normalizePath(
    c(path, other),
    winslash = "/",
    mustWork = FALSE
  )
  if (identical(.Platform$OS.type, "windows")) {
    paths <- tolower(paths)
  }
  identical(paths[[1]], paths[[2]]) ||
    startsWith(paths[[1]], paste0(paths[[2]], "/")) ||
    startsWith(paths[[2]], paste0(paths[[1]], "/"))
}

#' Build a deinitialization result
#'
#' @param root Normalized project root.
#' @param selected Selected components.
#' @param removed Removed relative paths.
#' @param rprofile_changed Whether `.Rprofile` changed.
#' @param preserved Named preservation reasons.
#' @param restart_required Whether R must be restarted.
#' @param cancelled Whether the user cancelled.
#' @return A deinitialization result list.
#' @noRd
.deinit_result <- function(
  root,
  selected = character(),
  removed = character(),
  rprofile_changed = FALSE,
  preserved = character(),
  restart_required = FALSE,
  cancelled = FALSE
) {
  list(
    root = root,
    selected = selected,
    removed = removed,
    rprofile_changed = rprofile_changed,
    preserved = preserved,
    restart_required = restart_required,
    cancelled = cancelled
  )
}
