test_that("rescue replaces a block from an earlier hook version with the current block", {
  old_block <- c(
    boosterpak:::rprofile_startup_begin_marker(),
    sprintf("try(%s)", boosterpak:::rprofile_line()),
    boosterpak:::rprofile_startup_end_marker()
  )
  lines <- c("before <- TRUE", 'source("renv/activate.R")', old_block, "after <- TRUE")

  planned <- boosterpak:::.rescue_rprofile_lines(lines)

  expect_true(planned$changed)
  expect_equal(
    planned$lines,
    c(
      "before <- TRUE",
      'source("renv/activate.R")',
      boosterpak:::rprofile_startup_block(),
      "after <- TRUE"
    )
  )
})

test_that("rescue adds the managed hook after existing post-activation repository lines", {
  reapply <- boosterpak:::rprofile_repository_reapply_lines()
  lines <- c("before <- TRUE", 'source("renv/activate.R")', reapply, "after <- TRUE")

  planned <- boosterpak:::.rescue_rprofile_lines(lines)

  expect_true(planned$changed)
  expect_equal(
    planned$lines,
    c(
      "before <- TRUE",
      'source("renv/activate.R")',
      reapply,
      boosterpak:::rprofile_startup_block(),
      "after <- TRUE"
    )
  )
})

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
  hook_line <- match(boosterpak:::rprofile_startup_begin_marker(), lines)

  expect_false(boosterpak:::legacy_rprofile_line() %in% lines)
  expect_true(policy < marker)
  expect_true(marker < renv_line)
  expect_equal(lines[[policy + 1L]], "options(renv.config.pak.enabled = TRUE)")
  expect_equal(lines[[policy + 3L]], 'options(install.packages.compile.from.source = "never")')
  expect_match(lines[[marker + 1L]], "options\\(repos = c")
  expect_match(lines[[marker + 1L]], "packagemanager\\.posit\\.co")
  expect_match(lines[[marker + 2L]], "renv.config.repos.override")
  expect_equal(lines[[renv_line + 1L]], boosterpak:::rprofile_repository_reapply_marker())
  expect_equal(hook_line, renv_line + 4L)
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
  # The README documents the exported upgrade_project(), not the internal helper.
  expect_true(any(grepl("boosterpak::upgrade_project()", readme, fixed = TRUE)))

  # Every R code block must parse, so the documented commands are valid R calls.
  opens <- grep("^``` ?r\\s*$", readme)
  closes <- grep("^```\\s*$", readme)
  expect_gt(length(opens), 0)
  parses <- vapply(opens, function(open) {
    close <- closes[closes > open][[1]]
    !inherits(
      tryCatch(parse(text = readme[(open + 1L):(close - 1L)]), error = identity),
      "error"
    )
  }, logical(1))
  expect_true(all(parses))
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

test_that("rescue replaces a v0.9.2 Linux binary line", {
  local_mocked_bindings(is_glibc_linux = function() TRUE)
  local_ppm_hosts()
  generic <- c(CRAN = "https://p3m.dev/cran/latest")
  withr::local_options(list(
    repos = generic,
    renv.config.repos.override = generic,
    boosterpak.configure_repositories = TRUE,
    boosterpak.configure_install_policy = FALSE
  ))
  withr::local_envvar(RENV_CONFIG_REPOS_OVERRIDE = NA)
  root <- withr::local_tempdir()
  boosterpak:::write_default_config(root)
  old_block <- boosterpak:::rprofile_repository_lines(generic)
  old_block[length(old_block)] <- v092_ppm_linux_line()
  writeLines(
    c("before <- TRUE", old_block, 'source("renv/activate.R")'),
    file.path(root, ".Rprofile")
  )

  boosterpak:::.rescue(root = root, verbose = FALSE)

  lines <- readLines(file.path(root, ".Rprofile"), warn = FALSE)
  expect_false(v092_ppm_linux_line() %in% lines)
  expect_true(boosterpak:::rprofile_ppm_linux_binary_line() %in% lines)
  expect_equal(sum(lines == boosterpak:::rprofile_repository_marker()), 1L)
  expect_true("before <- TRUE" %in% lines)
})

test_that("rescue dry run restores download options on Linux", {
  local_mocked_bindings(is_glibc_linux = function() TRUE)
  local_ppm_hosts()
  repos <- c(CRAN = "https://cran.rstudio.com/")

  for (extra in list(NULL, "-fsSL")) {
    withr::local_options(list(
      repos = repos,
      renv.config.repos.override = NULL,
      HTTPUserAgent = "custom",
      download.file.method = "curl",
      download.file.extra = extra,
      boosterpak.configure_repositories = TRUE,
      boosterpak.default_cran_mirrors = character(),
      boosterpak.configure_install_policy = FALSE
    ))
    withr::local_envvar(
      RENV_CONFIG_REPOS_OVERRIDE = NA,
      BOOSTERPAK_DEFAULT_CRAN_MIRRORS = NA
    )
    root <- withr::local_tempdir()
    boosterpak:::write_default_config(root)

    boosterpak:::.rescue(root = root, dry_run = TRUE, verbose = FALSE)

    expect_equal(getOption("repos"), repos)
    expect_null(getOption("renv.config.repos.override"))
    expect_equal(getOption("HTTPUserAgent"), "custom")
    expect_identical(getOption("download.file.extra"), extra)
  }
})

test_that("rescue applies the download header for real runs on Linux", {
  local_mocked_bindings(is_glibc_linux = function() TRUE)
  local_ppm_hosts()
  withr::local_options(list(
    repos = c(CRAN = "https://cran.rstudio.com/"),
    renv.config.repos.override = NULL,
    HTTPUserAgent = "custom",
    download.file.method = "wget",
    download.file.extra = NULL,
    boosterpak.configure_repositories = TRUE,
    boosterpak.default_cran_mirrors = character(),
    boosterpak.configure_install_policy = FALSE
  ))
  withr::local_envvar(
    RENV_CONFIG_REPOS_OVERRIDE = NA,
    BOOSTERPAK_DEFAULT_CRAN_MIRRORS = NA
  )
  root <- withr::local_tempdir()
  boosterpak:::write_default_config(root)

  boosterpak:::.rescue(root = root, verbose = FALSE)

  expect_match(getOption("download.file.extra"), "User-Agent: R \\(")
})

stale_boosters_version <- function(root, version = "0.6.0.9000") {
  path <- file.path(root, "boosters.toml")
  lines <- readLines(path, warn = FALSE)
  at <- grep("^boosters_version = ", lines)
  version_line <- sprintf('boosters_version = "%s"', version)
  if (length(at) == 0) {
    # init(rprofile = "no") records no version, so the stale record is added
    # under [project] to give the upgrade a record to refresh.
    project <- grep("^\\[project\\]", lines)
    lines <- append(lines, version_line, after = project[[1]])
  } else {
    lines[at] <- version_line
  }
  writeLines(lines, path)
}

recorded_version_line <- function(root) {
  lines <- readLines(file.path(root, "boosters.toml"), warn = FALSE)
  lines[grep("^boosters_version = ", lines)]
}

test_that("upgrade records the installed boosterpak version after a clean run", {
  withr::local_options(list(
    boosterpak.configure_repositories = FALSE,
    boosterpak.configure_install_policy = FALSE
  ))
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  stale_boosters_version(root)
  local_mocked_bindings(package_version_string = function() "99.0.0", .package = "boosterpak")

  report <- upgrade_project(root, verbose = FALSE)

  expect_equal(recorded_version_line(root), 'boosters_version = "99.0.0"')
  expect_false(boosterpak:::project_needs_upgrade(root))
  expect_true(any(grepl("boosters.toml$", report$paths)))
  expect_true(any(grepl("recorded the installed boosterpak version", report$actions, fixed = TRUE)))
})

test_that("upgrade dry run leaves boosters_version untouched and lists boosters.toml", {
  withr::local_options(list(
    boosterpak.configure_repositories = FALSE,
    boosterpak.configure_install_policy = FALSE
  ))
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  stale_boosters_version(root)
  path <- file.path(root, "boosters.toml")
  before <- readLines(path, warn = FALSE)
  local_mocked_bindings(package_version_string = function() "99.0.0", .package = "boosterpak")

  report <- upgrade_project(root, dry_run = TRUE, verbose = FALSE)

  expect_equal(readLines(path, warn = FALSE), before)
  expect_equal(recorded_version_line(root), 'boosters_version = "0.6.0.9000"')
  expect_true(any(grepl("boosters.toml$", report$paths)))
  expect_true(any(grepl("would record the installed boosterpak version", report$actions, fixed = TRUE)))
})

test_that("upgrade does not record the version when it finishes with warnings", {
  withr::local_options(list(
    boosterpak.configure_repositories = FALSE,
    boosterpak.configure_install_policy = FALSE
  ))
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  stale_boosters_version(root)
  path <- file.path(root, "boosters.toml")
  lines <- readLines(path, warn = FALSE)
  writeLines(sub("^enabled = true$", "enabled = \"yes\"", lines), path)
  local_mocked_bindings(package_version_string = function() "99.0.0", .package = "boosterpak")

  report <- upgrade_project(root, verbose = FALSE)

  expect_true(length(report$warnings) > 0)
  expect_true(any(grepl("boosters_version not recorded", report$skipped, fixed = TRUE)))
  expect_equal(recorded_version_line(root), 'boosters_version = "0.6.0.9000"')
})

test_that("upgrade does not record the version when the upgrade is aborted", {
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  stale_boosters_version(root)
  local_mocked_bindings(package_version_string = function() "99.0.0", .package = "boosterpak")
  local_mocked_bindings(
    .rescue_repositories = function(dry_run, verbose) stop("simulated abort", call. = FALSE),
    .package = "boosterpak"
  )

  expect_error(upgrade_project(root, verbose = FALSE), "simulated abort")
  expect_equal(recorded_version_line(root), 'boosters_version = "0.6.0.9000"')
})

test_that("rescue does not record boosters_version when workflow repair skips for renv", {
  withr::local_options(list(
    boosterpak.configure_repositories = FALSE,
    boosterpak.configure_install_policy = FALSE
  ))
  root <- withr::local_tempdir()
  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)
  stale_boosters_version(root)
  local_mocked_bindings(
    has_project_renv = function(root = ".") TRUE,
    .rescue_has_package = function(package) FALSE,
    .package = "boosterpak"
  )

  report <- boosterpak:::.rescue_report(root, dry_run = FALSE)
  report <- boosterpak:::.rescue_workflow_packages(root, FALSE, report)
  report <- boosterpak:::.rescue_record_version(root, FALSE, report)

  expect_true(any(grepl("renv is unavailable", report$warnings)))
  expect_true(any(grepl("boosters_version not recorded", report$skipped, fixed = TRUE)))
  expect_equal(recorded_version_line(root), 'boosters_version = "0.6.0.9000"')
})

test_that("upgrade reports renv/activate.R changes made while loading renv", {
  withr::local_options(list(
    boosterpak.configure_repositories = FALSE,
    boosterpak.configure_install_policy = FALSE
  ))
  root <- withr::local_tempdir()
  boosterpak:::write_default_config(root)
  dir.create(file.path(root, "renv"), showWarnings = FALSE)
  writeLines("# before load", file.path(root, "renv", "activate.R"))

  local_mocked_bindings(
    has_project_renv = function(root = ".") TRUE,
    .rescue_has_package = function(package) TRUE,
    is_project_renv_active = function(root = ".") FALSE,
    call_renv_load = function(root = ".") {
      writeLines("# rewritten by load", file.path(root, "renv", "activate.R"))
    },
    missing_packages = function(packages, root = ".", ...) character(),
    ensure_dependency_closure = function(packages, root = ".", library = "renv") {
      invisible(character())
    },
    call_renv_snapshot = function(root = ".", packages = NULL, update = FALSE) invisible(TRUE),
    .package = "boosterpak"
  )

  report <- boosterpak:::.rescue(root = root, verbose = FALSE)

  expect_true(any(grepl("renv/activate.R$", report$paths)))
  expect_true(any(grepl("updated renv/activate.R", report$actions, fixed = TRUE)))
})

test_that("rescue messages name upgrade_project rather than the internal function", {
  withr::local_options(list(
    boosterpak.configure_repositories = FALSE,
    boosterpak.configure_install_policy = FALSE
  ))
  root <- withr::local_tempdir()
  expect_error(
    upgrade_project(root, verbose = FALSE),
    "upgrade_project\\(\\) repairs existing boosterpak projects"
  )

  root <- withr::local_tempdir()
  boosterpak:::write_default_config(root)
  messages <- testthat::capture_messages(
    upgrade_project(root, dry_run = TRUE, verbose = TRUE)
  )
  expect_true(any(grepl("boosterpak upgrade dry run", messages, fixed = TRUE)))
  expect_false(any(grepl("rescue", messages, fixed = TRUE)))
})
