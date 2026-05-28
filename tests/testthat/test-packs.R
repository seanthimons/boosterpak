test_that("built-in packs are discoverable", {
  packs <- list_packs(verbose = FALSE)
  expect_setequal(packs$name, c("core", "example", "github-example"))
  expect_true(all(c("name", "description", "scope", "path") %in% names(packs)))
})

test_that("packs resolve transitively", {
  expect_equal(boosterpak:::resolve_pack("example"), "cli")
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
  expect_equal(boosterpak:::resolve_config_packages(config, root), "pointblank")
  expect_equal(boosterpak:::resolve_config_install_specs(config, root), "rstudio/pointblank")
})
