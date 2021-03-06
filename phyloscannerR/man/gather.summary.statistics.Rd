% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/main_analysis.R
\name{gather.summary.statistics}
\alias{gather.summary.statistics}
\title{Make a \code{data.table} of per-window host statistics}
\usage{
gather.summary.statistics(phyloscanner.trees,
  hosts = all.hosts.from.trees(phyloscanner.trees),
  tip.regex = "^(.*)_read_([0-9]+)_count_([0-9]+)$", verbose = F)
}
\arguments{
\item{phyloscanner.trees}{A list of class \code{phyloscanner.trees}}

\item{hosts}{A list of hosts to record statistics for. If not specified, every identifiable host in \code{phyloscanner.trees}}

\item{tip.regex}{Regular expression identifying tips from the dataset. This expects up to three capture groups, for host ID, read ID, and read count (in that order). If the latter two groups are missing then read information will not be used. The default matches input from the phyloscanner pipeline where the host ID is the BAM file name.}

\item{verbose}{Produce verbose output}
}
\value{
A \code{data.table}
}
\description{
This function collects per-window statistics on hosts
}
