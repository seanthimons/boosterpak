#' Import booster packs from a GitHub repository
#'
#' `add_github_pack()` clones a repository, discovers booster pack manifests
#' under `path`, copies selected packs into the current project's
#' `boosters/packs/` directory, declares them in `boosters.toml`, and
#' optionally runs the normal additive sync flow.
#'
#' @param repo GitHub repository as `"owner/repo"` or a git URL.
#' @param packs Character vector of pack names to import, `"all"` to import all
#'   discovered packs, or `NULL` to select interactively.
#' @param ref Optional git ref to check out after cloning.
#' @param path Directory inside the repository that contains pack manifests.
#' @param root Project root.
#' @param sync Whether to run additive sync after editing TOML.
#' @param hydrate Whether additive sync should reuse packages from
#'   renv-discoverable local libraries before downloading with pak.
#' @param overwrite Whether to replace existing project pack files.
#' @param overwrite_functions Whether to overwrite existing function files
#'   provided by the pack.
#' @param verbose Whether to print routine summaries.
#' @return Updated declared pack names, invisibly.
#' @export
add_github_pack <- function(
  repo,
  packs = NULL,
  ref = NULL,
  path = ".",
  root = ".",
  sync = TRUE,
  hydrate = TRUE,
  overwrite = FALSE,
  overwrite_functions = FALSE,
  verbose = NULL
) {
  check_verbose(verbose)
  repo_url <- normalize_github_pack_repo(repo)
  ref <- validate_optional_git_ref(ref)
  path <- validate_remote_pack_path(path)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  read_config(root)

  clone_dir <- clone_github_pack_repo(repo_url)
  on.exit(unlink(clone_dir, recursive = TRUE, force = TRUE), add = TRUE)
  checkout_github_pack_ref(clone_dir, ref)

  pack_dir <- remote_pack_dir(clone_dir, path)
  discovered <- discover_remote_packs(pack_dir)
  selected <- resolve_remote_pack_selection(packs, discovered, repo, path)
  selected_rows <- discovered[match(selected, discovered$name), , drop = FALSE]

  copy_remote_packs_to_project(
    selected_rows,
    root = root,
    overwrite = overwrite
  )
  declare_project_packs(
    selected,
    root = root,
    sync = sync,
    hydrate = hydrate,
    overwrite_functions = overwrite_functions,
    verbose = verbose
  )
}

normalize_github_pack_repo <- function(repo) {
  if (!is.character(repo) || length(repo) != 1 || !nzchar(repo)) {
    cli::cli_abort(
      "{.arg repo} must be one non-empty GitHub repository or git URL.",
      call = NULL
    )
  }

  if (dir.exists(repo) || file.exists(repo)) {
    return(normalizePath(repo, winslash = "/", mustWork = TRUE))
  }

  owner_repo <- "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(\\.git)?$"
  if (grepl(owner_repo, repo)) {
    parts <- strsplit(repo, "/", fixed = TRUE)[[1]]
    repo_name <- sub("\\.git$", "", parts[[2]])
    return(sprintf("https://github.com/%s/%s.git", parts[[1]], repo_name))
  }

  git_url <- "^(https?|ssh|git|file)://|^git@"
  if (grepl(git_url, repo)) {
    return(repo)
  }

  cli::cli_abort(
    "{.arg repo} must be {.val owner/repo}, a git URL, or a local git repository path.",
    call = NULL
  )
}

validate_optional_git_ref <- function(ref) {
  if (is.null(ref)) {
    return(NULL)
  }
  if (!is.character(ref) || length(ref) != 1 || !nzchar(ref)) {
    cli::cli_abort(
      "{.arg ref} must be {.code NULL} or one non-empty git ref.",
      call = NULL
    )
  }
  ref
}

validate_remote_pack_path <- function(path) {
  if (!is.character(path) || length(path) != 1 || !nzchar(path)) {
    cli::cli_abort(
      "{.arg path} must be one non-empty relative path inside {.arg repo}.",
      call = NULL
    )
  }
  if (grepl("^([A-Za-z]:|/|\\\\)", path)) {
    cli::cli_abort(
      "{.arg path} must be relative to the cloned repository.",
      call = NULL
    )
  }
  path
}

clone_github_pack_repo <- function(repo) {
  ensure_git_available()
  clone_dir <- tempfile("boosterpak-github-")
  run_git(c("clone", repo, clone_dir), "clone repository")
  normalizePath(clone_dir, winslash = "/", mustWork = TRUE)
}

checkout_github_pack_ref <- function(repo_dir, ref = NULL) {
  if (is.null(ref)) {
    return(invisible(repo_dir))
  }
  run_git(c("-C", repo_dir, "checkout", ref), "check out ref")
  invisible(repo_dir)
}

ensure_git_available <- function() {
  if (!nzchar(Sys.which("git"))) {
    cli::cli_abort(
      "{.command git} must be available on PATH to import GitHub packs.",
      call = NULL
    )
  }
  invisible(TRUE)
}

run_git <- function(args, action) {
  output <- tryCatch(
    suppressWarnings(git_system2("git", args, stdout = TRUE, stderr = TRUE)),
    error = function(err) {
      cli::cli_abort(
        c(
          "Failed to {action} with {.command git}.",
          "x" = conditionMessage(err)
        ),
        call = NULL
      )
    }
  )
  status <- attr(output, "status") %||% 0L
  if (!identical(as.integer(status), 0L)) {
    details <- paste(output, collapse = "\n")
    cli::cli_abort(
      c(
        "Failed to {action} with {.command git}.",
        "x" = details
      ),
      call = NULL
    )
  }
  invisible(output)
}

git_system2 <- function(command, args, stdout = TRUE, stderr = TRUE) {
  system2(command, args, stdout = stdout, stderr = stderr)
}

remote_pack_dir <- function(repo_dir, path) {
  candidate <- file.path(repo_dir, path)
  if (!dir.exists(candidate)) {
    cli::cli_abort(
      "Pack path {.file {path}} does not exist inside the cloned repository.",
      call = NULL
    )
  }

  repo_dir <- normalizePath(repo_dir, winslash = "/", mustWork = TRUE)
  candidate <- normalizePath(candidate, winslash = "/", mustWork = TRUE)
  if (!path_is_within(candidate, repo_dir)) {
    cli::cli_abort(
      "{.arg path} must stay inside the cloned repository.",
      call = NULL
    )
  }
  candidate
}

path_is_within <- function(path, root) {
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  if (identical(.Platform$OS.type, "windows")) {
    path <- tolower(path)
    root <- tolower(root)
  }
  identical(path, root) || startsWith(paste0(path, "/"), paste0(root, "/"))
}

discover_remote_packs <- function(dir) {
  packs <- discover_pack_scope("github", dir)
  if (nrow(packs) == 0) {
    cli::cli_abort(
      "No booster pack manifests were found in {.file {dir}}.",
      call = NULL
    )
  }
  packs
}

resolve_remote_pack_selection <- function(packs, discovered, repo, path) {
  available <- discovered$name

  if (is.null(packs)) {
    if (!interactive()) {
      cli::cli_abort(
        c(
          "{.arg packs} must be supplied in non-interactive sessions.",
          "Available packs: {paste(available, collapse = ', ')}",
          "i" = "Example: {.code boosterpak::add_github_pack({encodeString(repo, quote = '\"')}, packs = {format_r_string_vector(head(available, 2))})}"
        ),
        call = NULL
      )
    }
    selected <- utils::select.list(
      available,
      multiple = TRUE,
      title = sprintf("Select booster packs from %s/%s", repo, path),
      graphics = FALSE
    )
    if (length(selected) == 0) {
      cli::cli_abort("GitHub pack import cancelled.", call = NULL)
    }
    return(unique(selected))
  }

  if (!is.character(packs) || length(packs) == 0 || any(!nzchar(packs))) {
    cli::cli_abort(
      "{.arg packs} must be {.code NULL}, {.val all}, or a non-empty character vector.",
      call = NULL
    )
  }
  if (identical(packs, "all")) {
    return(available)
  }

  missing <- setdiff(packs, available)
  if (length(missing) > 0) {
    cli::cli_abort(
      c(
        "Unknown GitHub pack{?s}: {.val {missing}}.",
        "Available packs: {paste(available, collapse = ', ')}"
      ),
      call = NULL
    )
  }
  unique(packs)
}

format_r_string_vector <- function(x) {
  quoted <- vapply(x, encodeString, character(1), quote = '"')
  if (length(quoted) == 1) {
    quoted
  } else {
    sprintf("c(%s)", paste(quoted, collapse = ", "))
  }
}

copy_remote_packs_to_project <- function(packs, root, overwrite = FALSE) {
  invisible(lapply(seq_len(nrow(packs)), function(i) {
    copy_remote_pack_to_project(
      packs[i, , drop = FALSE],
      root = root,
      overwrite = overwrite
    )
  }))
}

copy_remote_pack_to_project <- function(pack, root, overwrite = FALSE) {
  name <- pack$name[[1]]
  source <- pack$path[[1]]
  data <- read_toml_file(source)
  validate_pack_schema(name, source, data, "github")

  target <- remote_pack_target(name, source, root)
  guard_pack_target_layout(name, "project", root, target, overwrite = overwrite)

  if (pack_is_nested_manifest(source)) {
    target_dir <- dirname(target)
    if (dir.exists(target_dir)) {
      if (!isTRUE(overwrite)) {
        cli::cli_abort(
          "{.file {target_dir}} already exists. Use {.code overwrite = TRUE} to replace it.",
          call = NULL
        )
      }
      unlink(target_dir, recursive = TRUE)
    }
    dir.create(project_packs_dir(root), recursive = TRUE, showWarnings = FALSE)
    copied <- file.copy(
      dirname(source),
      project_packs_dir(root),
      recursive = TRUE,
      overwrite = FALSE
    )
  } else {
    if (file.exists(target)) {
      if (!isTRUE(overwrite)) {
        cli::cli_abort(
          "{.file {target}} already exists. Use {.code overwrite = TRUE} to replace it.",
          call = NULL
        )
      }
      unlink(target)
    }
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    copied <- file.copy(source, target, overwrite = FALSE)
  }

  if (!isTRUE(copied)) {
    cli::cli_abort(
      "Failed to copy pack {.val {name}} to {.file {target}}.",
      call = NULL
    )
  }
  invisible(normalizePath(target, winslash = "/", mustWork = FALSE))
}

remote_pack_target <- function(name, source, root) {
  if (pack_is_nested_manifest(source)) {
    file.path(project_packs_dir(root), name, sprintf("%s.toml", name))
  } else {
    file.path(project_packs_dir(root), sprintf("%s.toml", name))
  }
}

declare_project_packs <- function(
  names,
  root = ".",
  sync = TRUE,
  hydrate = TRUE,
  overwrite_functions = FALSE,
  verbose = NULL
) {
  config <- read_config(root)
  validate_config(config, root)
  invisible(lapply(names, load_pack, root = root))

  current <- config$packs$declared %||% character()
  new_adds <- setdiff(names, current)
  next_packs <- unique(c(current, names))

  if (isTRUE(sync)) {
    ensure_project_renv(root)
  }
  if (length(new_adds) > 0 && !isTRUE(overwrite_functions)) {
    check_pack_function_conflicts(new_adds, root)
  }

  update_declared_array(boosters_file(root), "packs", "declared", next_packs)
  materialize_config_packs(read_config(root), root)
  materialize_pack_functions(
    names,
    root = root,
    overwrite = overwrite_functions
  )
  source_pack_functions(names, root = root)
  if (length(new_adds) > 0) {
    scaffold_pack_settings(new_adds, root = root)
  }

  if (isTRUE(sync)) {
    sync(mode = "apply", root = root, hydrate = hydrate, verbose = verbose)
    invisible(lapply(new_adds, run_pack_on_add_hooks, root = root))
  } else if (should_emit(verbose)) {
    cli::cli_alert_success(
      "Imported {length(names)} GitHub pack{?s} in {.file boosters.toml}."
    )
  }
  invisible(next_packs)
}
