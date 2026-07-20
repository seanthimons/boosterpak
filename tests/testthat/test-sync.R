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
    missing_packages = function(packages, root = ".", ...) character(),
    install_via = function(specs, root = ".", ...) TRUE,
    call_renv_snapshot = function(root = ".", packages = NULL) {
      snapshot_packages <<- packages
    },
    .package = "boosterpak"
  )

  sync(root = root, verbose = FALSE)

  expect_setequal(snapshot_packages, c("pak", "renv", "boosterpak", "cli"))
})

test_that("sync hydrates missing plain-name packages before pak install", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  add_pack("example", root = root, sync = FALSE, verbose = FALSE)
  hydrated <- NULL
  installed <- NULL

  local_mocked_bindings(
    ensure_project_renv = function(root = ".") TRUE,
    missing_packages = function(packages, root = ".", ...) c("pak", "renv", "boosterpak", "cli"),
    hydrate_via_renv = function(packages, root = ".") {
      hydrated <<- packages
    },
    install_via = function(specs, root = ".", ...) {
      installed <<- specs
    },
    call_renv_snapshot = function(root = ".", packages = NULL) TRUE,
    .package = "boosterpak"
  )

  sync(root = root, verbose = FALSE)

  expected_hydrated <- c("pak", "renv", "cli")
  if (identical(boosterpak:::self_install_spec(), "boosterpak")) {
    expected_hydrated <- c(expected_hydrated, "boosterpak")
  }
  expect_setequal(hydrated, expected_hydrated)
  expect_setequal(installed, c("pak", "renv", boosterpak:::self_install_spec(), "cli"))
})

test_that("sync rechecks missing packages after hydration before calling pak", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  add_pack("example", root = root, sync = FALSE, verbose = FALSE)
  calls <- 0
  installed <- NULL

  local_mocked_bindings(
    ensure_project_renv = function(root = ".") TRUE,
    missing_packages = function(packages, root = ".", ...) {
      calls <<- calls + 1
      if (calls == 1) c("pak", "renv", "boosterpak", "cli") else "boosterpak"
    },
    hydrate_via_renv = function(packages, root = ".") TRUE,
    install_via = function(specs, root = ".", ...) {
      installed <<- specs
    },
    call_renv_snapshot = function(root = ".", packages = NULL) TRUE,
    .package = "boosterpak"
  )

  sync(root = root, verbose = FALSE)

  expect_equal(calls, 2)
  expect_equal(installed, boosterpak:::self_install_spec())
})

test_that("sync hydrate false skips hydration", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  add_pack("example", root = root, sync = FALSE, verbose = FALSE)
  hydrated <- FALSE

  local_mocked_bindings(
    ensure_project_renv = function(root = ".") TRUE,
    missing_packages = function(packages, root = ".", ...) c("pak", "renv", "boosterpak", "cli"),
    hydrate_via_renv = function(packages, root = ".") {
      hydrated <<- TRUE
    },
    install_via = function(specs, root = ".", ...) TRUE,
    call_renv_snapshot = function(root = ".", packages = NULL) TRUE,
    .package = "boosterpak"
  )

  sync(root = root, hydrate = FALSE, verbose = FALSE)

  expect_false(hydrated)
})

test_that("sync does not hydrate source-specific package specs", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  add_pack("github-example", root = root, sync = FALSE, verbose = FALSE)
  hydrated <- NULL
  installed <- NULL

  local_mocked_bindings(
    ensure_project_renv = function(root = ".") TRUE,
    missing_packages = function(packages, root = ".", ...) "ComptoxR",
    hydrate_via_renv = function(packages, root = ".") {
      hydrated <<- packages
    },
    install_via = function(specs, root = ".", ...) {
      installed <<- specs
    },
    call_renv_snapshot = function(root = ".", packages = NULL) TRUE,
    .package = "boosterpak"
  )

  sync(root = root, verbose = FALSE)

  expect_equal(hydrated, character())
  expect_equal(installed, "seanthimons/ComptoxR")
})

test_that("install_via asks pak to avoid dependency upgrades", {
  root <- withr::local_tempdir()
  active_lib <- file.path(root, "active-library")
  dir.create(active_lib)
  old_libpaths <- .libPaths()
  withr::defer(.libPaths(old_libpaths))
  .libPaths(c(active_lib, old_libpaths))
  installed <- NULL
  installed_lib <- NULL
  upgrade <- NULL

  local_mocked_bindings(
    pkg_install = function(pkg, lib = .libPaths()[[1]], upgrade = TRUE, ...) {
      installed <<- pkg
      installed_lib <<- lib
      upgrade <<- upgrade
      invisible(TRUE)
    },
    .package = "pak"
  )

  boosterpak:::install_via("cli", root = root, library = "active")

  expect_equal(installed, "cli")
  expect_equal(
    installed_lib,
    normalizePath(active_lib, winslash = "/", mustWork = TRUE)
  )
  expect_false(upgrade)
})

test_that("active-library sync installs without renv and skips renv operations", {
  root <- withr::local_tempdir()
  active_lib <- file.path(root, "active-library")
  dir.create(active_lib)
  old_libpaths <- .libPaths()
  withr::defer(.libPaths(old_libpaths))
  .libPaths(c(active_lib, old_libpaths))
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  add_pack("github-example", root = root, sync = FALSE, verbose = FALSE)

  installed <- NULL
  used_library <- NULL
  hydrated <- FALSE
  snapshotted <- FALSE

  local_mocked_bindings(
    missing_packages = function(packages, root = ".", library = "renv") {
      used_library <<- library
      packages
    },
    install_via = function(specs, root = ".", library = "renv") {
      installed <<- specs
      used_library <<- library
    },
    hydrate_via_renv = function(packages, root = ".") {
      hydrated <<- TRUE
    },
    call_renv_snapshot = function(root = ".", packages = NULL) {
      snapshotted <<- TRUE
    },
    .package = "boosterpak"
  )

  sync(root = root, library = "active", verbose = FALSE)

  expect_identical(used_library, "active")
  expect_true("seanthimons/ComptoxR" %in% installed)
  expect_false(hydrated)
  expect_false(snapshotted)
  expect_true(file.exists(file.path(root, "boosters", "attach.R")))
})

test_that("sync reads the active-library strategy from project config", {
  root <- withr::local_tempdir()
  active_lib <- file.path(root, "active-library")
  dir.create(active_lib)
  old_libpaths <- .libPaths()
  withr::defer(.libPaths(old_libpaths))
  .libPaths(c(active_lib, old_libpaths))
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  path <- file.path(root, "boosters.toml")
  lines <- readLines(path, warn = FALSE)
  lines <- sub('library = "renv"', 'library = "active"', lines, fixed = TRUE)
  writeLines(lines, path)

  used_library <- NULL
  local_mocked_bindings(
    missing_packages = function(packages, root = ".", library = "renv") {
      used_library <<- library
      character()
    },
    install_via = function(specs, root = ".", library = "renv") TRUE,
    .package = "boosterpak"
  )

  sync(root = root, verbose = FALSE)

  expect_identical(used_library, "active")
})

test_that("sync restore does not hydrate", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  jsonlite::write_json(
    list(R = list(Version = "4.5.1"), Packages = list(pak = list(Package = "pak"), renv = list(Package = "renv"), boosterpak = list(Package = "boosterpak"))),
    file.path(root, "renv.lock"),
    auto_unbox = TRUE
  )
  hydrated <- FALSE

  local_mocked_bindings(
    call_renv_restore = function(root = ".") TRUE,
    hydrate_via_renv = function(packages, root = ".") {
      hydrated <<- TRUE
    },
    .package = "boosterpak"
  )

  sync(mode = "restore", root = root, verbose = FALSE)

  expect_false(hydrated)
})

test_that("missing package detection checks the project renv library", {
  root <- withr::local_tempdir()
  lib <- renv::paths$library(project = root)
  dir.create(file.path(lib, "cli"), recursive = TRUE)
  writeLines("Package: cli", file.path(lib, "cli", "DESCRIPTION"))

  missing <- boosterpak:::missing_packages(c("boosterpak", "cli"), root = root)

  expect_equal(missing, "boosterpak")
})

test_that("missing package detection checks the selected active library", {
  root <- withr::local_tempdir()
  active_lib <- file.path(root, "active-library")
  dir.create(file.path(active_lib, "cli"), recursive = TRUE)
  writeLines("Package: cli", file.path(active_lib, "cli", "DESCRIPTION"))
  old_libpaths <- .libPaths()
  withr::defer(.libPaths(old_libpaths))
  .libPaths(c(active_lib, old_libpaths))

  missing <- boosterpak:::missing_packages(
    c("boosterpak", "cli"),
    root = root,
    library = "active"
  )

  expect_equal(missing, "boosterpak")
})
