fake_installed_db <- function(versions, base = character()) {
  packages <- names(versions)
  db <- matrix(
    NA_character_,
    nrow = length(packages),
    ncol = 6,
    dimnames = list(
      packages,
      c("Package", "Version", "Priority", "Depends", "Imports", "LinkingTo")
    )
  )
  db[, "Package"] <- packages
  db[, "Version"] <- unname(versions)
  db[intersect(packages, base), "Priority"] <- "base"
  db["boosterpak", "Imports"] <- "cli, pak, renv, utils"
  db
}

write_upgrade_lock <- function(root) {
  lock <- list(
    R = list(
      Version = "0.0.1",
      Repositories = list(list(Name = "CRAN", URL = "https://cran.rstudio.com/"))
    ),
    Packages = list(
      renv = list(Package = "renv", Version = "1.2.3", Source = "Repository"),
      pak = list(Package = "pak", Version = "0.9.5", Source = "Repository"),
      boosterpak = list(Package = "boosterpak", Version = "0.9.2", Source = "Repository"),
      cli = list(Package = "cli", Version = "3.6.5", Source = "Repository"),
      utils = list(Package = "utils", Version = "4.0.0", Source = "Repository")
    )
  )
  jsonlite::write_json(lock, file.path(root, "renv.lock"), auto_unbox = TRUE, pretty = TRUE)
}

upgrade_installed_versions <- function() {
  c(renv = "1.3.1", pak = "0.11.1", boosterpak = "0.9.2", cli = "3.6.6", utils = "4.6.1")
}

test_that("upgrade_project dry run previews lockfile changes without touching files", {
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
  write_upgrade_lock(root)
  dir.create(file.path(root, "renv"), showWarnings = FALSE)
  writeLines("# old activate", file.path(root, "renv", "activate.R"))
  lock_before <- readLines(file.path(root, "renv.lock"), warn = FALSE)
  before <- list.files(root, all.files = TRUE, recursive = TRUE, no.. = TRUE)

  local_mocked_bindings(
    has_project_renv = function(root = ".") TRUE,
    .rescue_has_package = function(package) TRUE,
    is_project_renv_active = function(root = ".") TRUE,
    missing_packages = function(packages, root = ".") character(),
    installed_package_db = function(root = ".", library = "renv") {
      fake_installed_db(upgrade_installed_versions(), base = "utils")
    },
    .package = "boosterpak"
  )

  report <- upgrade_project(root, dry_run = TRUE, verbose = FALSE)

  expect_true(report$dry_run)
  expect_true(any(grepl("R version: 0.0.1 -> ", report$preview, fixed = TRUE)))
  expect_true(any(grepl(
    "CRAN repository: https://cran.rstudio.com/ -> https://packagemanager.posit.co/cran/latest",
    report$preview,
    fixed = TRUE
  )))
  expect_true(any(grepl("  renv: 1.2.3 -> 1.3.1", report$preview, fixed = TRUE)))
  expect_true(any(grepl("  pak: 0.9.5 -> 0.11.1", report$preview, fixed = TRUE)))
  expect_false(any(grepl("boosterpak:", report$preview, fixed = TRUE)))
  expect_true(any(grepl("  cli: 3.6.5 -> 3.6.6", report$preview, fixed = TRUE)))
  expect_false(any(grepl("utils", report$preview, fixed = TRUE)))
  expect_true(any(grepl("would snapshot workflow packages", report$actions, fixed = TRUE)))
  expect_true(any(grepl("renv/activate.R", report$paths, fixed = TRUE)))
  expect_true(any(grepl("renv.lock", report$paths, fixed = TRUE)))
  expect_equal(
    list.files(root, all.files = TRUE, recursive = TRUE, no.. = TRUE),
    before
  )
  expect_equal(readLines(file.path(root, "renv.lock"), warn = FALSE), lock_before)
  expect_equal(readLines(file.path(root, "renv", "activate.R"), warn = FALSE), "# old activate")
})

test_that("upgrade_project dry run prints the preview and touched files by default", {
  withr::local_options(list(
    repos = c(CRAN = "https://cran.rstudio.com/"),
    boosterpak.configure_repositories = FALSE,
    boosterpak.configure_install_policy = FALSE
  ))
  root <- withr::local_tempdir()
  boosterpak:::write_default_config(root)
  write_upgrade_lock(root)

  local_mocked_bindings(
    has_project_renv = function(root = ".") TRUE,
    .rescue_has_package = function(package) TRUE,
    is_project_renv_active = function(root = ".") TRUE,
    missing_packages = function(packages, root = ".") character(),
    installed_package_db = function(root = ".", library = "renv") {
      fake_installed_db(upgrade_installed_versions(), base = "utils")
    },
    .package = "boosterpak"
  )

  expect_message(upgrade_project(root, dry_run = TRUE), "Lockfile preview")
  expect_message(upgrade_project(root, dry_run = TRUE), "Files a real run would touch")
  expect_message(upgrade_project(root, dry_run = TRUE), "git diff")
})

test_that("upgrade_project dry run reports snapshot = FALSE without a lockfile preview", {
  withr::local_options(list(
    boosterpak.configure_repositories = FALSE,
    boosterpak.configure_install_policy = FALSE
  ))
  root <- withr::local_tempdir()
  boosterpak:::write_default_config(root)
  write_upgrade_lock(root)

  local_mocked_bindings(
    has_project_renv = function(root = ".") TRUE,
    .rescue_has_package = function(package) TRUE,
    is_project_renv_active = function(root = ".") TRUE,
    missing_packages = function(packages, root = ".") character(),
    installed_package_db = function(root = ".", library = "renv") {
      stop("installed packages must not be read when snapshot = FALSE")
    },
    .package = "boosterpak"
  )

  report <- upgrade_project(root, dry_run = TRUE, snapshot = FALSE, verbose = FALSE)

  expect_true(any(grepl("snapshot = FALSE", report$skipped, fixed = TRUE)))
  expect_length(report$preview, 0)
  expect_false(any(grepl("renv.lock", report$paths, fixed = TRUE)))
})

test_that("upgrade_project snapshot = FALSE leaves renv.lock unwritten", {
  withr::local_options(list(
    boosterpak.configure_repositories = FALSE,
    boosterpak.configure_install_policy = FALSE
  ))
  root <- withr::local_tempdir()
  boosterpak:::write_default_config(root)
  snapshot_calls <- 0L
  ensured <- NULL

  local_mocked_bindings(
    has_project_renv = function(root = ".") TRUE,
    .rescue_has_package = function(package) TRUE,
    is_project_renv_active = function(root = ".") TRUE,
    missing_packages = function(packages, root = ".") character(),
    ensure_dependency_closure = function(packages, root = ".", library = "renv") {
      ensured <<- packages
      invisible(character())
    },
    call_renv_snapshot = function(root = ".", packages = NULL, update = FALSE) {
      snapshot_calls <<- snapshot_calls + 1L
    },
    .package = "boosterpak"
  )

  report <- upgrade_project(root, snapshot = FALSE, verbose = FALSE)

  expect_equal(snapshot_calls, 0L)
  expect_equal(ensured, c("renv", "pak", "boosterpak"))
  expect_true(any(grepl("renv.lock not written: snapshot = FALSE", report$skipped, fixed = TRUE)))
  expect_false(any(grepl("renv.lock", report$paths, fixed = TRUE)))
})

test_that("upgrade_project reports renv.lock and activate.R as touched after a snapshot", {
  withr::local_options(list(
    boosterpak.configure_repositories = FALSE,
    boosterpak.configure_install_policy = FALSE
  ))
  root <- withr::local_tempdir()
  boosterpak:::write_default_config(root)
  dir.create(file.path(root, "renv"), showWarnings = FALSE)
  writeLines("# old activate", file.path(root, "renv", "activate.R"))

  local_mocked_bindings(
    has_project_renv = function(root = ".") TRUE,
    .rescue_has_package = function(package) TRUE,
    is_project_renv_active = function(root = ".") TRUE,
    missing_packages = function(packages, root = ".") character(),
    ensure_dependency_closure = function(packages, root = ".", library = "renv") {
      invisible(character())
    },
    call_renv_snapshot = function(root = ".", packages = NULL, update = FALSE) {
      writeLines("# new activate", file.path(root, "renv", "activate.R"))
    },
    .package = "boosterpak"
  )

  report <- upgrade_project(root, verbose = FALSE)

  expect_true(any(grepl("renv.lock", report$paths, fixed = TRUE)))
  expect_true(any(grepl("renv/activate.R", report$paths, fixed = TRUE)))
  expect_true(any(grepl("updated renv/activate.R", report$actions, fixed = TRUE)))
})

test_that("upgrade_project validates snapshot", {
  root <- withr::local_tempdir()

  expect_error(
    upgrade_project(root, snapshot = NA, verbose = FALSE),
    "snapshot must be TRUE or FALSE"
  )
  expect_error(
    upgrade_project(root, snapshot = "no", verbose = FALSE),
    "snapshot must be TRUE or FALSE"
  )
})

test_that("upgrade_project aborts without boosters.toml and does not write", {
  root <- withr::local_tempdir()

  expect_error(upgrade_project(root, verbose = FALSE), "repairs existing boosterpak projects")
  expect_length(list.files(root, all.files = TRUE, no.. = TRUE), 0)
})

test_that("lockfile preview helpers read both lockfile repository layouts", {
  expect_equal(
    boosterpak:::lockfile_cran_url(list(R = list(Repositories = list(
      list(Name = "CRAN", URL = "https://cran.rstudio.com"),
      list(Name = "BioCsoft", URL = "https://bioc.example")
    )))),
    "https://cran.rstudio.com"
  )
  expect_equal(
    boosterpak:::lockfile_cran_url(list(R = list(Repositories = list(CRAN = "https://legacy.example")))),
    "https://legacy.example"
  )
  expect_true(is.na(boosterpak:::lockfile_cran_url(list())))
  expect_equal(
    boosterpak:::lockfile_change_line("R version", "4.5.1", "4.5.1"),
    "R version: 4.5.1 (unchanged)"
  )
  expect_equal(
    boosterpak:::lockfile_change_line("R version", NA_character_, "4.6.1"),
    "R version: (none) -> 4.6.1"
  )
  expect_equal(
    boosterpak:::lockfile_package_change("pak", "0.9.5", NA_character_),
    "pak: 0.9.5 -> (will be installed)"
  )
  expect_equal(
    boosterpak:::lockfile_package_change("pak", NA_character_, "0.11.1"),
    "pak: not in lockfile -> 0.11.1"
  )
})

test_that("installed hard closure skips base packages and keeps missing dependencies", {
  db <- fake_installed_db(
    c(boosterpak = "0.9.2", cli = "3.6.6", renv = "1.3.1", utils = "4.6.1"),
    base = "utils"
  )

  closure <- boosterpak:::installed_hard_closure(c("renv", "boosterpak", "missingpkg"), db)

  # pak is a dependency that is not installed in this fake library; it is kept
  # so the preview can report it.
  expect_setequal(closure, c("renv", "boosterpak", "cli", "pak", "missingpkg"))
})

test_that("rate-limit detection matches GitHub limit wording only", {
  rate_limited <- c(
    "GitHub API rate limit exceeded for 203.0.113.7",
    "API rate limit exceeded",
    "GitHub: HTTP 429 Too Many Requests",
    "GET https://api.github.com/repos/x/y: HTTP 403 Forbidden on GitHub"
  )
  for (message in rate_limited) {
    expect_true(boosterpak:::is_github_rate_limit_error(message), info = message)
  }

  not_rate_limited <- c(
    "package 'nopkg' was not found",
    "HTTP 403 Forbidden",
    "network unreachable",
    "CRAN mirror rate limit reached, try again later",
    ""
  )
  for (message in not_rate_limited) {
    expect_false(boosterpak:::is_github_rate_limit_error(message), info = message)
  }
})

test_that("a bare GitHub 403 is hedged rather than stated as a rate limit", {
  withr::local_envvar(GITHUB_PAT = NA, GITHUB_TOKEN = NA)

  message <- tryCatch(
    boosterpak:::rethrow_github_rate_limit(
      simpleError("GET https://api.github.com/repos/x/y: HTTP 403 Forbidden")
    ),
    error = conditionMessage
  )

  expect_match(message, "GitHub may have rate-limited or refused the request.", fixed = TRUE)
  expect_false(grepl("GitHub rate limit reached.", message, fixed = TRUE))
  expect_match(message, "GITHUB_PAT", fixed = TRUE)
})

test_that("rate-limit detection reads the parent conditions", {
  withr::local_envvar(GITHUB_PAT = NA, GITHUB_TOKEN = NA)
  # A plain condition, unlike rlang_error, does not fold the parent text into
  # conditionMessage(), so the rate-limit text is reachable only through $parent.
  wrapped <- structure(
    class = c("error", "condition"),
    list(
      message = "Failed to install workflow packages.",
      call = NULL,
      parent = simpleError("GitHub API rate limit exceeded for 203.0.113.7")
    )
  )
  expect_equal(conditionMessage(wrapped), "Failed to install workflow packages.")
  expect_equal(
    boosterpak:::condition_chain_messages(wrapped),
    c(
      "Failed to install workflow packages.",
      "GitHub API rate limit exceeded for 203.0.113.7"
    )
  )

  message <- tryCatch(
    boosterpak:::rethrow_github_rate_limit(wrapped),
    error = conditionMessage
  )

  expect_match(message, "Failed to install workflow packages.", fixed = TRUE)
  expect_match(message, "GitHub rate limit reached.", fixed = TRUE)
  expect_true(boosterpak:::is_github_rate_limit_error(
    boosterpak:::condition_chain_messages(wrapped)[[2]]
  ))
})

test_that("the hint gives PowerShell and POSIX token commands", {
  withr::local_envvar(GITHUB_PAT = NA, GITHUB_TOKEN = NA)

  hint <- boosterpak:::github_rate_limit_hint("rate limit")

  expect_match(hint, "export GITHUB_PAT=$(gh auth token)", fixed = TRUE)
  expect_match(hint, "$env:GITHUB_PAT = gh auth token", fixed = TRUE)
})

test_that("rate-limit hint never prints a token value", {
  secret <- "ghp_TESTONLYSECRETVALUE123"
  withr::local_envvar(GITHUB_PAT = secret, GITHUB_TOKEN = NA)

  message <- tryCatch(
    boosterpak:::rethrow_github_rate_limit(simpleError("API rate limit exceeded")),
    error = conditionMessage
  )

  expect_match(message, "API rate limit exceeded", fixed = TRUE)
  expect_match(message, "GitHub rate limit reached.", fixed = TRUE)
  expect_match(message, "already set", fixed = TRUE)
  expect_match(message, "gh auth token", fixed = TRUE)
  expect_false(grepl(secret, message, fixed = TRUE))
})

test_that("rate-limit hint reports when no token is set", {
  withr::local_envvar(GITHUB_PAT = NA, GITHUB_TOKEN = NA)

  message <- tryCatch(
    boosterpak:::rethrow_github_rate_limit(simpleError("HTTP 429 Too Many Requests from GitHub")),
    error = conditionMessage
  )

  expect_match(message, "No GitHub token is set", fixed = TRUE)
})

test_that("rate-limit rethrow passes other errors through and does not repeat the hint", {
  withr::local_envvar(GITHUB_PAT = NA, GITHUB_TOKEN = NA)

  other <- tryCatch(
    boosterpak:::rethrow_github_rate_limit(simpleError("network unreachable")),
    error = conditionMessage
  )
  expect_equal(other, "network unreachable")

  once <- tryCatch(
    boosterpak:::rethrow_github_rate_limit(simpleError("API rate limit exceeded")),
    error = conditionMessage
  )
  twice <- tryCatch(
    boosterpak:::rethrow_github_rate_limit(simpleError(once)),
    error = conditionMessage
  )
  expect_equal(twice, once)
  expect_equal(lengths(regmatches(twice, gregexpr("GitHub rate limit reached.", twice, fixed = TRUE))), 1L)
})

test_that("install_via adds the rate-limit hint and keeps other failures unchanged", {
  withr::local_envvar(GITHUB_PAT = NA, GITHUB_TOKEN = NA)
  root <- withr::local_tempdir()
  installed_specs <- NULL

  local_mocked_bindings(
    configure_boosterpak_install_policy = function(verbose = TRUE) invisible(character()),
    package_library = function(root = ".", library = "renv") file.path(root, "lib"),
    pak_install_packages = function(packages, lib) {
      installed_specs <<- packages
      stop("GitHub API rate limit exceeded", call. = FALSE)
    },
    .package = "boosterpak"
  )

  expect_error(
    boosterpak:::install_via("seanthimons/boosterpak", root),
    "GitHub rate limit reached"
  )
  expect_equal(installed_specs, "seanthimons/boosterpak")

  local_mocked_bindings(
    pak_install_packages = function(packages, lib) stop("network unreachable", call. = FALSE),
    .package = "boosterpak"
  )
  error <- tryCatch(
    boosterpak:::install_via("cli", root),
    error = conditionMessage
  )
  expect_equal(error, "network unreachable")
})

test_that("workflow install reports the rate-limit hint in the rescue warnings", {
  withr::local_envvar(GITHUB_PAT = NA, GITHUB_TOKEN = NA)
  withr::local_options(list(
    boosterpak.configure_repositories = FALSE,
    boosterpak.configure_install_policy = FALSE
  ))
  root <- withr::local_tempdir()
  boosterpak:::write_default_config(root)
  report <- boosterpak:::.rescue_report(root, dry_run = FALSE)

  local_mocked_bindings(
    has_project_renv = function(root = ".") TRUE,
    .rescue_has_package = function(package) TRUE,
    is_project_renv_active = function(root = ".") TRUE,
    missing_packages = function(packages, root = ".") "boosterpak",
    hydrate_via_renv = function(packages, root = ".") invisible(packages),
    self_install_spec = function(desc = NULL) "seanthimons/boosterpak",
    configure_boosterpak_install_policy = function(verbose = TRUE) invisible(character()),
    pak_install_packages = function(packages, lib) {
      stop("GitHub API rate limit exceeded for 203.0.113.7", call. = FALSE)
    },
    .package = "boosterpak"
  )

  report <- boosterpak:::.rescue_workflow_packages(root, FALSE, report)

  expect_true(any(grepl("workflow package install skipped", report$warnings, fixed = TRUE)))
  expect_true(any(grepl("GitHub API rate limit exceeded", report$warnings, fixed = TRUE)))
  expect_true(any(grepl("GitHub rate limit reached.", report$warnings, fixed = TRUE)))
})

test_that("lockfile preview shows the generic Package Manager CRAN URL for manylinux repos", {
  root <- withr::local_tempdir()
  write_upgrade_lock(root)
  manylinux <- c(CRAN = "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28/latest")

  local_mocked_bindings(
    installed_package_db = function(root = ".", library = "renv") {
      fake_installed_db(upgrade_installed_versions(), base = "utils")
    },
    .package = "boosterpak"
  )

  preview <- workflow_lockfile_preview(
    root,
    c("renv", "pak", "boosterpak"),
    repos = manylinux
  )

  expect_true(any(grepl(
    "CRAN repository: https://cran.rstudio.com/ -> https://packagemanager.posit.co/cran/latest",
    preview$lines,
    fixed = TRUE
  )))
  expect_false(any(grepl("manylinux", preview$lines, fixed = TRUE)))
})

test_that("call_renv_snapshot keeps the session repos while renv strips the platform segment", {
  root <- withr::local_tempdir()
  manylinux <- c(CRAN = "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28/latest")
  withr::local_options(list(repos = manylinux))
  captured <- NULL

  local_mocked_bindings(
    renv_ppm_handling_enabled = function() TRUE,
    .package = "boosterpak"
  )
  local_mocked_bindings(
    snapshot = function(...) {
      captured <<- list(...)
      invisible(NULL)
    },
    .package = "renv"
  )

  call_renv_snapshot(root, packages = c("renv", "pak"), update = TRUE)

  # Passing the generic URL here makes renv record the manylinux URL as each
  # package's repository, so the session value must go through unchanged.
  expect_equal(captured$repos, manylinux)
  expect_equal(captured$packages, c("renv", "pak"))
  expect_true(captured$update)
  expect_identical(getOption("repos"), manylinux)
})

test_that("call_renv_snapshot passes the generic URL when renv Package Manager handling is off", {
  root <- withr::local_tempdir()
  withr::local_options(list(
    repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28/latest")
  ))
  captured <- NULL

  local_mocked_bindings(
    renv_ppm_handling_enabled = function() FALSE,
    .package = "boosterpak"
  )
  local_mocked_bindings(
    snapshot = function(...) {
      captured <<- list(...)
      invisible(NULL)
    },
    .package = "renv"
  )

  call_renv_snapshot(root)

  expect_equal(
    captured$repos,
    c(CRAN = "https://packagemanager.posit.co/cran/latest")
  )
  expect_identical(
    getOption("repos"),
    c(CRAN = "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28/latest")
  )
})

test_that("renv_ppm_handling_enabled reads renv's own setting and fails closed", {
  skip_if_not_installed("renv")
  withr::local_options(list(renv.config.ppm.enabled = FALSE))
  withr::local_envvar(RENV_PPM_ENABLED = NA, RENV_CONFIG_PPM_ENABLED = NA)

  expect_false(renv_ppm_handling_enabled())

  # With the setting on, only the mocked lookup decides the result: a lookup
  # that works gives TRUE, one that fails gives FALSE.
  withr::local_options(list(renv.config.ppm.enabled = TRUE))
  local_mocked_bindings(
    getFromNamespace = function(...) function() TRUE,
    .package = "utils"
  )
  expect_true(renv_ppm_handling_enabled())

  local_mocked_bindings(
    getFromNamespace = function(...) stop("renv changed its internals"),
    .package = "utils"
  )
  expect_false(renv_ppm_handling_enabled())
})
