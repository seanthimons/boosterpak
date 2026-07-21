#' Mutate a pack declaration
#'
#' @param name Pack name.
#' @param action Whether to add or remove the declaration.
#' @param root Project root.
#' @param sync Whether to synchronize packages after editing the configuration.
#' @param hydrate Whether renv-library sync may reuse packages from local
#'   libraries before downloading them.
#' @param overwrite_functions Whether to overwrite function files supplied by
#'   an added pack.
#' @param remove_functions Whether to remove unchanged function files supplied
#'   only by a removed pack.
#' @param verbose Whether to print routine summaries.
#' @param library Package-library strategy, or `NULL` to use configuration.
#' @return The updated declared pack names, invisibly.
#' @noRd
mutate_pack <- function(
  name,
  action = c("add", "remove"),
  root = ".",
  sync = TRUE,
  hydrate = TRUE,
  overwrite_functions = FALSE,
  remove_functions = FALSE,
  verbose = NULL,
  library = NULL
) {
  check_verbose(verbose)
  action <- match.arg(action)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  config <- read_config(root)
  validate_config(config, root)

  if (identical(action, "add")) {
    load_pack(name, root)
  }

  current <- config$packs$declared %||% character()
  is_new_add <- identical(action, "add") && !name %in% current
  next_packs <- if (identical(action, "add")) {
    unique(c(current, name))
  } else {
    setdiff(current, name)
  }

  if (isTRUE(sync)) {
    library <- resolve_library_strategy(library, config)
    ensure_package_library(root, library)
  }
  if (is_new_add && !isTRUE(overwrite_functions)) {
    check_pack_function_conflicts(name, root)
  }

  update_declared_array(boosters_file(root), "packs", "declared", next_packs)
  materialize_config_packs(read_config(root), root)
  if (identical(action, "add")) {
    materialize_pack_functions(
      name,
      root = root,
      overwrite = overwrite_functions
    )
    source_pack_functions(name, root = root)
    if (is_new_add) {
      scaffold_pack_settings(name, root = root)
    }
  } else if (isTRUE(remove_functions)) {
    remove_pack_functions(name, next_packs, root = root)
  }

  if (isTRUE(sync)) {
    sync(
      mode = "apply",
      root = root,
      hydrate = hydrate,
      verbose = verbose,
      library = library
    )
    if (is_new_add) {
      run_pack_on_add_hooks(name, root = root)
    }
  } else if (should_emit(verbose)) {
    cli::cli_alert_success(
      "{if (action == 'add') 'Added' else 'Removed'} pack {.val {name}} in {.file boosters.toml}."
    )
  }
  invisible(next_packs)
}

#' Add a pack declaration
#'
#' @param name Pack name.
#' @param root Project root.
#' @param sync Whether to run additive sync after editing TOML.
#' @param hydrate Whether renv-library additive sync should reuse packages from
#'   renv-discoverable local libraries before downloading with pak. The active
#'   library strategy ignores this option.
#' @param overwrite_functions Whether to overwrite existing function files
#'   provided by the pack.
#' @param verbose Whether to print routine summaries.
#' @param library Package-library strategy passed to [sync()]. `NULL` uses the
#'   project configuration.
#' @return Updated declared pack names, invisibly.
#' @export
add_pack <- function(
  name,
  root = ".",
  sync = TRUE,
  hydrate = TRUE,
  overwrite_functions = FALSE,
  verbose = NULL,
  library = NULL
) {
  mutate_pack(
    name,
    "add",
    root,
    sync,
    hydrate = hydrate,
    overwrite_functions = overwrite_functions,
    verbose = verbose,
    library = library
  )
}

#' Remove a pack declaration
#'
#' @param name Pack name.
#' @param root Project root.
#' @param sync Whether to run additive sync after editing TOML.
#' @param remove_functions Whether to remove unchanged function files provided
#'   only by the removed pack.
#' @param verbose Whether to print routine summaries.
#' @param library Package-library strategy passed to [sync()]. `NULL` uses the
#'   project configuration.
#' @return Updated declared pack names, invisibly.
#' @export
remove_pack <- function(
  name,
  root = ".",
  sync = TRUE,
  remove_functions = FALSE,
  verbose = NULL,
  library = NULL
) {
  mutate_pack(
    name,
    "remove",
    root,
    sync,
    remove_functions = remove_functions,
    verbose = verbose,
    library = library
  )
}

#' Update a declared TOML array
#'
#' @param path Path to the TOML configuration file.
#' @param section Name of the TOML section.
#' @param key Name of the array field within `section`.
#' @param values Character vector of values to write.
#' @return The configuration file path, invisibly.
#' @noRd
update_declared_array <- function(path, section, key, values) {
  read_toml_file(path)
  lines <- readLines(path, warn = FALSE)
  section_start <- grep(sprintf("^\\[%s\\]\\s*$", section), lines)
  if (length(section_start) != 1) {
    cli::cli_abort(
      "Could not find unique [{section}] section in {.file {path}}.",
      call = NULL
    )
  }
  next_section <- grep("^\\[.+\\]\\s*$", lines)
  next_section <- next_section[next_section > section_start]
  section_end <- if (length(next_section) == 0) {
    length(lines)
  } else {
    next_section[[1]] - 1
  }
  key_lines <- grep(
    sprintf("^\\s*%s\\s*=", key),
    lines[section_start:section_end]
  )
  if (length(key_lines) != 1) {
    cli::cli_abort(
      "Could not safely update [{section}].{key} in {.file {path}}.",
      call = NULL
    )
  }
  target <- section_start + key_lines[[1]] - 1
  if (!grepl("\\[.*\\]", lines[[target]])) {
    cli::cli_abort(
      "Could not safely update multi-line [{section}].{key} in {.file {path}}.",
      call = NULL
    )
  }
  lines[[target]] <- sprintf(
    "%s = [%s]",
    key,
    paste(
      sprintf('"%s"', vapply(values, escape_toml_string, character(1))),
      collapse = ", "
    )
  )
  writeLines(lines, path, useBytes = TRUE)
  invisible(path)
}
