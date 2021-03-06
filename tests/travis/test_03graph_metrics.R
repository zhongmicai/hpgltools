start <- as.POSIXlt(Sys.time())
library(testthat)
library(hpgltools)
context("03graph_metrics.R: Is it possible to graph the various metrics with hpgltools?
  1234567890123456789\n")

pasilla <- new.env()
load("pasilla.Rdata", envir=pasilla)
pasilla_expt <- pasilla[["expt"]]
## Uses these genes for quick tests
test_genes <- c("FBgn0000014", "FBgn0000008", "FBgn0000017", "FBgn0000018", "FBgn0000024")

## I am not sure if I should test this yet, it is slow.
if (isTRUE(FALSE)) {
    written <- write_expt(pasilla_expt, excel="pasilla_written.xlsx")
}

## What graphs can we make!?
libsize_plot <- plot_libsize(pasilla_expt)
actual <- libsize_plot[["table"]][["sum"]]
expected <- c(13971670, 21909886, 8357876, 9840745, 18668667, 9571213, 10343219)
## 01
test_that("The libsize plot is as expected?", {
    expect_equal(expected, actual)
})

nonzero_plot <- plot_nonzero(pasilla_expt)
actual <- nonzero_plot[["table"]][["nonzero_genes"]]
expected <- c(9863, 10074, 9730, 9786, 10087, 9798, 9797)
## 02
test_that("The non-zero genes is as expected?", {
    expect_equal(expected, actual)
})

## These tests have also been affected by the changed order of expressionsets.
density <- sm(plot_density(pasilla_expt))
density_plot <- density[["plot"]]
density_table <- density[["table"]]
expected <- c(92, 5, 4664, 583, 10, 1446)
actual <- head(density_table[["counts"]])
## 03
test_that("Density plot data is as expected?", {
    expect_equal(expected, actual)
})

hist_plot <- sm(plot_histogram(data.frame(exprs(pasilla_expt))))
actual <- head(hist_plot[["data"]][["values"]])
## The values of expected have not changed
## 04
test_that("Histogram data is as expected?", {
    expect_equal(expected, actual)
})

box_plot <- sm(plot_boxplot(pasilla_expt))
actual <- head(box_plot[["data"]][["value"]])
## 05
test_that("Box plot data is as expected?", {
    expect_equal(expected, actual, tolerance=1)
})

## Ahh yes I changed the cbcb_filter options to match those from the cbcbSEQ vignette.
## Note that the filtering has changed slightly, and this affects the results.
norm <- sm(normalize_expt(pasilla_expt, transform="log2", convert="cbcbcpm",
                          norm="quant", filter=TRUE))
expected <- "recordedplot"  ## for all the heatmaps

corheat_plot <- plot_corheat(norm)
actual <- class(corheat_plot[["plot"]])
## 06
test_that("corheat is a recorded plot?", {
    expect_equal(expected, actual)
})

disheat_plot <- plot_disheat(norm)
actual <- class(disheat_plot[["plot"]])
## 07
test_that("disheat is a recorded plot?", {
    expect_equal(expected, actual)
})

sampleheat_plot <- plot_sample_heatmap(norm)
actual <- class(sampleheat_plot)
## 08
test_that("sampleheat is a recorded plot?", {
    expect_equal(expected, actual)
})

smc_plot <- sm(plot_sm(norm, method="pearson"))
actual <- head(smc_plot[["data"]][["sm"]])
expected <- c(0.9759981, 0.9824316, 0.9759981, 0.9821373, 0.9784851, 0.9786376)
## 09
test_that("Is the normalized smc data expected?", {
    expect_equal(expected, actual, tolerance=0.004)
})

smd_plot <- sm(plot_sm(norm, method="euclidean"))
actual <- head(smd_plot[["data"]][["sm"]])
## 201812 Changed due to peculiarities in normalization methods.
##expected <- c(42.31502, 36.20613, 42.31502, 36.50773, 40.07146, 39.92637)
expected <- c(42.13977, 36.04136, 42.13977, 36.27883, 40.12076, 39.91451)
## 10
test_that("Is the normalized smd data expected?", {
    expect_equal(expected, actual, tolerance=0.001)
})

pca_stuff <- plot_pca(norm)
pca_plot <- pca_stuff[["plot"]]
pca_pca <- head(pca_stuff[["pca"]])

actual <- pca_plot[["data"]][["PC1"]]
## Ibid
##expected <- c(-0.3588028, -0.4049142, -0.2719889, -0.2427446, 0.2857222, 0.4986218, 0.4941065)
expected <- c(-0.3543755, -0.4013780, -0.2786620, -0.2487583, 0.2988357, 0.4950893, 0.4892487)
## 11
test_that("Is the pca data as expected for PC1?", {
    expect_equal(expected, actual, tolerance=0.01)
})

actual <- as.numeric(head(pca_stuff[["result"]][["v"]][, 1]))
## Ibid
##expected <- c(-0.3588028, -0.4049142, -0.2719889, -0.2427446, 0.2857222, 0.4986218)
expected <- c(-0.3543755, -0.4013780, -0.2786620, -0.2487583, 0.2988357, 0.4950893)
## 12
test_that("Is the SVD 'v' element expected?", {
    expect_equal(expected, actual, tolerance=0.01)
})

actual <- pca_stuff[["residual_df"]][[1]]
##expected <- c(42.54, 31.18, 13.13, 5.80, 4.13, 3.23)
expected <- c(42.76, 30.79, 13.28, 5.81, 4.12, 3.24)
## 13
test_that("Is the pca residual table as expected?", {
    expect_equal(expected, actual, tolerance=0.01)
})

actual <- pca_stuff[["prop_var"]]
##expected <- c(42.54, 31.18, 13.13, 5.80, 4.13, 3.23)
expected <- c(42.64, 30.89, 13.24, 5.86, 4.12, 3.25)
## 14
test_that("Is the variance list as expected?", {
    expect_equal(expected, actual, tolerance=0.01)
})

actual <- pca_stuff[["table"]][["PC2"]]
##expected <- c(0.3023078, 0.2728941, -0.4563121, -0.3892918, 0.6362636, -0.1467970, -0.2190646)
expected <- c(0.3072078, 0.2773027, -0.4492433, -0.3832709, 0.6343609, -0.1547031, -0.2316542)
## 15
test_that("Is the PCA PC2 as expected?", {
    expect_equal(expected, actual, tolerance=0.01)
})

tsne_stuff <- plot_tsne(norm, seed=1)
tsne_stuff$plot
actual <- tsne_stuff[["table"]][["Factor1"]]
##expected <- c(-498.6079, -491.3404, -159.4492, -167.6300, 450.3194, 437.5517, 429.1564)
expected <- c(-1125.1750, -1125.0970, -172.6207, -165.0895, 868.7556, 861.8851, 857.3414)
## These values seem to have changed in the new version of Rtsne.
## 16
test_that("Is the tsne data as expected for Comp1?", {
    expect_equal(expected, actual, tolerance=0.1)
})

actual <- as.numeric(head(tsne_stuff[["result"]][["Y"]][, 2]))
##expected <- c(103.6740, 99.5090, 5.1610, 0.9747, -68.0061, -70.0072)
##expected <- c(394.14239, 398.38090, -466.51450, -464.56575, 49.16611, 45.80158)
expected <- c(59.58659, 36.45026, 129.30037, 151.02012, -94.02516, -129.49206)
## These also changed.
## 17
test_that("Is the tsne second component data expected?", {
    expect_equal(expected, actual, tolerance=0.001)
})

actual <- head(tsne_stuff[["residual_df"]][["condition_rsquared"]])
##expected <- c(0.90183647, 0.01485401, 0.90183647, 0.01485401, 0.90183647, 0.01485401)
expected <- c(0.8103159, 0.8848959, 0.8103159, 0.8848959, 0.8103159, 0.8848959)
##expected <- c(99.74, 79.80)
## 18
test_that("Is the tsne r-squared by condition as expected?", {
    expect_equal(expected, actual, tolerance=0.001)
})

end <- as.POSIXlt(Sys.time())
elapsed <- round(x=as.numeric(end) - as.numeric(start))
message(paste0("\nFinished 03graph_metrics.R in ", elapsed, " seconds."))
tt <- try(clear_session())
