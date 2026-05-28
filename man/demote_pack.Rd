\name{demote_pack}
\alias{demote_pack}
\title{Demote a user pack to project scope}
\usage{
demote_pack(name, root = ".", overwrite = FALSE, verbose = NULL)
}
\arguments{
\item{name}{Pack name.}

\item{root}{Project root.}

\item{overwrite}{Whether to replace an existing project-scope pack.}

\item{verbose}{Whether to print routine summaries.}
}
\value{
Path to the copied project-scope pack, invisibly.
}
\description{
Demote a user pack to project scope
}
