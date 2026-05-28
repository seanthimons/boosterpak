mutate_pack <- function(name, action = c("add", "remove"), root = ".", sync = TRUE, verbose = NULL) {
  check_verbose(verbose)
  action <- match.arg(action)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  config <- read_config(root)
  validate_config(config, root)

  if (identical(action, "add")) {
    load_pack(name, root)
  }

  current <- config$packs$declared %||% character()
  next_packs <- if (identical(action, "add")) {
    unique(c(current, name))
  } else {
    setdiff(current, name)
  }

  if (isTRUE(sync)) {
    ensure_project_renv(root)
  }

  update_declared_array(boosters_file(root), "packs", "declared", next_packs)

  if (isTRUE(sync)) {
    sync(mode = "apply", root = root, verbose = verbose)
  } else if (should_emit(verbose)) {
    cli::cli_alert_success("{if (action == 'add') 'Added' else 'Removed'} pack {.val {name}} in {.file boosters.toml}.")
  }
  invisible(next_packs)
}

#' Add a pack declaration
#'
#' @param name Pack name.
#' @param root Project root.
#' @param sync Whether to run additive sync after editing TOML.
#' @param verbose Whether to print routine summaries.
#' @return Updated declared pack names, invisibly.
#' @export
add_pack <- function(name, root = ".", sync = TRUE, verbose = NULL) {
  mutate_pack(name, "add", root, sync, verbose)
}

#' Remove a pack declaration
#'
#' @param name Pack name.
#' @param root Project root.
#' @param sync Whether to run additive sync after editing TOML.
#' @param verbose Whether to print routine summaries.
#' @return Updated declared pack names, invisibly.
#' @export
remove_pack <- function(name, root = ".", sync = TRUE, verbose = NULL) {
  mutate_pack(name, "remove", root, sync, verbose)
}

update_declared_array <- function(path, section, key, values) {
  read_toml_file(path)
  lines <- readLines(path, warn = FALSE)
  section_start <- grep(sprintf("^\\[%s\\]\\s*$", section), lines)
  if (length(section_start) != 1) {
    cli::cli_abort("Could not find unique [{section}] section in {.file {path}}.", call = NULL)
  }
  next_section <- grep("^\\[.+\\]\\s*$", lines)
  next_section <- next_section[next_section > section_start]
  section_end <- if (length(next_section) == 0) length(lines) else next_section[[1]] - 1
  key_lines <- grep(sprintf("^\\s*%s\\s*=", key), lines[section_start:section_end])
  if (length(key_lines) != 1) {
    cli::cli_abort("Could not safely update [{section}].{key} in {.file {path}}.", call = NULL)
  }
  target <- section_start + key_lines[[1]] - 1
  if (!grepl("\\[.*\\]", lines[[target]])) {
    cli::cli_abort(
      "Could not safely update multi-line [{section}].{key} in {.file {path}}.",
      call = NULL
    )
  }
  lines[[target]] <- sprintf("%s = [%s]", key, paste(sprintf('"%s"', vapply(values, escape_toml_string, character(1))), collapse = ", "))
  writeLines(lines, path, useBytes = TRUE)
  invisible(path)
}
