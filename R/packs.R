read_toml_file <- function(path) {
  data <- tryCatch(
    toml::read_toml(path),
    error = function(err) {
      cli::cli_abort(c(
        "{.file {path}} is not valid TOML.",
        "x" = conditionMessage(err)
      ), call = NULL)
    }
  )
  normalize_toml_arrays(data)
}

normalize_toml_arrays <- function(x) {
  if (is.list(x) && !is.data.frame(x)) {
    if (length(x) == 0) {
      return(x)
    }
    if (all(vapply(x, is.character, logical(1))) && all(vapply(x, length, integer(1)) <= 1)) {
      preserve_names <- !is.null(names(x)) && all(nzchar(names(x)))
      return(unlist(x, use.names = preserve_names))
    }
    return(lapply(x, normalize_toml_arrays))
  }
  x
}

pack_paths <- function(root = ".") {
  builtin_dir <- system.file("packs", package = "boosterpak")
  paths <- list(
    project = project_packs_dir(root),
    user = user_packs_dir(),
    builtin = builtin_dir
  )
  paths[vapply(paths, nzchar, logical(1))]
}

discover_pack_scope <- function(scope, dir) {
  if (!dir.exists(dir)) {
    return(data.frame(
      name = character(),
      description = character(),
      scope = character(),
      sources = character(),
      path = character()
    ))
  }

  flat_files <- list.files(dir, pattern = "\\.toml$", full.names = TRUE)
  nested_dirs <- list.dirs(dir, recursive = FALSE, full.names = TRUE)
  nested_files <- file.path(nested_dirs, sprintf("%s.toml", basename(nested_dirs)))
  nested_files <- nested_files[file.exists(nested_files)]
  files <- c(flat_files, nested_files)
  rows <- lapply(files, function(path) {
    data <- read_toml_file(path)
    name <- data$name %||% tools::file_path_sans_ext(basename(path))
    validate_pack_layout(name, path, data)
    data.frame(
      name = name,
      description = data$description %||% "",
      scope = scope,
      sources = summarize_sources(data$sources %||% list()),
      functions = paste(toml_string_array(data$functions %||% character(), sprintf("%s functions", path)), collapse = ", "),
      path = normalizePath(path, winslash = "/", mustWork = FALSE),
      stringsAsFactors = FALSE
    )
  })

  out <- do.call(rbind, rows) %||% data.frame(
    name = character(),
    description = character(),
    scope = character(),
    sources = character(),
    functions = character(),
    path = character()
  )
  duplicated_names <- unique(out$name[duplicated(out$name)])
  if (length(duplicated_names) > 0) {
    details <- paste(vapply(duplicated_names, function(name) {
      paste(out$path[out$name == name], collapse = ", ")
    }, character(1)), collapse = "; ")
    cli::cli_abort(
      "Duplicate pack manifests found in {scope} scope for {paste(duplicated_names, collapse = ', ')}: {details}. Keep either packs/<name>.toml or packs/<name>/<name>.toml.",
      call = NULL
    )
  }
  out
}

validate_pack_layout <- function(name, path, data) {
  functions <- toml_string_array(data$functions %||% character(), sprintf("%s functions", path))
  hooks <- toml_string_array(data$hooks$on_add %||% character(), sprintf("%s [hooks].on_add", path))
  if ((length(functions) > 0 || length(hooks) > 0) && !pack_is_nested_manifest(path)) {
    nested <- file.path(dirname(path), name, sprintf("%s.toml", name))
    cli::cli_abort(
      "{.file {path}} declares functions or hooks, but function-bearing packs must use nested layout: {.file {nested}} with files in {.file {file.path(dirname(nested), 'functions')}}.",
      call = NULL
    )
  }
  invisible(TRUE)
}

summarize_sources <- function(sources) {
  sources <- unlist(sources, use.names = TRUE)
  if (length(sources) == 0) {
    return("")
  }
  paste(sprintf("%s=%s", names(sources), unname(sources)), collapse = ", ")
}

available_packs <- function(root = ".") {
  paths <- pack_paths(root)
  rows <- Map(discover_pack_scope, names(paths), paths)
  packs <- do.call(rbind, rows)
  packs[!duplicated(packs$name), , drop = FALSE]
}

load_pack <- function(name, root = ".") {
  packs <- available_packs(root)
  match <- packs[packs$name == name, , drop = FALSE]
  if (nrow(match) == 0) {
    abort_unknown_pack(name, packs)
  }

  path <- match$path[[1]]
  data <- read_toml_file(path)
  validate_pack_schema(name, path, data, match$scope[[1]])
  data$.__path__ <- path
  data$.__scope__ <- match$scope[[1]]
  data
}

abort_unknown_pack <- function(name, packs) {
  hint <- suggest_pack_name(name, packs$name)
  msg <- c(
    "{.val {name}} is not a known pack.",
    if (!is.null(hint)) "i" = "Did you mean {.val {hint}}?",
    "Available packs:",
    " " = "Built-in: {format_pack_group(packs, 'builtin')}",
    " " = "User:     {format_pack_group(packs, 'user')}",
    " " = "Project:  {format_pack_group(packs, 'project')}",
    "i" = "Run {.code boosterpak::list_packs()} for descriptions."
  )
  cli::cli_abort(msg, call = NULL)
}

suggest_pack_name <- function(name, choices) {
  if (length(choices) == 0) {
    return(NULL)
  }
  distance <- utils::adist(name, choices)
  if (min(distance) <= 3) {
    choices[[which.min(distance)]]
  } else {
    NULL
  }
}

format_pack_group <- function(packs, scope) {
  names <- packs$name[packs$scope == scope]
  if (length(names) == 0) {
    "(none)"
  } else {
    paste(names, collapse = ", ")
  }
}

validate_pack_schema <- function(expected_name, path, data, scope) {
  file_name <- tools::file_path_sans_ext(basename(path))
  if (!is.character(data$name) || length(data$name) != 1 || !nzchar(data$name)) {
    cli::cli_abort("{.file {path}} must declare a non-empty string {.field name}.", call = NULL)
  }
  if (!identical(data$name, file_name)) {
    cli::cli_abort("{.file {path}} declares name {.val {data$name}} but file name is {.val {file_name}}.", call = NULL)
  }
  if (!identical(data$name, expected_name)) {
    cli::cli_abort("{.file {path}} resolved for {.val {expected_name}} but declares {.val {data$name}}.", call = NULL)
  }
  if (!is.character(data$description) || length(data$description) != 1) {
    cli::cli_abort("{.file {path}} must declare a string {.field description}.", call = NULL)
  }
  if (is.null(data$packages)) {
    cli::cli_abort("{.file {path}} must declare {.field packages}, even if empty.", call = NULL)
  }
  data$packages <- toml_string_array(data$packages, sprintf("%s packages", path))
  data$extends <- toml_string_array(data$extends %||% character(), sprintf("%s extends", path))
  data$functions <- toml_string_array(data$functions %||% character(), sprintf("%s functions", path))
  data$hooks$on_add <- toml_string_array(data$hooks$on_add %||% character(), sprintf("%s [hooks].on_add", path))
  validate_pack_layout(data$name, path, data)
  invisible(lapply(data$functions, function(name) {
    if (!file.exists(pack_function_source_file(path, name, scope))) {
      cli::cli_abort("{.file {path}} declares function {.val {name}} but {.file {pack_function_file(path, name)}} is missing.", call = NULL)
    }
  }))
  invisible(lapply(data$hooks$on_add, function(name) {
    if (!name %in% data$functions) {
      cli::cli_abort("{.file {path}} declares on-add hook {.val {name}} but does not list it in {.field functions}.", call = NULL)
    }
    if (!file.exists(pack_function_source_file(path, name, scope))) {
      cli::cli_abort("{.file {path}} declares on-add hook {.val {name}} but {.file {pack_function_file(path, name)}} is missing.", call = NULL)
    }
  }))
  invisible(TRUE)
}

resolve_pack <- function(name, root = ".", stack = character()) {
  if (name %in% stack) {
    cycle <- paste(c(stack, name), collapse = " -> ")
    cli::cli_abort("Pack cycle detected: {cycle}.", call = NULL)
  }

  pack <- load_pack(name, root)
  pack$packages <- toml_string_array(pack$packages, sprintf("%s packages", pack$.__path__))
  parents <- toml_string_array(pack$extends %||% character(), sprintf("%s extends", pack$.__path__))
  parent_packages <- unlist(lapply(parents, resolve_pack, root = root, stack = c(stack, name)), use.names = FALSE)
  unique(c(parent_packages, pack$packages))
}

resolve_pack_names <- function(name, root = ".", stack = character()) {
  if (name %in% stack) {
    cycle <- paste(c(stack, name), collapse = " -> ")
    cli::cli_abort("Pack cycle detected: {cycle}.", call = NULL)
  }

  pack <- load_pack(name, root)
  parents <- toml_string_array(pack$extends %||% character(), sprintf("%s extends", pack$.__path__))
  parent_names <- unlist(lapply(parents, resolve_pack_names, root = root, stack = c(stack, name)), use.names = FALSE)
  unique(c(parent_names, name))
}

resolve_pack_functions <- function(name, root = ".", stack = character()) {
  if (name %in% stack) {
    cycle <- paste(c(stack, name), collapse = " -> ")
    cli::cli_abort("Pack cycle detected: {cycle}.", call = NULL)
  }

  pack <- load_pack(name, root)
  parents <- toml_string_array(pack$extends %||% character(), sprintf("%s extends", pack$.__path__))
  parent_functions <- unlist(lapply(parents, resolve_pack_functions, root = root, stack = c(stack, name)), use.names = FALSE)
  unique(c(parent_functions, pack$functions %||% character()))
}

resolve_pack_on_add_hooks <- function(name, root = ".", stack = character()) {
  if (name %in% stack) {
    cycle <- paste(c(stack, name), collapse = " -> ")
    cli::cli_abort("Pack cycle detected: {cycle}.", call = NULL)
  }

  pack <- load_pack(name, root)
  parents <- toml_string_array(pack$extends %||% character(), sprintf("%s extends", pack$.__path__))
  parent_hooks <- unlist(lapply(parents, resolve_pack_on_add_hooks, root = root, stack = c(stack, name)), use.names = FALSE)
  hooks <- toml_string_array(pack$hooks$on_add %||% character(), sprintf("%s [hooks].on_add", pack$.__path__))
  unique(c(parent_hooks, hooks))
}

resolve_config_pack_names <- function(config, root = ".") {
  declared <- toml_string_array(config$packs$declared %||% character(), "[packs].declared")
  unique(unlist(lapply(declared, resolve_pack_names, root = root), use.names = FALSE))
}

materialize_pack <- function(name, root = ".") {
  pack <- load_pack(name, root)
  dir.create(project_packs_dir(root), recursive = TRUE, showWarnings = FALSE)
  source_nested <- pack_is_nested_manifest(pack$.__path__)
  target <- if (source_nested) {
    file.path(project_packs_dir(root), name, sprintf("%s.toml", name))
  } else {
    file.path(project_packs_dir(root), sprintf("%s.toml", name))
  }
  same_path <- identical(normalizePath(pack$.__path__, winslash = "/", mustWork = FALSE), normalizePath(target, winslash = "/", mustWork = FALSE))
  if (!same_path && !file.exists(target)) {
    if (source_nested) {
      copied <- file.copy(dirname(pack$.__path__), project_packs_dir(root), recursive = TRUE, overwrite = FALSE)
    } else {
      dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
      copied <- file.copy(pack$.__path__, target, overwrite = FALSE)
    }
    if (!isTRUE(copied)) {
      cli::cli_abort("Failed to write pack {.val {name}} to {.file {target}}.", call = NULL)
    }
  }
  invisible(target)
}

materialize_config_packs <- function(config, root = ".") {
  names <- resolve_config_pack_names(config, root)
  invisible(lapply(names, materialize_pack, root = root))
  names
}

resolve_pack_sources <- function(name, root = ".", stack = character()) {
  if (name %in% stack) {
    cycle <- paste(c(stack, name), collapse = " -> ")
    cli::cli_abort("Pack cycle detected: {cycle}.", call = NULL)
  }

  pack <- load_pack(name, root)
  parents <- toml_string_array(pack$extends %||% character(), sprintf("%s extends", pack$.__path__))
  parent_sources <- lapply(parents, resolve_pack_sources, root = root, stack = c(stack, name))
  sources <- c(unlist(parent_sources, recursive = FALSE), unlist(pack$sources %||% list(), use.names = TRUE))
  sources[!duplicated(names(sources), fromLast = TRUE)]
}

resolve_config_packages <- function(config, root = ".") {
  declared <- toml_string_array(config$packs$declared %||% character(), "[packs].declared")
  extras <- vapply(
    toml_string_array(config$extras$declared %||% character(), "[extras].declared"),
    package_name_from_spec,
    character(1),
    USE.NAMES = FALSE
  )
  exclude <- toml_string_array(config$exclude$declared %||% character(), "[exclude].declared")
  packages <- unlist(lapply(declared, resolve_pack, root = root), use.names = FALSE)
  setdiff(unique(c(packages, extras)), exclude)
}

resolve_config_install_specs <- function(config, root = ".") {
  declared <- toml_string_array(config$packs$declared %||% character(), "[packs].declared")
  exclude <- toml_string_array(config$exclude$declared %||% character(), "[exclude].declared")
  packages <- resolve_config_packages(config, root)
  sources <- c(unlist(lapply(declared, resolve_pack_sources, root = root), recursive = FALSE), unlist(config$sources %||% list(), use.names = TRUE))
  extras <- toml_string_array(config$extras$declared %||% character(), "[extras].declared")
  if (length(extras) > 0) {
    extra_names <- vapply(extras, package_name_from_spec, character(1), USE.NAMES = FALSE)
    sources <- c(sources, stats::setNames(extras, extra_names))
  }
  vapply(packages, function(package) {
    if (!package %in% exclude && package %in% names(sources)) {
      as.character(sources[[package]])
    } else {
      package
    }
  }, character(1), USE.NAMES = FALSE)
}

package_name_from_spec <- function(spec) {
  if (grepl("^[A-Za-z][A-Za-z0-9.]*$", spec)) {
    return(spec)
  }
  if (grepl("^[^/]+/[^/]+$", spec)) {
    return(sub("\\.git$", "", basename(spec)))
  }
  spec
}

#' List available packs
#'
#' @param scope Optional scope filter: `"project"`, `"user"`, or `"builtin"`.
#' @param root Project root.
#' @param verbose Whether to print a routine summary.
#' @return A data frame of available packs, invisibly.
#' @export
list_packs <- function(scope = NULL, root = ".", verbose = NULL) {
  if (!is.null(scope)) {
    scope <- match.arg(scope, c("project", "user", "builtin"))
  }
  packs <- available_packs(root)
  if (!is.null(scope)) {
    packs <- packs[packs$scope == scope, , drop = FALSE]
  }
  if (should_emit(verbose)) {
    if (nrow(packs) == 0) {
      cli::cli_alert_info("No packs found.")
    } else {
      cli::cli_h1("Available booster packs")
      apply(packs, 1, function(row) {
        source_text <- if (nzchar(row[["sources"]])) paste0(" sources: ", row[["sources"]]) else ""
        cli::cli_li("{.val {row[['name']]}} [{row[['scope']]}]: {row[['description']]}{source_text}")
      })
    }
  }
  invisible(packs)
}

pack_scope_dir <- function(scope, root = ".") {
  switch(
    scope,
    project = project_packs_dir(root),
    user = user_packs_dir(),
    cli::cli_abort("Unsupported pack scope {.val {scope}}.", call = NULL)
  )
}

validate_new_pack_name <- function(name) {
  if (!is.character(name) || length(name) != 1 || !grepl("^[A-Za-z][A-Za-z0-9._-]*$", name)) {
    cli::cli_abort(
      "{.arg name} must be one pack name starting with a letter and containing only letters, numbers, dot, underscore, or hyphen.",
      call = NULL
    )
  }
  invisible(name)
}

pack_description <- function(name, from = NULL) {
  if (is.null(from)) {
    sprintf("Captured package snapshot for %s.", name)
  } else {
    sprintf("Captured package snapshot from %s.", from)
  }
}

write_pack_file <- function(path, name, description, packages, sources = character(), functions = character(), overwrite = FALSE) {
  if (file.exists(path) && !isTRUE(overwrite)) {
    cli::cli_abort("{.file {path}} already exists. Use {.code overwrite = TRUE} to replace it.", call = NULL)
  }

  lines <- c(
    sprintf('name = "%s"', escape_toml_string(name)),
    sprintf('description = "%s"', escape_toml_string(description)),
    sprintf("packages = [%s]", paste(sprintf('"%s"', vapply(packages, escape_toml_string, character(1))), collapse = ", ")),
    sprintf("functions = [%s]", paste(sprintf('"%s"', vapply(functions, escape_toml_string, character(1))), collapse = ", "))
  )
  if (length(sources) > 0) {
    lines <- c(
      lines,
      "",
      "[sources]",
      sprintf('"%s" = "%s"', vapply(names(sources), escape_toml_string, character(1)), vapply(unname(sources), escape_toml_string, character(1)))
    )
  }
  lines <- c(lines, "")

  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, path, useBytes = TRUE)
  invisible(path)
}

pack_sources_for_packages <- function(packages, sources) {
  sources <- unlist(sources %||% list(), use.names = TRUE)
  if (length(sources) == 0) {
    return(character())
  }
  sources <- sources[names(sources) %in% packages]
  sources[!duplicated(names(sources), fromLast = TRUE)]
}

resolve_save_pack_contents <- function(from = NULL, root = ".") {
  if (is.null(from)) {
    config <- read_config(root)
    validate_config(config, root)
    packages <- resolve_config_packages(config, root)
    install_specs <- resolve_config_install_specs(config, root)
    sources <- install_specs[install_specs != packages]
    names(sources) <- packages[install_specs != packages]
    functions <- installed_functions(config)
  } else {
    load_pack(from, root)
    packages <- resolve_pack(from, root)
    sources <- pack_sources_for_packages(packages, resolve_pack_sources(from, root))
    functions <- resolve_pack_functions(from, root)
  }
  list(packages = unique(packages), sources = sources, functions = functions)
}

local_function_names <- function(root = ".") {
  files <- list.files(functions_dir(root), pattern = "^fn_[A-Za-z0-9._-]+\\.R$", full.names = FALSE)
  sub("^fn_(.*)\\.R$", "\\1", files)
}

resolve_save_pack_functions <- function(functions, contents, root = ".") {
  if (is.character(functions) && length(functions) == 1 && functions %in% c("installed", "all", "none")) {
    names <- switch(
      functions,
      installed = contents$functions,
      all = local_function_names(root),
      none = character()
    )
  } else if (is.character(functions)) {
    names <- functions
  } else {
    cli::cli_abort("{.arg functions} must be {.val installed}, {.val all}, {.val none}, or a character vector.", call = NULL)
  }
  unique(names)
}

write_pack_function_sidecar <- function(path, names, root = ".", overwrite = FALSE) {
  sidecar <- pack_sidecar_dir(path)
  if (dir.exists(sidecar) && isTRUE(overwrite)) {
    unlink(sidecar, recursive = TRUE)
  }
  if (length(names) == 0) {
    return(invisible(sidecar))
  }
  dir.create(sidecar, recursive = TRUE, showWarnings = FALSE)
  invisible(lapply(names, function(name) {
    source <- function_file(name, root)
    target <- pack_function_file(path, name)
    if (!file.exists(source)) {
      cli::cli_abort("Requested function {.val {name}} is missing at {.file {source}}.", call = NULL)
    }
    copied <- file.copy(source, target, overwrite = TRUE)
    if (!isTRUE(copied)) {
      cli::cli_abort("Failed to copy function {.val {name}} to {.file {target}}.", call = NULL)
    }
  }))
  invisible(sidecar)
}

#' Save a resolved package set as a pack
#'
#' @param name Pack name to write.
#' @param scope Destination scope: `"project"` or `"user"`.
#' @param from Optional existing pack name to fork. When `NULL`, captures the
#'   current project's resolved package set.
#' @param root Project root.
#' @param functions Functions to carry with the pack: `"installed"`, `"all"`,
#'   `"none"`, or a character vector of function names.
#' @param overwrite Whether to replace an existing pack file.
#' @param verbose Whether to print routine summaries.
#' @return Path to the saved pack, invisibly.
#' @export
save_pack <- function(name, scope = c("project", "user"), from = NULL, root = ".", functions = "installed", overwrite = FALSE, verbose = NULL) {
  check_verbose(verbose)
  validate_new_pack_name(name)
  scope <- match.arg(scope)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)

  contents <- resolve_save_pack_contents(from, root)
  pack_functions <- resolve_save_pack_functions(functions, contents, root)
  target <- if (length(pack_functions) == 0) {
    file.path(pack_scope_dir(scope, root), sprintf("%s.toml", name))
  } else {
    file.path(pack_scope_dir(scope, root), name, sprintf("%s.toml", name))
  }
  guard_pack_target_layout(name, scope, root, target)
  write_pack_file(target, name, pack_description(name, from), contents$packages, contents$sources, pack_functions, overwrite)
  write_pack_function_sidecar(target, pack_functions, root, overwrite)

  if (should_emit(verbose)) {
    cli::cli_alert_success("Saved pack {.val {name}} to {.file {target}}.")
  }
  invisible(normalizePath(target, winslash = "/", mustWork = FALSE))
}

copy_pack_between_scopes <- function(name, from_scope, to_scope, root = ".", overwrite = FALSE, verbose = NULL) {
  check_verbose(verbose)
  validate_new_pack_name(name)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  source <- pack_manifest_in_scope(name, from_scope, root)
  target <- if (pack_is_nested_manifest(source)) {
    file.path(pack_scope_dir(to_scope, root), name, sprintf("%s.toml", name))
  } else {
    file.path(pack_scope_dir(to_scope, root), sprintf("%s.toml", name))
  }

  if (!file.exists(source)) {
    cli::cli_abort("Pack {.val {name}} does not exist in {from_scope} scope.", call = NULL)
  }
  guard_pack_target_layout(name, to_scope, root, target)
  if (file.exists(target) && !isTRUE(overwrite)) {
    cli::cli_abort("{.file {target}} already exists. Use {.code overwrite = TRUE} to replace it.", call = NULL)
  }

  if (pack_is_nested_manifest(source)) {
    if (dir.exists(dirname(target)) && isTRUE(overwrite)) {
      unlink(dirname(target), recursive = TRUE)
    }
    if (dir.exists(dirname(target)) && !isTRUE(overwrite)) {
      cli::cli_abort("{.file {dirname(target)}} already exists. Use {.code overwrite = TRUE} to replace it.", call = NULL)
    }
    dir.create(pack_scope_dir(to_scope, root), recursive = TRUE, showWarnings = FALSE)
    ok <- file.copy(dirname(source), pack_scope_dir(to_scope, root), recursive = TRUE, overwrite = TRUE)
  } else {
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    ok <- file.copy(source, target, overwrite = isTRUE(overwrite))
  }
  if (!isTRUE(ok)) {
    cli::cli_abort("Failed to copy pack {.val {name}} to {.file {target}}.", call = NULL)
  }

  if (should_emit(verbose)) {
    cli::cli_alert_success("Copied pack {.val {name}} to {to_scope} scope.")
  }
  invisible(normalizePath(target, winslash = "/", mustWork = FALSE))
}

guard_pack_target_layout <- function(name, scope, root, target) {
  dir <- pack_scope_dir(scope, root)
  flat <- file.path(dir, sprintf("%s.toml", name))
  nested <- file.path(dir, name, sprintf("%s.toml", name))
  target <- normalizePath(target, winslash = "/", mustWork = FALSE)
  flat <- normalizePath(flat, winslash = "/", mustWork = FALSE)
  nested <- normalizePath(nested, winslash = "/", mustWork = FALSE)
  alternate <- if (identical(target, flat)) nested else flat
  if (file.exists(alternate)) {
    cli::cli_abort(
      "Pack {.val {name}} already exists at {.file {alternate}}. Remove it before writing {.file {target}}.",
      call = NULL
    )
  }
  invisible(TRUE)
}

pack_manifest_in_scope <- function(name, scope, root = ".") {
  dir <- pack_scope_dir(scope, root)
  flat <- file.path(dir, sprintf("%s.toml", name))
  nested <- file.path(dir, name, sprintf("%s.toml", name))
  exists <- c(flat = file.exists(flat), nested = file.exists(nested))
  if (all(exists)) {
    cli::cli_abort(
      "Duplicate pack manifest found for {.val {name}} in {scope} scope. Keep either {.file {flat}} or {.file {nested}}.",
      call = NULL
    )
  }
  if (exists[["nested"]]) {
    nested
  } else {
    flat
  }
}

#' Promote a project pack to user scope
#'
#' @param name Pack name.
#' @param root Project root.
#' @param overwrite Whether to replace an existing user-scope pack.
#' @param verbose Whether to print routine summaries.
#' @return Path to the copied user-scope pack, invisibly.
#' @export
promote_pack <- function(name, root = ".", overwrite = FALSE, verbose = NULL) {
  copy_pack_between_scopes(name, "project", "user", root, overwrite, verbose)
}

#' Demote a user pack to project scope
#'
#' @param name Pack name.
#' @param root Project root.
#' @param overwrite Whether to replace an existing project-scope pack.
#' @param verbose Whether to print routine summaries.
#' @return Path to the copied project-scope pack, invisibly.
#' @export
demote_pack <- function(name, root = ".", overwrite = FALSE, verbose = NULL) {
  copy_pack_between_scopes(name, "user", "project", root, overwrite, verbose)
}

`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}
