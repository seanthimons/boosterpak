#' Check for the boosterpak startup hook
#'
#' @param root Project root.
#' @return A single logical value indicating whether `.Rprofile` has the hook.
#' @noRd
has_rprofile_line <- function(root = ".") {
  path <- file.path(root, ".Rprofile")
  file.exists(path) && any(readLines(path, warn = FALSE) == rprofile_line())
}

#' Ensure the boosterpak startup setup
#'
#' @param root Project root.
#' @param rprofile Whether to ask, add, or skip the startup setup.
#' @param repository_lines Character vector of repository setup lines to add.
#' @return `TRUE` invisibly when `.Rprofile` changes, otherwise `FALSE`
#'   invisibly.
#' @noRd
ensure_rprofile_line <- function(
  root = ".",
  rprofile = c("ask", "yes", "no"),
  repository_lines = character()
) {
  rprofile <- match.arg(rprofile)
  path <- file.path(root, ".Rprofile")
  line <- rprofile_line()
  existing <- if (file.exists(path)) readLines(path, warn = FALSE) else character()

  legacy <- legacy_rprofile_line()
  setup_missing <- length(repository_lines) > 0 &&
    !all(repository_lines %in% existing)
  hook_missing <- !line %in% existing || legacy %in% existing

  if (!setup_missing && !hook_missing) {
    return(invisible(FALSE))
  }

  if (identical(rprofile, "no")) {
    return(invisible(FALSE))
  }

  if (identical(rprofile, "ask")) {
    if (!interactive()) {
      cli::cli_abort(c(
        "{.file .Rprofile} does not contain the recommended boosterpak startup setup.",
        "i" = "Use {.code rprofile = 'yes'} to add it or {.code rprofile = 'no'} to skip repository setup and package/helper auto-sourcing.",
        ">" = paste(c(repository_lines, line), collapse = "\n")
      ), call = NULL)
    }
    answer <- utils::menu(
      c("Yes (recommended)", "No"),
      title = paste(
        "Add this boosterpak startup setup to .Rprofile?",
        paste(c(repository_lines, line), collapse = "\n"),
        sep = "\n"
      )
    )
    if (!identical(answer, 1L)) {
      return(invisible(FALSE))
    }
  }

  existing <- existing[existing != legacy]
  updated <- existing
  if (setup_missing) {
    updated <- remove_rprofile_boosterpak_setup_blocks(updated)
    updated <- insert_before_renv_activation(updated, repository_lines)
  }
  if (!line %in% updated) {
    updated <- insert_after_renv_activation(updated, line)
  }
  writeLines(updated, path, useBytes = TRUE)
  invisible(TRUE)
}

#' Remove managed boosterpak setup blocks
#'
#' @param lines Character vector of `.Rprofile` lines.
#' @return `lines` without managed install-policy and repository blocks.
#' @noRd
remove_rprofile_boosterpak_setup_blocks <- function(lines) {
  lines <- remove_rprofile_install_policy_block(lines)
  remove_rprofile_repository_block(lines)
}

#' Remove the managed install-policy block
#'
#' @param lines Character vector of `.Rprofile` lines.
#' @return `lines` without managed install-policy settings.
#' @noRd
remove_rprofile_install_policy_block <- function(lines) {
  marker <- rprofile_install_policy_marker()
  marker_idx <- which(lines == marker)
  if (length(marker_idx) == 0) {
    return(lines)
  }

  keep <- rep(TRUE, length(lines))
  option_names <- names(boosterpak_install_policy_options())
  option_pattern <- sprintf(
    "^options\\((%s)\\s*=",
    paste(gsub(".", "\\\\.", option_names, fixed = TRUE), collapse = "|")
  )
  for (idx in marker_idx) {
    keep[[idx]] <- FALSE
    cursor <- idx + 1L
    while (cursor <= length(lines) && grepl(option_pattern, trimws(lines[[cursor]]))) {
      keep[[cursor]] <- FALSE
      cursor <- cursor + 1L
    }
  }
  lines[keep]
}

#' Remove the managed repository block
#'
#' @param lines Character vector of `.Rprofile` lines.
#' @return `lines` without managed repository settings.
#' @noRd
remove_rprofile_repository_block <- function(lines) {
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

#' Insert lines before renv activation
#'
#' @param lines Character vector of `.Rprofile` lines.
#' @param new_lines Character vector of lines to insert.
#' @return The updated character vector of `.Rprofile` lines.
#' @noRd
insert_before_renv_activation <- function(lines, new_lines) {
  renv_line <- grep('source\\([\'"]renv/activate\\.R[\'"]\\)', lines)
  if (length(renv_line) > 0) {
    idx <- renv_line[[1]]
    append(lines, new_lines, after = idx - 1L)
  } else {
    c(new_lines, lines)
  }
}

#' Insert a line after renv activation
#'
#' @param lines Character vector of `.Rprofile` lines.
#' @param line A single line to insert.
#' @return The updated character vector of `.Rprofile` lines.
#' @noRd
insert_after_renv_activation <- function(lines, line) {
  renv_line <- grep('source\\([\'"]renv/activate\\.R[\'"]\\)', lines)
  if (length(renv_line) > 0) {
    idx <- renv_line[[length(renv_line)]]
    append(lines, line, after = idx)
  } else {
    c(lines, line)
  }
}
