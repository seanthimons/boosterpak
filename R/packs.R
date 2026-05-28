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
      return(unlist(x, use.names = FALSE))
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
      path = character()
    ))
  }

  files <- list.files(dir, pattern = "\\.toml$", full.names = TRUE)
  rows <- lapply(files, function(path) {
    data <- read_toml_file(path)
    data.frame(
      name = data$name %||% tools::file_path_sans_ext(basename(path)),
      description = data$description %||% "",
      scope = scope,
      path = normalizePath(path, winslash = "/", mustWork = FALSE),
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, rows) %||% data.frame(
    name = character(),
    description = character(),
    scope = character(),
    path = character()
  )
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
    suggest <- utils::adist(name, packs$name)
    hint <- NULL
    if (length(suggest) > 0 && min(suggest) <= 3) {
      hint <- packs$name[which.min(suggest)]
    }
    msg <- c(
      "{.val {name}} is not a known pack.",
      if (!is.null(hint)) "i" = "Did you mean {.val {hint}}?",
      "i" = "Run {.code boosterpak::list_packs()} for available packs."
    )
    cli::cli_abort(msg, call = NULL)
  }

  path <- match$path[[1]]
  data <- read_toml_file(path)
  validate_pack_schema(name, path, data)
  data$.__path__ <- path
  data$.__scope__ <- match$scope[[1]]
  data
}

validate_pack_schema <- function(expected_name, path, data) {
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

resolve_config_packages <- function(config, root = ".") {
  declared <- toml_string_array(config$packs$declared %||% character(), "[packs].declared")
  extras <- toml_string_array(config$extras$declared %||% character(), "[extras].declared")
  exclude <- toml_string_array(config$exclude$declared %||% character(), "[exclude].declared")
  packages <- unlist(lapply(declared, resolve_pack, root = root), use.names = FALSE)
  setdiff(unique(c(packages, extras)), exclude)
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
        cli::cli_li("{.val {row[['name']]}} [{row[['scope']]}]: {row[['description']]}")
      })
    }
  }
  invisible(packs)
}

`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}
