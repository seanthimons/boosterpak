test_that("sync apply requires active project-local renv", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  dir.create(file.path(root, "renv"), recursive = TRUE)
  writeLines("", file.path(root, "renv", "activate.R"))

  expect_error(
    sync(root = root, verbose = FALSE),
    "No active project-local renv library"
  )
})

test_that("sync restore requires boosters.toml and renv.lock", {
  root <- withr::local_tempdir()
  expect_error(
    sync(mode = "restore", root = root, verbose = FALSE),
    "boosters.toml"
  )

  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  expect_error(
    sync(mode = "restore", root = root, verbose = FALSE),
    "renv.lock"
  )
})

test_that("restore consistency warning reports direct packages absent from lockfile", {
  root <- withr::local_tempdir()
  lockfile <- file.path(root, "renv.lock")
  jsonlite::write_json(
    list(R = list(Version = "4.5.1"), Packages = list(renv = list(Package = "renv"))),
    lockfile,
    auto_unbox = TRUE
  )

  expect_warning(
    boosterpak:::warn_missing_lock_packages(c("cli"), lockfile),
    "cli"
  )
})

test_that("sync snapshots declared packages explicitly", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  add_pack("example", root = root, sync = FALSE, verbose = FALSE)
  snapshot_packages <- NULL

  local_mocked_bindings(
    ensure_project_renv = function(root = ".") TRUE,
    missing_packages = function(packages, root = ".") character(),
    install_via = function(specs, root = ".") TRUE,
    call_renv_snapshot = function(root = ".", packages = NULL) {
      snapshot_packages <<- packages
    },
    .package = "boosterpak"
  )

  sync(root = root, verbose = FALSE)

  expect_setequal(snapshot_packages, c("fs", "here", "janitor", "rio", "tidyverse", "digest", "boosterpak", "cli"))
})

test_that("missing package detection checks the project renv library", {
  root <- withr::local_tempdir()
  lib <- renv::paths$library(project = root)
  dir.create(file.path(lib, "cli"), recursive = TRUE)
  writeLines("Package: cli", file.path(lib, "cli", "DESCRIPTION"))

  missing <- boosterpak:::missing_packages(c("boosterpak", "cli"), root = root)

  expect_equal(missing, "boosterpak")
})
