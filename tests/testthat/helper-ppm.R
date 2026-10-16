# The managed Linux binary line exactly as boosterpak 0.9.2 wrote it. Kept as a
# literal so upgrade tests do not depend on the current generator.
v092_ppm_linux_line <- function(include_renv = TRUE) {
  rewrite <- function(option) {
    sprintf(
      paste0(
        'sub("^(https://packagemanager\\\\.(posit|rstudio)\\\\.co/cran)/',
        '(latest|[0-9]{4}-[0-9]{2}-[0-9]{2})$", ',
        '"\\\\1/__linux__/manylinux_2_28/\\\\3", getOption("%s"))'
      ),
      option
    )
  }
  args <- c(
    sprintf("repos = %s", rewrite("repos")),
    if (include_renv) {
      sprintf(
        "renv.config.repos.override = %s",
        rewrite("renv.config.repos.override")
      )
    },
    paste0(
      'HTTPUserAgent = sprintf("R/%s R (%s)", getRversion(), ',
      "paste(getRversion(), R.version$platform, R.version$arch, R.version$os))"
    )
  )
  paste0(
    'if (identical(R.version$os, "linux-gnu")) ',
    sprintf("options(%s)", paste(args, collapse = ", "))
  )
}

# Reset the once-per-session invalid host warning between tests.
local_ppm_hosts <- function(
  hosts = NULL,
  env_hosts = NA,
  repo = NA,
  .env = parent.frame()
) {
  withr::local_options(boosterpak.ppm_hosts = hosts, .local_envir = .env)
  withr::local_envvar(
    BOOSTERPAK_PPM_HOSTS = env_hosts,
    BOOSTERPAK_PPM_REPO = repo,
    .local_envir = .env
  )
  rm(list = ls(boosterpak:::ppm_state), envir = boosterpak:::ppm_state)
}
