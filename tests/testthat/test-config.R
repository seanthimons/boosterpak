test_that("init writes v0.1 config and Rprofile hook when explicit", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "yes", verbose = FALSE)

  expect_true(file.exists(file.path(root, "boosters.toml")))
  expect_true(file.exists(file.path(root, "boosters", "packs")))
  expect_true(file.exists(file.path(root, "air.toml")))
  expect_true(boosterpak:::has_rprofile_line(root))

  air <- boosterpak:::read_toml_file(file.path(root, "air.toml"))
  expect_equal(air$format$`line-width`, 120)
  expect_equal(air$format$`indent-width`, 2)
  expect_equal(air$format$`indent-style`, "space")
  expect_equal(air$format$`line-ending`, "auto")
  expect_true(air$format$`persistent-line-breaks`)
  expect_equal(air$format$exclude, list())
  expect_true(air$format$`default-exclude`)
  expect_equal(air$format$skip, list())
  expect_equal(air$format$table, list())
  expect_true(air$format$`default-table`)

  config <- boosterpak:::read_config(root)
  expect_equal(config$packs$declared, "core")
  expect_true(config$attach$enabled)
  expect_equal(config$attach$declared, list())
  expect_equal(config$attach$exclude, list())
  expect_equal(
    vapply(config$extras$declared, boosterpak:::package_name_from_spec, character(1), USE.NAMES = FALSE),
    "boosterpak"
  )
  expect_silent(boosterpak:::validate_config(config, root))
})

test_that("pack attach schema accepts documented shapes and rejects invalid types", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  dir.create(file.path(root, "boosters", "packs"), recursive = TRUE, showWarnings = FALSE)

  writeLines(c(
    'name = "attach_true"',
    'description = "Attach all direct packages."',
    'packages = ["cli"]',
    "attach = true"
  ), file.path(root, "boosters", "packs", "attach_true.toml"))
  expect_silent(boosterpak:::load_pack("attach_true", root))

  writeLines(c(
    'name = "attach_false"',
    'description = "Attach no packages."',
    'packages = ["cli"]',
    "attach = false"
  ), file.path(root, "boosters", "packs", "attach_false.toml"))
  expect_silent(boosterpak:::load_pack("attach_false", root))

  writeLines(c(
    'name = "attach_vector"',
    'description = "Attach selected packages."',
    'packages = ["cli", "glue"]',
    'attach = ["glue"]'
  ), file.path(root, "boosters", "packs", "attach_vector.toml"))
  expect_silent(boosterpak:::load_pack("attach_vector", root))

  writeLines(c(
    'name = "attach_missing"',
    'description = "Attach defaults."',
    'packages = ["cli"]'
  ), file.path(root, "boosters", "packs", "attach_missing.toml"))
  expect_silent(boosterpak:::load_pack("attach_missing", root))

  writeLines(c(
    'name = "attach_bad"',
    'description = "Invalid attach."',
    'packages = ["cli"]',
    "attach = 1"
  ), file.path(root, "boosters", "packs", "attach_bad.toml"))
  expect_error(boosterpak:::load_pack("attach_bad", root), "attach")
})

test_that("attach config validation rejects invalid top-level types", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  path <- file.path(root, "boosters.toml")
  lines <- readLines(path, warn = FALSE)
  lines[lines == "enabled = true"] <- 'enabled = "yes"'
  writeLines(lines, path)

  expect_error(boosterpak:::validate_config(boosterpak:::read_config(root), root), "enabled")
})

test_that("init repairs generated beta manifests with boosterpak self extra", {
  root <- withr::local_tempdir()
  writeLines(c(
    "# keep this comment",
    "[project]",
    'name = "beta"',
    "",
    "[packs]",
    'declared = ["core"]',
    "",
    "[extras]",
    "declared = [] # keep inline",
    "",
    "[future]",
    "value = true"
  ), file.path(root, "boosters.toml"))

  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  lines <- readLines(file.path(root, "boosters.toml"), warn = FALSE)
  expect_true("# keep this comment" %in% lines)
  expect_true("[future]" %in% lines)
  expect_match(lines[grep("^declared = ", lines)[2]], "boosterpak")
  config <- boosterpak:::read_config(root)
  expect_equal(
    vapply(config$extras$declared, boosterpak:::package_name_from_spec, character(1), USE.NAMES = FALSE),
    "boosterpak"
  )
})

test_that("init leaves custom extras arrays unchanged", {
  root <- withr::local_tempdir()
  writeLines(c(
    "[project]",
    'name = "custom"',
    "",
    "[packs]",
    'declared = ["core"]',
    "",
    "[extras]",
    "declared = [",
    '  "cli"',
    "]"
  ), file.path(root, "boosters.toml"))
  before <- readLines(file.path(root, "boosters.toml"), warn = FALSE)

  expect_error(init(root = root, renv = "no", rprofile = "no", verbose = FALSE), NA)

  expect_equal(readLines(file.path(root, "boosters.toml"), warn = FALSE), before)
})

test_that("self install spec follows install metadata", {
  expect_equal(
    boosterpak:::self_install_spec(list(Package = "boosterpak", Built = "R 4.5.1")),
    "boosterpak"
  )
  expect_equal(
    boosterpak:::self_install_spec(list(
      Package = "boosterpak",
      RemoteType = "github",
      RemoteUsername = "owner",
      RemoteRepo = "repo"
    )),
    "owner/repo"
  )
  expect_equal(
    boosterpak:::self_install_spec(list(Package = "boosterpak")),
    "seanthimons/boosterpak"
  )
})

test_that("init inserts Rprofile hook after renv activation", {
  root <- withr::local_tempdir()
  writeLines(c("before <- TRUE", "source(\"renv/activate.R\")", "after <- TRUE"), file.path(root, ".Rprofile"))

  init(root = root, renv = "no", rprofile = "yes", verbose = FALSE)

  lines <- readLines(file.path(root, ".Rprofile"), warn = FALSE)
  renv_line <- grep('source\\("renv/activate\\.R"\\)', lines)
  hook_line <- match(boosterpak:::rprofile_line(), lines)
  expect_equal(hook_line, renv_line + 1L)
})

test_that("init upgrades legacy Rprofile hook without duplication", {
  root <- withr::local_tempdir()
  writeLines(c("before <- TRUE", boosterpak:::legacy_rprofile_line(), "after <- TRUE"), file.path(root, ".Rprofile"))

  init(root = root, renv = "no", rprofile = "yes", verbose = FALSE)

  lines <- readLines(file.path(root, ".Rprofile"), warn = FALSE)
  expect_false(boosterpak:::legacy_rprofile_line() %in% lines)
  expect_equal(sum(lines == boosterpak:::rprofile_line()), 1L)
  expect_match(boosterpak:::rprofile_line(), "attach\\.R")
})

test_that("init leaves existing Rprofile hook unchanged", {
  root <- withr::local_tempdir()
  writeLines(c("before <- TRUE", boosterpak:::rprofile_line(), "after <- TRUE"), file.path(root, ".Rprofile"))
  before <- readLines(file.path(root, ".Rprofile"), warn = FALSE)

  init(root = root, renv = "no", rprofile = "yes", verbose = FALSE)

  expect_equal(readLines(file.path(root, ".Rprofile"), warn = FALSE), before)
})

test_that("init does not overwrite existing boosters.toml", {
  root <- withr::local_tempdir()
  writeLines(c("[project]", 'name = "kept"'), file.path(root, "boosters.toml"))
  before <- readLines(file.path(root, "boosters.toml"), warn = FALSE)

  expect_error(init(root = root, renv = "no", rprofile = "no", verbose = FALSE), NA)

  expect_equal(readLines(file.path(root, "boosters.toml"), warn = FALSE), before)
})

test_that("init with renv yes loads existing project renv when inactive", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  dir.create(file.path(root, "renv"), recursive = TRUE)
  writeLines("", file.path(root, "renv", "activate.R"))

  calls <- character()
  installed <- NULL
  snapshotted <- NULL
  local_mocked_bindings(
    call_renv_load = function(root = ".") calls <<- c(calls, "load"),
    call_renv_init = function(root = ".") calls <<- c(calls, "init"),
    missing_packages = function(packages, root = ".") packages,
    install_via = function(specs, root = ".") installed <<- specs,
    call_renv_snapshot = function(root = ".", packages = NULL) snapshotted <<- packages,
    .package = "boosterpak"
  )

  init(root = root, renv = "yes", rprofile = "no", verbose = FALSE)

  expect_equal(calls, "load")
  expect_setequal(installed, c("pak", "renv", boosterpak:::self_install_spec()))
  expect_setequal(snapshotted, c("pak", "renv", "boosterpak"))
})

test_that("init with renv yes initializes, bootstraps only workflow packages, and snapshots", {
  root <- withr::local_tempdir()
  installed <- NULL
  snapshotted <- NULL
  calls <- character()

  local_mocked_bindings(
    is_project_renv_active = function(root = ".") FALSE,
    has_project_renv = function(root = ".") FALSE,
    call_renv_init = function(root = ".") calls <<- c(calls, "init"),
    call_renv_load = function(root = ".") calls <<- c(calls, "load"),
    missing_packages = function(packages, root = ".") packages[packages != "renv"],
    install_via = function(specs, root = ".") installed <<- specs,
    call_renv_snapshot = function(root = ".", packages = NULL) snapshotted <<- packages,
    .package = "boosterpak"
  )

  init(root = root, renv = "yes", rprofile = "no", verbose = FALSE)

  expect_equal(calls, "init")
  expect_setequal(installed, c("pak", boosterpak:::self_install_spec()))
  expect_setequal(snapshotted, c("pak", "renv", "boosterpak"))
  expect_false(any(c("fs", "here", "janitor", "rio", "tidyverse", "digest") %in% installed))
})

test_that("init with renv yes skips bootstrap snapshot when auto_snapshot is false", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  path <- file.path(root, "boosters.toml")
  lines <- readLines(path, warn = FALSE)
  lines[lines == "auto_snapshot = true"] <- "auto_snapshot = false"
  writeLines(lines, path)
  snapshotted <- FALSE

  local_mocked_bindings(
    is_project_renv_active = function(root = ".") FALSE,
    has_project_renv = function(root = ".") FALSE,
    call_renv_init = function(root = ".") TRUE,
    missing_packages = function(packages, root = ".") character(),
    install_via = function(specs, root = ".") TRUE,
    call_renv_snapshot = function(root = ".", packages = NULL) snapshotted <<- TRUE,
    .package = "boosterpak"
  )

  init(root = root, renv = "yes", rprofile = "no", verbose = FALSE)

  expect_false(snapshotted)
})

test_that("init with renv no skips renv bootstrap", {
  root <- withr::local_tempdir()
  called <- FALSE

  local_mocked_bindings(
    is_project_renv_active = function(root = ".") TRUE,
    call_renv_init = function(root = ".") called <<- TRUE,
    install_via = function(specs, root = ".") called <<- TRUE,
    call_renv_snapshot = function(root = ".", packages = NULL) called <<- TRUE,
    .package = "boosterpak"
  )

  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  expect_false(called)
})

test_that("non-interactive ask errors when Rprofile action is needed", {
  root <- withr::local_tempdir()
  expect_error(
    init(root = root, renv = "no", rprofile = "ask", verbose = FALSE),
    "rprofile = 'yes'"
  )
})

test_that("status reports malformed config as invalid without aborting", {
  root <- withr::local_tempdir()
  writeLines("[packs", file.path(root, "boosters.toml"))

  s <- status(root = root, verbose = FALSE)

  expect_true(s$config_exists)
  expect_false(s$config_valid)
  expect_match(s$config_error, "TOML|toml|Expected|parse")
})

test_that("status reports broader package, pack, and function state", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  add_pack("example", root = root, sync = FALSE, verbose = FALSE)
  add_function("ni", root = root, verbose = FALSE)
  path <- boosterpak:::function_file("ni", root)
  writeLines(c(readLines(path, warn = FALSE), "# local edit"), path)

  local_mocked_bindings(
    missing_packages = function(packages, root = ".") packages[packages %in% "cli"],
    .package = "boosterpak"
  )

  s <- status(root = root, verbose = FALSE)

  expect_true(s$config_valid)
  expect_equal(s$packs, c("core", "example"))
  expect_setequal(s$resolved_packs, c("core", "example"))
  expect_true(s$package_count >= 1)
  expect_equal(s$missing_packages, "cli")
  expect_equal(s$missing_package_count, 1L)
  expect_equal(s$functions, "ni")
  expect_equal(s$function_count, 1L)
  expect_equal(s$function_missing_count, 0L)
  expect_equal(s$function_drift_count, 1L)
  expect_true(s$attach_enabled)
  expect_true(s$attach_package_count >= 1L)
  expect_false(s$attach_file_exists)
  expect_true(all(c("project", "user", "builtin") %in% names(s$pack_counts)))
  expect_true(all(c("name", "scope", "path") %in% names(s$pack_catalog)))
})

test_that("status reports TOML-installed functions with missing files", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  add_function("ni", root = root, verbose = FALSE)
  unlink(boosterpak:::function_file("ni", root))

  s <- status(root = root, verbose = FALSE)

  expect_equal(s$function_missing_count, 1L)
  expect_false(s$function_status$exists[s$function_status$name == "ni"])
})

test_that("v0.1 settings validation accepts documented shapes", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  path <- file.path(root, "boosters.toml")
  lines <- readLines(path, warn = FALSE)
  lines[lines == 'parallel_daemons = "auto"'] <- "parallel_daemons = 2"
  lines <- c(lines, "", "[settings.camcorder]", "enabled = false")
  writeLines(lines, path)

  expect_silent(boosterpak:::validate_config(boosterpak:::read_config(root), root))
})

test_that("v0.1 settings validation rejects invalid setting types", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  path <- file.path(root, "boosters.toml")
  lines <- readLines(path, warn = FALSE)
  lines[lines == "air_toml = true"] <- 'air_toml = "yes"'
  writeLines(lines, path)

  expect_error(
    boosterpak:::validate_config(boosterpak:::read_config(root), root),
    "air_toml"
  )

  lines[lines == 'air_toml = "yes"'] <- "air_toml = true"
  lines[lines == 'parallel_daemons = "auto"'] <- "parallel_daemons = 0"
  writeLines(lines, path)

  expect_error(
    boosterpak:::validate_config(boosterpak:::read_config(root), root),
    "parallel_daemons"
  )
})

test_that("unknown TOML keys warn instead of erroring", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  path <- file.path(root, "boosters.toml")
  writeLines(c(readLines(path, warn = FALSE), "", "[future]", "value = true"), path)

  expect_warning(
    boosterpak:::validate_config(boosterpak:::read_config(root), root),
    "Unknown top-level key"
  )
})
