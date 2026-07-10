has_rprofile_line <- function(root = ".") {
  path <- file.path(root, ".Rprofile")
  file.exists(path) && any(readLines(path, warn = FALSE) == rprofile_line())
}

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
  repo_missing <- length(repository_lines) > 0 &&
    !rprofile_repository_marker() %in% existing
  hook_missing <- !line %in% existing || legacy %in% existing

  if (!repo_missing && !hook_missing) {
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
  if (repo_missing) {
    updated <- insert_before_renv_activation(updated, repository_lines)
  }
  if (!line %in% updated) {
    updated <- insert_after_renv_activation(updated, line)
  }
  writeLines(updated, path, useBytes = TRUE)
  invisible(TRUE)
}

insert_before_renv_activation <- function(lines, new_lines) {
  renv_line <- grep('source\\([\'"]renv/activate\\.R[\'"]\\)', lines)
  if (length(renv_line) > 0) {
    idx <- renv_line[[1]]
    append(lines, new_lines, after = idx - 1L)
  } else {
    c(new_lines, lines)
  }
}

insert_after_renv_activation <- function(lines, line) {
  renv_line <- grep('source\\([\'"]renv/activate\\.R[\'"]\\)', lines)
  if (length(renv_line) > 0) {
    idx <- renv_line[[length(renv_line)]]
    append(lines, line, after = idx)
  } else {
    c(lines, line)
  }
}
