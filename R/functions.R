#' Build the Function Catalog
#'
#' @param root Project root.
#' @return A data frame with one row per uniquely named available function.
#' @noRd
function_catalog <- function(root = ".") {
  packs <- available_packs(root)
  rows <- lapply(seq_len(nrow(packs)), function(i) {
    functions <- strsplit(packs$functions[[i]], ", ", fixed = TRUE)[[1]]
    functions <- functions[nzchar(functions)]
    if (length(functions) == 0) {
      return(NULL)
    }
    data.frame(
      name = functions,
      pack = packs$name[[i]],
      description = packs$description[[i]],
      path = vapply(
        functions,
        function(name) pack_function_file(packs$path[[i]], name),
        character(1)
      ),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows) %||%
    data.frame(
      name = character(),
      pack = character(),
      description = character(),
      path = character(),
      stringsAsFactors = FALSE
    )
  out[!duplicated(out$name), , drop = FALSE]
}

#' Validate a Function Name
#'
#' @param name Function catalog name.
#' @param root Project root.
#' @return The matching catalog row, invisibly.
#' @noRd
validate_function_name <- function(name, root = ".") {
  catalog <- function_catalog(root)
  match <- catalog[catalog$name == name, , drop = FALSE]
  if (nrow(match) == 0) {
    hint <- suggest_pack_name(name, catalog$name)
    cli::cli_abort(
      c(
        "{.val {name}} is not a known function.",
        if (!is.null(hint)) "i" = "Did you mean {.val {hint}}?",
        "Available functions: {paste(catalog$name, collapse = ', ')}"
      ),
      call = NULL
    )
  }
  if (!file.exists(match$path[[1]])) {
    cli::cli_abort(
      "Catalog file for function {.val {name}} is missing.",
      call = NULL
    )
  }
  invisible(match)
}

#' Read Installed Function Names
#'
#' @param config Parsed project configuration.
#' @return A character vector of installed function names.
#' @noRd
installed_functions <- function(config) {
  toml_string_array(
    config$functions$installed %||% character(),
    "[functions].installed"
  )
}

#' Validate Configured Functions
#'
#' @param config Parsed project configuration.
#' @param root Project root.
#' @return `TRUE`, invisibly.
#' @noRd
validate_config_functions <- function(config, root = ".") {
  installed <- installed_functions(config)
  invisible(lapply(installed, validate_function_name, root = root))
  invisible(TRUE)
}

#' Ensure the Functions Configuration Section Exists
#'
#' @param path Path to a `boosters.toml` file.
#' @return `path`, invisibly.
#' @noRd
ensure_functions_section <- function(path) {
  lines <- readLines(path, warn = FALSE)
  if (!any(grepl("^\\[functions\\]\\s*$", lines))) {
    writeLines(
      c(lines, "", "[functions]", "installed = []"),
      path,
      useBytes = TRUE
    )
  }
  invisible(path)
}

#' Update Installed Function Names
#'
#' @param root Project root.
#' @param values Character vector of function names to record as installed.
#' @return The path to `boosters.toml`, invisibly.
#' @noRd
update_installed_functions <- function(root, values) {
  path <- boosters_file(root)
  ensure_functions_section(path)
  update_declared_array(path, "functions", "installed", values)
}

#' Materialize a Catalog Function
#'
#' @param name Function catalog name.
#' @param root Project root.
#' @param overwrite Whether to replace an existing function file.
#' @return The materialized file path, invisibly.
#' @noRd
materialize_function <- function(name, root = ".", overwrite = FALSE) {
  match <- validate_function_name(name, root)
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

#' Materialize a Pack Function
#'
#' @param pack_path Path to the pack manifest.
#' @param name Function name declared by the pack.
#' @param root Project root.
#' @param overwrite Whether to replace an existing function file.
#' @return The materialized file path, invisibly.
#' @noRd
materialize_pack_function <- function(
  pack_path,
  name,
  root = ".",
  overwrite = FALSE
) {
  pack <- load_pack(tools::file_path_sans_ext(basename(pack_path)), root)
  source <- pack_function_source_file(pack_path, name, pack$.__scope__)
  target <- function_file(name, root)
  if (!file.exists(source)) {
    cli::cli_abort(
      "Pack function source {.file {source}} is missing.",
      call = NULL
    )
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

#' Locate a Pack Function Source File
#'
#' @param pack_path Path to the pack manifest.
#' @param name Function name declared by the pack.
#' @param scope Pack scope. Currently unused because the manifest path determines
#'   the source location.
#' @return The path to the pack's function source file.
#' @noRd
pack_function_source_file <- function(pack_path, name, scope) {
  pack_function_file(pack_path, name)
}

#' Materialize Functions Provided by Packs
#'
#' @param names Character vector of pack names.
#' @param root Project root.
#' @param overwrite Whether to replace existing function files.
#' @return A list of per-pack materialization results, invisibly.
#' @noRd
materialize_pack_functions <- function(names, root = ".", overwrite = FALSE) {
  packs <- unique(unlist(
    lapply(names, resolve_pack_names, root = root),
    use.names = FALSE
  ))
  invisible(lapply(packs, function(pack_name) {
    pack <- load_pack(pack_name, root)
    functions <- toml_string_array(
      pack$functions %||% character(),
      sprintf("%s functions", pack$.__path__)
    )
    invisible(lapply(functions, function(name) {
      target <- function_file(name, root)
      if (!file.exists(target) || isTRUE(overwrite)) {
        materialize_pack_function(pack$.__path__, name, root, overwrite)
      }
    }))
  }))
}

#' Source Materialized Function Files
#'
#' @param names Character vector of function names.
#' @param root Project root.
#' @param envir Environment in which to source the functions.
#' @return A list of source results, invisibly.
#' @noRd
source_function_files <- function(names, root = ".", envir = .GlobalEnv) {
  invisible(lapply(names, function(name) {
    path <- function_file(name, root)
    if (!file.exists(path)) {
      cli::cli_abort(
        "Function {.val {name}} is declared but {.file {path}} is missing.",
        call = NULL
      )
    }
    sys.source(path, envir = envir)
  }))
}

#' Source Functions Provided by Packs
#'
#' @param names Character vector of pack names.
#' @param root Project root.
#' @param envir Environment in which to source the functions.
#' @return The resolved function names, invisibly.
#' @noRd
source_pack_functions <- function(names, root = ".", envir = .GlobalEnv) {
  functions <- unique(unlist(
    lapply(names, resolve_pack_functions, root = root),
    use.names = FALSE
  ))
  source_function_files(functions, root = root, envir = envir)
  invisible(functions)
}

#' Run Pack On-Add Hooks
#'
#' @param name Pack name.
#' @param root Project root used as the working directory while hooks run.
#' @param envir Environment containing the sourced hook functions.
#' @return The resolved hook names, invisibly.
#' @noRd
run_pack_on_add_hooks <- function(name, root = ".", envir = .GlobalEnv) {
  hooks <- resolve_pack_on_add_hooks(name, root = root)
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(root)
  invisible(lapply(hooks, function(hook) {
    if (!exists(hook, envir = envir, mode = "function", inherits = FALSE)) {
      cli::cli_abort(
        "On-add hook {.fun {hook}} is declared but was not sourced into {.code .GlobalEnv}.",
        call = NULL
      )
    }
    hook_fn <- get(hook, envir = envir, mode = "function", inherits = FALSE)
    hook_fn()
  }))
  invisible(hooks)
}

#' Check for Pack Function Conflicts
#'
#' @param names Character vector of pack names.
#' @param root Project root.
#' @return `TRUE`, invisibly, if no pack function conflicts exist.
#' @noRd
check_pack_function_conflicts <- function(names, root = ".") {
  packs <- unique(unlist(
    lapply(names, resolve_pack_names, root = root),
    use.names = FALSE
  ))
  conflicts <- character()
  invisible(lapply(packs, function(pack_name) {
    pack <- load_pack(pack_name, root)
    functions <- toml_string_array(
      pack$functions %||% character(),
      sprintf("%s functions", pack$.__path__)
    )
    conflicts <<- c(
      conflicts,
      functions[file.exists(function_file(functions, root))]
    )
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

#' Synchronize Configured Functions
#'
#' @param config Parsed project configuration.
#' @param root Project root.
#' @return A character vector of installed catalog function names.
#' @noRd
sync_functions <- function(config, root = ".") {
  installed <- installed_functions(config)
  invisible(lapply(installed, function(name) {
    if (!file.exists(function_file(name, root))) {
      materialize_function(name, root = root, overwrite = FALSE)
    }
  }))
  declared <- toml_string_array(
    config$packs$declared %||% character(),
    "[packs].declared"
  )
  materialize_pack_functions(declared, root = root, overwrite = FALSE)
  source_pack_functions(declared, root = root)
  installed
}

#' Resolve Function Names Provided by Configured Packs
#'
#' @param config Parsed project configuration.
#' @param root Project root.
#' @return A character vector of unique function names.
#' @noRd
pack_provided_function_names <- function(config, root = ".") {
  declared <- toml_string_array(
    config$packs$declared %||% character(),
    "[packs].declared"
  )
  unique(unlist(
    lapply(declared, resolve_pack_functions, root = root),
    use.names = FALSE
  ))
}

#' Remove Unshared Pack Functions
#'
#' @param name Name of the pack being removed.
#' @param remaining_packs Character vector of pack names that remain declared.
#' @param root Project root.
#' @return A character vector of removed function names, invisibly.
#' @noRd
remove_pack_functions <- function(name, remaining_packs, root = ".") {
  pack <- load_pack(name, root)
  removable <- toml_string_array(
    pack$functions %||% character(),
    sprintf("%s functions", pack$.__path__)
  )
  if (length(removable) == 0) {
    return(invisible(character()))
  }
  still_provided <- unique(unlist(
    lapply(remaining_packs, resolve_pack_functions, root = root),
    use.names = FALSE
  ))
  removed <- character()
  for (function_name in setdiff(removable, still_provided)) {
    target <- function_file(function_name, root)
    source <- pack_function_file(pack$.__path__, function_name)
    if (
      file.exists(target) &&
        file.exists(source) &&
        identical(
          readLines(target, warn = FALSE),
          readLines(source, warn = FALSE)
        )
    ) {
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
  catalog <- function_catalog(root)
  installed <- if (file.exists(boosters_file(root))) {
    installed_functions(read_config(root))
  } else {
    character()
  }
  catalog$installed <- catalog$name %in%
    installed &
    file.exists(function_file(catalog$name, root))
  if (should_emit(verbose)) {
    cli::cli_h1("Available booster functions")
    apply(catalog, 1, function(row) {
      cli::cli_li(
        "{.val {row[['name']]}} [{if (identical(row[['installed']], 'TRUE')) 'installed' else 'available'}]: {row[['description']]}"
      )
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
  validate_function_name(name, root)
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
    validate_function_name(name, root)
    local <- function_file(name, root)
    package <- catalog_function_file(name, root)
    exists <- file.exists(local)
    matches <- exists &&
      identical(
        readLines(local, warn = FALSE),
        readLines(package, warn = FALSE)
      )
    data.frame(
      name = name,
      path = local,
      exists = exists,
      matches = matches,
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows) %||%
    data.frame(
      name = character(),
      path = character(),
      exists = logical(),
      matches = logical()
    )
  if (should_emit(verbose)) {
    apply(out, 1, function(row) {
      if (!identical(row[["exists"]], "TRUE")) {
        cli::cli_alert_warning(
          "{.file {row[['path']]}} is missing. Run {.code boosterpak::sync()} to rematerialize it."
        )
      } else if (identical(row[["matches"]], "TRUE")) {
        cli::cli_alert_success(
          "{.file {row[['path']]}} matches package version."
        )
      } else {
        cli::cli_alert_info(
          "{.file {row[['path']]}} differs from package version."
        )
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
  validate_function_name(name, root)
  local <- function_file(name, root)
  package <- catalog_function_file(name, root)
  if (!file.exists(local)) {
    cli::cli_abort(
      "{.file {local}} does not exist. Run {.code boosterpak::add_function({name})} first.",
      call = NULL
    )
  }
  diff <- simple_line_diff(
    readLines(package, warn = FALSE),
    readLines(local, warn = FALSE)
  )
  if (should_emit(verbose)) {
    cli::cat_line(diff)
  }
  invisible(diff)
}

#' Read a pack setting
#'
#' Looks up a setting for a pack, preferring the project-level override in
#' `[settings.packs.<pack>]` of `boosters.toml`, then the pack's own
#' `[settings]` defaults, then `default`.
#'
#' @param pack Pack name.
#' @param key Setting key.
#' @param default Value returned when the setting is not declared anywhere.
#' @param root Project root.
#' @return The setting value.
#' @export
pack_setting <- function(pack, key, default = NULL, root = ".") {
  value <- NULL
  if (file.exists(boosters_file(root))) {
    config <- tryCatch(read_config(root), error = function(err) NULL)
    packs <- (config$settings %||% list())$packs %||% list()
    if (is.list(packs) && !is.data.frame(packs)) {
      entry <- packs[[pack]]
      if (is.list(entry) && !is.data.frame(entry)) {
        value <- entry[[key]]
      }
    }
  }
  if (is.null(value)) {
    pack_data <- tryCatch(load_pack(pack, root), error = function(err) NULL)
    settings <- pack_data$settings %||% list()
    if (is.list(settings) && !is.data.frame(settings)) {
      value <- settings[[key]]
    }
  }
  value %||% default
}

#' Build a Simple Line Diff
#'
#' @param package_lines Character vector of package-version lines.
#' @param local_lines Character vector of local-version lines.
#' @return A character vector containing a simple line diff.
#' @noRd
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
