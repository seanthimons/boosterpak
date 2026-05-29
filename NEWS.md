# boosterpak 0.5.0.9000

- `init(renv = "yes")` now initializes and loads `renv` without an immediate restart, installs the bootstrap workflow packages `pak`, `renv`, and `boosterpak` into the project library, and snapshots them when `auto_snapshot = true`.
- The built-in `core` pack is now minimal (`pak`, `renv`). The previous analysis-oriented package set is available as the new `eda` pack.
- Projects initialized with boosterpak 0.5 can recover by running:

  ```r
  install.packages("renv")
  renv::install(c("pak", "seanthimons/boosterpak"))
  renv::snapshot(packages = c("renv", "pak", "boosterpak"), prompt = FALSE)
  ```

  Then restart R and run `boosterpak::sync()`.
