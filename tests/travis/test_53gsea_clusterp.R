start <- as.POSIXlt(Sys.time())
library(testthat)
library(hpgltools)
context("53gsea_clusterp.R: Does clusterProfiler work?\n")

load("gsea_siggenes.rda")

dmel_cp <- simple_clusterprofiler(
  sig_genes=z_sig_genes,
  de_table=table,
  do_david=FALSE,
  orgdb="org.Dm.eg.db")

##expected <- c("GO:0001871", "GO:0003690", "GO:0003700",
##              "GO:0004175", "GO:0004222", "GO:0004252")
expected <- c("GO:0000981", "GO:0001871", "GO:0003700",
              "GO:0004175", "GO:0004222", "GO:0004252")
actual <- head(sort(dmel_cp[["enrich_go"]][["MF_all"]][["ID"]]))
test_that("Does the set of MF_all have the expected IDs?", {
    expect_equal(expected, actual)
})

actual <- length(dmel_cp[["enrich_go"]][["MF_all"]][["ID"]])
test_that("Do we get a similar number of MF ids?", {
  expect_gt(actual, 90)
})

##expected <- c("GO:0006022", "GO:0006030", "GO:0006040",
##              "GO:0006812", "GO:0006814", "GO:0006820")
expected <- c("GO:0006022", "GO:0006030", "GO:0006040",
              "GO:0006811", "GO:0006812", "GO:0006814")
actual <- head(sort(dmel_cp[["enrich_go"]][["BP_all"]][["ID"]]))
test_that("Does the set of BP_all have the expected IDs?", {
    expect_equal(expected, actual)
})

actual <- length(dmel_cp[["enrich_go"]][["BP_all"]][["ID"]])
test_that("Do we get a similar number of BP ids?", {
  expect_gt(actual, 10)
})

##expected <- c("GO:0009986", "GO:0031012", "GO:0043235",
##              "GO:0045202", "GO:0097060", "GO:1902495")
expected <- c("GO:0005887", "GO:0009986", "GO:0031012",
              "GO:0031226", "GO:0034702", "GO:0043235")
actual <- head(sort(dmel_cp[["enrich_go"]][["CC_all"]][["ID"]]))
test_that("Does the set of CC_all have the expected IDs?", {
    expect_equal(expected, actual)
})

actual <- length(dmel_cp[["enrich_go"]][["CC_all"]][["ID"]])
test_that("Do we get a similar number of CC ids?", {
  expect_gt(actual, 4)
})

## Gather some scores
expected <- c(9.448405e-07, 9.448405e-07, 5.461374e-06,
              5.461374e-06, 5.253210e-04, 1.071284e-03)
actual <- head(sort(dmel_cp[["enrich_go"]][["MF_sig"]][["p.adjust"]]))
test_that("Does the set of MF_sig have the expected p.adjusts?", {
    expect_equal(expected, actual, tolerance=0.001)
})

##expected <- c(5.177694e-05, 1.848659e-04, 2.963600e-02, 4.130014e-02)
##expected <- c(0.00144974, 0.01596185, 0.01849223, 0.02014316)
expected <- c(0.002813532)
actual <- head(sort(dmel_cp[["enrich_go"]][["BP_sig"]][["p.adjust"]]))
test_that("Does the set of BP_sig have the expected p.adjusts?", {
    expect_equal(expected, actual, tolerance=0.00001)
})

##expected <- c(0.002917828)
expected <- c(5.275610e-07, 5.275610e-07, 1.700242e-04, 8.653117e-03, 1.488470e-02)
actual <- head(sort(dmel_cp[["enrich_go"]][["CC_sig"]][["p.adjust"]]))
test_that("Does the set of CC_sig have the expected p.adjusts?", {
    expect_equal(expected, actual, tolerance=0.0001)
})

##expected <- c("dme00983", "dme00410", "dme00760",
##              "dme00240", "dme00650", "dme00860")
expected <- c("dme00240", "dme00410", "dme00650",
              "dme00760", "dme00860", "dme00983")
actual <- sort(head(rownames(dmel_cp[["kegg_data"]][["kegg_sig"]])))
test_that("Did cp pick up consistent KEGG categories?", {
    expect_equal(expected, actual)
})

expected <- c("GO:0000075", "GO:0000728", "GO:0000734",
              "GO:0000742", "GO:0000743", "GO:0000920")
actual <- head(sort(rownames(dmel_cp[["group_go"]][["BP"]])))
test_that("Does cp find consistent group_go categories in biological processes?", {
    expect_equal(expected, actual)
})

end <- as.POSIXlt(Sys.time())
elapsed <- round(x=as.numeric(end) - as.numeric(start))
message(paste0("\nFinished 53gsea_clusterp.R in ", elapsed,  " seconds."))
tt <- try(clear_session())
