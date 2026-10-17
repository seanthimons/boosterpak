test_that("init configures PPM repos from R default CRAN placeholder", {
  withr::local_options(list(
    repos = c(CRAN = "@CRAN@", Internal = "https://example.test/repo"),
    renv.config.repos.override = NULL,
    boosterpak.configure_repositories = TRUE
  ))
  withr::local_envvar(RENV_CONFIG_REPOS_OVERRIDE = NA)
  root <- withr::local_tempdir()

  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  expect_equal(
    getOption("repos")[["CRAN"]],
    "https://packagemanager.posit.co/cran/latest"
  )
  expect_equal(
    getOption("repos")[["Internal"]],
    "https://example.test/repo"
  )
  expect_equal(
    getOption("renv.config.repos.override"),
    c(
      CRAN = "https://packagemanager.posit.co/cran/latest",
      Internal = "https://example.test/repo"
    )
  )
  expect_false(file.exists(file.path(root, ".Rprofile")))
})

test_that("init configures PPM repos from known CRAN mirror", {
  withr::local_options(list(
    repos = c(CRAN = "https://cran.rstudio.com"),
    renv.config.repos.override = NULL,
    boosterpak.configure_repositories = TRUE,
    boosterpak.default_cran_mirrors = character()
  ))
  withr::local_envvar(
    RENV_CONFIG_REPOS_OVERRIDE = NA,
    BOOSTERPAK_DEFAULT_CRAN_MIRRORS = NA
  )
  root <- withr::local_tempdir()

  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  expect_equal(
    getOption("repos")[["CRAN"]],
    "https://packagemanager.posit.co/cran/latest"
  )
  expect_equal(
    getOption("renv.config.repos.override"),
    c(CRAN = "https://packagemanager.posit.co/cran/latest")
  )
})

test_that("init normalizes trailing slash and host case for CRAN mirrors", {
  withr::local_options(list(
    repos = c(CRAN = "HTTPS://CRAN.RSTUDIO.COM/"),
    renv.config.repos.override = NULL,
    boosterpak.configure_repositories = TRUE,
    boosterpak.default_cran_mirrors = character()
  ))
  withr::local_envvar(
    RENV_CONFIG_REPOS_OVERRIDE = NA,
    BOOSTERPAK_DEFAULT_CRAN_MIRRORS = NA
  )
  root <- withr::local_tempdir()

  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  expect_equal(
    getOption("repos")[["CRAN"]],
    "https://packagemanager.posit.co/cran/latest"
  )
  expect_equal(
    getOption("renv.config.repos.override"),
    c(CRAN = "https://packagemanager.posit.co/cran/latest")
  )
})

test_that("init preserves extra repos while upgrading CRAN mirror", {
  withr::local_options(list(
    repos = c(
      CRAN = "https://cloud.r-project.org",
      Internal = "https://example.test/repo"
    ),
    renv.config.repos.override = NULL,
    boosterpak.configure_repositories = TRUE,
    boosterpak.default_cran_mirrors = character()
  ))
  withr::local_envvar(
    RENV_CONFIG_REPOS_OVERRIDE = NA,
    BOOSTERPAK_DEFAULT_CRAN_MIRRORS = NA
  )
  root <- withr::local_tempdir()

  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  expect_equal(
    getOption("repos")[["CRAN"]],
    "https://packagemanager.posit.co/cran/latest"
  )
  expect_equal(
    getOption("repos")[["Internal"]],
    "https://example.test/repo"
  )
  expect_equal(
    getOption("renv.config.repos.override"),
    c(
      CRAN = "https://packagemanager.posit.co/cran/latest",
      Internal = "https://example.test/repo"
    )
  )
})

test_that("init persists PPM repository setup before renv activation", {
  withr::local_options(list(
    repos = c(CRAN = "@CRAN@"),
    renv.config.repos.override = NULL,
    boosterpak.configure_repositories = TRUE,
    boosterpak.configure_install_policy = FALSE
  ))
  withr::local_envvar(RENV_CONFIG_REPOS_OVERRIDE = NA)
  root <- withr::local_tempdir()
  writeLines(
    c("before <- TRUE", "source(\"renv/activate.R\")", "after <- TRUE"),
    file.path(root, ".Rprofile")
  )

  init(root = root, renv = "no", rprofile = "yes", verbose = FALSE)

  lines <- readLines(file.path(root, ".Rprofile"), warn = FALSE)
  marker <- match(boosterpak:::rprofile_repository_marker(), lines)
  renv_line <- grep('source\\("renv/activate\\.R"\\)', lines)
  hook_line <- match(boosterpak:::rprofile_startup_begin_marker(), lines)

  expect_equal(marker, renv_line - 4L)
  expect_equal(
    lines[[marker + 1L]],
    'options(repos = c(CRAN = "https://packagemanager.posit.co/cran/latest"))'
  )
  expect_equal(
    lines[[marker + 2L]],
    'options(renv.config.repos.override = c(CRAN = "https://packagemanager.posit.co/cran/latest"))'
  )
  expect_equal(lines[[marker + 3L]], boosterpak:::rprofile_ppm_linux_binary_line())
  expect_equal(lines[[renv_line + 1L]], boosterpak:::rprofile_repository_reapply_marker())
  expect_equal(
    lines[[renv_line + 2L]],
    boosterpak:::rprofile_cran_default_line(
      "https://packagemanager.posit.co/cran/latest"
    )
  )
  expect_equal(
    lines[[renv_line + 3L]],
    boosterpak:::rprofile_ppm_linux_binary_line(renv_ppm = TRUE)
  )
  expect_equal(hook_line, renv_line + 4L)
})

test_that("init configures package install policy before renv activation", {
  withr::local_options(list(
    repos = c(CRAN = "@CRAN@"),
    renv.config.repos.override = NULL,
    renv.config.pak.enabled = FALSE,
    renv.config.ppm.enabled = FALSE,
    install.packages.compile.from.source = "interactive",
    install.packages.check.source = "yes",
    boosterpak.configure_repositories = TRUE,
    boosterpak.configure_install_policy = TRUE
  ))
  withr::local_envvar(
    RENV_CONFIG_REPOS_OVERRIDE = NA,
    BOOSTERPAK_CONFIGURE_INSTALL_POLICY = NA
  )
  root <- withr::local_tempdir()
  writeLines(
    c("before <- TRUE", "source(\"renv/activate.R\")", "after <- TRUE"),
    file.path(root, ".Rprofile")
  )

  init(root = root, renv = "no", rprofile = "yes", verbose = FALSE)

  expect_true(getOption("renv.config.pak.enabled"))
  expect_true(getOption("renv.config.ppm.enabled"))
  expect_equal(getOption("install.packages.compile.from.source"), "never")
  expect_equal(getOption("install.packages.check.source"), "no")

  lines <- readLines(file.path(root, ".Rprofile"), warn = FALSE)
  policy <- match(boosterpak:::rprofile_install_policy_marker(), lines)
  repo <- match(boosterpak:::rprofile_repository_marker(), lines)
  renv_line <- grep('source\\("renv/activate\\.R"\\)', lines)

  expect_true(policy < repo)
  expect_true(repo < renv_line)
  expect_equal(lines[[policy + 1L]], "options(renv.config.pak.enabled = TRUE)")
  expect_equal(lines[[policy + 2L]], "options(renv.config.ppm.enabled = TRUE)")
  expect_equal(
    lines[[policy + 3L]],
    'options(install.packages.compile.from.source = "never")'
  )
  expect_equal(
    lines[[policy + 4L]],
    'options(install.packages.check.source = "no")'
  )
})

test_that("init preserves explicit non-PPM repos", {
  withr::local_options(list(
    repos = c(CRAN = "https://example.test/custom-cran"),
    renv.config.repos.override = NULL,
    boosterpak.configure_repositories = TRUE,
    boosterpak.default_cran_mirrors = character()
  ))
  withr::local_envvar(
    RENV_CONFIG_REPOS_OVERRIDE = NA,
    BOOSTERPAK_DEFAULT_CRAN_MIRRORS = NA
  )
  root <- withr::local_tempdir()

  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  expect_equal(getOption("repos")[["CRAN"]], "https://example.test/custom-cran")
  expect_null(getOption("renv.config.repos.override"))
})

test_that("R option allows additional default-like CRAN mirrors", {
  withr::local_options(list(
    repos = c(CRAN = "https://mirror.example.test/cran"),
    renv.config.repos.override = NULL,
    boosterpak.configure_repositories = TRUE,
    boosterpak.default_cran_mirrors = "https://mirror.example.test/cran/"
  ))
  withr::local_envvar(
    RENV_CONFIG_REPOS_OVERRIDE = NA,
    BOOSTERPAK_DEFAULT_CRAN_MIRRORS = NA
  )
  root <- withr::local_tempdir()

  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  expect_equal(
    getOption("repos")[["CRAN"]],
    "https://packagemanager.posit.co/cran/latest"
  )
  expect_equal(
    getOption("renv.config.repos.override"),
    c(CRAN = "https://packagemanager.posit.co/cran/latest")
  )
})

test_that("env var allows additional default-like CRAN mirrors", {
  withr::local_options(list(
    repos = c(CRAN = "https://mirror.example.test/cran"),
    renv.config.repos.override = NULL,
    boosterpak.configure_repositories = TRUE,
    boosterpak.default_cran_mirrors = character()
  ))
  withr::local_envvar(
    RENV_CONFIG_REPOS_OVERRIDE = NA,
    BOOSTERPAK_DEFAULT_CRAN_MIRRORS = paste(
      "https://other.example.test/cran",
      "https://mirror.example.test/cran/",
      sep = ";"
    )
  )
  root <- withr::local_tempdir()

  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  expect_equal(
    getOption("repos")[["CRAN"]],
    "https://packagemanager.posit.co/cran/latest"
  )
  expect_equal(
    getOption("renv.config.repos.override"),
    c(CRAN = "https://packagemanager.posit.co/cran/latest")
  )
})

test_that("init preserves existing renv repository override", {
  withr::local_options(list(
    repos = c(CRAN = "@CRAN@"),
    renv.config.repos.override = "CRAN=https://example.test/cran",
    boosterpak.configure_repositories = TRUE
  ))
  withr::local_envvar(RENV_CONFIG_REPOS_OVERRIDE = NA)
  root <- withr::local_tempdir()

  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  expect_equal(
    getOption("repos")[["CRAN"]],
    "https://packagemanager.posit.co/cran/latest"
  )
  expect_equal(
    getOption("renv.config.repos.override"),
    "CRAN=https://example.test/cran"
  )
})

test_that("repository helpers handle NA values and names", {
  expect_false(boosterpak:::uses_posit_package_manager(c(
    NA_character_,
    "https://example.test/repo"
  )))
  expect_true(boosterpak:::uses_posit_package_manager(c(
    NA_character_,
    "https://packagemanager.posit.co/cran/latest"
  )))

  repos <- c("https://cloud.r-project.org", "https://example.test/repo")
  names(repos) <- c("CRAN", NA_character_)

  expect_equal(
    boosterpak:::rprofile_repos_value(repos),
    '"https://cloud.r-project.org", "https://example.test/repo"'
  )

  repos <- c(
    CRAN = "https://packagemanager.posit.co/cran/latest",
    Internal = "https://example.test/repo",
    "private-repo" = "https://private.example.test/repo"
  )
  expect_equal(
    boosterpak:::rprofile_repos_value(repos),
    paste(
      'CRAN = "https://packagemanager.posit.co/cran/latest"',
      'Internal = "https://example.test/repo"',
      '"private-repo" = "https://private.example.test/repo"',
      sep = ", "
    )
  )
})

test_that("init repository configuration can be disabled by option", {
  withr::local_options(list(
    repos = c(CRAN = "@CRAN@"),
    renv.config.repos.override = NULL,
    boosterpak.configure_repositories = FALSE
  ))
  withr::local_envvar(RENV_CONFIG_REPOS_OVERRIDE = NA)
  root <- withr::local_tempdir()

  init(root = root, renv = "no", rprofile = "no", verbose = FALSE)

  expect_equal(getOption("repos")[["CRAN"]], "@CRAN@")
  expect_null(getOption("renv.config.repos.override"))
})

test_that("init emits cli alert when configuring repositories", {
  withr::local_options(list(
    repos = c(CRAN = "@CRAN@"),
    renv.config.repos.override = NULL,
    boosterpak.configure_repositories = TRUE
  ))
  withr::local_envvar(RENV_CONFIG_REPOS_OVERRIDE = NA)
  root <- withr::local_tempdir()

  expect_message(
    init(root = root, renv = "no", rprofile = "no", verbose = TRUE),
    "Posit Package Manager"
  )
})

test_that("init uses manylinux binaries on Linux but persists generic repos", {
  local_mocked_bindings(is_glibc_linux = function() TRUE)
  withr::local_options(list(
    repos = c(CRAN = "@CRAN@", Internal = "https://example.test/repo"),
    renv.config.repos.override = NULL,
    HTTPUserAgent = "custom",
    boosterpak.configure_repositories = TRUE,
    boosterpak.configure_install_policy = FALSE
  ))
  withr::local_envvar(RENV_CONFIG_REPOS_OVERRIDE = NA)
  root <- withr::local_tempdir()

  init(root = root, renv = "no", rprofile = "yes", verbose = FALSE)

  linux <- "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28/latest"
  expected <- c(CRAN = linux, Internal = "https://example.test/repo")
  expect_equal(getOption("repos"), expected)
  expect_equal(getOption("renv.config.repos.override"), expected)
  expect_match(getOption("HTTPUserAgent"), "^R/[0-9.]+ R \\(")

  lines <- readLines(file.path(root, ".Rprofile"), warn = FALSE)
  marker <- match(boosterpak:::rprofile_repository_marker(), lines)
  expect_false(any(grepl("__linux__", lines[marker + 1:2], fixed = TRUE)))

  # The persisted block replays the same rewrite in a fresh Linux session.
  skip_if_not(identical(R.version$os, "linux-gnu"))
  options(repos = NULL, renv.config.repos.override = NULL)
  eval(parse(text = lines[marker + 1:3]), baseenv())
  expect_equal(getOption("repos"), expected)
  expect_equal(getOption("renv.config.repos.override"), expected)
})

test_that("init upgrades an existing generic PPM .Rprofile on Linux", {
  local_mocked_bindings(is_glibc_linux = function() TRUE)
  generic <- c(CRAN = "https://packagemanager.posit.co/cran/latest")
  withr::local_options(list(
    repos = generic,
    renv.config.repos.override = generic,
    boosterpak.configure_repositories = TRUE,
    boosterpak.configure_install_policy = FALSE
  ))
  withr::local_envvar(RENV_CONFIG_REPOS_OVERRIDE = NA)
  root <- withr::local_tempdir()
  old_block <- boosterpak:::rprofile_repository_lines(generic)[1:3]
  user_line <- "# user Linux block"
  writeLines(
    c(old_block, user_line, 'source("renv/activate.R")'),
    file.path(root, ".Rprofile")
  )

  init(root = root, renv = "no", rprofile = "yes", verbose = FALSE)
  init(root = root, renv = "no", rprofile = "yes", verbose = FALSE)

  lines <- readLines(file.path(root, ".Rprofile"), warn = FALSE)
  expect_equal(sum(lines == boosterpak:::rprofile_repository_marker()), 1L)
  expect_equal(sum(lines == boosterpak:::rprofile_repository_reapply_marker()), 1L)
  # One line before renv activation and one after it.
  expect_equal(sum(lines == boosterpak:::rprofile_ppm_linux_binary_line()), 1L)
  expect_equal(
    sum(lines == boosterpak:::rprofile_ppm_linux_binary_line(renv_ppm = TRUE)),
    1L
  )
  expect_true(user_line %in% lines)
})

test_that("Linux binary rewrite leaves custom and distro PPM URLs alone", {
  local_mocked_bindings(is_glibc_linux = function() TRUE)
  repos <- c(
    CRAN = "https://packagemanager.posit.co/cran/__linux__/noble/latest",
    Snap = "https://packagemanager.posit.co/cran/2026-01-02",
    Internal = "https://example.test/cran/latest"
  )
  withr::local_options(list(repos = repos, renv.config.repos.override = NULL))

  boosterpak:::use_ppm_linux_binaries()

  expect_equal(
    getOption("repos"),
    c(
      CRAN = "https://packagemanager.posit.co/cran/__linux__/noble/latest",
      Snap = "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28/2026-01-02",
      Internal = "https://example.test/cran/latest"
    )
  )
  expect_null(getOption("renv.config.repos.override"))
})

test_that("Linux binary rewrite covers p3m.dev and any repository name", {
  local_mocked_bindings(is_glibc_linux = function() TRUE)
  local_ppm_hosts()
  repos <- c(
    CRAN = "https://p3m.dev/cran/latest",
    Team = "https://p3m.dev/team-cran/2026-01-02",
    Old = "https://packagemanager.rstudio.com/cran/latest"
  )
  withr::local_options(list(
    repos = repos, renv.config.repos.override = NULL,
    HTTPUserAgent = "custom"
  ))

  boosterpak:::use_ppm_linux_binaries()

  expect_equal(
    getOption("repos"),
    c(
      CRAN = "https://p3m.dev/cran/__linux__/manylinux_2_28/latest",
      Team = "https://p3m.dev/team-cran/__linux__/manylinux_2_28/2026-01-02",
      Old = "https://packagemanager.rstudio.com/cran/__linux__/manylinux_2_28/latest"
    )
  )
})

test_that("self-hosted Package Manager hosts are opt-in", {
  local_mocked_bindings(is_glibc_linux = function() TRUE)
  repos <- c(
    CRAN = "https://ppm.corp.test:8443/internal/latest",
    Other = "https://other.corp.test/internal/latest"
  )
  withr::local_options(list(
    repos = repos,
    renv.config.repos.override = NULL,
    HTTPUserAgent = "custom"
  ))

  local_ppm_hosts()
  expect_false(boosterpak:::uses_posit_package_manager(repos))
  boosterpak:::use_ppm_linux_binaries()
  expect_equal(getOption("repos"), repos)

  local_ppm_hosts(repo = "https://ppm.corp.test:8443/internal/latest")
  expect_true(boosterpak:::uses_posit_package_manager(repos))
  boosterpak:::use_ppm_linux_binaries()
  expect_equal(
    getOption("repos"),
    c(
      CRAN = "https://ppm.corp.test:8443/internal/__linux__/manylinux_2_28/latest",
      Other = "https://other.corp.test/internal/latest"
    )
  )
})

test_that("extra hosts come from the option and environment variable", {
  local_ppm_hosts(
    hosts = c("Option.Corp.Test", "https://urlform.corp.test/cran/latest"),
    env_hosts = "env-a.corp.test; env-b.corp.test:8080,env-c.corp.test"
  )

  expect_setequal(
    boosterpak:::ppm_extra_hosts(),
    c(
      "option.corp.test",
      "urlform.corp.test",
      "env-a.corp.test",
      "env-b.corp.test:8080",
      "env-c.corp.test"
    )
  )
  expect_true(boosterpak:::uses_posit_package_manager(
    "https://env-b.corp.test:8080/cran/latest"
  ))
  expect_false(boosterpak:::uses_posit_package_manager(
    "https://env-b.corp.test/cran/latest"
  ))
})

test_that("invalid host entries are ignored with one warning", {
  local_ppm_hosts(hosts = c("not a host!", "good.corp.test"))

  expect_warning(
    hosts <- boosterpak:::ppm_extra_hosts(),
    "invalid Package Manager host"
  )
  expect_equal(hosts, "good.corp.test")
  expect_no_warning(boosterpak:::ppm_extra_hosts())
})

test_that("host matching is anchored and case-insensitive", {
  local_ppm_hosts()

  expect_true(boosterpak:::uses_posit_package_manager(
    "HTTPS://P3M.DEV/cran/latest"
  ))
  expect_true(boosterpak:::uses_posit_package_manager("https://p3m.dev"))
  expect_false(boosterpak:::uses_posit_package_manager(c(
    "https://p3m.dev.evil.test/cran/latest",
    "https://notp3m.dev/cran/latest",
    "https://example.test/p3m.dev/cran/latest"
  )))
})

test_that("portable_ppm_repos reverses the rewrite for every host form", {
  local_ppm_hosts(hosts = "ppm.corp.test:8443")
  generic <- c(
    CRAN = "https://p3m.dev/cran/latest",
    Team = "https://ppm.corp.test:8443/team-cran/2026-01-02",
    Posit = "https://packagemanager.posit.co/cran/2026-01-02",
    Other = "https://example.test/cran/latest"
  )
  linux <- sub(
    boosterpak:::ppm_snapshot_pattern(),
    "\\1/__linux__/manylinux_2_28/\\3",
    generic
  )

  expect_false(identical(linux, generic))
  expect_equal(boosterpak:::portable_ppm_repos(linux), generic)
  expect_equal(boosterpak:::portable_ppm_repos(generic), generic)
})

test_that("persisted repository lines stay generic for every host form", {
  local_ppm_hosts(repo = "https://ppm.corp.test/team-cran/latest")
  linux <- c(
    CRAN = "https://p3m.dev/cran/__linux__/manylinux_2_28/latest",
    Team = "https://ppm.corp.test/team-cran/__linux__/manylinux_2_28/latest"
  )

  lines <- boosterpak:::rprofile_repository_lines(linux)

  expect_false(any(grepl("__linux__", lines[2:3], fixed = TRUE)))
  expect_match(lines[[2]], "https://p3m.dev/cran/latest", fixed = TRUE)
  expect_match(
    lines[[2]],
    "https://ppm.corp.test/team-cran/latest",
    fixed = TRUE
  )
})

test_that("the generated Linux line is self-contained", {
  skip_if_not(identical(R.version$os, "linux-gnu"))
  local_ppm_hosts(repo = "https://ppm.corp.test:8443/team-cran/latest")
  line <- boosterpak:::rprofile_ppm_linux_binary_line()
  repos <- c(
    CRAN = "https://p3m.dev/cran/latest",
    Team = "https://ppm.corp.test:8443/team-cran/2026-01-02",
    Other = "https://example.test/cran/latest"
  )
  expected <- c(
    CRAN = "https://p3m.dev/cran/__linux__/manylinux_2_28/latest",
    Team = "https://ppm.corp.test:8443/team-cran/__linux__/manylinux_2_28/2026-01-02",
    Other = "https://example.test/cran/latest"
  )
  withr::local_options(list(
    repos = repos,
    renv.config.repos.override = repos,
    HTTPUserAgent = "custom"
  ))
  # A fresh session has neither boosterpak's helpers nor its host settings, so
  # the line must carry the hosts it was generated with.
  local_ppm_hosts()

  expect_false(grepl("boosterpak", gsub("BOOSTERPAK_[A-Z_]+", "", line)))
  eval(parse(text = line), baseenv())
  expect_equal(getOption("repos"), expected)
  expect_equal(getOption("renv.config.repos.override"), expected)
})

test_that("BOOSTERPAK_CONFIGURE_REPOSITORIES=false disables an existing line", {
  skip_if_not(identical(R.version$os, "linux-gnu"))
  local_ppm_hosts()
  line <- boosterpak:::rprofile_ppm_linux_binary_line()
  repos <- c(CRAN = "https://p3m.dev/cran/latest")
  withr::local_options(list(
    repos = repos,
    renv.config.repos.override = repos,
    HTTPUserAgent = "custom"
  ))

  for (value in c("false", "FALSE", "0", "no", "off")) {
    withr::local_envvar(BOOSTERPAK_CONFIGURE_REPOSITORIES = value)
    eval(parse(text = line), baseenv())
    expect_equal(getOption("repos"), repos)
    expect_equal(getOption("HTTPUserAgent"), "custom")
  }

  withr::local_envvar(BOOSTERPAK_CONFIGURE_REPOSITORIES = "true")
  eval(parse(text = line), baseenv())
  expect_match(getOption("repos")[["CRAN"]], "manylinux_2_28", fixed = TRUE)
})

test_that("init upgrades a v0.9.2 .Rprofile line to the current form", {
  local_mocked_bindings(is_glibc_linux = function() TRUE)
  local_ppm_hosts()
  generic <- c(CRAN = "https://packagemanager.posit.co/cran/latest")
  withr::local_options(list(
    repos = generic,
    renv.config.repos.override = generic,
    boosterpak.configure_repositories = TRUE,
    boosterpak.configure_install_policy = FALSE
  ))
  withr::local_envvar(RENV_CONFIG_REPOS_OVERRIDE = NA)

  for (include_renv in c(TRUE, FALSE)) {
    root <- withr::local_tempdir()
    user_line <- "# user Linux block"
    old_block <- boosterpak:::rprofile_repository_lines(generic)
    old_block[length(old_block)] <- v092_ppm_linux_line(include_renv)
    if (!include_renv) {
      old_block <- old_block[-3]
    }
    writeLines(
      c(old_block, user_line, 'source("renv/activate.R")'),
      file.path(root, ".Rprofile")
    )

    init(root = root, renv = "no", rprofile = "yes", verbose = FALSE)
    first <- readLines(file.path(root, ".Rprofile"), warn = FALSE)
    init(root = root, renv = "no", rprofile = "yes", verbose = FALSE)
    lines <- readLines(file.path(root, ".Rprofile"), warn = FALSE)

    expect_equal(lines, first)
    expect_false(v092_ppm_linux_line(include_renv) %in% lines)
    expect_equal(sum(lines == boosterpak:::rprofile_repository_marker()), 1L)
    expect_equal(sum(lines == boosterpak:::rprofile_repository_reapply_marker()), 1L)
    # One line before renv activation and one after it.
    expect_equal(
      sum(vapply(lines, boosterpak:::is_rprofile_ppm_linux_line, logical(1))),
      2L
    )
    expect_true(user_line %in% lines)
  }
})

test_that("deinit removes a v0.9.2 and a current Linux line", {
  generic <- c(CRAN = "https://packagemanager.posit.co/cran/latest")
  old <- boosterpak:::rprofile_repository_lines(generic)
  old[length(old)] <- v092_ppm_linux_line()
  current <- boosterpak:::rprofile_repository_lines(generic)

  for (block in list(old, current)) {
    result <- boosterpak:::remove_rprofile_managed_lines(
      c("before <- TRUE", block, "after <- TRUE"),
      renv = FALSE
    )
    expect_equal(result$lines, c("before <- TRUE", "after <- TRUE"))
  }
})

test_that("init adds post-activation lines ahead of an existing managed hook", {
  local_ppm_hosts()
  generic <- c(CRAN = "https://packagemanager.posit.co/cran/latest")
  withr::local_options(list(
    repos = generic,
    renv.config.repos.override = generic,
    boosterpak.configure_repositories = TRUE,
    boosterpak.configure_install_policy = FALSE
  ))
  withr::local_envvar(RENV_CONFIG_REPOS_OVERRIDE = NA)
  root <- withr::local_tempdir()
  # A 0.9.2 layout: early repository lines and the managed hook, but no
  # post-activation lines yet.
  old_block <- boosterpak:::rprofile_repository_lines(generic)
  old_block[length(old_block)] <- v092_ppm_linux_line()
  writeLines(
    c(
      "before <- TRUE",
      old_block,
      'source("renv/activate.R")',
      boosterpak:::rprofile_startup_block(),
      "after <- TRUE"
    ),
    file.path(root, ".Rprofile")
  )

  init(root = root, renv = "no", rprofile = "yes", verbose = FALSE)

  lines <- readLines(file.path(root, ".Rprofile"), warn = FALSE)
  renv_line <- grep('source\\("renv/activate\\.R"\\)', lines)
  expect_equal(lines[[renv_line + 1L]], boosterpak:::rprofile_repository_reapply_marker())
  expect_equal(
    lines[[renv_line + 2L]],
    boosterpak:::rprofile_cran_default_line(
      "https://packagemanager.posit.co/cran/latest"
    )
  )
  expect_equal(
    lines[[renv_line + 3L]],
    boosterpak:::rprofile_ppm_linux_binary_line(renv_ppm = TRUE)
  )
  expect_equal(lines[[renv_line + 4L]], boosterpak:::rprofile_startup_begin_marker())
  expect_equal(sum(lines == boosterpak:::rprofile_startup_begin_marker()), 1L)
  expect_false(v092_ppm_linux_line() %in% lines)
  expect_true("before <- TRUE" %in% lines)
  expect_true("after <- TRUE" %in% lines)
})

test_that("a missing managed hook goes after the post-activation Linux lines", {
  generic <- c(CRAN = "https://packagemanager.posit.co/cran/latest")
  setup <- boosterpak:::rprofile_repository_lines(generic, include_renv = FALSE)
  reapply <- boosterpak:::rprofile_repository_reapply_lines(include_renv = FALSE)
  root <- withr::local_tempdir()
  # Setup lines and post-activation lines are current, but the hook is gone.
  writeLines(
    c("before <- TRUE", setup, 'source("renv/activate.R")', reapply, "after <- TRUE"),
    file.path(root, ".Rprofile")
  )

  changed <- boosterpak:::ensure_rprofile_line(
    root = root,
    rprofile = "yes",
    repository_lines = c(setup, reapply)
  )

  expect_true(changed)
  lines <- readLines(file.path(root, ".Rprofile"), warn = FALSE)
  expect_equal(
    lines,
    c(
      "before <- TRUE",
      setup,
      'source("renv/activate.R")',
      reapply,
      boosterpak:::rprofile_startup_block(),
      "after <- TRUE"
    )
  )
  # The re-apply runs before the hook sources boosters/.
  expect_lt(
    match('source("renv/activate.R")', lines),
    match(boosterpak:::rprofile_repository_reapply_marker(), lines)
  )
  expect_lt(
    match(boosterpak:::rprofile_repository_reapply_marker(), lines),
    match(boosterpak:::rprofile_startup_begin_marker(), lines)
  )
  expect_false(
    boosterpak:::ensure_rprofile_line(
      root = root,
      rprofile = "yes",
      repository_lines = c(setup, reapply)
    )
  )
})

test_that("the Linux binary rewrite is re-applied after renv activation", {
  skip_if_not(identical(R.version$os, "linux-gnu"))
  skip_if_not_installed("renv")
  loadNamespace("renv")
  local_ppm_hosts()
  withr::local_options(list(
    repos = c(CRAN = "@CRAN@"),
    renv.config.repos.override = NULL,
    renv.config.ppm.enabled = TRUE,
    HTTPUserAgent = "custom",
    download.file.extra = NULL,
    boosterpak.configure_repositories = TRUE,
    boosterpak.configure_install_policy = FALSE
  ))
  withr::local_envvar(
    RENV_CONFIG_REPOS_OVERRIDE = NA,
    RENV_CONFIG_PPM_ENABLED = NA,
    RENV_PPM_ENABLED = NA,
    RENV_RSPM_ENABLED = NA
  )
  root <- withr::local_tempdir()
  writeLines(
    c("before <- TRUE", 'source("renv/activate.R")', "after <- TRUE"),
    file.path(root, ".Rprofile")
  )
  init(root = root, renv = "no", rprofile = "yes", verbose = FALSE)

  # Stand-in for renv/activate.R: renv::load() resets repos to the lockfile URL.
  dir.create(file.path(root, "renv"))
  writeLines(
    'options(repos = c(CRAN = "https://packagemanager.posit.co/cran/latest"))',
    file.path(root, "renv", "activate.R")
  )
  lines <- readLines(file.path(root, ".Rprofile"), warn = FALSE)
  # Run the profile up to the managed hook, which would source boosters/.
  hook <- match(boosterpak:::rprofile_startup_begin_marker(), lines)
  lines <- lines[seq_len(hook - 1L)]

  withr::local_dir(root)
  env <- new.env(parent = baseenv())
  eval(parse(text = lines), envir = env)

  linux <- "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28/latest"
  expect_equal(getOption("repos")[["CRAN"]], linux)
  expect_equal(getOption("renv.config.repos.override")[["CRAN"]], linux)
  expect_true(env$before)
})

test_that("post-activation Linux lines are only planned for Package Manager repos", {
  withr::local_options(list(
    repos = c(CRAN = "https://example.test/cran"),
    renv.config.repos.override = NULL,
    boosterpak.configure_repositories = TRUE
  ))
  withr::local_envvar(RENV_CONFIG_REPOS_OVERRIDE = NA)

  expect_length(boosterpak:::boosterpak_repository_lines_for_session(), 0L)

  ppm <- "https://packagemanager.posit.co/cran/latest"
  options(repos = c(CRAN = ppm))
  lines <- boosterpak:::boosterpak_repository_lines_for_session()
  expect_equal(
    tail(lines, 3L),
    boosterpak:::rprofile_repository_reapply_lines(
      include_renv = FALSE,
      cran_url = ppm
    )
  )
  # Only re-applied when renv's own Package Manager handling is on, so the
  # manylinux URL cannot reach renv.lock.
  expect_match(tail(lines, 1L), "renv:::renv_ppm_enabled()", fixed = TRUE)
  expect_match(tail(lines, 2L)[[1]], "renv:::renv_ppm_enabled()", fixed = TRUE)
  expect_false(any(grepl("renv:::renv_ppm_enabled()", lines[seq_len(length(lines) - 3L)], fixed = TRUE)))
})

test_that("the post-activation Linux line is skipped when renv PPM handling is off", {
  skip_if_not(identical(R.version$os, "linux-gnu"))
  skip_if_not_installed("renv")
  # renv is loaded by activation in real use, and the guard checks that first.
  loadNamespace("renv")
  local_ppm_hosts()
  repos <- c(CRAN = "https://packagemanager.posit.co/cran/latest")
  withr::local_options(list(
    repos = repos,
    renv.config.repos.override = repos,
    renv.config.ppm.enabled = FALSE,
    HTTPUserAgent = "custom",
    download.file.extra = NULL
  ))
  withr::local_envvar(
    RENV_PPM_ENABLED = NA,
    RENV_RSPM_ENABLED = NA,
    RENV_CONFIG_PPM_ENABLED = NA
  )
  # Check the internal directly. A missing internal also makes the guard
  # FALSE, so the rest of the test could otherwise pass without this check.
  expect_false(renv:::renv_ppm_enabled())
  line <- boosterpak:::rprofile_repository_reapply_lines(include_renv = TRUE)[[2]]

  eval(parse(text = line), baseenv())

  expect_equal(getOption("repos"), repos)
  expect_equal(getOption("HTTPUserAgent"), "custom")
})

test_that("the post-activation guard never loads renv from the library", {
  skip_if_not(identical(R.version$os, "linux-gnu"))
  skip_if_not_installed("renv")
  line <- boosterpak:::rprofile_ppm_linux_binary_line(include_renv = FALSE, renv_ppm = TRUE)
  script <- tempfile(fileext = ".R")
  on.exit(unlink(script), add = TRUE)
  writeLines(c(
    'options(repos = c(CRAN = "https://packagemanager.posit.co/cran/latest"))',
    line,
    'cat(sprintf("renv loaded: %s\\n", isNamespaceLoaded("renv")))',
    'cat(sprintf("repos: %s\\n", getOption("repos")[["CRAN"]]))'
  ), script)
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")

  # The child process sees the same libraries as this session, so renv is
  # findable even when it is installed only outside the default library.
  lib_paths <- paste(.libPaths(), collapse = .Platform$path.sep)
  out <- system2(
    rscript,
    c("--vanilla", script),
    stdout = TRUE,
    stderr = TRUE,
    env = paste0("R_LIBS=", lib_paths)
  )

  expect_true("renv loaded: FALSE" %in% out)
  # renv is not loaded, so the guard is FALSE and the URL is left generic.
  expect_true("repos: https://packagemanager.posit.co/cran/latest" %in% out)
})

test_that("the post-activation CRAN line restores the session's Package Manager URL", {
  expect_equal(
    boosterpak:::ppm_cran_replacement(c(CRAN = "https://packagemanager.posit.co/cran/2026-01-02")),
    "https://packagemanager.posit.co/cran/2026-01-02"
  )
  expect_equal(
    boosterpak:::ppm_cran_replacement(c(
      CRAN = "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28/latest"
    )),
    "https://packagemanager.posit.co/cran/latest"
  )
  expect_null(boosterpak:::ppm_cran_replacement(c(CRAN = "https://example.test/cran")))
  expect_null(boosterpak:::ppm_cran_replacement(c(Internal = "https://packagemanager.posit.co/cran/latest")))
  expect_null(boosterpak:::ppm_cran_replacement("https://packagemanager.posit.co/cran/latest"))
})

test_that("the CRAN default mirror line restores Package Manager on any OS", {
  skip_if_not_installed("renv")
  loadNamespace("renv")
  local_ppm_hosts()
  ppm <- "https://packagemanager.posit.co/cran/latest"
  line <- boosterpak:::rprofile_cran_default_line(ppm)
  withr::local_options(list(
    repos = getOption("repos"),
    renv.config.repos.override = NULL,
    renv.config.ppm.enabled = TRUE
  ))
  withr::local_envvar(
    RENV_CONFIG_REPOS_OVERRIDE = NA,
    BOOSTERPAK_CONFIGURE_REPOSITORIES = NA,
    RENV_PPM_ENABLED = NA,
    RENV_RSPM_ENABLED = NA,
    RENV_CONFIG_PPM_ENABLED = NA
  )

  for (mirror in c(
    "https://cran.rstudio.com",
    "https://cran.rstudio.com/",
    "HTTPS://CRAN.RSTUDIO.COM/",
    "https://cloud.r-project.org/",
    "https://cran.r-project.org",
    "@CRAN@"
  )) {
    options(repos = c(CRAN = mirror, Internal = "https://example.test/repo"))
    eval(parse(text = line), baseenv())
    expect_equal(
      getOption("repos"),
      c(CRAN = ppm, Internal = "https://example.test/repo"),
      info = mirror
    )
  }

  options(
    repos = c(CRAN = "https://cran.rstudio.com"),
    renv.config.repos.override = c(CRAN = "https://cran.rstudio.com")
  )
  eval(parse(text = line), baseenv())
  expect_equal(getOption("renv.config.repos.override"), c(CRAN = ppm))

  # Without the renv override line, the override is not touched.
  options(
    repos = c(CRAN = "https://cran.rstudio.com"),
    renv.config.repos.override = c(CRAN = "https://cran.rstudio.com")
  )
  eval(
    parse(text = boosterpak:::rprofile_cran_default_line(ppm, include_renv = FALSE)),
    baseenv()
  )
  expect_equal(getOption("renv.config.repos.override"), c(CRAN = "https://cran.rstudio.com"))
  expect_equal(getOption("repos"), c(CRAN = ppm))
})

test_that("the CRAN default mirror line leaves custom and non-CRAN repositories alone", {
  skip_if_not_installed("renv")
  loadNamespace("renv")
  local_ppm_hosts()
  ppm <- "https://packagemanager.posit.co/cran/latest"
  line <- boosterpak:::rprofile_cran_default_line(ppm)
  withr::local_options(list(
    repos = getOption("repos"),
    renv.config.repos.override = NULL,
    renv.config.ppm.enabled = TRUE
  ))
  withr::local_envvar(
    RENV_CONFIG_REPOS_OVERRIDE = NA,
    BOOSTERPAK_CONFIGURE_REPOSITORIES = NA,
    RENV_PPM_ENABLED = NA,
    RENV_RSPM_ENABLED = NA,
    RENV_CONFIG_PPM_ENABLED = NA
  )

  for (mirror in c(
    "https://mirror.example.test/cran/",
    "https://cran.example.test",
    "http://cran.rstudio.com",
    "https://packagemanager.posit.co/cran/2026-01-02"
  )) {
    repos <- c(CRAN = mirror, Internal = "https://cran.rstudio.com")
    options(repos = repos)
    eval(parse(text = line), baseenv())
    expect_equal(getOption("repos"), repos, info = mirror)
  }

  # A session without a CRAN name, or with unnamed repos, must not error.
  options(repos = c(Internal = "https://example.test/repo"))
  expect_no_error(eval(parse(text = line), baseenv()))
  expect_equal(getOption("repos"), c(Internal = "https://example.test/repo"))
  options(repos = "https://cran.rstudio.com")
  expect_no_error(eval(parse(text = line), baseenv()))
  expect_equal(getOption("repos"), "https://cran.rstudio.com")
})

test_that("the CRAN default mirror line matches is_default_cran_mirror()", {
  skip_if_not_installed("renv")
  loadNamespace("renv")
  ppm <- "https://packagemanager.posit.co/cran/latest"
  line <- boosterpak:::rprofile_cran_default_line(ppm)
  withr::local_options(list(
    repos = getOption("repos"),
    renv.config.repos.override = NULL,
    boosterpak.default_cran_mirrors = character(),
    renv.config.ppm.enabled = TRUE
  ))
  withr::local_envvar(
    BOOSTERPAK_DEFAULT_CRAN_MIRRORS = NA,
    BOOSTERPAK_CONFIGURE_REPOSITORIES = NA,
    RENV_PPM_ENABLED = NA,
    RENV_RSPM_ENABLED = NA,
    RENV_CONFIG_PPM_ENABLED = NA
  )

  inputs <- c(
    "@CRAN@",
    "https://cran.rstudio.com/",
    "HTTPS://Cran.RStudio.com",
    "https://cloud.r-project.org",
    "https://cran.r-project.org//",
    "http://cran.rstudio.com",
    "https://cran.rstudio.com/src",
    "https://mirror.example.test"
  )
  for (repo in inputs) {
    options(repos = c(CRAN = repo))
    eval(parse(text = line), baseenv())
    expect_equal(
      getOption("repos")[["CRAN"]] == ppm,
      boosterpak:::is_default_cran_mirror(repo),
      info = repo
    )
  }
})

test_that("the CRAN default mirror line honors the opt-out and renv PPM handling", {
  skip_if_not_installed("renv")
  loadNamespace("renv")
  local_ppm_hosts()
  ppm <- "https://packagemanager.posit.co/cran/latest"
  line <- boosterpak:::rprofile_cran_default_line(ppm)
  withr::local_options(list(
    repos = c(CRAN = "https://cran.rstudio.com"),
    renv.config.repos.override = NULL,
    renv.config.ppm.enabled = TRUE
  ))
  withr::local_envvar(
    RENV_CONFIG_REPOS_OVERRIDE = NA,
    BOOSTERPAK_CONFIGURE_REPOSITORIES = "false",
    RENV_PPM_ENABLED = NA,
    RENV_RSPM_ENABLED = NA,
    RENV_CONFIG_PPM_ENABLED = NA
  )

  for (value in c("false", "0", "no", "off")) {
    withr::local_envvar(BOOSTERPAK_CONFIGURE_REPOSITORIES = value)
    eval(parse(text = line), baseenv())
    expect_equal(getOption("repos"), c(CRAN = "https://cran.rstudio.com"))
  }

  withr::local_envvar(BOOSTERPAK_CONFIGURE_REPOSITORIES = "true")
  options(renv.config.ppm.enabled = FALSE)
  expect_false(renv:::renv_ppm_enabled())
  eval(parse(text = line), baseenv())
  expect_equal(getOption("repos"), c(CRAN = "https://cran.rstudio.com"))

  options(renv.config.ppm.enabled = TRUE)
  eval(parse(text = line), baseenv())
  expect_equal(getOption("repos"), c(CRAN = ppm))
})

test_that("the CRAN default mirror line leaves no variables in the global environment", {
  skip_if_not_installed("renv")
  loadNamespace("renv")
  local_ppm_hosts()
  line <- boosterpak:::rprofile_cran_default_line("https://packagemanager.posit.co/cran/latest")
  withr::local_options(list(
    repos = c(CRAN = "https://cran.rstudio.com"),
    renv.config.ppm.enabled = TRUE
  ))
  withr::local_envvar(
    BOOSTERPAK_CONFIGURE_REPOSITORIES = NA,
    RENV_PPM_ENABLED = NA,
    RENV_RSPM_ENABLED = NA,
    RENV_CONFIG_PPM_ENABLED = NA
  )

  env <- new.env(parent = baseenv())
  eval(parse(text = line), env)

  expect_equal(ls(env, all.names = TRUE), character())
})

test_that("the CRAN default mirror line is recognised and other lines are not", {
  reapply <- boosterpak:::rprofile_repository_reapply_lines(
    cran_url = "https://packagemanager.posit.co/cran/latest"
  )
  expect_true(boosterpak:::is_rprofile_cran_default_line(reapply[[2]]))
  expect_false(boosterpak:::is_rprofile_cran_default_line(reapply[[3]]))
  expect_false(boosterpak:::is_rprofile_cran_default_line(reapply[[1]]))
  expect_false(boosterpak:::is_rprofile_cran_default_line(
    boosterpak:::rprofile_repository_lines("https://packagemanager.posit.co/cran/latest")[[2]]
  ))
  expect_true(all(vapply(reapply, boosterpak:::is_rprofile_reapply_line, logical(1))[-1]))
})

test_that("a CRAN default mirror reset by renv activation is restored on every OS", {
  skip_if_not_installed("renv")
  loadNamespace("renv")
  local_ppm_hosts()
  withr::local_options(list(
    repos = c(CRAN = "@CRAN@"),
    renv.config.repos.override = NULL,
    renv.config.ppm.enabled = TRUE,
    HTTPUserAgent = "custom",
    download.file.extra = NULL,
    boosterpak.configure_repositories = TRUE,
    boosterpak.configure_install_policy = FALSE
  ))
  withr::local_envvar(
    RENV_CONFIG_REPOS_OVERRIDE = NA,
    RENV_CONFIG_PPM_ENABLED = NA,
    RENV_PPM_ENABLED = NA,
    RENV_RSPM_ENABLED = NA
  )
  root <- withr::local_tempdir()
  writeLines(
    c("before <- TRUE", 'source("renv/activate.R")', "after <- TRUE"),
    file.path(root, ".Rprofile")
  )
  init(root = root, renv = "no", rprofile = "yes", verbose = FALSE)

  # Stand-in for renv/activate.R: the lockfile records a default CRAN mirror.
  dir.create(file.path(root, "renv"))
  writeLines(
    'options(repos = c(CRAN = "https://cran.rstudio.com"))',
    file.path(root, "renv", "activate.R")
  )
  lines <- readLines(file.path(root, ".Rprofile"), warn = FALSE)
  hook <- match(boosterpak:::rprofile_startup_begin_marker(), lines)
  lines <- lines[seq_len(hook - 1L)]

  withr::local_dir(root)
  env <- new.env(parent = baseenv())
  eval(parse(text = lines), envir = env)

  # The CRAN line restores Package Manager on every OS, and the Linux line
  # then rewrites it to the manylinux binary URL where that applies.
  expected <- if (identical(R.version$os, "linux-gnu")) {
    "https://packagemanager.posit.co/cran/__linux__/manylinux_2_28/latest"
  } else {
    "https://packagemanager.posit.co/cran/latest"
  }
  expect_equal(getOption("repos")[["CRAN"]], expected)
  expect_true(env$before)
})

test_that("the Linux rewrite stays Linux-only when the CRAN line restores Package Manager", {
  skip_if_not_installed("renv")
  loadNamespace("renv")
  local_ppm_hosts()
  ppm <- "https://packagemanager.posit.co/cran/latest"
  reapply <- boosterpak:::rprofile_repository_reapply_lines(
    include_renv = FALSE,
    cran_url = ppm
  )
  # Stand in for Windows or macOS: the Linux guard is always FALSE there.
  reapply[[3]] <- sub(
    'identical(R.version$os, "linux-gnu")',
    "FALSE",
    reapply[[3]],
    fixed = TRUE
  )
  withr::local_options(list(
    repos = c(CRAN = "https://cran.rstudio.com"),
    renv.config.repos.override = NULL,
    renv.config.ppm.enabled = TRUE,
    HTTPUserAgent = "custom",
    download.file.extra = NULL
  ))
  withr::local_envvar(
    RENV_CONFIG_REPOS_OVERRIDE = NA,
    BOOSTERPAK_CONFIGURE_REPOSITORIES = NA,
    RENV_PPM_ENABLED = NA,
    RENV_RSPM_ENABLED = NA,
    RENV_CONFIG_PPM_ENABLED = NA
  )

  for (line in reapply[-1]) {
    eval(parse(text = line), baseenv())
  }

  expect_equal(getOption("repos"), c(CRAN = ppm))
  expect_equal(getOption("HTTPUserAgent"), "custom")
  expect_null(getOption("renv.config.repos.override"))
})

test_that("init migrates an older post-activation block to the CRAN-aware block", {
  local_ppm_hosts()
  generic <- c(CRAN = "https://packagemanager.posit.co/cran/latest")
  withr::local_options(list(
    repos = generic,
    renv.config.repos.override = generic,
    boosterpak.configure_repositories = TRUE,
    boosterpak.configure_install_policy = FALSE
  ))
  withr::local_envvar(RENV_CONFIG_REPOS_OVERRIDE = NA)
  root <- withr::local_tempdir()
  # The post-activation block as the previous release wrote it: no CRAN line.
  writeLines(
    c(
      "before <- TRUE",
      boosterpak:::rprofile_repository_lines(generic),
      'source("renv/activate.R")',
      boosterpak:::rprofile_repository_reapply_lines(),
      boosterpak:::rprofile_startup_block(),
      "after <- TRUE"
    ),
    file.path(root, ".Rprofile")
  )

  init(root = root, renv = "no", rprofile = "yes", verbose = FALSE)
  first <- readLines(file.path(root, ".Rprofile"), warn = FALSE)
  init(root = root, renv = "no", rprofile = "yes", verbose = FALSE)
  lines <- readLines(file.path(root, ".Rprofile"), warn = FALSE)

  expect_equal(lines, first)
  expect_equal(sum(lines == boosterpak:::rprofile_repository_reapply_marker()), 1L)
  expect_equal(sum(vapply(lines, boosterpak:::is_rprofile_cran_default_line, logical(1))), 1L)
  expect_equal(
    sum(lines == boosterpak:::rprofile_ppm_linux_binary_line(renv_ppm = TRUE)),
    1L
  )
  expect_equal(sum(lines == boosterpak:::rprofile_startup_begin_marker()), 1L)
  renv_line <- grep('source\\("renv/activate\\.R"\\)', lines)
  expect_equal(
    lines[renv_line + 1:4],
    c(
      boosterpak:::rprofile_repository_reapply_marker(),
      boosterpak:::rprofile_cran_default_line(generic[[1]]),
      boosterpak:::rprofile_ppm_linux_binary_line(renv_ppm = TRUE),
      boosterpak:::rprofile_startup_begin_marker()
    )
  )
  expect_true(all(c("before <- TRUE", "after <- TRUE") %in% lines))
})

test_that("a missing managed hook goes after the CRAN default mirror and Linux lines", {
  generic <- c(CRAN = "https://packagemanager.posit.co/cran/latest")
  setup <- boosterpak:::rprofile_repository_lines(generic, include_renv = FALSE)
  reapply <- boosterpak:::rprofile_repository_reapply_lines(
    include_renv = FALSE,
    cran_url = generic[[1]]
  )
  root <- withr::local_tempdir()
  writeLines(
    c("before <- TRUE", setup, 'source("renv/activate.R")', reapply, "after <- TRUE"),
    file.path(root, ".Rprofile")
  )

  changed <- boosterpak:::ensure_rprofile_line(
    root = root,
    rprofile = "yes",
    repository_lines = c(setup, reapply)
  )

  expect_true(changed)
  lines <- readLines(file.path(root, ".Rprofile"), warn = FALSE)
  expect_equal(
    lines,
    c(
      "before <- TRUE",
      setup,
      'source("renv/activate.R")',
      reapply,
      boosterpak:::rprofile_startup_block(),
      "after <- TRUE"
    )
  )
  expect_false(
    boosterpak:::ensure_rprofile_line(
      root = root,
      rprofile = "yes",
      repository_lines = c(setup, reapply)
    )
  )
})

test_that("deinit removes the CRAN default mirror line with the other post-activation lines", {
  generic <- c(CRAN = "https://packagemanager.posit.co/cran/latest")
  lines <- c(
    "before <- TRUE",
    boosterpak:::rprofile_repository_lines(generic),
    'source("renv/activate.R")',
    boosterpak:::rprofile_repository_reapply_lines(cran_url = generic[[1]]),
    "after <- TRUE"
  )

  result <- boosterpak:::remove_rprofile_managed_lines(lines, renv = FALSE)

  expect_equal(
    result$lines,
    c("before <- TRUE", 'source("renv/activate.R")', "after <- TRUE")
  )
})

test_that("rescue leaves a current block with the CRAN default mirror line unchanged", {
  ppm <- "https://packagemanager.posit.co/cran/latest"
  setup <- boosterpak:::rprofile_repository_lines(c(CRAN = ppm))
  reapply <- boosterpak:::rprofile_repository_reapply_lines(cran_url = ppm)
  lines <- c(
    "before <- TRUE",
    setup,
    'source("renv/activate.R")',
    reapply,
    boosterpak:::rprofile_startup_block(),
    "after <- TRUE"
  )

  planned <- boosterpak:::.rescue_rprofile_lines(lines, c(setup, reapply))

  expect_false(planned$changed)
  expect_equal(planned$lines, lines)
})

test_that("deinit removes the post-activation Linux lines and keeps renv activation", {
  generic <- c(CRAN = "https://packagemanager.posit.co/cran/latest")
  lines <- c(
    "before <- TRUE",
    boosterpak:::rprofile_repository_lines(generic),
    'source("renv/activate.R")',
    boosterpak:::rprofile_repository_reapply_lines(),
    "after <- TRUE"
  )

  result <- boosterpak:::remove_rprofile_managed_lines(lines, renv = FALSE)

  expect_equal(
    result$lines,
    c("before <- TRUE", 'source("renv/activate.R")', "after <- TRUE")
  )
})

ppm_user_agent_header <- function() {
  sprintf(
    '--header "User-Agent: R (%s)"',
    paste(getRversion(), R.version$platform, R.version$arch, R.version$os)
  )
}

local_ppm_download_options <- function(method, extra, .env = parent.frame()) {
  local_ppm_hosts(.env = .env)
  withr::local_options(
    list(
      repos = c(CRAN = "https://p3m.dev/cran/latest"),
      renv.config.repos.override = NULL,
      HTTPUserAgent = "custom",
      download.file.method = method,
      download.file.extra = extra
    ),
    .local_envir = .env
  )
}

test_that("curl and wget get the R user agent header", {
  local_mocked_bindings(is_glibc_linux = function() TRUE)

  for (method in c("curl", "wget")) {
    local_ppm_download_options(method, extra = NULL)
    boosterpak:::use_ppm_linux_binaries()
    expect_equal(getOption("download.file.extra"), ppm_user_agent_header())
  }
})

test_that("an existing download.file.extra is appended to, not replaced", {
  local_mocked_bindings(is_glibc_linux = function() TRUE)

  for (method in c("curl", "wget")) {
    local_ppm_download_options(method, extra = "-fsSL")
    boosterpak:::use_ppm_linux_binaries()
    expect_equal(
      getOption("download.file.extra"),
      paste("-fsSL", ppm_user_agent_header())
    )
  }
})

test_that("the user agent header is added once and never overrides one", {
  local_mocked_bindings(is_glibc_linux = function() TRUE)

  local_ppm_download_options("curl", extra = NULL)
  boosterpak:::use_ppm_linux_binaries()
  boosterpak:::use_ppm_linux_binaries()
  expect_equal(getOption("download.file.extra"), ppm_user_agent_header())

  custom <- '-fsSL --header "user-agent: custom-agent"'
  local_ppm_download_options("curl", extra = custom)
  boosterpak:::use_ppm_linux_binaries()
  expect_equal(getOption("download.file.extra"), custom)
})

test_that("other download methods leave download.file.extra alone", {
  local_mocked_bindings(is_glibc_linux = function() TRUE)

  for (method in list(NULL, "libcurl", "internal", "auto")) {
    for (extra in list(NULL, "-fsSL")) {
      local_ppm_download_options(method, extra = extra)
      boosterpak:::use_ppm_linux_binaries()
      expect_identical(getOption("download.file.extra"), extra)
    }
  }
})

test_that("download.file.extra is untouched off glibc Linux or without PPM", {
  local_ppm_download_options("curl", extra = NULL)
  boosterpak:::use_ppm_linux_binaries()
  expect_null(getOption("download.file.extra"))

  local_mocked_bindings(is_glibc_linux = function() TRUE)
  withr::local_options(repos = c(CRAN = "https://example.test/cran/latest"))
  boosterpak:::use_ppm_linux_binaries()
  expect_null(getOption("download.file.extra"))
})

test_that("the generated Linux line sets the header for curl and wget", {
  skip_if_not(identical(R.version$os, "linux-gnu"))
  line <- boosterpak:::rprofile_ppm_linux_binary_line()

  for (extra in list(NULL, "-fsSL")) {
    for (method in c("curl", "wget")) {
      local_ppm_download_options(method, extra = extra)
      eval(parse(text = line), baseenv())
      expect_equal(
        getOption("download.file.extra"),
        paste(c(extra, ppm_user_agent_header()), collapse = " ")
      )
    }
  }

  local_ppm_download_options("libcurl", extra = "-fsSL")
  eval(parse(text = line), baseenv())
  expect_equal(getOption("download.file.extra"), "-fsSL")
  local_ppm_download_options(NULL, extra = NULL)
  eval(parse(text = line), baseenv())
  expect_null(getOption("download.file.extra"))
})

test_that("a second init without renv activation leaves .Rprofile unchanged", {
  local_ppm_hosts()
  withr::local_envvar(RENV_CONFIG_REPOS_OVERRIDE = NA)
  root <- withr::local_tempdir()
  base_options <- list(
    repos = c(CRAN = "https://packagemanager.posit.co/cran/latest"),
    renv.config.repos.override = NULL,
    boosterpak.configure_repositories = TRUE,
    boosterpak.configure_install_policy = FALSE
  )
  run_init <- function(rprofile) {
    withr::with_options(
      base_options,
      init(root = root, renv = "no", rprofile = rprofile, verbose = FALSE)
    )
  }

  expect_true(run_init("yes")$rprofile_changed)
  before <- readLines(file.path(root, ".Rprofile"), warn = FALSE)
  expect_false(boosterpak:::has_renv_activation(before))

  # Non-interactive "ask" must not abort once the setup is complete.
  expect_false(run_init("ask")$rprofile_changed)
  expect_false(run_init("yes")$rprofile_changed)
  expect_equal(readLines(file.path(root, ".Rprofile"), warn = FALSE), before)
})

test_that("init migrates a block from an earlier hook version to one current block", {
  withr::local_options(list(
    boosterpak.configure_repositories = FALSE,
    boosterpak.configure_install_policy = FALSE
  ))
  root <- withr::local_tempdir()
  old_block <- c(
    boosterpak:::rprofile_startup_begin_marker(),
    sprintf("try(%s)", boosterpak:::rprofile_line()),
    boosterpak:::rprofile_startup_end_marker()
  )
  writeLines(
    c("before <- TRUE", old_block, "after <- TRUE"),
    file.path(root, ".Rprofile")
  )

  result <- init(root = root, renv = "no", rprofile = "yes", verbose = FALSE)

  expect_true(result$rprofile_changed)
  # No activation line, so the current block is appended after the old one
  # is removed.
  expect_equal(
    readLines(file.path(root, ".Rprofile"), warn = FALSE),
    c("before <- TRUE", "after <- TRUE", boosterpak:::rprofile_startup_block())
  )
})

test_that("a failing boosters function file does not stop later function files", {
  root <- withr::local_tempdir()
  dir.create(file.path(root, "boosters"))
  writeLines('stop("broken fn")', file.path(root, "boosters", "fn_a_broken.R"))
  writeLines(
    "options(boosterpak.test.later_fn = TRUE)",
    file.path(root, "boosters", "fn_b_later.R")
  )
  writeLines(boosterpak:::rprofile_startup_block(), file.path(root, ".Rprofile"))
  withr::local_options(list(boosterpak.test.later_fn = NULL))
  withr::local_dir(root)
  env <- new.env(parent = baseenv())

  # try() reports the broken file on stderr.
  out <- capture.output(
    sys.source(".Rprofile", envir = env),
    type = "message"
  )

  expect_true(getOption("boosterpak.test.later_fn"))
  expect_match(paste(out, collapse = "\n"), "broken fn", fixed = TRUE)
})
