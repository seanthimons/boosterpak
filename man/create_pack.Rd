\name{create_pack}
\alias{create_pack}
\title{Create a new pack from declared intent}
\usage{
create_pack(
  name,
  packages = character(),
  root = ".",
  scope = "project",
  description = NULL,
  extends = NULL,
  attach = c("ask", "all", "some", "none"),
  function_template = c("ask", "yes", "no"),
  overwrite = FALSE,
  verbose = NULL
)
}
\arguments{
\item{name}{Pack name to write. The name is also used as the TOML \code{name} and file name.}
\item{packages}{Character vector of package specs. Plain package names are written to \code{packages}; source-specific specs are preserved in \code{[sources]}.}
\item{root}{Project root.}
\item{scope}{Destination scope: \code{"project"} or \code{"user"}.}
\item{description}{Optional pack description.}
\item{extends}{Optional character vector of known pack names to extend.}
\item{attach}{Attach intent: \code{"ask"}, \code{"all"}, \code{"some"}, \code{"none"}, or a character vector of package names to attach.}
\item{function_template}{Whether to create a nested function sidecar template: \code{"ask"}, \code{"yes"}, or \code{"no"}.}
\item{overwrite}{Whether to replace an existing pack file or template.}
\item{verbose}{Whether to print routine summaries.}
}
\value{
Path to the created pack, invisibly.
}
\description{
\code{create_pack()} writes a pack manifest from package specs you provide. It does not add the pack to \code{boosters.toml}, install packages, sync \code{renv}, or copy functions into the project.
}
