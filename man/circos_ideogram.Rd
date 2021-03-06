% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/plot_circos.r
\name{circos_ideogram}
\alias{circos_ideogram}
\title{Create the description of chromosome markings.}
\usage{
circos_ideogram(name = "default", conf_dir = "circos/conf",
  band_url = NULL, fill = "yes", stroke_color = "black",
  thickness = "20", stroke_thickness = "2", fill_color = "black",
  radius = "0.85", label_size = "36", band_stroke_thickness = "2")
}
\arguments{
\item{name}{Name of the configuration file to which to add the ideogram.}

\item{conf_dir}{Where does the configuration live?}

\item{band_url}{Provide a url for making these imagemaps?}

\item{fill}{Fill in the strokes?}

\item{stroke_color}{What color?}

\item{thickness}{How thick to color the lines}

\item{stroke_thickness}{How much of them to fill in}

\item{fill_color}{What color to fill}

\item{radius}{Where on the circle to put them}

\item{label_size}{How large to make the labels in px.}

\item{band_stroke_thickness}{How big to make the strokes!}
}
\value{
The file to which the ideogram configuration was written.
}
\description{
This function writes ideogram files for circos.
}
