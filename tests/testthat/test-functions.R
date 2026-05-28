test_that("list_functions reports catalog and installation status", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  functions <- list_functions(root = root, verbose = FALSE)

  expect_setequal(functions$name, c("ni", "my_skim", "theme_custom", "geo_mean"))
  expect_false(any(functions$installed))
})

test_that("add_function materializes file and updates TOML", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  path <- add_function("ni", root = root, verbose = FALSE)

  expect_true(file.exists(path))
  expect_equal(readLines(path, warn = FALSE), readLines(boosterpak:::catalog_function_file("ni"), warn = FALSE))
  config <- boosterpak:::read_config(root)
  expect_equal(config$functions$installed, "ni")
  functions <- list_functions(root = root, verbose = FALSE)
  expect_true(functions$installed[functions$name == "ni"])
})

test_that("add_function refuses to overwrite local edits unless explicit", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  path <- add_function("ni", root = root, verbose = FALSE)
  writeLines(c(readLines(path, warn = FALSE), "# local edit"), path)

  expect_error(add_function("ni", root = root, verbose = FALSE), "overwrite = TRUE")

  add_function("ni", root = root, overwrite = TRUE, verbose = FALSE)
  expect_equal(readLines(path, warn = FALSE), readLines(boosterpak:::catalog_function_file("ni"), warn = FALSE))
})

test_that("remove_function deletes file and updates TOML", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  path <- add_function("geo_mean", root = root, verbose = FALSE)

  remaining <- remove_function("geo_mean", root = root, verbose = FALSE)

  expect_false(file.exists(path))
  expect_equal(remaining, character())
  expect_equal(boosterpak:::installed_functions(boosterpak:::read_config(root)), character())
})

test_that("check_functions and diff_function report drift", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  path <- add_function("ni", root = root, verbose = FALSE)

  expect_true(check_functions(root = root, verbose = FALSE)$matches)

  writeLines(c(readLines(path, warn = FALSE), "# local edit"), path)
  checks <- check_functions(root = root, verbose = FALSE)
  diff <- diff_function("ni", root = root, verbose = FALSE)

  expect_false(checks$matches)
  expect_true(any(grepl("^\\+# local edit", diff)))
})

test_that("sync rematerializes TOML-installed missing function files", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  path <- add_function("ni", root = root, verbose = FALSE)
  unlink(path)

  local_mocked_bindings(
    ensure_project_renv = function(root = ".") TRUE,
    missing_packages = function(packages) character(),
    install_via = function(specs, root = ".") TRUE,
    call_renv_snapshot = function(root = ".", packages = NULL) TRUE,
    .package = "boosterpak"
  )

  sync(root = root, verbose = FALSE)

  expect_true(file.exists(path))
})

test_that("sync leaves existing materialized function files untouched", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  path <- add_function("ni", root = root, verbose = FALSE)
  edited <- c(readLines(path, warn = FALSE), "# local edit")
  writeLines(edited, path)

  local_mocked_bindings(
    ensure_project_renv = function(root = ".") TRUE,
    missing_packages = function(packages) character(),
    install_via = function(specs, root = ".") TRUE,
    call_renv_snapshot = function(root = ".", packages = NULL) TRUE,
    .package = "boosterpak"
  )

  sync(root = root, verbose = FALSE)

  expect_equal(readLines(path, warn = FALSE), edited)
})

test_that("add_pack copies bundled functions and refuses local overwrite by default", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  add_function("ni", root = root, verbose = FALSE)
  save_pack("portable_fns", root = root, verbose = FALSE)
  remove_function("ni", root = root, verbose = FALSE)

  add_pack("portable_fns", root = root, sync = FALSE, overwrite_functions = TRUE, verbose = FALSE)
  expect_true(file.exists(file.path(root, "boosters", "fn_ni.R")))
  expect_true(file.exists(file.path(root, "boosters", "packs", "portable_fns", "functions", "fn_ni.R")))

  remove_pack("portable_fns", root = root, sync = FALSE, verbose = FALSE)
  writeLines("# local", file.path(root, "boosters", "fn_ni.R"))
  expect_error(add_pack("portable_fns", root = root, sync = FALSE, verbose = FALSE), "overwrite_functions = TRUE")
  add_pack("portable_fns", root = root, sync = FALSE, overwrite_functions = TRUE, verbose = FALSE)
  expect_equal(
    readLines(file.path(root, "boosters", "fn_ni.R"), warn = FALSE),
    readLines(file.path(root, "boosters", "packs", "portable_fns", "functions", "fn_ni.R"), warn = FALSE)
  )
})

test_that("sync copies missing pack-bundled functions without overwriting edits", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  add_function("ni", root = root, verbose = FALSE)
  save_pack("portable_fns", root = root, verbose = FALSE)
  remove_function("ni", root = root, verbose = FALSE)
  add_pack("portable_fns", root = root, sync = FALSE, overwrite_functions = TRUE, verbose = FALSE)
  path <- file.path(root, "boosters", "fn_ni.R")
  unlink(path)

  local_mocked_bindings(
    ensure_project_renv = function(root = ".") TRUE,
    missing_packages = function(packages) character(),
    install_via = function(specs, root = ".") TRUE,
    call_renv_snapshot = function(root = ".", packages = NULL) TRUE,
    .package = "boosterpak"
  )

  sync(root = root, verbose = FALSE)
  expect_true(file.exists(path))

  edited <- c(readLines(path, warn = FALSE), "# local edit")
  writeLines(edited, path)
  sync(root = root, verbose = FALSE)
  expect_equal(readLines(path, warn = FALSE), edited)
})

test_that("remove_pack optionally removes only unchanged unshared bundled functions", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  add_function("ni", root = root, verbose = FALSE)
  save_pack("portable_fns", root = root, verbose = FALSE)
  remove_function("ni", root = root, verbose = FALSE)
  add_pack("portable_fns", root = root, sync = FALSE, verbose = FALSE)
  path <- file.path(root, "boosters", "fn_ni.R")

  remove_pack("portable_fns", root = root, sync = FALSE, verbose = FALSE)
  expect_true(file.exists(path))

  add_pack("portable_fns", root = root, sync = FALSE, overwrite_functions = TRUE, verbose = FALSE)
  writeLines(c(readLines(path, warn = FALSE), "# local edit"), path)
  remove_pack("portable_fns", root = root, sync = FALSE, remove_functions = TRUE, verbose = FALSE)
  expect_true(file.exists(path))

  add_pack("portable_fns", root = root, sync = FALSE, overwrite_functions = TRUE, verbose = FALSE)
  remove_pack("portable_fns", root = root, sync = FALSE, remove_functions = TRUE, verbose = FALSE)
  expect_false(file.exists(path))
})

test_that("function validation uses did-you-mean for unknown functions", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  path <- file.path(root, "boosters.toml")
  lines <- readLines(path, warn = FALSE)
  lines[lines == "installed = []"] <- 'installed = ["geo_meen"]'
  writeLines(lines, path)

  expect_error(
    boosterpak:::validate_config(boosterpak:::read_config(root), root),
    "Did you mean"
  )
})
