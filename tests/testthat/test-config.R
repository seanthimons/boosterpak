test_that("init writes v0.1 config and Rprofile hook when explicit", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "yes", verbose = FALSE)

  expect_true(file.exists(file.path(root, "boosters.toml")))
  expect_true(file.exists(file.path(root, "boosters", "packs")))
  expect_true(file.exists(file.path(root, "air.toml")))
  expect_true(boosterpak:::has_rprofile_line(root))

  config <- boosterpak:::read_config(root)
  expect_equal(config$packs$declared, "core")
  expect_silent(boosterpak:::validate_config(config, root))
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
  local_mocked_bindings(
    call_renv_load = function(root = ".") calls <<- c(calls, "load"),
    call_renv_init = function(root = ".") calls <<- c(calls, "init"),
    .package = "boosterpak"
  )

  init(root = root, renv = "yes", rprofile = "no", verbose = FALSE)

  expect_equal(calls, "load")
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
