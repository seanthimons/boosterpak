# The curl redirect warning reads these options, so pin them to keep tests
# independent of the session running them.
local_default_download_options <- function(.env = parent.frame()) {
  withr::local_options(
    download.file.method = NULL,
    download.file.extra = NULL,
    .local_envir = .env
  )
}

mock_binary_check <- function(
  type = "binary",
  tag = "4.6-manylinux_2_28",
  status = 200L,
  version = "3.6.6",
  .env = parent.frame()
) {
  local_default_download_options(.env)
  headers <- c(`x-package-type` = type, `x-package-binary-tag` = tag)
  local_mocked_bindings(
    is_linux = function() TRUE,
    fetch_package_version = function(contriburl, package) {
      list(version = version, error = NULL)
    },
    fetch_package_headers = function(url) {
      if (is.null(status)) {
        return(list(error = "Timeout was reached"))
      }
      list(status = status, headers = headers[!is.na(headers)])
    },
    .env = .env
  )
}

ppm_repos <- function() {
  c(CRAN = "https://p3m.dev/cran/__linux__/manylinux_2_28/latest")
}

test_that("parse_response_headers reads only the final response", {
  lines <- c(
    "HTTP/2 302 \r\n",
    "location: https://cdn.example.test/cli.tar.gz\r\n",
    "x-package-type: source\r\n",
    "\r\n",
    "HTTP/2 200 \r\n",
    "Content-Type: binary/octet-stream\r\n",
    "X-Package-Type: binary\r\n",
    "x-package-binary-tag: 4.6-manylinux_2_28\r\n",
    "\r\n"
  )

  headers <- boosterpak:::parse_response_headers(lines)

  expect_equal(headers[["x-package-type"]], "binary")
  expect_equal(headers[["x-package-binary-tag"]], "4.6-manylinux_2_28")
  expect_false("location" %in% names(headers))
  expect_length(boosterpak:::parse_response_headers(character()), 0L)
  expect_length(boosterpak:::parse_response_headers("HTTP/2 200 \r\n"), 0L)
})

test_that("check_binary_repos reports binaries", {
  mock_binary_check()
  local_ppm_hosts()

  expect_no_warning(
    result <- check_binary_repos(ppm_repos(), verbose = FALSE)
  )

  expect_equal(nrow(result), 1L)
  expect_equal(result$name, "CRAN")
  expect_equal(result$package, "cli")
  expect_equal(result$version, "3.6.6")
  expect_equal(result$status, 200L)
  expect_equal(result$package_type, "binary")
  expect_equal(result$binary_tag, "4.6-manylinux_2_28")
  expect_true(result$binary)
  expect_message(
    check_binary_repos(ppm_repos(), verbose = TRUE),
    "serving binary packages"
  )
})

test_that("check_binary_repos warns when Package Manager serves source", {
  mock_binary_check(type = "source", tag = NA)
  local_ppm_hosts()
  repos <- c(CRAN = "https://p3m.dev/cran/latest")

  expect_warning(
    result <- check_binary_repos(repos, verbose = FALSE),
    "serving source packages"
  )
  expect_equal(result$package_type, "source")
  expect_true(is.na(result$binary_tag))
  expect_false(result$binary)
  expect_warning(
    check_binary_repos(repos, verbose = FALSE),
    "__linux__/manylinux_2_28/latest",
    fixed = TRUE
  )
})

test_that("check_binary_repos handles failed and unusual responses", {
  local_ppm_hosts()

  mock_binary_check(status = NULL)
  expect_warning(
    result <- check_binary_repos(ppm_repos(), verbose = FALSE),
    "failed (Timeout was reached)",
    fixed = TRUE
  )
  expect_true(is.na(result$binary))
  expect_equal(result$version, "3.6.6")

  mock_binary_check(status = 404L)
  expect_warning(
    result <- check_binary_repos(ppm_repos(), verbose = FALSE),
    "HTTP 404"
  )
  expect_equal(result$status, 404L)

  mock_binary_check(type = NA, tag = NA)
  expect_warning(
    result <- check_binary_repos(ppm_repos(), verbose = FALSE),
    "no X-Package-Type header"
  )
  expect_true(is.na(result$binary))
})

test_that("check_binary_repos tolerates a missing package", {
  mock_binary_check(version = NA_character_)
  local_ppm_hosts()

  expect_no_warning(
    result <- check_binary_repos(ppm_repos(), verbose = FALSE)
  )
  expect_true(is.na(result$version))
  expect_true(is.na(result$status))
  expect_true(is.na(result$binary))
  expect_message(
    check_binary_repos(ppm_repos(), verbose = TRUE),
    "is not in this repository"
  )
})

test_that("curl_lacks_redirect_flag finds the redirect flag in any form", {
  lacks <- boosterpak:::curl_lacks_redirect_flag
  ua <- '--header "User-Agent: R (4.6.1 x86_64-pc-linux-gnu x86_64 linux-gnu)"'

  # curl without a redirect flag
  expect_true(lacks("curl", NULL))
  expect_true(lacks("curl", character()))
  expect_true(lacks("curl", "-fsS"))
  expect_true(lacks("curl", ua))
  expect_true(lacks("curl", c("-sS", ua)))
  expect_true(lacks("curl", "--limit-rate 1M"))
  expect_true(lacks("curl", '-w "%{http_code}"'))

  # curl with one
  expect_false(lacks("curl", "-L"))
  expect_false(lacks("curl", "-fsSL"))
  expect_false(lacks("curl", "-4L"))
  expect_false(lacks("curl", paste("-fsSL", ua)))
  expect_false(lacks("curl", c("-sS", "-L", ua)))
  expect_false(lacks("curl", "--location"))
  expect_false(lacks("curl", "--location-trusted --fail"))
  expect_false(lacks("curl", paste(ua, "-L")))

  # other methods never need it
  expect_false(lacks(NULL, NULL))
  expect_false(lacks("libcurl", NULL))
  expect_false(lacks("wget", NULL))
  expect_false(lacks("internal", "-fsS"))
})

test_that("check_binary_repos warns when curl cannot follow redirects", {
  mock_binary_check()
  local_ppm_hosts()
  withr::local_options(
    download.file.method = "curl",
    download.file.extra = "-fsS"
  )

  expect_warning(
    result <- check_binary_repos(ppm_repos(), verbose = FALSE),
    "has no .-L."
  )
  # The check itself still ran and passed, which is why the warning exists.
  expect_true(result$binary)
  expect_warning(
    check_binary_repos(ppm_repos(), verbose = FALSE),
    "redirect page"
  )
})

test_that("check_binary_repos stays quiet when redirects are followed", {
  mock_binary_check()
  local_ppm_hosts()

  for (setup in list(
    list(method = "curl", extra = "-fsSL"),
    list(method = "curl", extra = "--location"),
    list(method = "wget", extra = NULL),
    list(method = "libcurl", extra = NULL),
    list(method = NULL, extra = NULL)
  )) {
    withr::local_options(
      download.file.method = setup$method,
      download.file.extra = setup$extra
    )
    expect_no_warning(check_binary_repos(ppm_repos(), verbose = FALSE))
  }
})

test_that("the curl redirect warning needs a Package Manager repository", {
  mock_binary_check()
  local_ppm_hosts()
  withr::local_options(
    download.file.method = "curl",
    download.file.extra = NULL
  )

  expect_no_warning(
    check_binary_repos(c(CRAN = "https://example.test/repo"), verbose = FALSE)
  )
})

test_that("check_binary_repos warns about an unreadable package index", {
  local_ppm_hosts()
  local_default_download_options()
  local_mocked_bindings(
    is_linux = function() TRUE,
    fetch_package_version = function(contriburl, package) {
      list(version = NA_character_, error = "cannot open URL")
    }
  )

  expect_warning(
    result <- check_binary_repos(ppm_repos(), verbose = FALSE),
    "could not read the package index (cannot open URL)",
    fixed = TRUE
  )
  expect_true(is.na(result$binary))
})

test_that("check_binary_repos warns about an unexpected package type", {
  mock_binary_check(type = "mystery")
  local_ppm_hosts()

  expect_warning(
    result <- check_binary_repos(ppm_repos(), verbose = FALSE),
    "unexpected X-Package-Type",
    fixed = FALSE
  )
  expect_false(result$binary)
})

test_that("check_binary_repos explains source on a binary URL", {
  mock_binary_check(type = "source", tag = NA)
  local_ppm_hosts()

  expect_warning(
    check_binary_repos(ppm_repos(), verbose = FALSE),
    "already selects binaries.*HTTPUserAgent"
  )
})

test_that("the source hint depends on the repository URL", {
  local_ppm_hosts()

  generic <- boosterpak:::source_hint("https://p3m.dev/cran/latest/")
  expect_match(generic, "__linux__/manylinux_2_28/latest", fixed = TRUE)
  expect_false(grepl("//", sub("https://", "", generic, fixed = TRUE), fixed = TRUE))

  linux <- boosterpak:::source_hint(
    "https://p3m.dev/cran/__linux__/manylinux_2_28/latest"
  )
  expect_match(linux, "already selects binaries", fixed = TRUE)
  expect_match(linux, "HTTPUserAgent", fixed = TRUE)

  # A distro URL is not a manylinux URL, so it gets neither of the above.
  distro <- boosterpak:::source_hint(
    "https://p3m.dev/cran/__linux__/noble/latest"
  )
  expect_false(grepl("already selects binaries", distro, fixed = TRUE))
  expect_match(distro, "Use a binary URL for your platform", fixed = TRUE)

  # Braces in a URL must not be read as cli templates.
  braces <- boosterpak:::source_hint("https://p3m.dev/cra{n}/latest")
  expect_no_error(cli::format_inline(braces))
})

test_that("check_binary_repos skips other repositories and handles many", {
  mock_binary_check()
  local_ppm_hosts()
  repos <- c(
    CRAN = "https://p3m.dev/cran/__linux__/manylinux_2_28/latest",
    Internal = "https://example.test/repo",
    Snap = "https://p3m.dev/cran/__linux__/manylinux_2_28/2026-01-02"
  )

  result <- check_binary_repos(repos, verbose = FALSE)

  expect_equal(result$name, c("CRAN", "Snap"))
  expect_equal(nrow(result), 2L)

  result <- check_binary_repos(
    unname(repos[1]),
    verbose = FALSE
  )
  expect_equal(result$name, "")

  expect_message(
    result <- check_binary_repos(c(CRAN = "https://example.test/repo"), verbose = TRUE),
    "No Posit Package Manager repositories"
  )
  expect_equal(nrow(result), 0L)
})

test_that("check_binary_repos recognizes self-hosted Package Manager hosts", {
  mock_binary_check()
  local_ppm_hosts(repo = "https://ppm.corp.test/team-cran/latest")

  result <- check_binary_repos(
    c(Team = "https://ppm.corp.test/team-cran/__linux__/manylinux_2_28/latest"),
    verbose = FALSE
  )

  expect_equal(nrow(result), 1L)
  expect_true(result$binary)
})

test_that("check_binary_repos only runs on Linux", {
  local_mocked_bindings(
    is_linux = function() FALSE,
    fetch_package_version = function(...) stop("unexpected request"),
    fetch_package_headers = function(...) stop("unexpected request")
  )

  expect_message(
    result <- check_binary_repos(ppm_repos(), verbose = TRUE),
    "only supports Linux"
  )
  expect_equal(nrow(result), 0L)
  expect_named(
    result,
    c(
      "repo", "name", "package", "version", "status", "package_type",
      "binary_tag", "binary"
    )
  )
})

test_that("check_binary_repos validates its arguments", {
  expect_error(check_binary_repos(package = NA_character_), "single package name")
  expect_error(check_binary_repos(package = c("a", "b")), "single package name")
  expect_error(check_binary_repos(verbose = "yes"), "verbose")
})

test_that("check_binary_repos sees binaries on Package Manager", {
  skip_on_cran()
  skip_if_not(identical(R.version$os, "linux-gnu"))
  skip_if(grepl("development", R.version$status))
  skip_if_not_installed("curl")
  skip_if_offline("p3m.dev")
  local_ppm_hosts()
  local_default_download_options()
  withr::local_options(HTTPUserAgent = sprintf(
    "R/%s R (%s)",
    getRversion(),
    paste(getRversion(), R.version$platform, R.version$arch, R.version$os)
  ))
  manylinux <- "https://p3m.dev/cran/__linux__/manylinux_2_28/latest"
  generic <- "https://p3m.dev/cran/latest"

  binary <- check_binary_repos(c(CRAN = manylinux), verbose = FALSE)
  expect_equal(binary$status, 200L)
  expect_equal(binary$package_type, "binary")
  expect_match(binary$binary_tag, "manylinux_2_28", fixed = TRUE)
  expect_true(binary$binary)

  expect_warning(
    source <- check_binary_repos(c(CRAN = generic), verbose = FALSE),
    "serving source packages"
  )
  expect_equal(source$package_type, "source")
  expect_false(source$binary)
})

test_that("fetch_package_version reads a repository package index", {
  repo <- withr::local_tempdir()
  contrib <- file.path(repo, "src", "contrib")
  dir.create(contrib, recursive = TRUE)
  writeLines(
    c("Package: cli", "Version: 3.6.6", "", "Package: other", "Version: 1.0"),
    file.path(contrib, "PACKAGES")
  )
  contriburl <- paste0("file://", contrib)

  found <- boosterpak:::fetch_package_version(contriburl, "cli")
  expect_equal(found$version, "3.6.6")
  expect_null(found$error)

  missing <- boosterpak:::fetch_package_version(contriburl, "absent")
  expect_true(is.na(missing$version))
  expect_null(missing$error)

  unreadable <- boosterpak:::fetch_package_version(
    paste0("file://", file.path(repo, "nowhere")),
    "cli"
  )
  expect_true(is.na(unreadable$version))
  expect_type(unreadable$error, "character")
})

test_that("fetch_package_headers reports request failures", {
  skip_if_not_installed("curl")

  response <- boosterpak:::fetch_package_headers("http://127.0.0.1:1/cli_1.0.tar.gz")

  expect_type(response$error, "character")
  expect_null(response$status)
})
