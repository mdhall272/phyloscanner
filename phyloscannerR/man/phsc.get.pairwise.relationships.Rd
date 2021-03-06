% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/multinomial_functions.R
\name{phsc.get.pairwise.relationships}
\alias{phsc.get.pairwise.relationships}
\title{Calculate pairwise relationships}
\usage{
phsc.get.pairwise.relationships(df, get.groups = c("TYPE_PAIR_DI2",
  "TYPE_PAIR_TO", "TYPE_PAIR_TODI2x2", "TYPE_PAIR_TODI2", "TYPE_DIR_TODI2",
  "TYPE_NETWORK_SCORES", "TYPE_CHAIN_TODI", "TYPE_ADJ_NETWORK_SCORES",
  "TYPE_ADJ_DIR_TODI2"))
}
\arguments{
\item{df}{data.table to which new columns of relationship groups will be added. Must contain a column with name TYPE_BASIC. This column contains fundamental relationship states for every window, from which other relationships are derived.}

\item{get.groups}{names of relationship groups}
}
\value{
input data.table with new columns. Each new column defines relationship states for a specific relationship group.
}
\description{
This function calculates pairwise relationships of two individuals in any window. Several different relationship groups can be calculated, for example just using pairwise distance, or using both pairwise distance and topology to define likely pairs.
}
\keyword{internal}
