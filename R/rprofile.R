#' Check for the boosterpak startup hook
#'
#' @param root Project root.
#' @return A single logical value indicating whether `.Rprofile` has the hook.
#' @noRd
has_rprofile_line <- function(root = ".") {
  path <- file.path(root, ".Rprofile")
  file.exists(path) && has_rprofile_startup_block(readLines(path, warn = FALSE))
}

#' Check for an exact managed startup block
#'
#' @param lines Character vector of `.Rprofile` lines.
#' @return A single logical value.
#' @noRd
has_rprofile_startup_block <- function(lines) {
  block <- rprofile_startup_block()
  starts <- which(lines == block[[1]])
  any(vapply(
    starts,
    function(start) {
      end <- start + length(block) - 1L
      end <= length(lines) && identical(lines[start:end], block)
    },
    logical(1)
  ))
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
  block <- rprofile_startup_block()
  existing <- if (file.exists(path)) readLines(path, warn = FALSE) else character()

  historical <- c(legacy_rprofile_line(), rprofile_line())
  setup_missing <- length(repository_lines) > 0 &&
    !all(repository_lines %in% existing)
  hook_missing <- !has_rprofile_startup_block(existing) ||
    any(historical %in% existing)

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
        ">" = paste(c(repository_lines, block), collapse = "\n")
      ), call = NULL)
    }
    answer <- utils::menu(
      c("Yes (recommended)", "No"),
      title = paste(
        "Add this boosterpak startup setup to .Rprofile?",
        paste(c(repository_lines, block), collapse = "\n"),
        sep = "\n"
      )
    )
    if (!identical(answer, 1L)) {
      return(invisible(FALSE))
    }
  }

  existing <- existing[!existing %in% historical]
  updated <- existing
  if (setup_missing) {
    updated <- remove_rprofile_boosterpak_setup_blocks(updated)
    updated <- insert_before_renv_activation(updated, repository_lines)
  }
  if (!has_rprofile_startup_block(updated)) {
    updated <- insert_after_renv_activation(updated, block)
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
    paste(gsub(".", "\\.", option_names, fixed = TRUE), collapse = "|")
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

#' Remove boosterpak-managed lines from an R profile
#'
#' @param lines Character vector of `.Rprofile` lines.
#' @param renv Whether to remove whole-line renv activation expressions.
#' @return A list containing transformed `lines`, a `changed` flag, and a
#'   `malformed_startup` flag.
#' @noRd
remove_rprofile_managed_lines <- function(lines, renv = TRUE) {
  original <- lines
  startup <- remove_rprofile_startup_blocks(lines)
  lines <- startup$lines
  lines <- lines[!lines %in% c(rprofile_line(), legacy_rprofile_line())]
  lines <- remove_rprofile_boosterpak_setup_blocks(lines)
  if (isTRUE(renv)) {
    lines <- lines[!is_rprofile_renv_activation(lines)]
  }
  list(
    lines = lines,
    changed = !identical(lines, original),
    malformed_startup = startup$malformed
  )
}

#' Remove valid marker-delimited boosterpak startup blocks
#'
#' @param lines Character vector of `.Rprofile` lines.
#' @return A list containing transformed `lines` and a `malformed` flag.
#' @noRd
remove_rprofile_startup_blocks <- function(lines) {
  begin <- rprofile_startup_begin_marker()
  end <- rprofile_startup_end_marker()
  keep <- rep(TRUE, length(lines))
  open <- NA_integer_
  nested <- FALSE
  malformed <- FALSE

  for (idx in seq_along(lines)) {
    if (identical(lines[[idx]], begin)) {
      if (is.na(open)) {
        open <- idx
        nested <- FALSE
      } else {
        nested <- TRUE
        malformed <- TRUE
      }
    } else if (identical(lines[[idx]], end)) {
      if (is.na(open)) {
        malformed <- TRUE
      } else {
        if (!nested) {
          keep[open:idx] <- FALSE
        }
        open <- NA_integer_
        nested <- FALSE
      }
    }
  }
  if (!is.na(open)) {
    malformed <- TRUE
  }

  list(lines = lines[keep], malformed = malformed)
}

#' Identify whole-line renv activation expressions
#'
#' @param lines Character vector of `.Rprofile` lines.
#' @return A logical vector.
#' @noRd
is_rprofile_renv_activation <- function(lines) {
  grepl(
    "^\\s*source\\(\\s*([\"'])renv/activate\\.R\\1\\s*\\)\\s*(?:#.*)?$",
    lines,
    perl = TRUE
  )
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
