% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/annotation_uniprot.r
\name{download_uniprot_proteome}
\alias{download_uniprot_proteome}
\title{Download the txt uniprot data for a given accession/species}
\usage{
download_uniprot_proteome(accession = NULL, species = NULL,
  all = FALSE, first = FALSE)
}
\arguments{
\item{accession}{Which accession to grab?}

\item{species}{Or perhaps species?}

\item{all}{If there are more than 1 hit, grab them all?}

\item{first}{Or perhaps just grab the first hit?}
}
\value{
A filename/accession tuple.
}
\description{
Download the txt uniprot data for a given accession/species
}
