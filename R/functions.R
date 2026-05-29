function_catalog <- function() {
  data.frame(
    name = c("ni", "my_skim", "theme_custom", "geo_mean"),
    object = c("%ni%", "my_skim", "theme_custom", "geo_mean"),
    description = c(
      "Negation of %in%.",
      "skim_with() preset for numeric EDA with geometric mean and inline histogram.",
      "Minimal ggplot2 theme with white panels and angled x-axis labels.",
      "Geometric mean of positive values."
    ),
    path = vapply(c("ni", "my_skim", "theme_custom", "geo_mean"), catalog_function_file, character(1)),
    stringsAsFactors = FALSE
  )
}

validate_function_name <- function(name) {
  catalog <- function_catalog()
  match <- catalog[catalog$name == name, , drop = FALSE]
  if (nrow(match) == 0) {
    hint <- suggest_pack_name(name, catalog$name)
    cli::cli_abort(c(
      "{.val {name}} is not a known function.",
      if (!is.null(hint)) "i" = "Did you mean {.val {hint}}?",
      "Available functions: {paste(catalog$name, collapse = ', ')}"
    ), call = NULL)
  }
  if (!file.exists(match$path[[1]])) {
    cli::cli_abort("Catalog file for function {.val {name}} is missing.", call = NULL)
  }
  invisible(match)
}

installed_functions <- function(config) {
  toml_string_array(config$functions$installed %||% character(), "[functions].installed")
}

validate_config_functions <- function(config) {
  installed <- installed_functions(config)
  invisible(lapply(installed, validate_function_name))
  invisible(TRUE)
}

ensure_functions_section <- function(path) {
  lines <- readLines(path, warn = FALSE)
  if (!any(grepl("^\\[functions\\]\\s*$", lines))) {
    writeLines(c(lines, "", "[functions]", "installed = []"), path, useBytes = TRUE)
  }
  invisible(path)
}

update_installed_functions <- function(root, values) {
  path <- boosters_file(root)
  ensure_functions_section(path)
  update_declared_array(path, "functions", "installed", values)
}

materialize_function <- function(name, root = ".", overwrite = FALSE) {
  match <- validate_function_name(name)
  dir.create(functions_dir(root), recursive = TRUE, showWarnings = FALSE)
  target <- function_file(name, root)
  if (file.exists(target) && !isTRUE(overwrite)) {
    cli::cli_abort(
      "{.file {target}} already exists. Use {.code overwrite = TRUE} to replace it.",
      call = NULL
    )
  }
  copied <- file.copy(match$path[[1]], target, overwrite = TRUE)
  if (!isTRUE(copied)) {
    cli::cli_abort("Failed to write {.file {target}}.", call = NULL)
  }
  invisible(target)
}

materialize_pack_function <- function(pack_path, name, root = ".", overwrite = FALSE) {
  pack <- load_pack(tools::file_path_sans_ext(basename(pack_path)), root)
  source <- pack_function_source_file(pack_path, name, pack$.__scope__)
  target <- function_file(name, root)
  if (!file.exists(source)) {
    cli::cli_abort("Pack function source {.file {source}} is missing.", call = NULL)
  }
  dir.create(functions_dir(root), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(target) && !isTRUE(overwrite)) {
    cli::cli_abort(
      "{.file {target}} already exists. Use {.code overwrite_functions = TRUE} to replace it.",
      call = NULL
    )
  }
  copied <- file.copy(source, target, overwrite = TRUE)
  if (!isTRUE(copied)) {
    cli::cli_abort("Failed to write {.file {target}}.", call = NULL)
  }
  invisible(target)
}

pack_function_source_file <- function(pack_path, name, scope) {
  pack_function_file(pack_path, name)
}

materialize_pack_functions <- function(names, root = ".", overwrite = FALSE) {
  packs <- unique(unlist(lapply(names, resolve_pack_names, root = root), use.names = FALSE))
  invisible(lapply(packs, function(pack_name) {
    pack <- load_pack(pack_name, root)
    functions <- toml_string_array(pack$functions %||% character(), sprintf("%s functions", pack$.__path__))
    invisible(lapply(functions, function(name) {
      target <- function_file(name, root)
      if (!file.exists(target) || isTRUE(overwrite)) {
        materialize_pack_function(pack$.__path__, name, root, overwrite)
      }
    }))
  }))
}

check_pack_function_conflicts <- function(names, root = ".") {
  packs <- unique(unlist(lapply(names, resolve_pack_names, root = root), use.names = FALSE))
  conflicts <- character()
  invisible(lapply(packs, function(pack_name) {
    pack <- load_pack(pack_name, root)
    functions <- toml_string_array(pack$functions %||% character(), sprintf("%s functions", pack$.__path__))
    conflicts <<- c(conflicts, functions[file.exists(function_file(functions, root))])
  }))
  conflicts <- unique(conflicts)
  if (length(conflicts) > 0) {
    paths <- paste(function_file(conflicts, root), collapse = ", ")
    cli::cli_abort(
      "Function file{?s} already exist{?s}: {paths}. Use {.code overwrite_functions = TRUE} to replace {?it/them}.",
      call = NULL
    )
  }
  invisible(TRUE)
}

sync_functions <- function(config, root = ".") {
  installed <- installed_functions(config)
  invisible(lapply(installed, function(name) {
    if (!file.exists(function_file(name, root))) {
      materialize_function(name, root = root, overwrite = FALSE)
    }
  }))
  declared <- toml_string_array(config$packs$declared %||% character(), "[packs].declared")
  materialize_pack_functions(declared, root = root, overwrite = FALSE)
  installed
}

pack_provided_function_names <- function(config, root = ".") {
  declared <- toml_string_array(config$packs$declared %||% character(), "[packs].declared")
  unique(unlist(lapply(declared, resolve_pack_functions, root = root), use.names = FALSE))
}

remove_pack_functions <- function(name, remaining_packs, root = ".") {
  pack <- load_pack(name, root)
  removable <- toml_string_array(pack$functions %||% character(), sprintf("%s functions", pack$.__path__))
  if (length(removable) == 0) {
    return(invisible(character()))
  }
  still_provided <- unique(unlist(lapply(remaining_packs, resolve_pack_functions, root = root), use.names = FALSE))
  removed <- character()
  for (function_name in setdiff(removable, still_provided)) {
    target <- function_file(function_name, root)
    source <- pack_function_file(pack$.__path__, function_name)
    if (file.exists(target) && file.exists(source) && identical(readLines(target, warn = FALSE), readLines(source, warn = FALSE))) {
      unlink(target)
      removed <- c(removed, function_name)
    }
  }
  invisible(removed)
}

#' List available materializable functions
#'
#' @param root Project root.
#' @param verbose Whether to print a routine summary.
#' @return A data frame of available functions and installation status, invisibly.
#' @export
list_functions <- function(root = ".", verbose = NULL) {
  check_verbose(verbose)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  catalog <- function_catalog()
  installed <- if (file.exists(boosters_file(root))) {
    installed_functions(read_config(root))
  } else {
    character()
  }
  catalog$installed <- catalog$name %in% installed & file.exists(function_file(catalog$name, root))
  if (should_emit(verbose)) {
    cli::cli_h1("Available booster functions")
    apply(catalog, 1, function(row) {
      cli::cli_li("{.val {row[['name']]}} [{if (identical(row[['installed']], 'TRUE')) 'installed' else 'available'}]: {row[['description']]}")
    })
  }
  invisible(catalog)
}

#' Materialize a helper function
#'
#' @param name Function catalog name.
#' @param root Project root.
#' @param overwrite Whether to replace an existing materialized file.
#' @param verbose Whether to print a routine summary.
#' @return Materialized file path, invisibly.
#' @export
add_function <- function(name, root = ".", overwrite = FALSE, verbose = NULL) {
  check_verbose(verbose)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  config <- read_config(root)
  validate_config(config, root)
  path <- materialize_function(name, root, overwrite)
  installed <- unique(c(installed_functions(config), name))
  update_installed_functions(root, installed)
  if (should_emit(verbose)) {
    cli::cli_alert_success("Materialized {.val {name}} to {.file {path}}.")
  }
  invisible(path)
}

#' Remove a materialized helper function
#'
#' @param name Function catalog name.
#' @param root Project root.
#' @param verbose Whether to print a routine summary.
#' @return Remaining installed function names, invisibly.
#' @export
remove_function <- function(name, root = ".", verbose = NULL) {
  check_verbose(verbose)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  config <- read_config(root)
  validate_config(config, root)
  validate_function_name(name)
  path <- function_file(name, root)
  if (file.exists(path)) {
    unlink(path)
  }
  installed <- setdiff(installed_functions(config), name)
  update_installed_functions(root, installed)
  if (should_emit(verbose)) {
    cli::cli_alert_success("Removed materialized function {.val {name}}.")
  }
  invisible(installed)
}

#' Check materialized helper functions for drift
#'
#' @param root Project root.
#' @param verbose Whether to print a routine summary.
#' @return A data frame with drift status, invisibly.
#' @export
check_functions <- function(root = ".", verbose = NULL) {
  check_verbose(verbose)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  config <- read_config(root)
  validate_config(config, root)
  installed <- installed_functions(config)
  rows <- lapply(installed, function(name) {
    validate_function_name(name)
    local <- function_file(name, root)
    package <- catalog_function_file(name)
    exists <- file.exists(local)
    matches <- exists && identical(readLines(local, warn = FALSE), readLines(package, warn = FALSE))
    data.frame(name = name, path = local, exists = exists, matches = matches, stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows) %||% data.frame(
    name = character(),
    path = character(),
    exists = logical(),
    matches = logical()
  )
  if (should_emit(verbose)) {
    apply(out, 1, function(row) {
      if (!identical(row[["exists"]], "TRUE")) {
        cli::cli_alert_warning("{.file {row[['path']]}} is missing. Run {.code boosterpak::sync()} to rematerialize it.")
      } else if (identical(row[["matches"]], "TRUE")) {
        cli::cli_alert_success("{.file {row[['path']]}} matches package version.")
      } else {
        cli::cli_alert_info("{.file {row[['path']]}} differs from package version.")
      }
    })
  }
  invisible(out)
}

#' Diff a materialized helper function against the package version
#'
#' @param name Function catalog name.
#' @param root Project root.
#' @param verbose Whether to print the diff.
#' @return Character vector containing a simple line diff, invisibly.
#' @export
diff_function <- function(name, root = ".", verbose = NULL) {
  check_verbose(verbose)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  validate_function_name(name)
  local <- function_file(name, root)
  package <- catalog_function_file(name)
  if (!file.exists(local)) {
    cli::cli_abort("{.file {local}} does not exist. Run {.code boosterpak::add_function({name})} first.", call = NULL)
  }
  diff <- simple_line_diff(readLines(package, warn = FALSE), readLines(local, warn = FALSE))
  if (should_emit(verbose)) {
    cli::cat_line(diff)
  }
  invisible(diff)
}

simple_line_diff <- function(package_lines, local_lines) {
  n <- max(length(package_lines), length(local_lines))
  out <- c("--- package", "+++ local")
  for (i in seq_len(n)) {
    package_line <- if (i <= length(package_lines)) package_lines[[i]] else NULL
    local_line <- if (i <= length(local_lines)) local_lines[[i]] else NULL
    if (identical(package_line, local_line)) {
      next
    }
    if (!is.null(package_line)) {
      out <- c(out, paste0("-", package_line))
    }
    if (!is.null(local_line)) {
      out <- c(out, paste0("+", local_line))
    }
  }
  if (length(out) == 2) {
    out <- c(out, "(no differences)")
  }
  out
}
