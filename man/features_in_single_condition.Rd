% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/expt.r
\name{features_in_single_condition}
\alias{features_in_single_condition}
\title{I want an easy way to answer the question: what features are in condition x but no others.}
\usage{
features_in_single_condition(expt, cutoff = 2)
}
\arguments{
\item{expt}{An experiment to query.}

\item{cutoff}{What is the minimum number of counts required to define
'included.'}
}
\value{
A set of features.
}
\description{
The answer to this lies in a combination of subset_expt() and
features_greater_than().
}
