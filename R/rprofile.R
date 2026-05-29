has_rprofile_line <- function(root = ".") {
  path <- file.path(root, ".Rprofile")
  file.exists(path) && any(readLines(path, warn = FALSE) == rprofile_line())
}

ensure_rprofile_line <- function(root = ".", rprofile = c("ask", "yes", "no")) {
  rprofile <- match.arg(rprofile)
  path <- file.path(root, ".Rprofile")
  line <- rprofile_line()
  existing <- if (file.exists(path)) readLines(path, warn = FALSE) else character()

  legacy <- legacy_rprofile_line()
  if (line %in% existing && !legacy %in% existing) {
    return(invisible(FALSE))
  }

  if (identical(rprofile, "no")) {
    return(invisible(FALSE))
  }

  if (identical(rprofile, "ask")) {
    if (!interactive()) {
      cli::cli_abort(c(
        "{.file .Rprofile} does not contain the recommended boosterpak startup hook.",
        "i" = "Use {.code rprofile = 'yes'} to add it or {.code rprofile = 'no'} to skip package and helper auto-sourcing.",
        ">" = line
      ), call = NULL)
    }
    answer <- utils::menu(c("Yes (recommended)", "No"), title = paste("Add this boosterpak startup hook to .Rprofile?", line, sep = "\n"))
    if (!identical(answer, 1L)) {
      return(invisible(FALSE))
    }
  }

  existing <- existing[existing != legacy]
  updated <- insert_after_renv_activation(existing, line)
  writeLines(updated, path, useBytes = TRUE)
  invisible(TRUE)
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
