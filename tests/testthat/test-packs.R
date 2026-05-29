test_that("built-in packs are discoverable", {
  packs <- list_packs(scope = "builtin", verbose = FALSE)
  expect_setequal(packs$name, c("scaffold-analysis", "core", "eda", "example", "github-example"))
  expect_true(all(c("name", "description", "scope", "sources", "path") %in% names(packs)))
  expect_equal(
    packs$sources[packs$name == "github-example"],
    "ComptoxR=seanthimons/ComptoxR"
  )
})

test_that("packs resolve transitively", {
  expect_equal(boosterpak:::resolve_pack("example"), "cli")
})

test_that("built-in catalog matches v0.1 PRD contents", {
  expect_equal(
    boosterpak:::resolve_pack("core"),
    c("pak", "renv")
  )
  expect_equal(
    boosterpak:::resolve_pack("eda"),
    c("fs", "here", "janitor", "rio", "dplyr", "tidyr", "readr", "ggplot2", "stringr", "purrr", "lubridate", "scales", "glue", "digest", "skimr")
  )
  expect_equal(
    boosterpak:::resolve_pack_functions("eda"),
    c("ni", "my_skim", "theme_custom", "geo_mean")
  )
  expect_equal(boosterpak:::resolve_pack("github-example"), "ComptoxR")
  expect_equal(
    boosterpak:::resolve_pack_sources("github-example"),
    c(ComptoxR = "seanthimons/ComptoxR")
  )
  expect_equal(boosterpak:::resolve_pack("scaffold-analysis"), c("fs", "here"))
  expect_equal(boosterpak:::resolve_pack_functions("scaffold-analysis"), "scaffold_analysis")
})

test_that("scaffold analysis pack materializes its nested helper function", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  add_pack("scaffold-analysis", root = root, sync = FALSE, verbose = FALSE)

  expect_true(file.exists(file.path(root, "boosters", "packs", "scaffold-analysis", "scaffold-analysis.toml")))
  expect_true(file.exists(file.path(
    root,
    "boosters",
    "packs",
    "scaffold-analysis",
    "functions",
    "fn_scaffold_analysis.R"
  )))
})

test_that("pack discovery supports flat package packs and nested function packs", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "boosters", "packs", "nested", "functions"), recursive = TRUE)
  writeLines(c(
    'name = "flat"',
    'description = "Flat pack"',
    'packages = ["cli"]'
  ), file.path(root, "boosters", "packs", "flat.toml"))
  writeLines(c(
    'name = "nested"',
    'description = "Nested pack"',
    'packages = ["cli"]',
    'functions = ["helper"]'
  ), file.path(root, "boosters", "packs", "nested", "nested.toml"))
  writeLines("helper <- function() TRUE", file.path(root, "boosters", "packs", "nested", "functions", "fn_helper.R"))

  packs <- list_packs(root = root, scope = "project", verbose = FALSE)

  expect_setequal(packs$name, c("flat", "nested"))
  expect_equal(boosterpak:::resolve_pack_functions("nested", root = root), "helper")
})

test_that("flat packs cannot declare functions", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "boosters", "packs"), recursive = TRUE)
  writeLines(c(
    'name = "bad"',
    'description = "Bad flat function pack"',
    'packages = ["cli"]',
    'functions = ["helper"]'
  ), file.path(root, "boosters", "packs", "bad.toml"))

  expect_error(
    list_packs(root = root, scope = "project", verbose = FALSE),
    "function-bearing packs must use nested layout"
  )
})

test_that("duplicate flat and nested packs fail clearly", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "boosters", "packs", "dupe"), recursive = TRUE)
  writeLines(c(
    'name = "dupe"',
    'description = "Flat duplicate"',
    'packages = ["cli"]'
  ), file.path(root, "boosters", "packs", "dupe.toml"))
  writeLines(c(
    'name = "dupe"',
    'description = "Nested duplicate"',
    'packages = ["digest"]'
  ), file.path(root, "boosters", "packs", "dupe", "dupe.toml"))

  expect_error(
    list_packs(root = root, scope = "project", verbose = FALSE),
    "Duplicate pack manifest"
  )
})

test_that("init materializes declared built-in packs into the project", {
  root <- withr::local_tempdir()

  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  path <- file.path(root, "boosters", "packs", "core.toml")
  expect_true(file.exists(path))
  expect_equal(
    readLines(path, warn = FALSE),
    readLines(system.file("packs", "core.toml", package = "boosterpak"), warn = FALSE)
  )
  expect_equal(list_packs(root = root, scope = "project", verbose = FALSE)$name, "core")
})

test_that("add_pack materializes newly declared packs even without sync", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  add_pack("example", root = root, sync = FALSE, verbose = FALSE)

  expect_true(file.exists(file.path(root, "boosters", "packs", "example.toml")))
})

test_that("pack materialization preserves existing project-local pack files", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "boosters", "packs"), recursive = TRUE)
  writeLines(c(
    'name = "core"',
    'description = "Project core"',
    'packages = ["cli"]'
  ), file.path(root, "boosters", "packs", "core.toml"))
  before <- readLines(file.path(root, "boosters", "packs", "core.toml"), warn = FALSE)

  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  expect_equal(readLines(file.path(root, "boosters", "packs", "core.toml"), warn = FALSE), before)
  expect_equal(boosterpak:::resolve_pack("core", root = root), "cli")
})

test_that("materialization includes extended parent packs", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  writeLines(c(
    'name = "child"',
    'description = "Project child"',
    'packages = ["digest"]',
    'extends = ["example"]'
  ), file.path(root, "boosters", "packs", "child.toml"))

  add_pack("child", root = root, sync = FALSE, verbose = FALSE)

  expect_true(file.exists(file.path(root, "boosters", "packs", "example.toml")))
})

test_that("source overrides become install specs", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  writeLines(c(
    'name = "custom"',
    'description = "Custom pack"',
    'packages = ["pointblank"]',
    "",
    "[sources]",
    '"pointblank" = "rstudio/pointblank"'
  ), file.path(root, "boosters", "packs", "custom.toml"))
  add_pack("custom", root = root, sync = FALSE, verbose = FALSE)

  config <- boosterpak:::read_config(root)
  expect_true("pointblank" %in% boosterpak:::resolve_config_packages(config, root))
  expect_true("rstudio/pointblank" %in% boosterpak:::resolve_config_install_specs(config, root))
})

test_that("GitHub extras are install specs but resolve to package-like names", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  path <- file.path(root, "boosters.toml")
  boosterpak:::update_declared_array(path, "extras", "declared", c("seanthimons/boosterpak", "rstudio/pointblank"))

  config <- boosterpak:::read_config(root)

  expect_true("pointblank" %in% boosterpak:::resolve_config_packages(config, root))
  expect_true("rstudio/pointblank" %in% boosterpak:::resolve_config_install_specs(config, root))
  expect_true("boosterpak" %in% boosterpak:::resolve_config_packages(config, root))
  expect_true("seanthimons/boosterpak" %in% boosterpak:::resolve_config_install_specs(config, root))
})

test_that("unknown pack errors include suggestion and grouped availability", {
  expect_error(
    boosterpak:::load_pack("exampel"),
    regexp = "Did you mean.+example.+Built-in.+core.+eda.+User:.+Project:",
    class = "rlang_error"
  )
})

test_that("project packs shadow built-in packs", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  writeLines(c(
    'name = "example"',
    'description = "Project-local example shadow"',
    'packages = ["digest"]'
  ), file.path(root, "boosters", "packs", "example.toml"))

  packs <- list_packs(root = root, verbose = FALSE)

  expect_equal(packs$scope[packs$name == "example"], "project")
  expect_equal(boosterpak:::resolve_pack("example", root = root), "digest")
})

test_that("pack cycles are detected clearly", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  writeLines(c(
    'name = "a"',
    'description = "Cycle A"',
    'packages = []',
    'extends = ["b"]'
  ), file.path(root, "boosters", "packs", "a.toml"))
  writeLines(c(
    'name = "b"',
    'description = "Cycle B"',
    'packages = []',
    'extends = ["a"]'
  ), file.path(root, "boosters", "packs", "b.toml"))

  expect_error(
    boosterpak:::resolve_pack("a", root = root),
    "Pack cycle detected: a -> b -> a"
  )
})

test_that("save_pack captures resolved project packages as a flat project pack", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  add_pack("example", root = root, sync = FALSE, verbose = FALSE)
  path <- boosters_file(root)
  boosterpak:::update_declared_array(path, "extras", "declared", c("seanthimons/boosterpak", "withr", "rstudio/pointblank"))
  boosterpak:::update_declared_array(path, "exclude", "declared", "digest")

  saved <- save_pack("project_baseline", root = root, verbose = FALSE)
  data <- boosterpak:::read_toml_file(saved)

  expect_equal(saved, normalizePath(file.path(root, "boosters", "packs", "project_baseline.toml"), winslash = "/", mustWork = FALSE))
  expect_equal(data$name, "project_baseline")
  expect_null(data$extends)
  expect_setequal(data$packages, c("pak", "renv", "cli", "boosterpak", "withr", "pointblank"))
  expect_equal(data$sources[["boosterpak"]], "seanthimons/boosterpak")
  expect_equal(data$sources[["pointblank"]], "rstudio/pointblank")
  expect_equal(boosterpak:::toml_string_array(data$functions, "functions"), character())
})

test_that("save_pack captures installed, all, none, and explicit nested functions", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  ni <- add_function("ni", root = root, verbose = FALSE)
  writeLines("custom_helper <- function() TRUE", file.path(root, "boosters", "fn_custom_helper.R"))

  installed <- save_pack("installed_fns", root = root, verbose = FALSE)
  expect_equal(installed, normalizePath(file.path(root, "boosters", "packs", "installed_fns", "installed_fns.toml"), winslash = "/", mustWork = FALSE))
  expect_equal(boosterpak:::read_toml_file(installed)$functions, "ni")
  expect_equal(readLines(boosterpak:::pack_function_file(installed, "ni"), warn = FALSE), readLines(ni, warn = FALSE))

  all <- save_pack("all_fns", root = root, functions = "all", verbose = FALSE)
  expect_equal(all, normalizePath(file.path(root, "boosters", "packs", "all_fns", "all_fns.toml"), winslash = "/", mustWork = FALSE))
  expect_setequal(boosterpak:::read_toml_file(all)$functions, c("ni", "custom_helper"))

  none <- save_pack("no_fns", root = root, functions = "none", verbose = FALSE)
  expect_equal(none, normalizePath(file.path(root, "boosters", "packs", "no_fns.toml"), winslash = "/", mustWork = FALSE))
  expect_equal(boosterpak:::toml_string_array(boosterpak:::read_toml_file(none)$functions, "functions"), character())
  expect_false(dir.exists(boosterpak:::pack_sidecar_dir(none)))

  explicit <- save_pack("explicit_fns", root = root, functions = "custom_helper", verbose = FALSE)
  expect_equal(explicit, normalizePath(file.path(root, "boosters", "packs", "explicit_fns", "explicit_fns.toml"), winslash = "/", mustWork = FALSE))
  expect_equal(boosterpak:::read_toml_file(explicit)$functions, "custom_helper")
  expect_error(save_pack("missing_fns", root = root, functions = "missing", verbose = FALSE), "missing")
})

test_that("save_pack can fork one named pack and refuses overwrite by default", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  saved <- save_pack("core_fork", from = "core", root = root, verbose = FALSE)
  data <- boosterpak:::read_toml_file(saved)

  expect_equal(data$packages, c("pak", "renv"))
  expect_error(
    save_pack("core_fork", from = "core", root = root, verbose = FALSE),
    "already exists"
  )
  expect_no_error(save_pack("core_fork", from = "example", root = root, overwrite = TRUE, verbose = FALSE))
  expect_equal(boosterpak:::read_toml_file(saved)$packages, "cli")
})

test_that("save_pack writes to user scope", {
  withr::local_envvar(R_USER_CONFIG_DIR = withr::local_tempdir())
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  saved <- save_pack("user_baseline", scope = "user", root = root, verbose = FALSE)

  expect_true(file.exists(saved))
  expect_true(startsWith(saved, normalizePath(boosterpak:::user_packs_dir(), winslash = "/", mustWork = FALSE)))
  expect_true("user_baseline" %in% list_packs(root = root, scope = "user", verbose = FALSE)$name)
})

test_that("promote_pack and demote_pack copy between project and user scopes", {
  withr::local_envvar(R_USER_CONFIG_DIR = withr::local_tempdir())
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  save_pack("portable", from = "example", root = root, verbose = FALSE)

  user_path <- promote_pack("portable", root = root, verbose = FALSE)
  expect_true(file.exists(user_path))
  expect_equal(
    readLines(user_path, warn = FALSE),
    readLines(file.path(root, "boosters", "packs", "portable.toml"), warn = FALSE)
  )
  expect_error(promote_pack("portable", root = root, verbose = FALSE), "already exists")

  unlink(file.path(root, "boosters", "packs", "portable.toml"))
  project_path <- demote_pack("portable", root = root, verbose = FALSE)
  expect_true(file.exists(project_path))
  expect_equal(readLines(project_path, warn = FALSE), readLines(user_path, warn = FALSE))
})

test_that("promote_pack and demote_pack copy nested function packs", {
  withr::local_envvar(R_USER_CONFIG_DIR = withr::local_tempdir())
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  add_function("ni", root = root, verbose = FALSE)
  save_pack("portable_fns", root = root, verbose = FALSE)

  user_path <- promote_pack("portable_fns", root = root, verbose = FALSE)
  expect_equal(user_path, normalizePath(file.path(boosterpak:::user_packs_dir(), "portable_fns", "portable_fns.toml"), winslash = "/", mustWork = FALSE))
  expect_true(file.exists(boosterpak:::pack_function_file(user_path, "ni")))

  unlink(file.path(root, "boosters", "packs", "portable_fns"), recursive = TRUE)
  project_path <- demote_pack("portable_fns", root = root, verbose = FALSE)
  expect_equal(project_path, normalizePath(file.path(root, "boosters", "packs", "portable_fns", "portable_fns.toml"), winslash = "/", mustWork = FALSE))
  expect_true(file.exists(boosterpak:::pack_function_file(project_path, "ni")))
})
