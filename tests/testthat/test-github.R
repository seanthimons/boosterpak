skip_if_no_git <- function() {
  testthat::skip_if(!nzchar(Sys.which("git")), "git is not available")
}

run_test_git <- function(args) {
  output <- suppressWarnings(system2("git", args, stdout = TRUE, stderr = TRUE))
  status <- attr(output, "status")
  if (is.null(status)) {
    status <- 0L
  }
  if (!identical(as.integer(status), 0L)) {
    stop(paste(output, collapse = "\n"), call. = FALSE)
  }
  invisible(output)
}

commit_test_repo <- function(repo) {
  run_test_git(c("-C", repo, "add", "."))
  run_test_git(c("-C", repo, "commit", "-m", "add-packs"))
  invisible(repo)
}

init_test_repo <- function() {
  repo <- tempfile("boosterpak-remote-pack-repo-")
  dir.create(repo, recursive = TRUE)
  withr::defer(unlink(repo, recursive = TRUE, force = TRUE), teardown_env())
  run_test_git(c("init", repo))
  run_test_git(c("-C", repo, "config", "user.email", "test@example.com"))
  run_test_git(c("-C", repo, "config", "user.name", "TestUser"))
  repo
}

write_flat_remote_pack <- function(repo, name, packages = character(), path = ".") {
  dir <- file.path(repo, path)
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(c(
    sprintf('name = "%s"', name),
    sprintf('description = "%s pack"', name),
    sprintf("packages = [%s]", paste(sprintf('"%s"', packages), collapse = ", "))
  ), file.path(dir, sprintf("%s.toml", name)))
}

write_function_remote_pack <- function(repo, name, function_name, body, hook = FALSE, path = ".") {
  dir <- file.path(repo, path, name)
  dir.create(file.path(dir, "functions"), recursive = TRUE, showWarnings = FALSE)
  lines <- c(
    sprintf('name = "%s"', name),
    sprintf('description = "%s pack"', name),
    "packages = []",
    sprintf('functions = ["%s"]', function_name)
  )
  if (isTRUE(hook)) {
    lines <- c(lines, "", "[hooks]", sprintf('on_add = ["%s"]', function_name))
  }
  writeLines(lines, file.path(dir, sprintf("%s.toml", name)))
  writeLines(body, file.path(dir, "functions", sprintf("fn_%s.R", function_name)))
}

make_remote_repo <- function(packages = c("cli"), path = ".") {
  skip_if_no_git()
  repo <- init_test_repo()
  write_function_remote_pack(
    repo,
    "analysis",
    "remote_helper",
    c(
      "remote_helper <- function() {",
      "  'ok'",
      "}"
    ),
    path = path
  )
  write_flat_remote_pack(repo, "reporting", packages = packages, path = path)
  commit_test_repo(repo)
}

test_that("owner/repo specs normalize to GitHub clone URLs", {
  expect_equal(
    boosterpak:::normalize_github_pack_repo("seanthimons/boosterpak"),
    "https://github.com/seanthimons/boosterpak.git"
  )
  expect_equal(
    boosterpak:::normalize_github_pack_repo("seanthimons/boosterpak.git"),
    "https://github.com/seanthimons/boosterpak.git"
  )
})

test_that("packs = NULL errors non-interactively with discovered pack names", {
  repo <- make_remote_repo()
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  expect_error(
    add_github_pack(repo, root = root, sync = FALSE, verbose = FALSE),
    "analysis.+reporting"
  )
})

test_that("packs = 'all' imports and declares discovered remote packs", {
  repo <- make_remote_repo()
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  withr::defer(rm(list = intersect("remote_helper", ls(envir = .GlobalEnv)), envir = .GlobalEnv), teardown_env())

  declared <- add_github_pack(repo, packs = "all", root = root, sync = FALSE, verbose = FALSE)

  expect_setequal(declared, c("core", "analysis", "reporting"))
  expect_true(file.exists(file.path(root, "boosters", "packs", "analysis", "analysis.toml")))
  expect_true(file.exists(file.path(root, "boosters", "packs", "analysis", "functions", "fn_remote_helper.R")))
  expect_true(file.exists(file.path(root, "boosters", "packs", "reporting.toml")))
  expect_true(file.exists(file.path(root, "boosters", "fn_remote_helper.R")))
  expect_true(exists("remote_helper", envir = .GlobalEnv, mode = "function", inherits = FALSE))
})

test_that("selected remote packs under path copy and declare only selected packs", {
  repo <- make_remote_repo(path = "packs")
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  declared <- add_github_pack(repo, packs = "reporting", path = "packs", root = root, sync = FALSE, verbose = FALSE)

  expect_equal(declared, c("core", "reporting"))
  expect_true(file.exists(file.path(root, "boosters", "packs", "reporting.toml")))
  expect_false(file.exists(file.path(root, "boosters", "packs", "analysis", "analysis.toml")))
})

test_that("existing project pack conflicts fail unless overwrite is true", {
  repo <- make_remote_repo(packages = "cli")
  replacement <- make_remote_repo(packages = "digest")
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  add_github_pack(repo, packs = "reporting", root = root, sync = FALSE, verbose = FALSE)

  expect_error(
    add_github_pack(replacement, packs = "reporting", root = root, sync = FALSE, verbose = FALSE),
    "already exists"
  )
  expect_no_error(
    add_github_pack(replacement, packs = "reporting", root = root, sync = FALSE, overwrite = TRUE, verbose = FALSE)
  )
  expect_equal(
    boosterpak:::read_toml_file(file.path(root, "boosters", "packs", "reporting.toml"))$packages,
    "digest"
  )
})

test_that("sync false imports and sources functions without running hooks", {
  skip_if_no_git()
  repo <- init_test_repo()
  write_function_remote_pack(
    repo,
    "hooked",
    "create_marker",
    c(
      "create_marker <- function() {",
      "  dir.create('hook-output', showWarnings = FALSE)",
      "  invisible(TRUE)",
      "}"
    ),
    hook = TRUE
  )
  commit_test_repo(repo)
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  withr::defer(rm(list = intersect("create_marker", ls(envir = .GlobalEnv)), envir = .GlobalEnv), teardown_env())

  add_github_pack(repo, packs = "hooked", root = root, sync = FALSE, verbose = FALSE)

  expect_true(file.exists(file.path(root, "boosters", "fn_create_marker.R")))
  expect_true(exists("create_marker", envir = .GlobalEnv, mode = "function", inherits = FALSE))
  expect_false(dir.exists(file.path(root, "hook-output")))
})

test_that("sync true batches sync once and runs hooks for new additions", {
  skip_if_no_git()
  repo <- init_test_repo()
  write_function_remote_pack(
    repo,
    "hooked",
    "create_marker",
    c(
      "create_marker <- function() {",
      "  dir.create('hook-output', showWarnings = FALSE)",
      "  invisible(TRUE)",
      "}"
    ),
    hook = TRUE
  )
  write_flat_remote_pack(repo, "reporting", packages = character())
  commit_test_repo(repo)
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  withr::defer(rm(list = intersect("create_marker", ls(envir = .GlobalEnv)), envir = .GlobalEnv), teardown_env())

  sync_calls <- 0L
  local_mocked_bindings(
    ensure_project_renv = function(root = ".") TRUE,
    sync = function(mode = c("apply", "restore"), root = ".", hydrate = TRUE, verbose = NULL, ...) {
      sync_calls <<- sync_calls + 1L
      TRUE
    },
    .package = "boosterpak"
  )

  add_github_pack(repo, packs = "all", root = root, sync = TRUE, verbose = FALSE)

  expect_equal(sync_calls, 1L)
  expect_true(dir.exists(file.path(root, "hook-output")))
})

test_that("ref checkout shells out to git checkout", {
  calls <- list()
  local_mocked_bindings(
    git_system2 = function(command, args, stdout = TRUE, stderr = TRUE) {
      calls[[length(calls) + 1L]] <<- list(command = command, args = args, stdout = stdout, stderr = stderr)
      ""
    },
    .package = "boosterpak"
  )

  boosterpak:::checkout_github_pack_ref("repo-dir", "feature-branch")

  expect_equal(calls[[1]]$command, "git")
  expect_equal(calls[[1]]$args, c("-C", "repo-dir", "checkout", "feature-branch"))
  expect_true(calls[[1]]$stdout)
  expect_true(calls[[1]]$stderr)
})
