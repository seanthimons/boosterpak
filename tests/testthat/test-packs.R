test_that("built-in packs are discoverable", {
  packs <- list_packs(verbose = FALSE)
  expect_setequal(packs$name, c("core", "example", "github-example"))
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
    c("fs", "here", "janitor", "rio", "tidyverse", "digest")
  )
  expect_equal(boosterpak:::resolve_pack("github-example"), "ComptoxR")
  expect_equal(
    boosterpak:::resolve_pack_sources("github-example"),
    c(ComptoxR = "seanthimons/ComptoxR")
  )
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
  lines <- readLines(path, warn = FALSE)
  lines[lines == "declared = []"][1] <- 'declared = ["rstudio/pointblank"]'
  writeLines(lines, path)

  config <- boosterpak:::read_config(root)

  expect_true("pointblank" %in% boosterpak:::resolve_config_packages(config, root))
  expect_true("rstudio/pointblank" %in% boosterpak:::resolve_config_install_specs(config, root))
})

test_that("unknown pack errors include suggestion and grouped availability", {
  expect_error(
    boosterpak:::load_pack("exampel"),
    regexp = "Did you mean.+example.+Built-in.+core.+User:.+Project:",
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
