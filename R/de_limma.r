#' A minor change to limma's voom with quality weights to attempt to address some corner cases.
#'
#' This copies the logic employed in hpgl_voom().  I suspect one should not use it.
#'
#' @param data  Some data!
#' @param fun_model  A model for voom() and arrayWeights()
#' @param libsize  Library sizes passed to voom().
#' @param normalize.method  Passed to voom()
#' @param plot  Do the plot of mean variance?
#' @param span  yes
#' @param var.design maybe
#' @param method kitty!
#' @param maxiter 50 is good
#' @param tol I have no tolerance.
#' @param trace no trace for you.
#' @param replace.weights  Replace the weights?
#' @param col yay columns!
#' @param ... more arguments!
#' @return a voom return
#' @seealso \pkg{limma}
#' @examples
#' \dontrun{
#' ## No seriously, dont run this, I think it is wiser to use the functions provided by limma.
#' ## But this provides a place to test stuff out.
#'  voom_result <- hpgl_voomweighted(dataset, model)
#' }
#' @export
hpgl_voomweighted <- function(data, fun_model, libsize=NULL, normalize.method="none",
                              plot=TRUE, span=0.5, var.design=NULL, method="genebygene",
                              maxiter=50, tol=1E-10, trace=FALSE, replace.weights=TRUE,
                              col=NULL, ...) {

  if (isTRUE(plot)) {
    oldpar <- par(mfrow = c(1, 2))
    on.exit(par(oldpar))
  }
  v1 <- hpgl_voom(data, model=fun_model, libsize=libsize,
                  normalize.method = normalize.method,
                  plot=TRUE, span=span, ...)
  aw <- try(limma::arrayWeights(v1, design=fun_model, method=method, maxiter=maxiter,
                                tol=tol, var.design=var.design))
  if (class(aw) == "try-error") {
    message("arrayWeights failed, returning the voom result.")
    return(v1)
  }
  v <- hpgl_voom(data, model=fun_model, weights=aw, libsize=libsize,
                 normalize.method=normalize.method, plot=TRUE, span=span, ...)
  aw <- limma::arrayWeights(v, design=fun_model, method=method, maxiter=maxiter,
                            tol=tol, trace=trace, var.design=var.design)
  wts <- limma::asMatrixWeights(aw, dim(v)) * v[["weights"]]
  attr(wts, "arrayweights") <- NULL
  if (plot) {
    barplot(aw, names = 1:length(aw), main = "Sample-specific weights",
            ylab = "Weight", xlab = "Sample", col = col)
    abline(h = 1, col = 2, lty = 2)
    voom_barplot <- grDevices::recordPlot()
  }
  if (replace.weights) {
    v[["weights"]] <- wts
    v[["sample.weights"]] <- aw
    v[["barplot"]] <- voom_barplot
    v[["first_iter"]] <- v1
    return(v)
  } else {
    return(wts)
  }
}

#' A slight modification of limma's voom().
#'
#' Estimate mean-variance relationship between samples and generate 'observational-level weights' in
#' preparation for linear modeling RNAseq data.  This particular implementation was primarily
#' scabbed from cbcbSEQ, but changes the mean-variance plot slightly and attempts to handle corner
#' cases where the sample design is confounded by setting the coefficient to 1 for those samples
#' rather than throwing an unhelpful error.  Also, the Elist output gets a 'plot' slot which
#' contains the plot rather than just printing it.
#'
#' @param dataframe  Dataframe of sample counts which have been normalized and log transformed.
#' @param model  Experimental model defining batches/conditions/etc.
#' @param libsize  Size of the libraries (usually provided by edgeR).
#' @param normalize.method  Normalization method used in voom().
#' @param span  The span used in voom().
#' @param stupid  Cheat when the resulting matrix is not solvable?
#' @param logged  Is the input data is known to be logged?
#' @param converted  Is the input data is known to be cpm converted?
#' @param ...  Extra arguments are passed to arglist.
#' @return EList containing the following information:
#'  E = The normalized data
#'  weights = The weights of said data
#'  design = The resulting design
#'  lib.size = The size in pseudocounts of the library
#'  plot = A ggplot of the mean/variance trend with a blue loess fit and red trend fit
#' @seealso \pkg{limma} \pkg{ggplot2}
#' @examples
#' \dontrun{
#'  funkytown = hpgl_voom(samples, model)
#' }
#' @export
hpgl_voom <- function(dataframe, model=NULL, libsize=NULL,
                      normalize.method="none", span=0.5,
                      stupid=FALSE, logged=FALSE, converted=FALSE, ...) {
  arglist <- list(...)
  ## Going to attempt to as closely as possible dovetail the original implementation.
  ## I think at this point, my implementation is the same as the original with the exception
  ## of a couple of tests to check that the data is not fubar and I think my plot is prettier.
  counts <- dataframe
  out <- list()
  if (is(counts, "DGEList")) {
    out[["genes"]] <- counts[["genes"]]
    out[["targets"]] <- counts[["samples"]]
    if (is.null(model) &&
        diff(range(as.numeric(counts[["sample"]][["group"]]))) > 0) {
      model <- model.matrix(~group, data = counts[["samples"]])
    }
    if (is.null(libsize)) {
      ## libsize <- with(counts[["samples"]], libsize * norm.factors)
      ## This is a bit confusing.
      libsize <- with(counts[["samples"]], counts[["libsize"]] * counts[["norm.factors"]])
    }
    counts <- counts[["counts"]]
  } else {
    isExpressionSet <- sm(is(counts, "ExpressionSet"))
    if (isExpressionSet) {
      if (length(fData(counts))) {
        out[["genes"]] <- fData(counts)
      }
      if (length(pData(counts))) {
        out[["targets"]] <- pData(counts)
      }
      counts <- exprs(counts)
    } else {
      counts <- as.matrix(counts)
    }
  }
  if (is.null(model)) {
    model <- matrix(1, ncol(counts), 1)
    rownames(model) <- colnames(counts)
    colnames(model) <- "GrandMean"
  }
  if (is.null(libsize)) {
    libsize <- colSums(dataframe, na.rm=TRUE)
  }
  if (converted == "cpm") {
    converted <- TRUE
  }
  if (!isTRUE(converted)) {
    message("The voom input was not cpm, converting now.")
    posed <- t(dataframe + 0.5)
    dataframe <- t(posed / (libsize + 1) * 1e+06)
    ##y <- t(log2(t(counts + 0.5)/(lib.size + 1) * 1000000)) ## from voom()
  }
  if (logged == "log2") {
    logged <- TRUE
  }
  if (isTRUE(logged)) {
    if (max(dataframe) > 1000) {
      warning("This data appears to not be logged, the lmfit will do weird things.")
    }
  } else {
    if (max(dataframe) < 200) {
      warning("This data says it was not logged, but the maximum counts seem small.")
      warning("If it really was log2 transformed, then we are about to double-log it and that would be very bad.")
    }
    message("The voom input was not log2, transforming now.")
    dataframe <- log2(dataframe)
  }
  dataframe <- as.matrix(dataframe)
  dataframe <- limma::normalizeBetweenArrays(dataframe, method=normalize.method)


  linear_fit <- limma::lmFit(dataframe, model, method="ls")
  if (is.null(linear_fit[["Amean"]])) {
    linear_fit[["Amean"]] <- rowMeans(dataframe, na.rm=TRUE)
  }
  sx <- linear_fit[["Amean"]] + mean(log2(libsize + 1)) - log2(1e+06)
  sy <- sqrt(linear_fit[["sigma"]])
  if (is.na(sum(sy))) {
    ## 1 replicate
    return(NULL)
  }
  allzero <- rowSums(dataframe) == 0
  stupid_NAs <- is.na(sx)
  sx <- sx[!stupid_NAs]
  stupid_NAs <- is.na(sy)
  sy <- sy[!stupid_NAs]
  if (any(allzero == TRUE, na.rm=TRUE)) {
    sx <- sx[!allzero]
    sy <- sy[!allzero]
  }
  fitted <- gplots::lowess(sx, sy, f=0.5)
  f <- stats::approxfun(fitted, rule=2)
  mean_var_df <- data.frame(mean=sx, var=sy)
  mean_var_plot <- ggplot2::ggplot(mean_var_df, ggplot2::aes_string(x="mean", y="var")) +
    ggplot2::geom_point() +
    ggplot2::xlab("Log2(count size + 0.5)") +
    ggplot2::ylab("Square root of the standard deviation.") +
    ggplot2::stat_density2d(geom="tile", ggplot2::aes_string(fill="..density..^0.25"),
                            contour=FALSE, show.legend=FALSE) +
    ggplot2::scale_fill_gradientn(colours=grDevices::colorRampPalette(c("white", "black"))(256)) +
    ggplot2::geom_smooth(method="loess") +
    ggplot2::stat_function(fun=f, colour="red") +
    ggplot2::theme(legend.position="none")
  if (is.null(linear_fit[["rank"]])) {
    message("Some samples cannot be balanced across the experimental design.")
    if (isTRUE(stupid)) {
      ## I think this is telling me I have confounded data, and so
      ## for those replicates I will have no usable coefficients, so
      ## I say set them to 1 and leave them alone.
      linear_fit[["coefficients"]][is.na(linear_fit[["coefficients"]])] <- 1
      fitted.values <- linear_fit[["coefficients"]] %*%
        t(linear_fit[["design"]])
    }
  } else if (linear_fit[["rank"]] < ncol(linear_fit[["design"]])) {
    j <- linear_fit[["pivot"]][1:linear_fit[["rank"]]]
    fitted.values <- linear_fit[["coefficients"]][, j, drop=FALSE] %*%
      t(linear_fit[["design"]][, j, drop=FALSE])
  } else {
    fitted.values <- linear_fit[["coefficients"]] %*%
      t(linear_fit[["design"]])
  }
  fitted.cpm <- 2 ^ fitted.values
  fitted.count <- 1e-06 * t(t(fitted.cpm) * (libsize + 1.0))
  fitted.logcount <- log2(fitted.count)
  w <- 1 / f(fitted.logcount) ^ 4
  dim(w) <- dim(fitted.logcount)
  rownames(w) <- rownames(dataframe)
  colnames(w) <- colnames(dataframe)
  out[["E"]] <- dataframe
  out[["weights"]] <- w
  out[["design"]] <- model
  out[["lib.size"]] <- libsize
  out[["plot"]] <- mean_var_plot
  new("EList", out)
}

#' Set up a model matrix and set of contrasts for pairwise comparisons using voom/limma.
#'
#' Creates the set of all possible contrasts and performs them using voom/limma.
#'
#' @param input Dataframe/vector or expt class containing count tables, normalization state, etc.
#' @param conditions Factor of conditions in the experiment.
#' @param batches Factor of batches in the experiment.
#' @param model_cond Include condition in the model?
#' @param model_batch Include batch in the model? This is hopefully TRUE.
#' @param model_intercept Perform a cell-means or intercept model? A little more difficult for me to
#'  understand.  I have tested and get the same answer either way.
#' @param extra_contrasts Some extra contrasts to add to the list.
#'  This can be pretty neat, lets say one has conditions A,B,C,D,E
#'  and wants to do (C/B)/A and (E/D)/A or (E/D)/(C/B) then use this
#'  with a string like: "c_vs_b_ctrla = (C-B)-A, e_vs_d_ctrla = (E-D)-A,
#'  de_vs_cb = (E-D)-(C-B),"
#' @param alt_model Separate model matrix instead of the normal condition/batch.
#' @param annot_df Data frame for annotations.
#' @param libsize I've recently figured out that libsize is far more important than I previously
#'  realized.  Play with it here.
#' @param force  Force data which may not be appropriate for limma into it?
#' @param ... Use the elipsis parameter to feed options to write_limma().
#' @return List including the following information:
#'  macb = the mashing together of condition/batch so you can look at it
#'  macb_model = The result of calling model.matrix(~0 + macb)
#'  macb_fit =  The result of calling lmFit(data, macb_model)
#'  voom_result = The result from voom()
#'  voom_design = The design from voom (redundant from voom_result, but convenient)
#'  macb_table = A table of the number of times each condition/batch pairing happens
#'  cond_table = A table of the number of times each condition appears (the denominator for the identities)
#'  batch_table = How many times each batch appears
#'  identities = The list of strings defining each condition by itself
#'  all_pairwise = The list of strings defining all the pairwise contrasts
#'  contrast_string = The string making up the makeContrasts() call
#'  pairwise_fits = The result from calling contrasts.fit()
#'  pairwise_comparisons = The result from eBayes()
#'  limma_result = The result from calling write_limma()
#' @seealso \pkg{limma} \pkg{Biobase}
#'  \code{\link{write_limma}}
#' @examples
#' \dontrun{
#'  pretend <- limma_pairwise(expt)
#' }
#' @export
limma_pairwise <- function(input=NULL, conditions=NULL,
                           batches=NULL, model_cond=TRUE,
                           model_batch=TRUE, model_intercept=TRUE,
                           alt_model=NULL, extra_contrasts=NULL,
                           annot_df=NULL, libsize=NULL,
                           force=FALSE, ...) {
  arglist <- list(...)
  
  ## This is used in the invocation of a voom() implementation for normalization.
  voom_norm <- "quantile"  ## a normalize.method supported by limma.
  if (!is.null(arglist[["voom_norm"]])) {
    voom_norm <- arglist[["voom_norm"]]
  }
  ## Which implementation of voom() to use?
  which_voom <- "limma"  ## limma, limma_weighted, hpgl, or hpgl_weighted are possible
  if (!is.null(arglist[["which_voom"]])) {
    which_voom <- arglist[["which_voom"]]
  }
  ## This is for the lmFit() call.
  limma_method="ls" ## or robust
  if (!is.null(arglist[["limma_method"]])) {
    limma_method <- arglist[["limma_method"]]
  }
  ## This is for the eBayes() call.
  limma_robust=FALSE
  if (!is.null(arglist[["limma_robust"]])) {
    if (!identical(arglist[["limma_robus"]], FALSE)) {
      limma_robust <- TRUE
    }
  }
  ## This is also used in eBayes()
  limma_trend=FALSE
  if (!is.null(arglist[["limma_trend"]])) {
    limma_trend <- arglist[["limma_trend"]]
  }

  message("Starting limma pairwise comparison.")
  input_data <- choose_limma_dataset(input, force=force, which_voom=which_voom)
  design <- pData(input)
  if (is.null(conditions)) {
    conditions <- design[["condition"]]
  }
  if (is.null(batches)) {
    batches <- design[["batch"]]
  }
  data <- input_data[["data"]]

  if (is.null(libsize)) {
    message("libsize was not specified, this parameter has profound effects on limma's result.")
    if (!is.null(input[["best_libsize"]])) {
      message("Using the libsize from expt$best_libsize.")
      libsize <- input[["best_libsize"]]
    } else if (!is.null(input[["libsize"]])) {
      message("Using the libsize from expt$libsize.")
      libsize <- input[["libsize"]]
    } else if (!is.null(input[["normalized"]][["intermediate_counts"]][["normalization"]][["libsize"]])) {
      libsize <- colSums(data)
    } else {
      message("Using the libsize from expt$normalized$intermediate_counts$normalization$libsize")
      libsize <- input[["normalized"]][["intermediate_counts"]][["normalization"]][["libsize"]]
    }
  } else {
    message("libsize was specified.  This parameter has profound effects on limma's result.")
  }

  if (is.null(libsize)) {
    libsize <- colSums(data)
  }
  condition_table <- table(conditions)
  batch_table <- table(batches)
  conditions <- as.factor(conditions)
  batches <- as.factor(batches)

  message("Limma step 1/6: choosing model.")
  model <- choose_model(input, conditions, batches,
                        model_batch=model_batch,
                        model_cond=model_cond,
                        model_intercept=model_intercept,
                        alt_model=alt_model, ...)
  ##model <- choose_model(input, conditions, batches,
  ##                      model_batch=model_batch,
  ##                      model_cond=model_cond,
  ##                      model_intercept=model_intercept,
  ##                      alt_model=alt_model)
  chosen_model <- model[["chosen_model"]]

  fun_voom <- NULL
  ## voom() it, taking into account whether the data has been log2 transformed.

  ##  Leaving the following here for the moment, but I think it will no longer be needed.
  ##  Instead, I am checking the data state before passing it to this function with the
  ##  choose_limma_dataset() call above.
  loggedp <- input[["state"]][["transform"]]
  if (is.null(loggedp)) {
    message("I don't know if this data is logged, testing if it is integer.")
    if (is.integer(data)) {
      loggedp <- FALSE
    } else {
      loggedp <- TRUE
    }
  } else {
    if (grepl(pattern="log", x=loggedp)) {
      loggedp <- TRUE
    } else {
      loggedp <- FALSE
    }
  }

  convertedp <- input[["state"]][["conversion"]]
  if (is.null(convertedp)) {
    message("I cannot determine if this data has been converted, assuming no.")
    convertedp <- FALSE
  } else {
    if (convertedp == "raw") {
      convertedp <- FALSE
    } else {
      convertedp <- TRUE
    }
  }

  fun_voom <- NULL
  voom_plot <- NULL
  if (which_voom == "hpgl_weighted") {
    message("Limma step 2/6: running hpgl_voomweighted(), switch with the argument 'which_voom'.")
    fun_voom <- hpgl_voomweighted(data, chosen_model,
                                  libsize=libsize,
                                  voom_norm=voom_norm,
                                  span=0.5, var.design=NULL,
                                  method="genebygene",
                                  maxiter=50, tol=1E-10,
                                  trace=FALSE, replace.weights=TRUE, col=NULL,
                                  logged=loggedp,
                                  converted=convertedp)
    voom_plot <- fun_voom[["plot"]]
  } else if (which_voom == "hpgl") {
    message("Limma step 2/6: running hpgl_voom(), switch with the argument 'which_voom'.")
    fun_voom <- hpgl_voom(data,
                          chosen_model,
                          libsize=libsize,
                          logged=loggedp,
                          converted=convertedp)
    voom_plot <- fun_voom[["plot"]]
  } else if (which_voom == "limma_weighted") {
    message("Limma step 2/6: running limma::voomWithQualityWeights(), switch with the argument 'which_voom'.")
    fun_voom <- try(limma::voomWithQualityWeights(counts=data,
                                                  design=chosen_model,
                                                  lib.size=libsize,
                                                  normalize.method=voom_norm,
                                                  plot=TRUE,
                                                  span=0.5,
                                                  var.design=NULL,
                                                  method="genebygene",
                                                  maxiter=50,
                                                  tol=1E-10,
                                                  trace=FALSE,
                                                  replace.weights=TRUE,
                                                  col=NULL))
    if (class(fun_voom) == "try-error") {
      message("voomWithQualityWeights failed, falling back to voom.")
      fun_voom <- limma::voom(counts=data,
                              design=chosen_model,
                              lib.size=libsize,
                              normalize.method=voom_norm,
                              span=0.5,
                              plot=TRUE,
                              save.plot=TRUE)
    }
    voom_plot <- grDevices::recordPlot()
  } else {
    message("Limma step 2/6: running limma::voom(), switch with the argument 'which_voom'.")
    message(paste0("Using normalize.method=", voom_norm, " for voom."))
    ## Note to self, the defaults are span=0.5, plot=FALSE, save.plot=FALSE,
    ## normalize.method="none", lib.size=NULL, design=NULL
    fun_voom <- limma::voom(counts=data,
                            design=model,
                            lib.size=libsize,
                            normalize.method=voom_norm,
                            span=0.5,
                            plot=TRUE,
                            save.plot=TRUE)
    voom_plot <- grDevices::recordPlot()
  }

  one_replicate <- FALSE
  if (is.null(fun_voom)) {
    ## Apparently voom returns null where there is only 1 replicate.
    message("voom returned null, I am not sure what will happen.")
    one_replicate <- TRUE
    fun_voom <- data
    fun_design <- NULL
  } else {
    fun_design <- fun_voom[["design"]]
  }

  ## Do the lmFit() using this model
  pairwise_fits <- NULL
  identity_fits <- NULL
  message(paste0("Limma step 3/6: running lmFit with method: ", limma_method, "."))
  fitted_data <- limma::lmFit(object=fun_voom,
                              design=chosen_model,
                              method=limma_method)
  all_tables <- NULL
  if (isTRUE(model_intercept)) {
    message("Limma step 4/6: making and fitting contrasts with an intercept.")
    contrasts <- make_pairwise_contrasts(model=chosen_model, conditions=conditions,
                                         extra_contrasts=extra_contrasts)
    all_pairwise_contrasts <- contrasts[["all_pairwise_contrasts"]]
    contrast_string <- contrasts[["contrast_string"]]
    all_pairwise <- contrasts[["all_pairwise"]]
    ## Once all that is done, perform the fit
    ## This will first provide the relative abundances of each condition
    ## followed by the set of all pairwise comparisons.
    pairwise_fits <- limma::contrasts.fit(fit=fitted_data, contrasts=all_pairwise_contrasts)

    identity_contrasts <- make_pairwise_contrasts(model=chosen_model, conditions=conditions,
                                                  do_identities=TRUE, do_pairwise=FALSE)
    identities <- identity_contrasts[["all_pairwise_contrasts"]]
    identity_fits <- limma::contrasts.fit(fit=fitted_data, contrasts=identities)
    message(paste0("Limma step 5/6: Running eBayes with robust=",
                   limma_robust, " and trend=", limma_trend, "."))
    if (isTRUE(one_replicate)) {
      all_pairwise_comparisons <- pairwise_fits[["coefficients"]]
      all_identity_comparisons <- pairwise_fits[["coefficients"]]
    } else {
      all_pairwise_comparisons <- limma::eBayes(pairwise_fits,
                                                robust=limma_robust,
                                                trend=limma_trend)
      all_identity_comparisons <- limma::eBayes(identity_fits,
                                                robust=limma_robust,
                                                trend=limma_trend)
    }
    message("Limma step 6/6: Writing limma outputs.")
    pairwise_results <- make_limma_tables(fit=all_pairwise_comparisons, adjust="BH",
                                          n=0, coef=NULL, annot_df=NULL)
    limma_tables <- pairwise_results[["contrasts"]]
    identity_results <- make_limma_tables(fit=all_identity_comparisons, adjust="BH",
                                          n=0, coef=NULL, annot_df=NULL)
    limma_identities <- identity_results[["identities"]]
    
    contrasts_performed <- names(limma_tables)
  } else {
    message("Limma step 4/6: making and fitting contrasts without an intercept.")
    contrasts <- "nointercept"
    all_pairwise_contrasts <- NULL
    contrast_string <- "no intercept done"
    all_pairwise <- NULL
    pairwise_fits <- fitted_data
    identity_contrasts <- NULL
    identities <- NULL
    identity_fits <- fitted_data
    message(paste0("Limma step 5/6: Running eBayes with robust=",
                   limma_robust, " and trend=", limma_trend, "."))
    all_pairwise_comparisons <- limma::eBayes(fitted_data,
                                              robust=limma_robust,
                                              trend=limma_trend)
    all_identity_comparisons <- NULL
    message("Limma step 6/6: Writing limma outputs without an intercept.")
    pairwise_results <- make_limma_tables(fit=all_pairwise_comparisons, adjust="BH",
                                          n=0, coef=NULL, annot_df=NULL, intercept=FALSE)
    limma_tables <- pairwise_results[["contrasts"]]
    contrasts_performed <- names(limma_tables)
    limma_identities <- pairwise_results[["identities"]]
  }

  result <- list(
    "all_pairwise" = all_pairwise,
    "all_tables" = limma_tables,
    "identity_tables" = limma_identities,
    "batches" = batches,
    "batches_table" = batch_table,
    "conditions" = conditions,
    "conditions_table" = condition_table,
    "contrast_string" = contrast_string,
    "fit" = fitted_data,
    "identities" = identities,
    "input_data" = data,
    "model" = model,
    "pairwise_comparisons" = all_pairwise_comparisons,
    "identity_comparisons" = all_identity_comparisons,
    "single_table" = all_tables,
    "voom_design" = fun_design,
    "contrasts_performed" = contrasts_performed,
    "voom_plot" = voom_plot,
    "voom_result" = fun_voom)
  return(result)
}

#' Plot arbitrary data from limma as a scatter plot.
#'
#' Extract the adjusted abundances for the two conditions used in the pairw
#'
#' @param all_pairwise_result Result from calling balanced_pairwise().
#' @param first_table First table from all_pairwise_result$limma_result to look at (may be a name or number).
#' @param first_column Name of the column to plot from the first table.
#' @param second_table Second table inside all_pairwise_result$limma_result (name or number).
#' @param second_column Column to compare against.
#' @param type Type of scatter plot (linear model, distance, vanilla).
#' @param ... Use the elipsis to feed options to the html graphs.
#' @return plot_linear_scatter() set of plots comparing the chosen columns.  If you forget to
#'  specify tables to compare, it will try the first vs the second.
#' @seealso \pkg{limma}
#'  \code{\link{plot_linear_scatter}}
#' @examples
#' \dontrun{
#'  compare_logFC <- limma_scatter(all_pairwise, first_table="wild_type", second_column="mutant",
#'                                 first_table="AveExpr", second_column="AveExpr")
#'  compare_B <- limma_scatter(all_pairwise, first_column="B", second_column="B")
#' }
#' @export
limma_scatter <- function(all_pairwise_result, first_table=1, first_column="logFC",
                          second_table=2, second_column="logFC", type="linear_scatter", ...) {
  tables <- all_pairwise_result[["all_tables"]]
  if (is.numeric(first_table)) {
    x_name <- paste(names(tables)[first_table], first_column, sep=":")
  }
  if (is.numeric(second_table)) {
    y_name <- paste(names(tables)[second_table], second_column, sep=":")
  }

  ## This section is a little bit paranoid
  ## I want to make absolutely certain that I am adding only the
  ## two columns I care about and that nothing gets reordered
  ## As a result I am explicitly pulling a single column, setting
  ## the names, then pulling the second column, then cbind()ing them.
  x_name <- paste(first_table, first_column, sep=":")
  y_name <- paste(second_table, second_column, sep=":")
  df <- data.frame(x=tables[[first_table]][[first_column]])
  rownames(df) <- rownames(tables[[first_table]])
  second_column_list <- tables[[second_table]][[second_column]]
  names(second_column_list) <- rownames(tables[[second_table]])
  df <- cbind(df, second_column_list)
  colnames(df) <- c(x_name, y_name)
  plots <- NULL
  if (type == "linear_scatter") {
    plots <- plot_linear_scatter(df, loess=TRUE, ...)
  } else if (type == "dist_scatter") {
    plots <- plot_dist_scatter(df, ...)
  } else {
    plots <- plot_scatter(df, ...)
  }
  plots[["dataframe"]] <- df
  return(plots)
}

#' Writes out the results of a limma search using toptable().
#'
#' However, this will do a couple of things to make one's life easier:
#' 1.  Make a list of the output, one element for each comparison of the contrast matrix
#' 2.  Write out the toptable() output for them in separate .csv files and/or sheets in excel
#' 3.  Since I have been using qvalues a lot for other stuff, add a column for them.
#'
#' @param fit  Result from lmFit()/eBayes()
#' @param adjust  Pvalue adjustment chosen.
#' @param n  Number of entries to report, 0 says do them all.
#' @param coef  Which coefficients/contrasts to report, NULL says do them all.
#' @param annot_df  Optional data frame including annotation information to include with the tables.
#' @param intercept  Intercept model?
#' @return List of data frames comprising the toptable output for each coefficient, I also added a
#'  qvalue entry to these toptable() outputs.
#' @seealso \pkg{limma} \pkg{qvalue}
#'  \code{\link{write_xls}} \code{\link[limma]{topTable}}
#' @examples
#' \dontrun{
#'  finished_comparison = eBayes(limma_output)
#'  table = make_limma_tables(finished_comparison, adjust="fdr")
#' }
#' @export
make_limma_tables <- function(fit=NULL, adjust="BH", n=0, coef=NULL,
                              annot_df=NULL, intercept=TRUE) {
  ## Figure out the number of genes if not provided
  if (n == 0) {
    n <- nrow(fit[["coefficients"]])
  }

  ## If specific contrast(s) is/are not requested, get them all.
  if (is.null(coef)) {
    if (isTRUE(intercept)) {
      coef <- colnames(fit[["contrasts"]])
    } else {
      coef <- colnames(fit[["coefficients"]])
      coef <- coef[2:length(coef)]
    }
  } else {
    coef <- as.character(coef)
  }
  return_identities <- list()
  return_data <- list()
  end <- length(coef)
  data_tables <- list()
  ##all_tables <- try(limma::topTable(all_pairwise_comparisons,
  ##                                  number=nrow(all_pairwise_comparisons)))
  ##classified <- limma::classifyTestsP(all_pairwise_comparisons, method="BH")
  ##classified <- limma::decideTests(all_pairwise_comparisons, method="global")
  ##print(summary(classified))
  ##a <- limma::vennCounts(classified)
  ##b <- limma::vennDiagram(a)
  if (isTRUE(intercept)) {

    for (c in 1:end) {
      comparison <- coef[c]
      message(paste0("Limma step 6/6: ", c, "/", end, ": Creating table: ",
                     comparison, ".  Adjust=", adjust))
      data_tables[[c]] <- limma::topTable(fit,
                                          adjust.method=adjust,
                                          n=n,
                                          coef=comparison,
                                          sort.by="logFC")
    }

    ## Take a moment to prettily format the numbers in the tables
    ## and fill in the identity table.
    for (d in 1:length(data_tables)) {
      comparison <- coef[d]
      table <- data_tables[[d]]
      for (column in 1:ncol(table)) {
        table[[column]] <- signif(x=as.numeric(table[[column]]), digits=4)
      }
      if (!is.null(annot_df)) {
        table <- merge(table, annot_df, by.x="row.names", by.y="row.names")
      }
      if (grepl(pattern="_vs_", x=comparison)) {
        return_data[[comparison]] <- table
      } else {
        return_identities[[comparison]] <- table
      }
    }
    
  } else {
    ## If we do not have an intercept model, then we get the data
    ## in a slightly different fashion.
    for (c in 1:ncol(fit[["coefficients"]])) {
      data_table <-  limma::topTable(fit,
                                     adjust.method=adjust,
                                     n=n,
                                     coef=c,
                                     sort.by="logFC")

      for (column in 1:ncol(data_table)) {
        data_table[[column]] <- signif(x=as.numeric(data_table[[column]]), digits=4)
      }
      if (!is.null(annot_df)) {
        data_table <- merge(data_table, annot_df, by.x="row.names", by.y="row.names")
      }

      if (c == 1) {
        return_identities[[1]] <- data_table
      } else {
        comparison <- colnames(fit[["coefficients"]])[c]
        return_data[[comparison]] <- data_table
      }
    }
  } ## End checking for an intercept/nointercept model.

  retlist <- list(
    "identities" = return_identities,
    "contrasts" = return_data)
  return(retlist)
}

#' Writes out the results of a limma search using write_de_table()
#'
#' Looking to provide a single interface for writing tables from limma and friends.
#'
#' Tested in test_21limma.R
#'
#' @param data  Output from limma_pairwise()
#' @param ...  Options for writing the xlsx file.
#' @seealso \code{\link{write_de_table}}
#' @examples
#' \dontrun{
#'  finished_comparison = limma_pairwise(expressionset)
#'  data_list = write_limma(finished_comparison)
#' }
#' @export
write_limma <- function(data, ...) {
  result <- write_de_table(data, type="limma", ...)
  return(result)
}

## EOF
