% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/model_varpartition.r
\name{simple_varpart}
\alias{simple_varpart}
\title{Use variancePartition to try and understand where the variance lies in a data set.}
\usage{
simple_varpart(expt, predictor = NULL, factors = c("condition",
  "batch"), chosen_factor = "batch", do_fit = FALSE, cor_gene = 1,
  cpus = 6, genes = 40, parallel = TRUE, modify_expt = TRUE)
}
\arguments{
\item{expt}{Some data}

\item{predictor}{Non-categorical predictor factor with which to begin the
model.}

\item{factors}{Character list of columns in the experiment design to query}

\item{chosen_factor}{When checking for sane 'batches', what column to
extract from the design?}

\item{do_fit}{Perform a fitting using variancePartition?}

\item{cor_gene}{Provide a set of genes to look at the correlations, defaults
to the first gene.}

\item{cpus}{Number cpus to use}

\item{genes}{Number of genes to count.}

\item{parallel}{use doParallel?}

\item{modify_expt}{Add annotation columns with the variance/factor?}
}
\value{
partitions  List of plots and variance data frames
}
\description{
variancePartition is the newest toy introduced by Hector.
}
\details{
Tested in 19varpart.R.
}
\seealso{
\pkg{doParallel} \pkg{variancePartition}
}
