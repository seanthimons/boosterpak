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
  hook_line <- match(boosterpak:::rprofile_line(), lines)

  expect_equal(marker, renv_line - 3L)
  expect_equal(
    lines[[marker + 1L]],
    'options(repos = c(CRAN = "https://packagemanager.posit.co/cran/latest"))'
  )
  expect_equal(
    lines[[marker + 2L]],
    'options(renv.config.repos.override = c(CRAN = "https://packagemanager.posit.co/cran/latest"))'
  )
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
