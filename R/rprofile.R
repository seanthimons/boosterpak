#' Check for the boosterpak startup hook
#'
#' @param root Project root.
#' @return A single logical value indicating whether `.Rprofile` has the hook.
#' @noRd
has_rprofile_line <- function(root = ".") {
  path <- file.path(root, ".Rprofile")
  file.exists(path) && has_rprofile_startup_block(readLines(path, warn = FALSE))
}

#' Check whether the `.Rprofile` startup hook uses an earlier layout
#'
#' An earlier layout is the unmarked hook line from an older boosterpak, or a
#' managed block whose text differs from the current block. A file with no
#' boosterpak hook at all is not old. That is a project set up with
#' `rprofile = "no"`, which is a valid choice.
#'
#' @param root Project root.
#' @return A single logical value.
#' @noRd
rprofile_layout_is_old <- function(root = ".") {
  path <- file.path(root, ".Rprofile")
  if (!file.exists(path)) {
    return(FALSE)
  }
  lines <- readLines(path, warn = FALSE)
  if (any(lines %in% c(legacy_rprofile_line(), rprofile_line()))) {
    return(TRUE)
  }
  any(lines == rprofile_startup_begin_marker()) &&
    !has_rprofile_startup_block(lines)
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
#'   invisibly. A `FALSE` that has a `skipped` attribute set to `TRUE` means
#'   the setup was missing and was not written (`rprofile = "no"` or a declined
#'   prompt).
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
  # Without an activation line, insert_repository_lines() writes only the
  # setup lines, so only those are expected. Otherwise a second run would
  # always see the post-activation lines as missing.
  expected <- if (has_renv_activation(existing)) {
    repository_lines
  } else {
    split_repository_lines(repository_lines)$setup
  }
  setup_missing <- length(expected) > 0 && !all(expected %in% existing)
  hook_missing <- !has_rprofile_startup_block(existing) ||
    any(historical %in% existing)

  if (!setup_missing && !hook_missing) {
    return(invisible(FALSE))
  }

  # "skipped" marks a setup that is still missing and was not written, so
  # init() does not record the project as migrated.
  if (identical(rprofile, "no")) {
    return(invisible(structure(FALSE, skipped = TRUE)))
  }

  if (identical(rprofile, "ask")) {
    if (!interactive()) {
      cli::cli_abort(c(
        "{.file .Rprofile} does not contain the recommended boosterpak startup setup.",
        "i" = "Use {.code rprofile = 'yes'} to add it or {.code rprofile = 'no'} to skip repository setup and package/helper auto-sourcing.",
        ">" = paste(c(expected, block), collapse = "\n")
      ), call = NULL)
    }
    answer <- utils::menu(
      c("Yes (recommended)", "No"),
      title = paste(
        "Add this boosterpak startup setup to .Rprofile?",
        paste(c(expected, block), collapse = "\n"),
        sep = "\n"
      )
    )
    if (!identical(answer, 1L)) {
      return(invisible(structure(FALSE, skipped = TRUE)))
    }
  }

  existing <- existing[!existing %in% historical]
  updated <- existing
  # The hook goes in first. A block from an earlier version is removed first,
  # so the file ends up with exactly one managed block.
  if (!has_rprofile_startup_block(updated)) {
    updated <- remove_rprofile_startup_blocks(updated)$lines
    updated <- insert_startup_block(updated, block)
  }
  if (setup_missing) {
    updated <- remove_rprofile_boosterpak_setup_blocks(updated)
    updated <- insert_repository_lines(updated, repository_lines)
  }
  writeLines(updated, path, useBytes = TRUE)
  invisible(TRUE)
}

#' Remove managed boosterpak setup blocks
#'
#' @param lines Character vector of `.Rprofile` lines.
#' @return `lines` without managed install-policy, repository, and
#'   post-activation repository blocks.
#' @noRd
remove_rprofile_boosterpak_setup_blocks <- function(lines) {
  lines <- remove_rprofile_install_policy_block(lines)
  lines <- remove_rprofile_repository_block(lines)
  remove_rprofile_repository_reapply_block(lines)
}

#' Remove the managed post-activation repository block
#'
#' @param lines Character vector of `.Rprofile` lines.
#' @return `lines` without the post-activation marker and the lines that follow
#'   it (the CRAN default mirror line and the Linux binary line).
#' @noRd
remove_rprofile_repository_reapply_block <- function(lines) {
  marker_idx <- which(lines == rprofile_repository_reapply_marker())
  if (length(marker_idx) == 0) {
    return(lines)
  }

  keep <- rep(TRUE, length(lines))
  for (idx in marker_idx) {
    keep[[idx]] <- FALSE
    cursor <- idx + 1L
    while (cursor <= length(lines) && is_rprofile_reapply_line(lines[[cursor]])) {
      keep[[cursor]] <- FALSE
      cursor <- cursor + 1L
    }
  }
  lines[keep]
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
      cursor <- cursor + 1L
    }
    if (cursor <= length(lines) && is_rprofile_ppm_linux_line(lines[[cursor]])) {
      keep[[cursor]] <- FALSE
    }
  }
  lines[keep]
}

#' Identify the managed Linux binary repository line
#'
#' Recognizes every form boosterpak has written: the original
#' `if (identical(R.version$os, "linux-gnu")) options(repos = sub(` line and
#' the later form that also checks `BOOSTERPAK_CONFIGURE_REPOSITORIES`.
#'
#' @param line A single `.Rprofile` line.
#' @return A single logical value.
#' @noRd
is_rprofile_ppm_linux_line <- function(line) {
  grepl(
    '^if \\(identical\\(R\\.version\\$os, "linux-gnu"\\).*\\) options\\(repos = sub\\(',
    trimws(line)
  )
}

#' Identify the managed CRAN default mirror line
#'
#' Recognizes the post-activation line written by `rprofile_cran_default_line()`.
#'
#' @param line A single `.Rprofile` line.
#' @return A single logical value.
#' @noRd
is_rprofile_cran_default_line <- function(line) {
  grepl(
    '^if \\(isNamespaceLoaded\\("renv"\\).*\\) local\\(\\{ for \\(option in c\\(',
    trimws(line)
  )
}

#' Identify any line in the managed post-activation block
#'
#' @param line A single `.Rprofile` line.
#' @return A single logical value.
#' @noRd
is_rprofile_reapply_line <- function(line) {
  is_rprofile_ppm_linux_line(line) || is_rprofile_cran_default_line(line)
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

#' Check for an renv activation line
#'
#' @param lines Character vector of `.Rprofile` lines.
#' @return A single logical value.
#' @noRd
has_renv_activation <- function(lines) {
  any(grepl('source\\([\'"]renv/activate\\.R[\'"]\\)', lines))
}

#' Split repository setup lines at the post-activation block
#'
#' @param lines Repository setup lines as built by
#'   `boosterpak_rprofile_setup_lines()`.
#' @return A list with `setup` (lines written before renv activation) and
#'   `reapply` (lines written after it, starting at the re-apply marker).
#' @noRd
split_repository_lines <- function(lines) {
  idx <- match(rprofile_repository_reapply_marker(), lines)
  if (is.na(idx)) {
    return(list(setup = lines, reapply = character()))
  }
  list(
    setup = lines[seq_len(idx - 1L)],
    reapply = lines[idx:length(lines)]
  )
}

#' Insert repository setup lines around renv activation
#'
#' Setup lines go before the activation line so renv sees them. Post-activation
#' lines go directly after it. Without an activation line there is no renv load
#' to undo, so the post-activation lines are not written.
#'
#' @param lines Character vector of `.Rprofile` lines.
#' @param repository_lines Repository setup lines to insert.
#' @return The updated character vector of `.Rprofile` lines.
#' @noRd
insert_repository_lines <- function(lines, repository_lines) {
  parts <- split_repository_lines(repository_lines)
  lines <- insert_before_renv_activation(lines, parts$setup)
  if (length(parts$reapply) > 0 && has_renv_activation(lines)) {
    lines <- insert_after_renv_activation(lines, parts$reapply)
  }
  lines
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

#' Insert the managed startup block after renv activation
#'
#' The block goes after the activation line and after the post-activation
#' repository lines when they are already there. The CRAN and Linux binary
#' re-apply then runs before the `boosters/` files are sourced, so the hook never
#' ends up between the activation line and the re-apply.
#'
#' @param lines Character vector of `.Rprofile` lines.
#' @param block The managed startup block lines.
#' @return The updated character vector of `.Rprofile` lines.
#' @noRd
insert_startup_block <- function(lines, block) {
  renv_line <- grep('source\\([\'"]renv/activate\\.R[\'"]\\)', lines)
  if (length(renv_line) == 0) {
    return(c(lines, block))
  }
  idx <- renv_line[[length(renv_line)]]
  marker <- which(lines == rprofile_repository_reapply_marker())
  marker <- marker[marker > idx]
  if (length(marker) > 0) {
    idx <- marker[[1]]
    while (idx + 1L <= length(lines) && is_rprofile_reapply_line(lines[[idx + 1L]])) {
      idx <- idx + 1L
    }
  }
  append(lines, block, after = idx)
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
