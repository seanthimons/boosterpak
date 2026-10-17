status_messages <- function(root) {
  paste(testthat::capture_messages(status(root = root, verbose = TRUE)), collapse = "")
}

write_stale_record <- function(root, version = "0.6.0.9000") {
  path <- file.path(root, "boosters.toml")
  lines <- readLines(path, warn = FALSE)
  at <- grep("^boosters_version = ", lines)
  lines[at] <- sprintf('boosters_version = "%s"', version)
  writeLines(lines, path)
}

test_that("status lists each attached package with the pack that requests it", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  add_pack("example", root = root, sync = FALSE, verbose = FALSE)

  s <- status(root = root, verbose = FALSE)

  expect_true(is.data.frame(s$attach_sources))
  expect_equal(s$attach_sources$package, "cli")
  expect_equal(s$attach_sources$pack, "example")
  expect_equal(s$attach_packages, s$attach_sources$package)
  expect_equal(
    s$attach_packages,
    boosterpak:::resolve_config_attach_packages(boosterpak:::read_config(root), root)
  )
  expect_false("boosterpak" %in% s$attach_sources$package)
})

test_that("attach sources name the declaring pack for parent-inherited packages", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  add_pack("example", root = root, sync = FALSE, verbose = FALSE)
  writeLines(
    c(
      'name = "child"',
      'description = "Child pack."',
      'extends = ["example"]',
      'packages = ["glue"]'
    ),
    file.path(root, "boosters", "packs", "child.toml")
  )
  boosterpak:::update_declared_array(
    file.path(root, "boosters.toml"),
    "packs",
    "declared",
    c("core", "example", "child")
  )

  s <- status(root = root, verbose = FALSE)

  expect_setequal(s$attach_sources$package, c("cli", "glue"))
  expect_equal(s$attach_sources$pack[s$attach_sources$package == "cli"], "example")
  expect_equal(s$attach_sources$pack[s$attach_sources$package == "glue"], "child")
})

test_that("attach sources label packages declared in [attach] by boosters.toml", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  boosterpak:::update_declared_array(
    file.path(root, "boosters.toml"),
    "attach",
    "declared",
    "glue"
  )

  s <- status(root = root, verbose = FALSE)

  expect_equal(s$attach_sources$package, "glue")
  expect_equal(s$attach_sources$pack, "[attach].declared")
})

test_that("status has no attach sources when attach is disabled", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  add_pack("example", root = root, sync = FALSE, verbose = FALSE)
  path <- file.path(root, "boosters.toml")
  lines <- readLines(path, warn = FALSE)
  writeLines(sub("^enabled = true$", "enabled = false", lines), path)

  s <- status(root = root, verbose = FALSE)

  expect_false(s$attach_enabled)
  expect_equal(nrow(s$attach_sources), 0L)
  expect_equal(s$attach_packages, character())
  expect_match(status_messages(root), "attached on every R start: disabled")
  expect_false(grepl("attached on every R start \\(including workers\\)", status_messages(root)))
})

test_that("status prints the attach line with a singular or plural count", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  add_pack("example", root = root, sync = FALSE, verbose = FALSE)

  one <- status_messages(root)
  expect_match(one, "attached on every R start \\(including workers\\): 1 package\\b")
  expect_match(one, "cli from example", fixed = TRUE)

  boosterpak:::update_declared_array(
    file.path(root, "boosters.toml"),
    "attach",
    "declared",
    c("glue", "fs")
  )
  two <- status_messages(root)
  expect_match(two, "attached on every R start \\(including workers\\): 3 packages")
  expect_match(two, "glue from \\[attach\\]\\.declared")
})

test_that("status warns and reports upgrade_needed when the record is stale", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  # init(rprofile = "no") records no version. Recording it here stands in for
  # a completed .Rprofile step, so the project starts out current.
  boosterpak:::set_boosters_version(root)

  current <- status(root = root, verbose = FALSE)
  expect_false(current$upgrade_needed)
  expect_no_match(status_messages(root), "upgrade_project\\(dry_run = TRUE\\)")

  write_stale_record(root)
  stale <- status(root = root, verbose = FALSE)

  expect_true(stale$upgrade_needed)
  expect_match(status_messages(root), "upgrade_project(dry_run = TRUE)", fixed = TRUE)
})

test_that("status prints no attach or upgrade advice without boosters.toml", {
  root <- withr::local_tempdir()

  messages <- status_messages(root)

  expect_no_match(messages, "attached on every R start", fixed = TRUE)
  expect_no_match(messages, "0 packages", fixed = TRUE)
  expect_no_match(messages, "upgrade_project", fixed = TRUE)
})

test_that("status reports a project without a record calmly", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  messages <- status_messages(root)

  expect_match(messages, "boosters_version: no version recorded", fixed = TRUE)
  expect_no_match(messages, "newer than this project", fixed = TRUE)
  expect_no_match(messages, "upgrade_project(dry_run = TRUE)", fixed = TRUE)
  expect_match(messages, "rprofile = \"no\" is a valid choice", fixed = TRUE)
})

test_that("status warns about an earlier .Rprofile layout only", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  boosterpak:::set_boosters_version(root)
  writeLines(boosterpak:::legacy_rprofile_line(), file.path(root, ".Rprofile"))

  expect_match(status_messages(root), "earlier boosterpak layout", fixed = TRUE)
  expect_match(status_messages(root), "upgrade_project(dry_run = TRUE)", fixed = TRUE)
})

test_that("status reports upgrade_needed for a project without a readable record", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  path <- file.path(root, "boosters.toml")
  lines <- readLines(path, warn = FALSE)
  writeLines(lines[-grep("^boosters_version = ", lines)], path)

  expect_true(status(root = root, verbose = FALSE)$upgrade_needed)
})

test_that("status hints at check_binary_repos on glibc Linux when renv.lock exists", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  hint <- 'check_binary_repos(lockfile = "renv.lock")'

  local_mocked_bindings(is_glibc_linux = function() TRUE, .package = "boosterpak")
  expect_no_match(status_messages(root), hint, fixed = TRUE)

  writeLines("{}", file.path(root, "renv.lock"))
  expect_match(status_messages(root), hint, fixed = TRUE)

  local_mocked_bindings(is_glibc_linux = function() FALSE, .package = "boosterpak")
  expect_no_match(status_messages(root), hint, fixed = TRUE)
})

test_that("status omits the binary-check hint on non-glibc systems", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  writeLines("{}", file.path(root, "renv.lock"))

  local_mocked_bindings(is_glibc_linux = function() FALSE, .package = "boosterpak")
  expect_no_match(status_messages(root), "check_binary_repos", fixed = TRUE)
})

test_that("GitHub token visibility is NA unless the project declares GitHub sources", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  withr::local_envvar(GITHUB_PAT = NA, GITHUB_TOKEN = NA)
  boosterpak:::update_declared_array(file.path(root, "boosters.toml"), "extras", "declared", character())

  expect_true(is.na(status(root = root, verbose = FALSE)$github_token_visible))
  expect_no_match(status_messages(root), "GitHub token visible", fixed = TRUE)

  boosterpak:::update_declared_array(
    file.path(root, "boosters.toml"),
    "extras",
    "declared",
    "seanthimons/ComptoxR"
  )
  local_mocked_bindings(gitcreds_token_is_visible = function() FALSE, .package = "boosterpak")

  s <- status(root = root, verbose = FALSE)

  expect_false(s$github_token_visible)
  expect_match(status_messages(root), "GitHub token visible: FALSE", fixed = TRUE)
})

test_that("GitHub token visibility reads GITHUB_PAT or GITHUB_TOKEN without exposing the value", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  boosterpak:::update_declared_array(
    file.path(root, "boosters.toml"),
    "extras",
    "declared",
    "seanthimons/ComptoxR"
  )
  secret <- "ghp_status_test_value_0123"
  local_mocked_bindings(gitcreds_token_is_visible = function() FALSE, .package = "boosterpak")

  withr::local_envvar(GITHUB_PAT = secret, GITHUB_TOKEN = NA)
  s <- status(root = root, verbose = FALSE)
  expect_true(s$github_token_visible)
  dump <- paste(c(capture.output(str(s)), status_messages(root)), collapse = "\n")
  expect_false(grepl(secret, dump, fixed = TRUE))

  withr::local_envvar(GITHUB_PAT = NA, GITHUB_TOKEN = secret)
  expect_true(status(root = root, verbose = FALSE)$github_token_visible)
  expect_false(grepl(secret, paste(capture.output(str(status(root = root, verbose = FALSE))), collapse = "\n"), fixed = TRUE))
})

test_that("gitcreds is consulted only when no GitHub token variable is set", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  boosterpak:::update_declared_array(
    file.path(root, "boosters.toml"),
    "extras",
    "declared",
    "seanthimons/ComptoxR"
  )
  calls <- 0L
  local_mocked_bindings(
    gitcreds_token_is_visible = function() {
      calls <<- calls + 1L
      TRUE
    },
    .package = "boosterpak"
  )

  withr::local_envvar(GITHUB_PAT = "ghp_env_value", GITHUB_TOKEN = NA)
  expect_true(status(root = root, verbose = FALSE)$github_token_visible)
  expect_equal(calls, 0L)

  withr::local_envvar(GITHUB_PAT = NA, GITHUB_TOKEN = NA)
  expect_true(status(root = root, verbose = FALSE)$github_token_visible)
  expect_equal(calls, 1L)
})

test_that("gitcreds check returns a logical scalar without prompting", {
  skip_if_not_installed("gitcreds")
  withr::local_envvar(GIT_TERMINAL_PROMPT = "1")
  seen <- NULL
  local_mocked_bindings(
    gitcreds_lookup = function() {
      seen <<- Sys.getenv("GIT_TERMINAL_PROMPT")
      NULL
    },
    .package = "boosterpak"
  )

  value <- boosterpak:::gitcreds_token_is_visible()

  expect_type(value, "logical")
  expect_length(value, 1L)
  expect_false(value)
  expect_identical(seen, "0")
  expect_identical(Sys.getenv("GIT_TERMINAL_PROMPT"), "1")
})

test_that("gitcreds check reports a stored token without returning it", {
  skip_if_not_installed("gitcreds")
  secret <- "ghp_gitcreds_test_value_0123"
  local_mocked_bindings(
    gitcreds_lookup = function() list(protocol = "https", host = "github.com", password = secret),
    .package = "boosterpak"
  )

  value <- boosterpak:::gitcreds_token_is_visible()

  expect_identical(value, TRUE)
})

test_that("github_source_specs keeps owner/repo specs and skips other remotes", {
  specs <- c(
    "seanthimons/ComptoxR",
    "r-lib/pak@v0.9",
    "owner/repo/subdir",
    "owner/repo/subdir@main",
    "gitlab::owner/repo",
    "bioc::Biobase",
    "local::./pkg",
    "https://github.com/owner/repo",
    "./local/path",
    "../other/path",
    "cli"
  )

  expect_equal(
    boosterpak:::github_source_specs(specs),
    c("seanthimons/ComptoxR", "r-lib/pak@v0.9", "owner/repo/subdir", "owner/repo/subdir@main")
  )
})
