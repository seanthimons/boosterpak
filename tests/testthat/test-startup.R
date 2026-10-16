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
  expect_equal(hook_line, renv_line + 1L)
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
  expect_equal(sum(lines == boosterpak:::rprofile_ppm_linux_binary_line()), 1L)
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
    expect_equal(
      sum(vapply(lines, boosterpak:::is_rprofile_ppm_linux_line, logical(1))),
      1L
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
