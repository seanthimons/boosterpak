geo_mean <- function(x, na.rm = FALSE) {
  if (na.rm) {
    x <- x[!is.na(x)]
  }
  if (any(is.na(x))) {
    return(NA_real_)
  }
  if (length(x) == 0 || any(x <= 0)) {
    return(NA_real_)
  }
  exp(mean(log(x)))
}
