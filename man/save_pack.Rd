\name{save_pack}
\alias{save_pack}
\title{Save a resolved package set as a pack}
\usage{
save_pack(
  name,
  scope = c("project", "user"),
  from = NULL,
  root = ".",
  overwrite = FALSE,
  verbose = NULL
)
}
\arguments{
\item{name}{Pack name to write.}

\item{scope}{Destination scope: \code{"project"} or \code{"user"}.}

\item{from}{Optional existing pack name to fork. When \code{NULL}, captures the current project's resolved package set.}

\item{root}{Project root.}

\item{overwrite}{Whether to replace an existing pack file.}

\item{verbose}{Whether to print routine summaries.}
}
\value{
Path to the saved pack, invisibly.
}
\description{
Save a resolved package set as a pack
}
