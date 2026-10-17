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
  removal_before <- if (identical(action, "remove")) {
    list(
      packs = resolve_config_pack_names(config, root),
      packages = resolve_config_packages(config, root)
    )
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
  removal <- NULL
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
  } else {
    if (isTRUE(remove_functions)) {
      remove_pack_functions(name, next_packs, root = root)
    }
    removal <- remove_pack_outputs(removal_before, root = root)
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
  if (identical(action, "remove")) {
    report_pack_removal(name, removal, verbose = verbose)
  }
  invisible(next_packs)
}

#' Regenerate outputs after a pack is removed from the declaration
#'
#' Drops `[settings.packs.<name>]` sections for packs that left the resolved
#' pack set, then rewrites `boosters/attach.R` so packages from the removed
#' pack stop attaching at startup. This needs no package installs, so it runs
#' whether or not sync is requested. Settings of packs that remain resolved
#' (including packs pulled in through `extends`) are left untouched.
#'
#' @param before Resolved pack names and packages captured before the edit.
#' @param root Project root.
#' @return A list with `sections` (pack names whose settings sections were
#'   removed) and `retained` (packages dropped from the declaration that are
#'   still listed in `renv.lock`), invisibly.
#' @noRd
remove_pack_outputs <- function(before, root = ".") {
  after <- read_config(root)
  dropped_packs <- setdiff(
    before$packs,
    resolve_config_pack_names(after, root)
  )
  dropped_packages <- setdiff(
    before$packages,
    resolve_config_packages(after, root)
  )
  sections <- remove_pack_settings_sections(boosters_file(root), dropped_packs)
  write_attach(root, verbose = FALSE)
  invisible(list(
    sections = sections,
    retained = intersect(dropped_packages, lockfile_packages(root))
  ))
}

#' Remove settings sections for packs that are no longer resolved
#'
#' The `[settings.packs.<name>]` table, its key lines, and its child tables
#' `[settings.packs.<name>.*]` are removed, together with one blank separator
#' line before it. Child tables are removed wherever they appear in the file,
#' including after an unrelated table. Each removed table ends at the next
#' table, and blank and comment lines directly above that next table are kept,
#' since they describe it. Other content in `boosters.toml` is preserved.
#'
#' @param path Path to `boosters.toml`.
#' @param pack_names Pack names whose settings sections should be removed.
#' @return The pack names whose sections were removed, invisibly.
#' @noRd
remove_pack_settings_sections <- function(path, pack_names) {
  removed <- character()
  if (length(pack_names) == 0 || !file.exists(path)) {
    return(invisible(removed))
  }
  lines <- readLines(path, warn = FALSE)
  for (pack_name in pack_names) {
    headers <- sub("\\s+#.*$", "", trimws(lines))
    blank_or_comment <- grepl("^\\s*(#.*)?$", lines)
    targets <- c(
      sprintf("[settings.packs.%s]", pack_name),
      sprintf('[settings.packs."%s"]', pack_name)
    )
    child_prefixes <- c(
      sprintf("[settings.packs.%s.", pack_name),
      sprintf('[settings.packs."%s".', pack_name)
    )
    owned <- headers %in% targets |
      startsWith(headers, child_prefixes[[1]]) |
      startsWith(headers, child_prefixes[[2]])
    # Owned tables are matched wherever they appear, so a child table that
    # follows an unrelated table is removed along with the parent.
    # Only lines shaped like a TOML table header count, so a line inside a
    # multi-line array such as `[1, 2]` is not mistaken for one.
    key <- "([A-Za-z0-9_-]+|\"[^\"]*\"|'[^']*')"
    header_pattern <- sprintf(
      "^\\[\\[?\\s*%s(\\s*\\.\\s*%s)*\\s*\\]\\]?$",
      key,
      key
    )
    table_lines <- which(grepl(header_pattern, headers))
    drop <- rep(FALSE, length(lines))
    for (k in seq_along(table_lines)) {
      first <- table_lines[[k]]
      if (!owned[[first]]) {
        next
      }
      last <- if (k < length(table_lines)) table_lines[[k + 1L]] - 1L else length(lines)
      if (k < length(table_lines)) {
        while (last > first && blank_or_comment[[last]]) {
          last <- last - 1L
        }
      }
      if (first > 1L && !nzchar(headers[[first - 1L]])) {
        first <- first - 1L
      }
      drop[seq.int(first, last)] <- TRUE
    }
    if (!any(drop)) {
      next
    }
    lines <- lines[!drop]
    removed <- c(removed, pack_name)
  }
  if (length(removed) > 0) {
    writeLines(lines, path, useBytes = TRUE)
  }
  invisible(removed)
}

#' Report what a pack removal did and did not change
#'
#' Reports removed settings sections when routine output is shown (see
#' `should_emit()`). Also prints a note that packages dropped from the
#' declaration remain in `renv.lock` and the project library until the user
#' runs `renv::snapshot()` and `renv::remove()`. That note is suppressed only by
#' `verbose = FALSE`.
#'
#' @param name Removed pack name.
#' @param removal Result of `remove_pack_outputs()`.
#' @param verbose Verbosity setting passed to `remove_pack()`.
#' @return `TRUE` invisibly when messages were emitted, otherwise `FALSE`.
#' @noRd
report_pack_removal <- function(name, removal, verbose = NULL) {
  if (identical(verbose, FALSE) || is.null(removal)) {
    return(invisible(FALSE))
  }
  if (length(removal$sections) > 0 && should_emit(verbose)) {
    cli::cli_alert_info(
      "Removed {length(removal$sections)} settings section{?s} ({.val {removal$sections}}) from {.file boosters.toml}."
    )
  }
  if (length(removal$retained) > 0) {
    cli::cli_inform(c(
      "!" = "{length(removal$retained)} package{?s} from pack {.val {name}} still listed in {.file renv.lock}: {.pkg {removal$retained}}.",
      "i" = "boosterpak does not change {.file renv.lock} or the project library when a pack is removed.",
      "i" = "Run {.code renv::snapshot()} to drop them from the lockfile, and {.code renv::remove()} to uninstall them."
    ))
  }
  invisible(TRUE)
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
#' Removes the pack from `boosters.toml`, drops its `[settings.packs.<name>]`
#' section when no remaining pack needs it, and regenerates
#' `boosters/attach.R` so its packages stop attaching at startup. This happens
#' whether or not `sync` is `TRUE`.
#'
#' Removing a pack does not uninstall anything. Packages it provided stay in
#' `renv.lock` and the project library; run `renv::snapshot()` to drop them
#' from the lockfile and `renv::remove()` to uninstall them. A note saying so
#' is printed unless `verbose = FALSE`.
#'
#' @param name Pack name.
#' @param root Project root.
#' @param sync Whether to run additive sync after editing TOML.
#' @param remove_functions Whether to remove unchanged function files provided
#'   only by the removed pack.
#' @param verbose Whether to print routine summaries and the note about
#'   packages that remain installed. `FALSE` suppresses both.
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
