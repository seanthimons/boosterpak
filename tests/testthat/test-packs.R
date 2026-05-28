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
  expect_equal(
    boosterpak:::resolve_pack("example"),
    c("fs", "here", "janitor", "rio", "tidyverse", "digest", "cli")
  )
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
