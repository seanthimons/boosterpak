test_that("rescue aborts when boosters.toml is absent", {
  root <- withr::local_tempdir()

  expect_error(
    boosterpak:::.rescue(root = root, verbose = FALSE),
    "repairs existing boosterpak projects"
  )
})

test_that("rescue dry run reports planned repairs without file changes", {
  withr::local_options(list(
    repos = c(CRAN = "https://cran.rstudio.com/"),
    renv.config.repos.override = NULL,
    renv.config.pak.enabled = FALSE,
    renv.config.ppm.enabled = FALSE,
    install.packages.compile.from.source = "interactive",
    install.packages.check.source = "yes",
    boosterpak.configure_repositories = TRUE,
    boosterpak.default_cran_mirrors = character(),
    boosterpak.configure_install_policy = TRUE
  ))
  withr::local_envvar(
    RENV_CONFIG_REPOS_OVERRIDE = NA,
    BOOSTERPAK_DEFAULT_CRAN_MIRRORS = NA,
    BOOSTERPAK_CONFIGURE_INSTALL_POLICY = NA
  )
  root <- withr::local_tempdir()
  boosterpak:::write_default_config(root)
  before <- list.files(root, all.files = TRUE, recursive = TRUE, no.. = TRUE)

  report <- boosterpak:::.rescue(root = root, dry_run = TRUE, verbose = FALSE)

  expect_true(report$dry_run)
  expect_true(any(grepl("would configure", report$actions)))
  expect_true(any(grepl("would repair \\.Rprofile", report$actions)))
  expect_true(any(grepl("would materialize built-in pack 'core'", report$actions, fixed = TRUE)))
  expect_true(any(grepl("would rewrite managed boosters/attach\\.R", report$actions)))
  expect_equal(
    list.files(root, all.files = TRUE, recursive = TRUE, no.. = TRUE),
    before
  )
  expect_false(file.exists(file.path(root, ".Rprofile")))
  expect_false(file.exists(file.path(root, "boosters", "packs", "core.toml")))
  expect_false(file.exists(file.path(root, "boosters", "attach.R")))
  expect_equal(getOption("repos")[["CRAN"]], "https://cran.rstudio.com/")
  expect_null(getOption("renv.config.repos.override"))
  expect_false(getOption("renv.config.pak.enabled"))
  expect_false(getOption("renv.config.ppm.enabled"))
  expect_equal(getOption("install.packages.compile.from.source"), "interactive")
  expect_equal(getOption("install.packages.check.source"), "yes")
})

test_that("rescue repairs legacy Rprofile hook around renv activation", {
  withr::local_options(list(
    repos = c(CRAN = "https://cran.rstudio.com"),
    renv.config.repos.override = NULL,
    renv.config.pak.enabled = FALSE,
    renv.config.ppm.enabled = FALSE,
    install.packages.compile.from.source = "interactive",
    install.packages.check.source = "yes",
    boosterpak.configure_repositories = TRUE,
    boosterpak.default_cran_mirrors = character(),
    boosterpak.configure_install_policy = TRUE
  ))
  withr::local_envvar(
    RENV_CONFIG_REPOS_OVERRIDE = NA,
    BOOSTERPAK_DEFAULT_CRAN_MIRRORS = NA,
    BOOSTERPAK_CONFIGURE_INSTALL_POLICY = NA
  )
  root <- withr::local_tempdir()
  boosterpak:::write_default_config(root)
  writeLines(
    c(
      "before <- TRUE",
      boosterpak:::legacy_rprofile_line(),
      "source(\"renv/activate.R\")",
      "after <- TRUE"
    ),
    file.path(root, ".Rprofile")
  )

  boosterpak:::.rescue(root = root, verbose = FALSE)

  lines <- readLines(file.path(root, ".Rprofile"), warn = FALSE)
  policy <- match(boosterpak:::rprofile_install_policy_marker(), lines)
  marker <- match(boosterpak:::rprofile_repository_marker(), lines)
  renv_line <- grep('source\\("renv/activate\\.R"\\)', lines)
  hook_line <- match(boosterpak:::rprofile_line(), lines)

  expect_false(boosterpak:::legacy_rprofile_line() %in% lines)
  expect_true(policy < marker)
  expect_true(marker < renv_line)
  expect_equal(lines[[policy + 1L]], "options(renv.config.pak.enabled = TRUE)")
  expect_equal(lines[[policy + 3L]], 'options(install.packages.compile.from.source = "never")')
  expect_match(lines[[marker + 1L]], "options\\(repos = c")
  expect_match(lines[[marker + 1L]], "packagemanager\\.posit\\.co")
  expect_match(lines[[marker + 2L]], "renv.config.repos.override")
  expect_equal(hook_line, renv_line + 1L)
  expect_true("before <- TRUE" %in% lines)
  expect_true("after <- TRUE" %in% lines)
})

test_that("rescue snapshots workflow packages with update true", {
  withr::local_options(boosterpak.configure_repositories = FALSE)
  root <- withr::local_tempdir()
  boosterpak:::write_default_config(root)
  calls <- character()
  snapshotted <- NULL
  snapshot_update <- NULL

  local_mocked_bindings(
    has_project_renv = function(root = ".") TRUE,
    is_project_renv_active = function(root = ".") FALSE,
    call_renv_load = function(root = ".") {
      calls <<- c(calls, "load")
    },
    missing_packages = function(packages, root = ".") character(),
    call_renv_snapshot = function(root = ".", packages = NULL, update = FALSE) {
      snapshotted <<- packages
      snapshot_update <<- update
    },
    .package = "boosterpak"
  )

  boosterpak:::.rescue(root = root, verbose = FALSE)

  expect_equal(calls, "load")
  expect_equal(snapshotted, c("renv", "pak", "boosterpak"))
  expect_true(snapshot_update)
})

test_that("rescue reapplies repositories after loading project renv", {
  withr::local_options(list(
    repos = c(CRAN = "https://cran.rstudio.com"),
    renv.config.repos.override = NULL,
    renv.config.pak.enabled = FALSE,
    renv.config.ppm.enabled = FALSE,
    install.packages.compile.from.source = "interactive",
    install.packages.check.source = "yes",
    boosterpak.configure_repositories = TRUE,
    boosterpak.default_cran_mirrors = character(),
    boosterpak.configure_install_policy = TRUE
  ))
  withr::local_envvar(
    RENV_CONFIG_REPOS_OVERRIDE = NA,
    BOOSTERPAK_DEFAULT_CRAN_MIRRORS = NA,
    BOOSTERPAK_CONFIGURE_INSTALL_POLICY = NA
  )
  root <- withr::local_tempdir()
  boosterpak:::write_default_config(root)
  repo_at_snapshot <- NULL
  override_at_snapshot <- NULL
  pak_at_snapshot <- NULL
  ppm_at_snapshot <- NULL
  compile_at_snapshot <- NULL

  local_mocked_bindings(
    has_project_renv = function(root = ".") TRUE,
    is_project_renv_active = function(root = ".") FALSE,
    call_renv_load = function(root = ".") {
      options(repos = c(CRAN = "https://cloud.r-project.org"))
      options(renv.config.repos.override = NULL)
      options(renv.config.pak.enabled = FALSE)
      options(renv.config.ppm.enabled = FALSE)
      options(install.packages.compile.from.source = "interactive")
      options(install.packages.check.source = "yes")
    },
    missing_packages = function(packages, root = ".") character(),
    call_renv_snapshot = function(root = ".", packages = NULL, update = FALSE) {
      repo_at_snapshot <<- getOption("repos")[["CRAN"]]
      override_at_snapshot <<- getOption("renv.config.repos.override")
      pak_at_snapshot <<- getOption("renv.config.pak.enabled")
      ppm_at_snapshot <<- getOption("renv.config.ppm.enabled")
      compile_at_snapshot <<- getOption("install.packages.compile.from.source")
    },
    .package = "boosterpak"
  )

  report <- boosterpak:::.rescue(root = root, verbose = FALSE)

  expect_equal(
    repo_at_snapshot,
    "https://packagemanager.posit.co/cran/latest"
  )
  expect_equal(
    override_at_snapshot,
    c(CRAN = "https://packagemanager.posit.co/cran/latest")
  )
  expect_true(pak_at_snapshot)
  expect_true(ppm_at_snapshot)
  expect_equal(compile_at_snapshot, "never")
  expect_true(any(grepl("reapplied", report$actions)))
})

test_that("rescue skips workflow repair when renv package is unavailable", {
  root <- withr::local_tempdir()
  report <- boosterpak:::.rescue_report(root, dry_run = FALSE)

  local_mocked_bindings(
    has_project_renv = function(root = ".") TRUE,
    .rescue_has_package = function(package) FALSE,
    .package = "boosterpak"
  )

  report <- boosterpak:::.rescue_workflow_packages(root, FALSE, report)

  expect_true(any(grepl("renv is unavailable", report$skipped)))
})

test_that("rescue reports workflow install and snapshot failures without aborting", {
  root <- withr::local_tempdir()
  report <- boosterpak:::.rescue_report(root, dry_run = FALSE)

  local_mocked_bindings(
    has_project_renv = function(root = ".") TRUE,
    is_project_renv_active = function(root = ".") TRUE,
    missing_packages = function(packages, root = ".") "pak",
    .rescue_install_workflow_packages = function(root, packages) {
      stop("install unavailable", call. = FALSE)
    },
    .package = "boosterpak"
  )

  report <- boosterpak:::.rescue_workflow_packages(root, FALSE, report)

  expect_true(any(grepl("workflow package install skipped", report$warnings)))
  expect_true(any(grepl("install unavailable", report$warnings)))

  report <- boosterpak:::.rescue_report(root, dry_run = FALSE)
  local_mocked_bindings(
    has_project_renv = function(root = ".") TRUE,
    is_project_renv_active = function(root = ".") TRUE,
    missing_packages = function(packages, root = ".") character(),
    call_renv_snapshot = function(root = ".", packages = NULL, update = FALSE) {
      stop("snapshot unavailable", call. = FALSE)
    },
    .package = "boosterpak"
  )

  report <- boosterpak:::.rescue_workflow_packages(root, FALSE, report)

  expect_true(any(grepl("workflow package snapshot skipped", report$warnings)))
  expect_true(any(grepl("snapshot unavailable", report$warnings)))
})

test_that("rescue materializes core pack and rewrites managed attach file", {
  withr::local_options(boosterpak.configure_repositories = FALSE)
  root <- withr::local_tempdir()
  boosterpak:::write_default_config(root)
  dir.create(file.path(root, "boosters"), recursive = TRUE, showWarnings = FALSE)
  writeLines("stale attach", file.path(root, "boosters", "attach.R"))

  boosterpak:::.rescue(root = root, verbose = FALSE)

  expect_true(file.exists(file.path(root, "boosters", "packs", "core.toml")))
  attach <- readLines(file.path(root, "boosters", "attach.R"), warn = FALSE)
  expect_equal(attach[[1]], "# Generated by boosterpak::write_attach(); do not edit by hand.")
  expect_false("stale attach" %in% attach)
})

test_that("rescue skips workflow repair when project renv is absent", {
  withr::local_options(boosterpak.configure_repositories = FALSE)
  root <- withr::local_tempdir()
  boosterpak:::write_default_config(root)

  report <- boosterpak:::.rescue(root = root, verbose = FALSE)

  expect_true(any(grepl("no project renv found", report$skipped)))
})

test_that("rescue reports attach rewrite failures without aborting", {
  withr::local_options(boosterpak.configure_repositories = FALSE)
  root <- withr::local_tempdir()
  boosterpak:::write_default_config(root)
  local_mocked_bindings(
    write_attach = function(root = ".", verbose = NULL) {
      stop("missing emergency dependency", call. = FALSE)
    },
    .package = "boosterpak"
  )

  report <- boosterpak:::.rescue(root = root, verbose = FALSE)

  expect_true(any(grepl("attach file rewrite skipped", report$warnings)))
  expect_true(any(grepl("missing emergency dependency", report$warnings)))
})

test_that("README documents bootstrap before hidden rescue when boosterpak is absent", {
  readme_path <- file.path(testthat::test_path(), "..", "..", "README.md")
  skip_if_not(
    file.exists(readme_path),
    "README.md is not available in installed package checks."
  )
  readme <- readLines(readme_path, warn = FALSE)

  expect_true(any(grepl('requireNamespace\\("renv"', readme)))
  expect_true(any(grepl("renv::load()", readme, fixed = TRUE)))
  expect_true(any(grepl('renv::install("seanthimons/boosterpak"', readme, fixed = TRUE)))
  expect_true(any(grepl("boosterpak:::.rescue()", readme, fixed = TRUE)))
})

test_that("rescue does not use interactive cli repository messages", {
  captured_verbose <- NULL
  local_mocked_bindings(
    configure_boosterpak_repositories = function(verbose = TRUE) {
      captured_verbose <<- verbose
      "repos"
    },
    boosterpak_repository_lines_for_session = function(changes = character()) {
      character()
    },
    .package = "boosterpak"
  )

  result <- boosterpak:::.rescue_repositories(dry_run = FALSE, verbose = TRUE)

  expect_false(captured_verbose)
  expect_equal(result$changes, "repos")
})
