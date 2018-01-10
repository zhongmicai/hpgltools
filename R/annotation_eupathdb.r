#' Search the eupathdb metadata for a given species substring.
#'
#' If the specific species is not found, look for a reasonably approximation.
#' stop() if nothing is found.
#'
#' @param species  Guess
#' @param metadata  Eupathdb metadata.
#' @param ...  Extra arguments passed to download_eupath_metadata()
#' @return  A single entry from the eupathdb metadata.
check_eupath_species <- function(species="Leishmania major strain Friedlin", metadata=NULL, ...) {
  if (is.null(metadata)) {
    message("Starting metadata download.")
    metadata <- download_eupath_metadata(...)
    ## metadata <- download_eupath_metadata(dir=dir)
    message("Finished metadata download.")
  }
  all_species <- metadata[["Species"]]
  entry <- NULL
  grep_hits <- grepl(species, all_species)
  grepped_hits <- all_species[grep_hits]
  if (species %in% all_species) {
    entry <- metadata[metadata[["Species"]] == species, ]
    message(paste0("Found: ", entry[["Species"]]))
  } else if (sum(grep_hits > 0)) {
    species <- grepped_hits[[1]]
    entry <- metadata[metadata[["Species"]] == species, ]
    message("Found the following hits: ", toString(grepped_hits), ", choosing the first.")
  } else {
    message(paste0("Here are the possible species: ", toString(all_species)))
    stop("Did not find your species.")
  }
  return(entry)
}

#' Invoke the appropriate get_eupath_ function.
#'
#' This small function provides a single entrypoint for multiple get_eupath functions.
#'
#' @param type  One of: gff, genes, go, pathways, etc. (The type of table to download.)
#' @param granges  When downloading a gff, use this.
#' @param provider  Generally only tritrypdb or eupathdb
#' @param genus_species  A string identifying the genus and species
#' @param species  As opposed to just the species
#' @param flatten  Flatten the resulting table (if it is a table of tables)
#' @param abbreviation  Used for kegg downloads.
#' @param dir  Where to dump the data.
#' @return Table of eupathdb information.
do_eupath_table <- function(type, granges=NULL, provider=NULL, genus_species=NULL,
                            species=NULL, flatten=FALSE, abbreviation=NULL,
                            dir="eupathdb", do_kegg=TRUE) {
  message(paste0("Starting collection of the ", type, " data."))
  a_result <- NULL
  switchret <- switch(
    type,
    "gff" = {
      a_result <- try(get_eupath_gff_table(granges))
    },
    "genes" = {
      a_result <- try(get_eupath_gene_types(provider=provider, species=species, dir=dir))
    },
    "go" = {
      a_result <- try(get_eupath_go_term_table(provider=provider, species=species, dir=dir))
    },
    "pathways" = {
      a_result <- try(get_eupath_pathway_table(provider=provider, species=species, dir=dir))
    },
    "interpro" = {
      a_result <- try(get_eupath_interpro_table(provider=provider, species=species, dir=dir))
    },
    "kegg" = {
      if (isTRUE(do_kegg)) {
        a_result <- try(load_kegg_annotations(species=genus_species,
                                              flatten=flatten,
                                              abbreviation=abbreviation))
      } else {
        a_result <- NULL
      }
    },
    "orthologs" = {
      a_result <- try(get_eupath_ortholog_table(provider=provider, species=species,
                                                dir=dir))
    },
    {
      message("Do not recognize this table.")
      a_result <- data.frame()
    }
  ) ## End of the switch.
  if (class(a_result) == "try-error") {
    a_result <- data.frame()
  }
  
  retlist <- list("type" = type,
                  "result" = a_result)
  return(retlist)
}

#' Returns metadata for all eupathdb organisms.
#'
#' @param overwrite  Overwrite existing data?
#' @param webservice  Optional alternative webservice for hard-to-find species.
#' @param dir  Where to put the json.
#' @param use_savefile  Make a savefile of the data for future reference.
#' @return  Dataframe with lots of rows for the various species in eupathdb.
#' @author  Keith Hughitt
#' @export
download_eupath_metadata <- function(overwrite=FALSE, webservice="eupathdb",
                                     dir="eupathdb", use_savefile=TRUE) {
  ## Get EuPathDB version (same for all databases)
  savefile <- paste0(webservice, "_metadata-v", format(Sys.time(), "%Y%m"), ".rda")

  if (!file.exists(dir)) {
    dir.create(dir, recursive=TRUE)
  }
  if (isTRUE(use_savefile)) {
    savefile <- file.path(dir, savefile)
    if (isTRUE(overwrite)) {
      file.remove(savefile)
    }
    if (file.exists(savefile)) {
      metadata <- new.env()
      loaded <- load(savefile, envir=metadata)
      metadata <- metadata[["metadata"]]
      return(metadata)
    }
  }

  db_version <- readLines("http://tritrypdb.org/common/downloads/Current_Release/Build_number")
  .data <- NULL  ## To satisfy R CMD CHECK
  shared_tags <- c("Annotation", "EuPathDB", "Eukaryote", "Pathogen", "Parasite")
  tags <- list(
    "AmoebaDB" = c(shared_tags, "Amoeba"),
    "CryptoDB" = c(shared_tags, "Cryptosporidium"),
    "FungiDB" = c(shared_tags, "Fungus", "Fungi"),
    "GiardiaDB" = c(shared_tags, "Giardia"),
    "MicrosporidiaDB" = c(shared_tags, "Microsporidia"),
    "PiroplasmaDB" = c(shared_tags, "Piroplasma"),
    "PlasmoDB" = c(shared_tags, "Plasmodium"),
    "ToxoDB" = c(shared_tags, "Toxoplasmosis"),
    "TrichDB" = c(shared_tags, "Trichomonas"),
    "TriTrypDB" = c(shared_tags, "Trypanosome", "Kinetoplastid", "Leishmania"))
  tag_strings <- lapply(tags, function(x) { paste(x, collapse=",") })

  ## construct API request URL
  ##base_url <- "http://eupathdb.org/eupathdb/webservices/"
  base_url <- paste0("http://", webservice, ".org/", webservice, "/webservices/")
  query_string <- "OrganismQuestions/GenomeDataTypes.json?o-fields=all"
  request_url <- paste0(base_url, query_string)

  ## retrieve organism metadata from EuPathDB
  metadata_json <- paste0(dir, "/metadata.json")
  file <- download.file(url=request_url, destfile=metadata_json, method="curl", quiet=FALSE)
  result <- jsonlite::fromJSON(metadata_json)
  records <- result[["response"]][["recordset"]][["records"]]
  message(paste0("Downloaded: ", request_url))

  ## convert to a dataframe
  dat <- data.frame(t(sapply(records[["fields"]], function (x) { x[,"value"] } )),
                    stringsAsFactors=FALSE)
  colnames(dat) <- records[["fields"]][[1]][["name"]]

  ## shared metadata
  ## I wish I were this confident with %>% and transmute, I always get confused by them
  shared_metadata <- dat %>% dplyr::transmute(
                                      "BiocVersion"=as.character(BiocInstaller::biocVersion()),
                                      "Genome"=sub(".gff", "", basename(.data[["URLgff"]])),
                                      "NumGenes"=.data[["genecount"]],
                                      "NumOrthologs"=.data[["orthologcount"]],
                                      "SourceType"="GFF",
                                      "SourceUrl"=.data[["URLgff"]],
                                      "SourceVersion"=db_version,
                                      "Species"=.data[["organism"]],
                                      "TaxonomyId"=.data[["ncbi_tax_id"]],
                                      "Coordinate_1_based"=TRUE,
                                      "DataProvider"=.data[["project_id"]],
                                      "Maintainer"="Keith Hughitt <khughitt@umd.edu>")

  ## Add project-specific tags for each entry
  shared_metadata[["Tags"]] <- sapply(shared_metadata[["DataProvider"]],
                                      function(x) { tag_strings[[x]] })

  ## replace missing taxonomy ids with NAs
  shared_metadata[["TaxonomyId"]][shared_metadata[["TaxonomyId"]] == ''] <- NA

  ## overide missing taxonomy ids for strains where it can be assigned; ideally
  ## OrgDb and GRanges objects should not depend on taxonomy id information since
  ## this precludes the inclusion of a lot of prokaryotic resources.
  known_taxon_ids <- data.frame(
    species=c("Ordospora colligata OC4",
              "Trypanosoma cruzi CL Brener Esmeraldo-like",
              "Trypanosoma cruzi CL Brener Non-Esmeraldo-like"),
    taxonomy_id=c("1354746", "353153", "353153"),
    stringsAsFactors=FALSE)

  taxon_mask <- shared_metadata[["Species"]] %in% known_taxon_ids[["species"]]
  ind <- match(shared_metadata[taxon_mask, "Species"], known_taxon_ids[["species"]])
  shared_metadata[taxon_mask,][["TaxonomyId"]] <- as.character(known_taxon_ids[["taxonomy_id"]][ind])

  ## exclude remaining species which are missing taxonomy information from
  ## metadata; cannot construct GRanges/OrgDb instances for them since they are
  ## have no known taxonomy id, and are not in available.species()
  na_ind <- is.na(shared_metadata[["TaxonomyId"]])
  ## I think I will try to hack around this problem.
  ##message(sprintf("- Excluding %d organisms for which no taxonomy id could be assigned (%d remaining)",
  ##                sum(na_ind), sum(!na_ind)))
  ##shared_metadata <- shared_metadata[!na_ind,]

  ## convert remaining taxonomy ids to numeric
  shared_metadata[["TaxonomyId"]] <- as.numeric(shared_metadata[["TaxonomyId"]])

  ## remove any organisms for which no GFF is available
  ## gff_exists <- sapply(shared_metadata[["SourceUrl"]],
  ##                      function(url) { httr::HEAD(url)[["status_code"]] == 200 })
  ## remove any organisms for which no GFF is available
  ## Once again, I will attempt a workaround, probably via bioconductor.
  ## gff_exists <- sapply(shared_metadata$SourceUrl, function(url) { HEAD(url)$status_code == 200 })
  ##message(sprintf("- Excluding %d organisms for which no GFF file is available (%d remaining)",
  ##                sum(!gff_exists), sum(gff_exists)))
  ##shared_metadata <- shared_metadata[gff_exists,]

  ## generate separate metadata table for OrgDB and GRanges targets
  granges_metadata <- shared_metadata %>%
    dplyr::mutate(
             Title=sprintf("Transcript information for %s", .data[["Species"]]),
             Description=sprintf("%s %s transcript information for %s",
                                 .data[["DataProvider"]], .data[["SourceVersion"]],
                                 .data[["Species"]]),
             RDataClass="GRanges",
             DispatchClass="GRanges",
             ResourceName=sprintf("GRanges.%s.%s%s.rda", gsub("[ /.]+", "_", .data[["Species"]]),
                                  tolower(.data[["DataProvider"]]), .data[["SourceVersion"]], "rda")) %>%
    dplyr::mutate(DataPath=file.path("EuPathDB", "GRanges", .data[["BiocVersion"]], .data[["ResourceName"]]))

  metadata <- shared_metadata %>%
    dplyr::mutate(
             "Title"=sprintf("Genome wide annotations for %s", .data[["Species"]]),
             "Description"=sprintf("%s %s annotations for %s",
                                   .data[["DataProvider"]],
                                   .data[["SourceVersion"]],
                                   .data[["Species"]]),
             "RDataClass"="OrgDb",
             "DispatchClass"="SQLiteFile",
             "ResourceName"=sprintf("org.%s.%s.db.sqlite", gsub("[ /.]+", "_", .data[["Species"]]),
                                    tolower(substring(.data[["DataProvider"]], 1, nchar(.data[["DataProvider"]]) - 2)))
           ) %>%
    dplyr::mutate("RDataPath"=file.path("EuPathDB", "OrgDb",
                                        .data[["BiocVersion"]],
                                        .data[["ResourceName"]]))

  if (isTRUE(use_savefile)) {
    if (isTRUE(overwrite) | !file.exists(savefile)) {
      saved <- save(list="metadata", file=savefile)
    }
  }

  return(metadata)
}

#' Extract gene information from a GFF file
#'
#' @param granges GenomicRanges instance as returned by `import.gff3`
#' @return data.frame containing basic gene information (ID, description,
#' etc.)
#' @author Keith Hughitt
#' @export
get_eupath_gff_table <- function(granges=NULL) {
  ## get gene features and convert to a dataframe
  if (class(granges) != "GRanges") {
    return(data.frame())
  }
  genes <- granges[granges$type == "gene"]
  gene_info <- as.data.frame(GenomicRanges::elementMetadata(genes))

  ## drop any empty and NA columns
  na_mask <- apply(gene_info, 2, function(x) { sum(!is.na(x)) > 0 })
  empty_mask <- apply(gene_info, 2, function(x) { length(unlist(x)) > 0 })
  gene_info <- gene_info[, na_mask & empty_mask]

  ## remove problematic GENECOLOUR field if it exists.
  ## Found for "Leishmania braziliensis MHOM/BR/75/M2904" -- only one row
  ## has a non-empty value and it does not appear to be correct:
  ## > gene_info$GENECOLOUR[1859]
  ## [[1]]
  ## [1] "10"                  "LbrM15.0470"         "LbrM.15.0630"
  ## "LbrM15_V2.0630"      "LbrM15_V2.0630:pep"  "LbrM15_V2.0630:mRNA"
  gene_info <- gene_info[, colnames(gene_info) != "GENECOLOUR"]

  ## Convert form-encoded description string to human-readable
  gene_info[["description"]] <- gsub("\\+", " ", gene_info[["description"]])

  ## Normalize columns names
  colnames(gene_info) <- toupper(colnames(gene_info))
  colnames(gene_info)[colnames(gene_info) == "ID"] <- "GID"

  ## Move gid to the front of the line.
  gid_index <- grep("GID", colnames(gene_info))
  gene_info <- gene_info[, c(gid_index, (1:ncol(gene_info))[-gid_index])]
  colnames(gene_info) <- paste0("GENE", colnames(gene_info))
  colnames(gene_info)[1] <- "GID"

  ## fix type for GENEALIAS column if present (found in version 28 and
  ## earlier)
  if ("GENEALIAS" %in% colnames(gene_info)) {
    gene_info[["GENEALIAS"]] <- as.character(gene_info[["GENEALIAS"]])

    ## Remove any newlines present in GENEALIAS field;
    ## as.character inserts newlines for objects with >500 characters.
    ## https://stat.ethz.ch/R-manual/R-devel/library/base/html/character.html
    gene_info[["GENEALIAS"]] <- gsub("\n", "", gene_info[["GENEALIAS"]])
  }

  return(gene_info)
}

#' Returns a mapping of gene ID to gene type for a specified organism
#'
#' @param provider Name of data provider to query (e.g. 'TriTrypDB')
#' @param species Full name of organism, as used by EuPathDB APIs
#' @param dir  Where to put the downloaded data?
#' @return Dataframe with 'GID' and 'TYPE' columns.
#' @author Keith Hughitt
#' @export
get_eupath_gene_types <- function(provider="TriTrypDB", species="Leishmania major",
                                  dir="eupathdb") {
  ## query EuPathDB API
  res <- query_eupathdb(
    provider=provider,
    species=species,
    dir=dir,
    prefix="types",
    list(`o-fields` = "primary_key,gene_type"))
  dat <- res[["response"]][["recordset"]][["records"]]
  ## get vector of types
  ids <- unlist(sapply(dat[["fields"]], function(x) { strsplit(x[, "value"], ",")[1] }))
  types <- unlist(sapply(dat[["fields"]], function(x) { strsplit(x[, "value"], ",")[2] }))

  df <- data.frame("GID" = ids,
                   "TYPE" = types,
                   stringsAsFactors=FALSE)
  ## remove duplicated rows and return
  df <- df[!duplicated(df), ]
  return(df)
}

#'  Returns a mapping of gene ID to gene GO categories for a given organism.
#'
#' @param provider  Name of data provider to query.
#' @param species  Full name of the organism as per the eupathdb api.
#' @param overwrite  Overwrite the existing table?
#' @param dir  Where to dump the data.
#' @return Table of GO terms/gene IDs
#' @export
get_eupath_go_term_table <- function(provider="TriTrypDB", species="Leishmania major",
                                     overwrite=FALSE, dir="eupathdb") {
  result <- retrieve_eupathdb_attributes(
    provider=provider,
    species=species,
    table="GOTerms",
    overwrite=FALSE,
    dir=dir)

  if (nrow(result) == 0) {
    return(result)
  }

  ## convert column names to uppercase for consistency
  colnames(result) <- toupper(colnames(result))
  ## drop uneeded columns
  result <- result[, colnames(result) %in% c("GID", "ONTOLOGY", "GO_ID",
                                             "GO_TERM_NAME", "SOURCE",
                                             "EVIDENCE_CODE")]
  ## remove duplicated entries resulting from alternative sources / envidence
  ## codes
  result <- result[!duplicated(result), ]
  ## remove rows missing the ontology field (Bug in EuPathDB 33; affects only
  ## a small number of entries)
  result <- result[!is.na(result[["ONTOLOGY"]]), ]
  return(result)
}

#' Returns a mapping of gene ID to metabolic pathways (KEGG, LeishCyc, etc.)
#'
#' @param provider  Name of data provider to query (e.g. 'TriTrypDB')
#' @param species  Full name of organism, as used by EuPathDB APIs
#' @param overwrite  Overwrite already existing data?
#' @param dir  Where to place the data.
#' @return Dataframe with gene/pathway mapping
#' @author Keith Hughitt
#' @export
get_eupath_pathway_table <- function(provider="TriTrypDB", species="Leishmania major",
                                     overwrite=FALSE, dir="eupathdb") {
  result <- retrieve_eupathdb_attributes(
    provider=provider,
    species=species,
    table="MetabolicPathways",
    overwrite=overwrite,
    dir=dir)
  colnames(result) <- toupper(sub("_+$", "", sub("^X_+", "", gsub("\\.", "_", colnames(result)))))
  result <- result[!duplicated(result), ]
  return(result)
}

#' Returns a mapping of gene ID to InterPro domains for a specified organism
#'
#' @param provider  Name of data provider to query (e.g. 'TriTrypDB')
#' @param species  Full name of organism, as used by EuPathDB APIs
#' @param overwrite  Overwrite existing data?
#' @param dir  Where to place the downloaded data.
#' @return Dataframe with ....
#' @author Keith Hughitt
#' @export
get_eupath_interpro_table <- function(provider="TriTrypDB", species="Leishmania major",
                                      overwrite=FALSE, dir="eupathdb") {
  result <- retrieve_eupathdb_attributes(
    provider=provider,
    species=species,
    table="InterPro",
    overwrite=overwrite,
    dir=dir)
  ## fix numeric types
  result[["interpro_e_value"]] <- as.numeric(result[["interpro_e_value"]])
  result[["interpro_start_min"]] <- as.numeric(result[["interpro_start_min"]])
  result[["interpro_end_min"]] <- as.numeric(result[["interpro_end_min"]])

  ## fix column names and return result
  colnames(result) <- toupper(colnames(result))
  ## replace NA"s with empty strings (occur in INTERPRO_FAMILY_ID and
  ## INTERPRO_SECONDARY_ID fields)
  ## result[is.na(result)] <- ""
  for (col in colnames(result)) {
    if (class(result[[col]]) != "numeric") {
      nas <- is.na(result[[col]])
      result[nas, col] <- ""
    }
  }
  return(result)
}

#' Returns a mapping of gene ID to ortholog genes
#'
#' @param provider  Name of data provider to query (e.g. 'TriTrypDB')
#' @param species  Full name of organism, as used by EuPathDB APIs
#' @param overwrite  Overwrite existing data?
#' @param dir  Where to place the data.
#' @return Dataframe with ....
#' @author Keith Hughitt
#' @export
get_eupath_ortholog_table <- function(provider="TriTrypDB", species="Leishmania major",
                                      overwrite=FALSE, dir="eupathdb") {
  result <- retrieve_eupathdb_attributes(
    provider=provider,
    species=species,
    table="Orthologs",
    overwrite=overwrite,
    dir=dir)
  ## fix column names and return result
  colnames(result) <- toupper(colnames(result))
  return(result)
}

#' Gather most(all?) of the data which used to be in the .txt files from the eupathdb.
#'
#' Starting with revision 33, the eupathdb discontinued maintaining the
#' downloadable text tables. For much of the eupath data, this was not a
#' significant concern, Keith wrote the get_eupath_ family of functions which
#' provided a reasonable facsimile of that information.  Some pieces remained
#' missing, this function attempts to address that.
#'
#' @param species  Species to query.
#' @param entry  Metadata entry to use.
#' @param dir  Directory in which to put intermediate data.
#' @param metadata  Existing dataframe of metadata.
#' @param question_type  Usually GeneQuestions, I am not sure what other types are in use.
#' @param question  There are a bunch of possible query types, GenesByTaxon is
#'   the most comprehensive.
#' @param ...  Arguments passed to download_eupath_metadata()
#' @return data table of fun annotation data.
#' @export
get_eupath_text <- function(species=NULL, entry=NULL,
                            dir="eupathdb", metadata=NULL,
                            question_type="GeneQuestions",
                            question="GenesByTaxon", ...) {
  if (is.null(entry) & is.null(species)) {
    stop("Need either an entry or species.")
  } else if (is.null(entry)) {
    if (is.null(metadata)) {
      metadata <- download_eupath_metadata(dir=dir, ...)
    ##  metadata <- download_eupath_metadata(dir=dir)
    }
    entry <- check_eupath_species(species=species, metadata=metadata)
  }
  species <- entry[["Species"]]
  provider <- entry[["DataProvider"]]

  defaults <- list(
    "GenesByMolecularWeight" = list(
      "min_molecular_weight" = 10000,
      "max_molecular_weight" = 50000,
      "o-fields" = "gene_type, organism"),
    "GenesByLocation" = list(
      "start_point" = 1,
      "end_point" = 10,
      "sequenceId" = NULL,
      "chromosome" = NULL),
    "GenesByExonCount" = list(
      "num_exons_gt" = 1,
      "num_exons_lt" = 2,
      "scope" = NULL),
    "GenesByTextSearch" = list(
      "text_expression" = "DGF",
      "text_fields" = "all"),
    "GenesWithSignalPeptide" = list(
      "min_sigp_sum_score" = 1,
      "min_sigp_d_score" = 0,
      "min_sigp_signal_probability" = 0),
    "GenesByTransmembraneDomains" = list(
      "o-fields" = "primary_key,tm_count",
      "min_tm" = "0",
      "max_tm" = "100"),
    "GenesByTaxon" = list(
      "o-fields" = "primary_key,sequence_id,chromosome,organism,gene_type,gene_location_text,gene_name,gene_exon_count,is_pseudo,gene_transcript_count,gene_ortholog_number,gene_paralog_number,gene_orthomcl_name,gene_total_hts_snps,gene_hts_nonsynonymous_snps,gene_hts_noncoding_snps,gene_hts_stop_codon_snps,gene_hts_nonsyn_syn_ratio,uniprot_id,gene_entrez_id,transcript_length,exon_count,strand,cds_length,tm_count,molecular_weight,isoelectric_point,signalp_scores,signalp_peptide,annotated_go_function,annotated_go_process,annotated_go_component,annotated_go_id_function,annotated_go_id_process,annotated_go_id_component,predicted_go_id_function,predicted_go_id_process,predicted_go_id_component,ec_numbers,ec_numbers_derived,five_prime_utr_length,three_prime_utr_length,location_text,gene_previous_ids,protein_sequence,cds")
  )

  query_url <- sprintf("http://%s.org/webservices/%s/%s.json?",
                       tolower(provider), question_type, question)
  query_arglst <- list(
    "organism" = utils::URLencode(species, reserved=TRUE))
  for (arg in names(defaults[[question]])) {
    query_arglst[[arg]] <- defaults[[question]][[arg]]
  }

  query_string <- paste0(paste(names(query_arglst), query_arglst, sep="="),
                         collapse="&")
  request_url <- paste0(query_url, query_string)
  message(sprintf("- Querying %s", request_url))
  organism_filename <- gsub(pattern="\\s+|[[:punct:]]", replacement="", x=species)
  destfile <- file.path(dir, paste0(provider, "_", question, "_",
                                    organism_filename, ".json"))
  if (!file.exists(destfile)) {
    original_options <- options(timeout=300)
    file <- download.file(url=request_url, destfile=destfile, method="curl", quiet=FALSE)
    temp_options <- options(original_options)
  }
  result <- try(jsonlite::fromJSON(destfile))
  if (class(result) == "try-error") {
    message("The request seems to have failed:")
    message(request_url)
    return(NULL)
  }
  message("- Finished query.")
  dat <- data.table::as.data.table(result[["response"]][["recordset"]][["records"]])
  data <- data.table::as.data.table(dat[["id"]])
  colnames(data) <- "id"
  count <- 0
  final_names <- colnames(data)
  bar <- utils::txtProgressBar(style=3)
  all_n <- length(dat[["fields"]][[1]][, "name"])
  for (n in dat[["fields"]][[1]][, "name"]) {
    count <- count + 1
    pct_done <- count / all_n
    setTxtProgressBar(bar, pct_done)
    final_names <- c(final_names, n)
    data[[n]] <- sapply(dat[["fields"]], function(x) { x[, "value"][count] })
  }
  close(bar)

  ## Drop columns which are all NA
  not_all_nas <- colSums(is.na(data)) != nrow(data)
  data <- data[, not_all_nas, with=FALSE]

  ## Lets take a moment and set some column data types.
  avail_columns <- colnames(data)
  numeric_patterns <- c("^isoelectric_point$", "^molecular_weight$",
                         "^.+_count$", "^.+_length$", "^.+_number$")
  for (pattern in numeric_patterns) {
    found_cols <- grepl(pattern=pattern, x=avail_columns)
    for (change in avail_columns[found_cols]) {
      data[[change]] <- as.numeric(data[[change]])
    }
  }
  factor_patterns <- c("strand")
  for (pattern in factor_patterns) {
    found_cols <- grepl(pattern=pattern, x=avail_columns)
    for (change in avail_columns[found_cols]) {
      data[[change]] <- as.factor(data[[change]])
    }
  }

  return(data)
}

#' Generate a BSgenome package from the eupathdb.
#'
#' Since we go to the trouble to try and generate nice orgdb/txdb/organismdbi packages, it
#' seems to me that we ought to also be able to make a readable genome package.  I should
#' probably use some of the logic from this to make the organismdbi generator smarter.
#'
#' @param species  Species to create.
#' @param entry  Single eupathdb metadata entry.
#' @param dir  Working directory.
#' @param reinstall  Rewrite an existing package directory.
#' @param metadata  Eupathdb metadata dataframe.
#' @param ... Extra arguments for downloading metadata when not provided.
#' @return  List of package names generated (only 1).
#' @export
make_eupath_bsgenome <- function(species="Leishmania major strain Friedlin", entry=NULL,
                                 dir="eupathdb", reinstall=FALSE, metadata=NULL, ...) {
  if (is.null(entry) & is.null(species)) {
    stop("Need either an entry or species.")
  } else if (is.null(entry)) {
    if (is.null(metadata)) {
      metadata <- download_eupath_metadata(dir=dir, ...)
      ## metadata <- download_eupath_metadata(dir=dir)
    }
    entry <- check_eupath_species(species=species, metadata=metadata)
  }
  taxa <- make_taxon_names(entry)
  pkgnames <- make_eupath_pkgnames(species=species, metadata=metadata)
  pkgname <- pkgnames[["bsgenome"]]
  if (pkgname %in% installed.packages() & !isTRUE(reinstall)) {
    message(paste0(pkgname, " is already installed, set reinstall=TRUE if you wish to reinstall."))
    retlist <- list(
      "bsgenome_name" = pkgname
    )
    return(retlist)
  }

  ## Figure out the version numbers and download urls.
  db_version <- entry[["SourceVersion"]]
  fasta_start <- entry[["SourceUrl"]]
  fasta_starturl <- sub(pattern="gff",
                        replacement="fasta",
                        x=fasta_start,
                        perl=TRUE)
  fasta_url <- sub(pattern="\\.gff", replacement="_Genome\\.fasta",
                   x=fasta_starturl)
  fasta_hostname <- sub(pattern="http://(.*)\\.org.*$",
                        replacement="\\1",
                        x=fasta_start)
  genome_filename <- file.path(dir, paste0(pkgname, ".fasta"))

  ## Find a spot to dump the fasta files
  bsgenome_base <- file.path(dir)
  bsgenome_dir <- file.path(bsgenome_base, pkgname)
  if (!file.exists(bsgenome_dir)) {
    created <- dir.create(bsgenome_dir, recursive=TRUE)
  }
  ## Download them to this directory.
  downloaded <- download.file(url=fasta_url, destfile=genome_filename, quiet=FALSE)
  ## And extract all the individual chromosomes into this directory.
  input <- Biostrings::readDNAStringSet(genome_filename)
  output_list <- list()
  sequence_names <- "c("
  message("Writing chromosome files, this may take some time for especially fragmented scaffolds.")
  for (index in 1:length(input)) {
    chr <- names(input)[index]
    chr_name <- strsplit(chr, split=" ")[[1]][1]
    chr_file <- file.path(bsgenome_dir, paste0(chr_name, ".fa"))
    output <- Biostrings::writeXStringSet(input[index], chr_file, append=FALSE,
                                          compress=FALSE, format="fasta")
    output_list[[chr_name]] <- chr_file
    sequence_names <- paste0(sequence_names, '"', chr_name, '", ')
  }
  sequence_names <- gsub(pattern=", $", replacement=")", x=sequence_names)

  ## Now start creating the DESCRIPTION file
  desc_file <- file.path(bsgenome_dir, "DESCRIPTION")
  descript <- desc::description$new("!new")
  descript$set(Package=pkgname)
  author <- "Ashton Trey Belew <abelew@umd.edu>"
  title <- paste0(taxa[["genus"]], " ", taxa[["species"]], " strain ", taxa[["strain"]],
                  " version ", db_version)
  descript$set(Title=title)
  descript$set(Author=author)
  version_string <- format(Sys.time(), "%Y.%m")
  descript$set(Version=version_string)
  descript$set(Maintainer=author)
  descript$set(Description=paste0("A full genome from the eupathdb/tritrypdb for ", title, "."))
  descript$set(License="Artistic-2.0")
  descript$set(URL="http://eupathdb.org")
  descript$set(BugReports="http://github.com/elsayed-lab")
  descript$set(seqs_srcdir=bsgenome_dir)
  descript$set(seqnames=sequence_names)
  descript$set(organism=taxa[["taxon"]])
  descript$set(common_name=taxa[["genus_species"]])
  descript$set(provider=fasta_hostname)
  descript$set(provider_version=paste0(fasta_hostname, " ", db_version))
  descript$set(release_date=format(Sys.time(), "%Y%m%d"))
  descript$set(BSgenomeObjname=paste0(taxa[["genus_species"]], "_", taxa[["strain"]]))
  descript$set(release_name=db_version)
  descript$set(organism_biocview=paste0(taxa[["genus_species"]], "_", taxa[["strain"]]))
  descript$del("LazyData")
  descript$del("Authors@R")
  descript$del("URL")
  descript$del("BugReports")
  descript$del("Encoding")
  description_file <- file.path(bsgenome_dir, "DESCRIPTION")
  descript$write(description_file)

  ## Generate the package, this puts it into the cwd.
  message("Starting forgeBSgenomeDataPkg().")
  annoying <- sm(BSgenome::forgeBSgenomeDataPkg(description_file))

  if (class(annoying) != "try-error") {
    inst <- sm(try(devtools::install(pkgname, quiet=TRUE)))
  }
  
  retlist <- list()
  if (class(inst) != "try-error") {
    retlist[["bsgenome_name"]] <- pkgname
    ## Clean up a little.
    deleted <- unlink(x=bsgenome_dir, recursive=TRUE, force=TRUE)
    built <- sm(try(devtools::build(pkgname, quiet=TRUE)))
    if (class(built) != "try-error") {
      moved <- file.rename(paste0(pkgname, "_", version_string, ".tar.gz"),
                           paste0(bsgenome_dir, "_", version_string, ".tar.gz"))
      final_deleted <- unlink(x=pkgname, recursive=TRUE, force=TRUE)
    }
  } else {
    retlist <- inst
  }
  return(retlist)
}

#' Generate standardized package names for the various eupathdb species.
#'
#' In my test directory, I have a little for loop which randomly chooses a couple
#' of eupathdb species for which to try and generate genome/annotation packages.
#' I am on my 4th or 5th iteration of passing that loop and in all of them
#' I have found some new and exciting exception to how a strain should be named.
#' The default argument for this function shows the funniest one so far.
#' With that in mind, this function should provide consistent, valid package names.
#'
#' @param species  Guess.
#' @param metadata  Eupathdb metadata.
#' @param ...  Further arguments to pass to download_eupath_metadata()
#' @return  List of package names and some booleans to see if they have already been installed.
make_eupath_pkgnames <- function(species="Coprinosis.cinerea.okayama7#130",
                                 metadata=NULL, ...) {
  if (is.null(metadata)) {
    message("Starting metadata download.")
    metadata <- sm(download_eupath_metadata(...))
    ## metadata <- download_eupath_metadata(dir=dir)
    message("Finished metadata download.")
  }
  all_species <- metadata[["Species"]]
  entry <- NULL
  grep_hits <- grepl(species, all_species)
  grepped_hits <- all_species[grep_hits]
  if (species %in% all_species) {
    entry <- metadata[metadata[["Species"]] == species, ]
    message(paste0("Found: ", entry[["Species"]]))
  } else if (sum(grep_hits > 0)) {
    species <- grepped_hits[[1]]
    entry <- metadata[metadata[["Species"]] == species, ]
    message("Found the following hits: ", toString(grepped_hits), ", choosing the first.")
  } else {
    message(paste0("Here are the possible species: ", toString(all_species)))
    stop("Did not find your species.")
  }

  taxa <- make_taxon_names(entry)
  first_char <- strsplit(taxa[["genus"]], split="")[[1]][[1]]
  pkg_list <- list(
    "bsgenome" = paste0("BSGenome.", taxa[["taxon"]], ".v", entry[["SourceVersion"]]),
    "bsgenome_installed" = FALSE,
    "organismdbi" = paste0(taxa[["taxon"]], ".v", entry[["SourceVersion"]]),
    "organismdbi_installed" = FALSE,
    "orgdb" = paste0("org.", first_char, taxa[["species_strain"]], ".v",
                     entry[["SourceVersion"]], ".eg.db"),
    "orgdb_installed" = FALSE,
    "txdb" = paste0("TxDb.", taxa[["genus"]], ".", taxa[["species_strain"]],
                    ".", entry[["DataProvider"]], ".v", entry[["SourceVersion"]]),
    "txdb_installed" = FALSE
  )

  inst <- as.data.frame(installed.packages())
  if (pkg_list[["bsgenome"]] %in% inst[["Package"]]) {
    message(paste0(pkg_list[["bsgenome"]], " is already installed."))
    pkg_list[["bsgenome_installed"]] <- TRUE
  }
  if (pkg_list[["organismdbi"]] %in% inst[["Package"]]) {
    message(paste0(pkg_list[["organismdbi"]], " is already installed."))
    pkg_list[["organismdbi_installed"]] <- TRUE
  }
  if (pkg_list[["orgdb"]] %in% inst[["Package"]]) {
    message(paste0(pkg_list[["orgdb"]], " is already installed."))
    pkg_list[["orgdb_installed"]] <- TRUE
  }
  if (pkg_list[["txdb"]] %in% inst[["Package"]]) {
    message(paste0(pkg_list[["txdb"]], " is already installed."))
    pkg_list[["txdb_installed"]] <- TRUE
  }

  return(pkg_list)
}

#' Create an organismDbi instance for an eupathdb organism.
#'
#' @param species  A species in the eupathDb metadata.
#' @param entry  A row from the eupathdb metadataframe.
#' @param dir  Directory in which to build the packages.
#' @param reinstall  Overwrite existing data files?
#' @param metadata  Use a pre-existing metadata table, or download a new one.
#' @param kegg_abbreviation  For when we cannot automagically find the kegg species id.
#' @param ...  Extra arguments when downloading metadata.
#' @return  The result of attempting to install the organismDbi package.
#' @author  Keith Hughitt
#' @export
make_eupath_organismdbi <- function(species="Leishmania major strain Friedlin", entry=NULL,
                                    dir="eupathdb", reinstall=FALSE, metadata=NULL,
                                    kegg_abbreviation=NULL, exclude_join="ENTREZID",
                                    ...) {
  arglist <- list(...)
  if (is.null(entry) & is.null(species)) {
    stop("Need either an entry or species.")
  } else if (is.null(entry)) {
    if (is.null(metadata)) {
      metadata <- download_eupath_metadata(dir=dir, ...)
      ## metadata <- download_eupath_metadata(dir=dir)
    }
    entry <- check_eupath_species(species=species, metadata=metadata)
  }
  taxa <- make_taxon_names(entry)
  pkgnames <- make_eupath_pkgnames(species=species, metadata=metadata)
  pkgname <- pkgnames[["organismdbi"]]
  if (isTRUE(pkgnames[["organismdbi_installed"]]) & !isTRUE(reinstall)) {
    message(paste0(pkgname, " is already installed, set reinstall=TRUE if you wish to reinstall."))
    retlist <- list(
      "organdb_name" = pkgname
    )
    return(retlist)
  }
  orgdb_name <- pkgnames[["orgdb"]]
  txdb_name <- pkgnames[["txdb"]]

  orgdb_ret <- make_eupath_orgdb(
    species=species,
    entry=entry,
    metadata=metadata,
    dir=dir,
    kegg_abbreviation=kegg_abbreviation,
    reinstall=reinstall)
  if (is.null(orgdb_ret)) {
    return(NULL)
  }
  txdb_ret <- make_eupath_txdb(
    species=species,
    entry=entry,
    metadata=metadata,
    dir=dir,
    reinstall=reinstall)
  if (is.null(txdb_ret)) {
    return(NULL)
  }

  tt <- sm(requireNamespace(orgdb_name))
  tt <- sm(requireNamespace(txdb_name))
  libstring <- paste0("library(", orgdb_name, ")")
  library_ret <- try(eval(parse(text=libstring)))
  if (class(library_ret) == "try-error") {
    message("The orgdb failed to load.")
    return(NULL)
  }
  libstring <- paste0("library(", txdb_name, ")")
  library_ret <- try(eval(parse(text=libstring)))
  if (class(library_ret) == "try-error") {
    message("The orgdb failed to load.")
    return(NULL)
  }
  organism <- taxa[["taxon"]]
  required <- sm(requireNamespace("OrganismDbi"))

  message("Joining the txdb and orgdb objects.")
  version <- paste0(entry[["SourceVersion"]], ".0")
  count <- 0
  graph_data <- list()
  geneids_found <- "GID" %in% AnnotationDbi::keytypes(get(orgdb_name)) &&
    "GENEID" %in% AnnotationDbi::keytypes(get(txdb_name))
  if (isTRUE(geneids_found)) {
    count <- count + 1
    name <- paste0("join", count)
    graph_data[[name]] <- c(orgdb="GID",  txdb="GENEID")
    names(graph_data[[name]]) <- c(orgdb_name, txdb_name)
  }
  required <- sm(requireNamespace("GO.db"))
  required <- sm(try(attachNamespace("GO.db"), silent=TRUE))

  goids_found <- "GOID" %in% AnnotationDbi::keytypes(get("GO.db")) &&
    "GO_ID" %in% AnnotationDbi::keytypes(get(orgdb_name))
  if (isTRUE(goids_found)) {
    count <- count + 1
    name <- paste0("join", count)
    graph_data[[name]] <- c(GO.db="GOID", orgdb="GO_ID")
    names(graph_data[[name]]) <- c("GO.db", orgdb_name)
  }

  required <- sm(requireNamespace("reactome.db"))
  required <- sm(try(attachNamespace("reactome.db"), silent=TRUE))
  reactomeids_found <- "REACTOMEID" %in% AnnotationDbi::keytypes(get("reactome.db")) &&
    "REACTIONS" %in% AnnotationDbi::keytypes(get(orgdb_name))
  if (isTRUE(reactomeids_found)) {
    count <- count + 1
    name <- paste0("join", count)
    graph_data[[name]] <- c(reactome.db="REACTOMEID", orgdb="REACTIONS")
    names(graph_data[[name]]) <- c("reactome.db", orgdb_name)
  }

  author <- as.character(entry[["Maintainer"]])
  maintainer <- as.character(entry[["Maintainer"]])
  final_dir <- file.path(dir, pkgname)
  if (file.exists(final_dir)) {
    if (isTRUE(reinstall)) {
      unlinkret <- unlink(x=final_dir, recursive=TRUE)
    } else {
      if (file.exists(paste0(final_dir, ".bak"))) {
        unlinkret <- unlink(x=paste0(final_dir, ".bak"),
                            recursive=TRUE)
      }
      renamed <- file.rename(from=final_dir, to=paste0(final_dir, ".bak"))
    }
  }
  version <- format(as.numeric(version), nsmall=1)

  tmp_pkg_dir <- file.path(dir)
  if (!file.exists(tmp_pkg_dir)) {
    dir.create(tmp_pkg_dir, recursive=TRUE)
  }
  version_string <- format(Sys.time(), "%Y.%m")
  organdb <- OrganismDbi::makeOrganismPackage(
                            pkgname=pkgname,
                            graphData=graph_data,
                            organism=organism,
                            version=version_string,
                            maintainer=maintainer,
                            author=author,
                            destDir=tmp_pkg_dir,
                            license="Artistic-2.0"
                          )
  organdb_path <- sm(clean_pkg(final_dir))
  organdb_path <- sm(clean_pkg(organdb_path, removal="_", replace="", sqlite=FALSE))
  organdb_path <- sm(clean_pkg(organdb_path, removal="_like", replace="like", sqlite=FALSE))
  if (class(organdb) == "list") {
    inst <- sm(try(devtools::install(organdb_path)))
    if (class(inst) != "try-error") {
      built <- sm(try(devtools::build(organdb_path, quiet=TRUE)))
      if (class(built) != "try-error") {
        final_deleted <- unlink(x=organdb_path, recursive=TRUE, force=TRUE)
      }
    }
  }
  final_organdb_name <- basename(organdb_path)
  retlist <- list(
    "orgdb_name" = orgdb_name,
    "txdb_name" = txdb_name,
    "organdb_name" = final_organdb_name
  )
  return(retlist)
}

#' Generate OrgDb for EuPathDB organism
#'
#' This is probably the most difficult function in this family, as orgdb instances are rather
#' more complex than the other annotation data (at least for the eupathdb).  It gathers the
#' KEGG/GO/gene/etc data and bundles it into a single sqlite instance and does some
#' rudimentary sanity checks on the result.
#'
#' FIXME: The eupathdb family is moving away from the json-based queries.  The
#' get_something() family of functions upon which this process depends is
#' therefore not likely to continue to work over time.  It needs therefore to be
#' migrated to queries similar to what is performed in get_eupath_text().
#'
#' @param species  Single species to work on.
#' @param entry One dimensional dataframe with organism metadata
#' @param dir  Where to put the data
#' @param kegg_abbreviation  A kegg abbreviation when it cannot be automatically determined.
#' @param reinstall  Overwrite an existing installed package?
#' @param metadata  Large metadata dataframe.
#' @param ...  Extra arguments when downloading metadata.
#' @return OrgDb instance package name.
#' @author Keith Hughitt
#' @export
make_eupath_orgdb <- function(species=NULL, entry=NULL, dir="eupathdb",
                              kegg_abbreviation=NULL, reinstall=FALSE, metadata=NULL, ...) {
  if (is.null(entry) & is.null(species)) {
    stop("Need either an entry or species.")
  } else if (is.null(entry)) {
    if (is.null(metadata)) {
      metadata <- download_eupath_metadata(dir=dir, ...)
    }
    entry <- check_eupath_species(species=species, metadata=metadata)
  }
  taxa <- make_taxon_names(entry)
  pkgnames <- make_eupath_pkgnames(species=species, metadata=metadata)
  pkgname <- pkgnames[["orgdb"]]
  if (isTRUE(pkgnames[["orgdb_installed"]]) & !isTRUE(reinstall)) {
    message(paste0(pkgname, " is already installed, set reinstall=TRUE if you wish to reinstall."))
    retlist <- list(
      "orgdb_name" = pkgname
    )
    return(retlist)
  }

  if (!file.exists(dir)) {
    created <- dir.create(dir, recursive=TRUE)
  }

  do_kegg <- TRUE
  if (is.null(kegg_abbreviation)) {
    kegg_abbreviation <- get_kegg_orgn(paste0(taxa[["genus"]], " ", taxa[["species"]]))
    if (length(kegg_abbreviation) == 0) {
      do_kegg <- FALSE
    }
  }

  ## save gff as tempfile
  input_gff <- file.path(dir, paste0(pkgname, ".gff"))
  downloaded <- download.file(entry[["SourceUrl"]], input_gff, quiet=FALSE)

  ## get chromosome information from GFF file
  gff <- try(rtracklayer::import.gff3(input_gff))
  genes <- data.frame()
  chr_mapping <- data.frame()
  if (class(gff) == "try-error") {
    message(paste0("Check the file ", input_gff, " for problems."))
  } else {
    ## gene/chr mapping
    genes <- gff[gff$type == "gene"]
    chr_mapping <- data.frame(
      "GID" = genes$ID,
      "CHR" = as.character(GenomicRanges::seqnames(genes)),
      stringsAsFactors=FALSE)
  }

  tables <- list(
    "gff" = NULL,
    "genes" = NULL,
    "go" = NULL, 
    "pathways" = NULL,
    "interpro" = NULL, 
    "kegg" = NULL, 
    "orthologs" = NULL)
  res <- NULL
  chosen_provider <- entry[["DataProvider"]]
  chosen_species <- entry[["Species"]]
  results <- list()
  for (c in 1:length(names(tables))) {
    type <- names(tables)[c]
    results[[type]] <- do_eupath_table(
      type, provider=chosen_provider, species=chosen_species, genus_species=taxa[["genus_species"]],
      flatten=FALSE, abbreviation=kegg_abbreviation, granges=gff, dir=dir, do_kegg=do_kegg)
    tables[[type]] <- results[[type]][["result"]]
    if (is.null(tables[[type]])) {
      message(paste0("After do_eupath_table, the ", type, " table is still empty."))
      tables[[type]] <- data.frame()
    }
  }
  rm(results)

  if (nrow(tables[["gff"]]) == 0) {
    message("Something is wrong with the gene_info table.")
    message("Rerunning gene_info generator.")
    tmp <- do_eupath_table("gff", granges=gff, dir=dir)
    tables[["gff"]] <- tmp[["result"]]
    rm(tmp)
  }
  if (nrow(tables[["genes"]]) == 0) {
    message("Something is wrong with the gene types table.")
    message("Rerunning the genes generator.")
    tmp <- do_eupath_table("genes",
                           provider=chosen_provider,
                           species=chosen_species,
                           dir=dir)
    tables[["genes"]] <- tmp[["result"]]
    rm(tmp)
  }

  ## Compile list of arguments for makeOrgPackage call
  version_string <- format(Sys.time(), "%Y.%m")
  orgdb_args <- list(
    "gene_info"  = tables[["gff"]],
    "chromosome" = chr_mapping,
    "type" = tables[["genes"]],
    "version" = version_string,
    "author" = entry[["Maintainer"]],
    "maintainer" = entry[["Maintainer"]],
    "tax_id" = as.character(entry[["TaxonomyId"]]),
    "genus" = taxa[["genus"]],
    "species" = paste0(taxa[["species_strain"]], ".v", entry[["SourceVersion"]]),
    ##unlink = TRUE,
    "outputDir" = dir)
  
  ## add non-empty tables
  if (is.null(tables[["go"]])) {
    message("This should not be possible, but the go table is still null.")
  } else if (nrow(tables[["go"]]) > 0) {
    orgdb_args[["go"]] <- tables[["go"]]
  }

  if (is.null(tables[["pathways"]])) {
    message("This should not be possible, but the pathways table is still null.")
  } else if (nrow(tables[["pathways"]]) > 0) {
    orgdb_args[["pathways"]] <- tables[["pathways"]]
  }

  if (is.null(tables[["interpro"]])) {
    message("This should not be possible, but the interpro table is still null.")
  } else if (nrow(tables[["interpro"]]) > 0) {
    orgdb_args[["interpro"]] <- tables[["interpro"]]
  }

  if (is.null(tables[["orthologs"]])) {
    message("This should not be possible, but the orthologs table is still null.")
  } else if (nrow(tables[["orthologs"]]) > 0) {
    orgdb_args[["orthologs"]] <- tables[["orthologs"]]
  }

  if (is.null(tables[["kegg"]])) {
    message("This should not be possible, but the kegg table is still null.")
  } else if (nrow(tables[["kegg"]]) > 0) {
    orgdb_args[["kegg"]] <- tables[["kegg"]]
  }

  ## Make sure no duplicated stuff snuck through, or makeOrgPackage throws an error.
  ## Make sure that every GID field is character, too
  ## -- otherwise you get 'The type of data in the 'GID' columns must be the same for all data.frames.'
  for (i in 1:length(orgdb_args)) {
    if (class(orgdb_args[[i]]) == "data.frame") {
      ## First swap out NA to ""
      na_tmp <- orgdb_args[[i]]
      na_set <- is.na(na_tmp)
      na_tmp[na_set] <- ""
      orgdb_args[[i]] <- na_tmp
      ## Then remove duplicated elements.
      orgdb_dups <- duplicated(orgdb_args[[i]])
      if (sum(orgdb_dups) > 0) {
        tmp <- orgdb_args[[i]]
        tmp <- tmp[!orgdb_dups, ]
        orgdb_args[[i]] <- tmp
      }
      ## Finally, make sure all GID columns are characters
      orgdb_args[[i]][["GID"]] <- as.character(orgdb_args[[i]][["GID"]])
    }
  }

  tt <- sm(require("AnnotationForge"))
  message(sprintf("- Calling makeOrgPackage for %s", entry[["Species"]]))
  ## The following lines are because makeOrgPackage fails stupidly if the directory exists.
  backup_path <- file.path(dir, paste0(pkgname, ".bak"))
  first_path <- file.path(dir, pkgname)
  if (file.exists(backup_path)) {
    message(paste0(backup_path, " already exists, deleting it."))
    ret <- unlink(backup_path, recursive=TRUE)
  }
  if (file.exists(first_path)) {
    message(paste0(first_path, " already exists,
 backing it up."))
    ret <- file.rename(first_path, backup_path)
  }
  orgdb_path <- sm(try(do.call("makeOrgPackage", orgdb_args)))
  if (class(orgdb_path) == "try-error") {
    return(NULL)
  }

  ## Fix name in sqlite metadata table
  dbpath <- file.path(
    orgdb_path, "inst/extdata", sub(".db", ".sqlite", basename(orgdb_path)))
  message(sprintf("- Fixing sqlite Orgdb sqlite database %s", dbpath))

  ## make sqlite database editable
  Sys.chmod(dbpath, mode='0644')
  db <- RSQLite::dbConnect(RSQLite::SQLite(), dbname=dbpath)
  ## update SPECIES field
  query <- sprintf('UPDATE metadata SET value="%s" WHERE name="SPECIES";', entry[["Species"]])
  sq_result <- RSQLite::dbSendQuery(conn=db, query)
  ## update ORGANISM field
  query <- sprintf('UPDATE metadata SET value="%s" WHERE name="ORGANISM";', entry[["Species"]])
  sq_result <- RSQLite::dbSendQuery(conn=db, query)
  ## lock it back down
  Sys.chmod(dbpath, mode="0444")

  ## Clean up any strangeness in the DESCRIPTION file
  orgdb_path <- sm(clean_pkg(orgdb_path))
  orgdb_path <- sm(clean_pkg(orgdb_path, removal="_", replace=""))
  orgdb_path <- sm(clean_pkg(orgdb_path, removal="_like", replace="like"))
  testthat::expect_equal(first_path, orgdb_path)
  ## And install the resulting package.
  inst <- sm(try(devtools::install(orgdb_path, quiet=TRUE)))
  if (class(inst) != "try-error") {
    built <- sm(try(devtools::build(orgdb_path, quiet=TRUE)))
    if (class(built) != "try-error") {
      final_deleted <- unlink(x=orgdb_path, recursive=TRUE, force=TRUE)
    }
  }

  ## return the path to the sqlite database
  retlist <- list(
    "orgdb_name" = pkgname
  )
  return(retlist)
}

#' Generate TxDb for EuPathDB organism
#'
#' @param species  guess
#' @param entry  One dimensional dataframe with organism metadata.
#' @param dir  Base directory for building the package.
#' @param reinstall  Overwrite an existing installed package?
#' @param metadata  dataframe of eupathdb metadata.
#' @param ...  Extra arguments for getting metadata.
#' @return TxDb instance name.
#' @author atb
#' @export
make_eupath_txdb <- function(species=NULL, entry=NULL, dir="eupathdb",
                             reinstall=FALSE, metadata=NULL, ...) {
  if (is.null(entry) & is.null(species)) {
    stop("Need either an entry or species.")
  } else if (is.null(entry)) {
    if (is.null(metadata)) {
      metadata <- sm(download_eupath_metadata(dir=dir, ...))
    }
    entry <- check_eupath_species(species=species, metadata=metadata)
  }
  taxa <- make_taxon_names(entry)
  pkgnames <- make_eupath_pkgnames(species=species, metadata=metadata)
  pkgname <- pkgnames[["txdb"]]

  if (isTRUE(pkgnames[["txdb_installed"]]) & !isTRUE(reinstall)) {
    message(paste0(pkgname, " is already installed, set reinstall=TRUE if you wish to reinstall."))
    retlist <- list(
      "txdb_name" = pkgname
    )
    return(retlist)
  }

  ## save gff as tempfile
  input_gff <- file.path(dir, paste0(pkgname, ".gff"))
  tt <- sm(download.file(url=entry[["SourceUrl"]], destfile=input_gff,
                         method="internal", quiet=FALSE))

  chr_entries <- read.delim(file=input_gff, header=FALSE, sep="")
  chromosomes <- chr_entries[["V1"]] == "##sequence-region"
  chromosomes <- chr_entries[chromosomes, c("V2", "V3", "V4")]
  colnames(chromosomes) <- c("ID", "start", "end")
  chromosome_info <- data.frame(
    "chrom" = chromosomes[["ID"]],
    "length" = as.numeric(chromosomes[["end"]]),
    "is_circular" = NA,
    stringsAsFactors=FALSE)

  txdb_metadata <- as.data.frame(t(entry))
  txdb_metadata[["name"]] <- rownames(txdb_metadata)
  colnames(txdb_metadata) <- c("value", "name")
  txdb_metadata <- txdb_metadata[, c("name", "value")]
  txdb <- sm(try(GenomicFeatures::makeTxDbFromGFF(
                                    file=input_gff,
                                    format="gff",
                                    chrominfo=chromosome_info,
                                    dataSource=entry[["SourceUrl"]],
                                    organism=paste0(taxa[["genus"]], " ", taxa[["species"]]),
                                    ## metadata=t(entry))
                                    )))
  if (class(txdb) == "try-error") {
    message("The txdb creation failed.")
    return(NULL)
  }

  ## This is the section I yanked
  provider <- GenomicFeatures:::.getMetaDataValue(txdb, "Data source")
  providerVersion <- GenomicFeatures:::.getTxDbVersion(txdb)
  dbType <- GenomicFeatures:::.getMetaDataValue(txdb, "Db type")
  authors <- GenomicFeatures:::.normAuthor(entry[["Maintainer"]], entry[["Maintainer"]])
  template_path <- system.file("txdb-template", package = "GenomicFeatures")
  version_string <- format(Sys.time(), "%Y.%m")
  symvals <- list(
    "PKGTITLE" = paste("Annotation package for", dbType, "object(s)"),
    "PKGDESCRIPTION" = paste("Exposes an annotation databases generated from",
                             GenomicFeatures:::.getMetaDataValue(txdb, "Data source"),
                             "by exposing these as", dbType, "objects"),
    "PKGVERSION" = version_string,
    "AUTHOR" = paste(authors, collapse = ", "),
    "MAINTAINER" = as.character(GenomicFeatures:::.getMaintainer(authors)),
    "GFVERSION" = GenomicFeatures:::.getMetaDataValue(txdb, "GenomicFeatures version at creation time"),
    "LIC" = "Artistic-2.0",
    "DBTYPE" = dbType,
    "ORGANISM" = GenomicFeatures:::.getMetaDataValue(txdb,"Organism"),
    "SPECIES" = GenomicFeatures:::.getMetaDataValue(txdb, "Organism"),
    "PROVIDER" = provider,
    "PROVIDERVERSION" = providerVersion,
    "RELEASEDATE" = GenomicFeatures:::.getMetaDataValue(txdb, "Creation time"),
    ## SOURCEURL = GenomicFeatures:::.getMetaDataValue(txdb, "Resource URL"),
    "SOURCEURL" = entry[["SourceUrl"]],
    "ORGANISMBIOCVIEW" = gsub(" ", "_", GenomicFeatures:::.getMetaDataValue(txdb, "Organism")),
    "TXDBOBJNAME" = pkgname)
  if (any(duplicated(names(symvals)))) {
    str(symvals)
    stop("'symvals' contains duplicated symbols")
  }
  is_OK <- sapply(symvals, S4Vectors::isSingleString)
  if (!all(is_OK)) {
    bad_syms <- paste(names(is_OK)[!is_OK], collapse=", ")
    stop("values for symbols ", bad_syms, " are not single strings")
  }
  if (!file.exists(dir)) {
    tt <- dir.create(dir, recursive=TRUE)
  }

  pkg_list <- sm(Biobase::createPackage(
                            pkgname=pkgname,
                            destinationDir=dir,
                            originDir=template_path,
                            symbolValues=symvals,
                            unlink=TRUE))
  db_dir <- file.path(dir, pkgname, "inst", "extdata")
  if (!file.exists(db_dir)) {
    tt <- dir.create(db_dir, recursive=TRUE)
  }
  db_path <- file.path(db_dir, paste(pkgname, "sqlite", sep="."))

  obj <- try(AnnotationDbi::saveDb(txdb, file=db_path))
  if (class(obj) == "try-error") {
    warning("Failed to save the txdb object.")
  }

  install_dir <- file.path(dir, pkgname)
  install_dir <- sm(clean_pkg(install_dir))
  install_dir <- sm(clean_pkg(install_dir, removal="_", replace=""))
  install_dir <- sm(clean_pkg(install_dir, removal="_like", replace="like"))

  inst <- sm(try(devtools::install(install_dir, quiet=TRUE)))
  if (class(inst) != "try-error") {
    built <- sm(try(devtools::build(install_dir, quiet=TRUE)))
    if (class(built) != "try-error") {
      final_deleted <- unlink(x=install_dir, recursive=TRUE, force=TRUE)
    }
  }

  retlist <- list(
    "txdb_name" = pkgname)
  return(retlist)
}

#' Iterate through the various ways of representing taxon names
#'
#' Spend some time making sure they are valid, too.  Thus we want to get rid of weird characters
#' like hash marks, pipes, etc.
#'
#' @param entry  An entry of the eupathdb metadata.
#' @return  A list of hopefully valid nomenclature names to be used elsewhere in this family.
make_taxon_names <- function(entry) {
  taxon <- entry[["Species"]]
  species_parts <- unlist(strsplit(taxon, " "))
  genus <- species_parts[1]
  first <- toupper(substring(genus, 1, 1))
  species <- species_parts[2]
  strain <- ""
  if (length(species_parts) >= 3) {
    for (part in 3:length(species_parts)) {
      strain <- paste0(strain, ".", species_parts[part])
    }
  }
  strain <- gsub(pattern="^\\.", replacement="", x=strain)

  ## Start by getting rid of annoying text
  strain_pattern <- "(_| |\\.)strain(_| |\\.)"
  taxon <- gsub(pattern=strain_pattern, replacement="\\1", x=taxon)
  genus <- gsub(pattern=strain_pattern, replacement="\\1", x=genus)
  species <- gsub(pattern=strain_pattern, replacement="\\1", x=species)
  strain <- gsub(pattern=strain_pattern, replacement="\\1", x=strain)

  ## Replace some annoying characters with .
  annoying_pattern <- "(_|-|#| )"
  taxon <- gsub(pattern=annoying_pattern, replacement="\\.", x=taxon)
  genus <- gsub(pattern=annoying_pattern, replacement="\\.", x=genus)
  species <- gsub(pattern=annoying_pattern, replacement="\\.", x=species)
  strain <- gsub(pattern=annoying_pattern, replacement="\\.", x=strain)

  ## Completely remove the truly stupid characters.
  stupid_pattern <- "(\\,|\\/|\\?|\\|\\[|\\])"
  taxon <- gsub(pattern=stupid_pattern, replacement="", x=taxon)
  genus <- gsub(pattern=stupid_pattern, replacement="", x=genus)
  species <- gsub(pattern=stupid_pattern, replacement="", x=species)
  strain <- gsub(pattern=stupid_pattern, replacement="", x=strain)

  ## There are a few extra-weirdos with double-.s
  silly_pattern <- "\\.\\."
  taxon <- gsub(pattern=silly_pattern, replacement="\\.", x=taxon)
  genus <- gsub(pattern=silly_pattern, replacement="\\.", x=genus)
  species <- gsub(pattern=silly_pattern, replacement="\\.", x=species)
  strain <- gsub(pattern=silly_pattern, replacement="\\.", x=strain)

  species_strain <- paste0(species, ".", strain)
  genus_species <- paste0(genus, ".", species)

  species_strain <- paste(unlist(strsplit(taxon, split="\\."))[-1], collapse=".")
  genus_species <- paste0(genus, ".", species)

  gspecies <- paste0(first, species)
  gsstrain <- paste0(gspecies, strain)

  taxa <- list(
    "taxon" = taxon,
    "genus" = genus,
    "species" = species,
    "strain" = strain,
    "species_strain" = species_strain,
    "genus_species" = genus_species,
    "gspecies" = gspecies,
    "gsstrain" = gsstrain)
  return(taxa)
}

#' Queries one of the EuPathDB APIs using a POST request and returns a
#' dataframe representation of the result.
#' Note: As of 2017/07/13, POST requests are not yet supported on EuPathDB.
#' Note: 2017/07/13 POST queries can only use the new API
#'
#' @param provider Name of data provider to query (e.g. 'TriTrypDB')
#' @param query_body String of additional query arguments
#' @return list containing response from API request.
#'
#' More information
#' ----------------
#' 1. http://tritrypdb.org/tritrypdb/serviceList.jsp
#' @author Keith Hughitt
post_eupath_query <- function(entry, query_body, minutes=20) {
  ## determine appropriate prefix to use
  prefix_mapping <- list(
    "amoebadb" = "amoeba",
    "microbiomedb" = "mbio",
    "microsporidiadb" = "micro",
    "piroplasmadb" = "piro",
    "plasmodb" = "plasmo",
    "schistodb" = "schisto",
    "toxodb" = "toxo"
  )
  provider <- tolower(entry[["DataProvider"]])
  uri_prefix <- provider
  if (uri_prefix %in% names(prefix_mapping)) {
    uri_prefix <- prefix_mapping[[uri_prefix]]
  }

  ##provider = "fungidb"
  ##uri_prefix = "fungidb"
  ##tt <- '{"answerSpec": {"questionName": "GeneQuestions.GenesByMolecularWeight","parameters": { "organism": "Aspergillus clavatus", "min_molecular_weight":"10000", "max_molecular_weight":"50000" }, "filters": [] }, "formatting": { "formatConfig": { "includeHeader": true, "attributes": [ "organism", "gene_type" ], "attachmentType": "plain" }, "format": "fullRecord" } }'
  ## tt =   '{"answerSpec":{"questionName": "GeneQuestions.GenesByMolecularWeight","parameters": { "organism": "Leishmania major strain Friedlin","min_molecular_weight":"10","max_molecular_weight":"500000"},"filters":[]},"formatting":{"formatConfig":{"includeHeader":true,"attributes":["organism", "gene_type"],"attachmentType":"plain"},"format":"fullRecord"}}'
  ## construct API query
  api_uri <- sprintf("http://%s.org/%s/service/answer", provider, uri_prefix)
  ##result <- httr::POST(api_uri, body=tt,
  body <- jsonlite::toJSON(query_body)
  result <- httr::POST(
                    api_uri,
                    body=body,
                    httr::content_type("application/json"),
                    httr::timeout(minutes * 60))
  ## check status
  ## if (res$status_code == 404) { ... }
  ## return response contents
  result <- httr::content(result)
  result <- read.delim(textConnection(result), sep="\t")

  ## If nothing was received, return nothing.
  if (nrow(result) == 0) {
    return(data.frame())
  }

  ## If a column is just 'X', then I think it can go away.
  non_stupid_columns <- colnames(result) != "X"
  result <- result[, non_stupid_columns]

  ## simplify column names
  ## > colnames(dat)
  ## [1] "X.Gene.ID."                        "X.pathway_source_id."
  ## [3] "X.Pathway."                        "X.Pathway.Source."
  ## [5] "X.EC.Number.Matched.in.Pathway."   "X.expasy_url."
  ## [7] "X...Reactions.Matching.EC.Number."
  new_colnames <- toupper(colnames(result))
  ## Get rid of dumb X. prefix
  new_colnames <- gsub("^X\\.+", replacement="", x=new_colnames)
  ## Get rid of spurious end .
  new_colnames <- gsub("\\.$", replacement="", x=new_colnames)
  ## Get rid of internal .'s
  new_colnames <- gsub("\\.", replacement="_", x=new_colnames)
  colnames(result) <- new_colnames
  colnames(result)[1] <- "GID"
  ## remove duplicated rows
  result <- result[!duplicated(result), ]
  return(result)
}

post_eupath_go_table <- function(species="Leishmania major", entry=NULL,
                                 metadata=NULL, overwrite=FALSE, dir="eupathdb") {
  if (is.null(entry) & is.null(species)) {
    stop("Need either an entry or species.")
  } else if (is.null(entry)) {
    if (is.null(metadata)) {
      metadata <- sm(download_eupath_metadata(dir=dir, ...))
      ## metadata <- sm(download_eupath_metadata(dir=dir))
    }
    entry <- check_eupath_species(species=species, metadata=metadata)
  }
  ## query body as a structured list
  ## Parameters taken from the pdf "Exporting Data - Web Services.pdf" received
  ## from Cristina
  query_body <- list(
    ## 3 elements, answerSpec, formatting, format.
    "answerSpec" = list(
      "questionName" = jsonlite::unbox("GeneQuestions.GenesByTaxonGene"),
      "parameters" = list("organism" = jsonlite::unbox(species)),
      "viewFilters" = list(),
      "filters" = list()
    ),
    "formatting" = list(
      "formatConfig" = list(
        "tables" = "GOTerms",
        "includeEmptyTables" = jsonlite::unbox("true"),
        "attachmentType" = jsonlite::unbox("plain")
      ),
      "format" = jsonlite::unbox("tableTabular")
    ))

  message("Posting these queries might take a while, be warned.")
  result <- post_eupath_query(entry, query_body)

  return(result)
}

post_eupath_ortholog_table <- function(species="Leishmania major", entry=NULL,
                                       metadata=NULL, overwrite=FALSE, dir="eupathdb") {
  if (is.null(entry) & is.null(species)) {
    stop("Need either an entry or species.")
  } else if (is.null(entry)) {
    if (is.null(metadata)) {
      metadata <- sm(download_eupath_metadata(dir=dir, ...))
      ##metadata <- sm(download_eupath_metadata(dir=dir))
    }
    entry <- check_eupath_species(species=species, metadata=metadata)
  }
  ## query body as a structured list
  query_body <- list(
    "answerSpec" = list(
      "questionName" = jsonlite::unbox("GeneQuestions.GenesByTaxonGene"),
      "parameters" = list("organism" = jsonlite::unbox(species)),
      "viewFilters" = list(),
      "filters" = list()
    ),
    "formatting" = list(
      "formatConfig" = list(
        "tables" = "MetabolicPathways",
        "includeHeader" = jsonlite::unbox("true"),
        "attachmentType" = jsonlite::unbox("plain")
      ),
      "format" = jsonlite::unbox("tableTabular")
    ))

  message("Posting these queries might take a while, be warned.")
  result <- post_eupath_query(entry, query_body)
  return(result)
}

post_eupath_pathway_table <- function(species="Leishmania major", entry=NULL,
                                      metadata=NULL, overwrite=FALSE, dir="eupathdb") {
  if (is.null(entry) & is.null(species)) {
    stop("Need either an entry or species.")
  } else if (is.null(entry)) {
    if (is.null(metadata)) {
      metadata <- sm(download_eupath_metadata(dir=dir, ...))
      ## metadata <- sm(download_eupath_metadata(dir=dir))
    }
    entry <- check_eupath_species(species=species, metadata=metadata)
  }
  ## query body as a structured list
  query_body <- list(
    "answerSpec" = list(
      "questionName" = jsonlite::unbox("GeneQuestions.GenesByTaxonGene"),
      "parameters" = list(organism=jsonlite::unbox(species)),
      "viewFilters" = list(),
      "filters" = list()
    ),
    "formatting" = list(
      "formatConfig" = list(
        "tables" = "MetabolicPathways",
        "includeHeader" = jsonlite::unbox("true"),
        "attachmentType" = jsonlite::unbox("plain")
      ),
      "format" = jsonlite::unbox("tableTabular")
    ))
  result <- post_eupath_query(entry, query_body)
  return(result)
}

post_eupath_text <- function(species="Leishmania major", entry=NULL,
                             metadata=NULL, overwrite=FALSE, dir="eupathdb") {
  if (is.null(entry) & is.null(species)) {
    stop("Need either an entry or species.")
  } else if (is.null(entry)) {
    if (is.null(metadata)) {
      metadata <- sm(download_eupath_metadata(dir=dir, ...))
      ## metadata <- sm(download_eupath_metadata(dir=dir))
    }
    entry <- check_eupath_species(species=species, metadata=metadata)
    species <- entry[["Species"]]
  }
  ## query body as a structured list
  field_list <- c(
    "primary_key", "sequence_id", "chromosome", "organism", "gene_type", "gene_location_text",
    "gene_name", "gene_exon_count", "is_pseudo", "gene_transcript_count", "gene_ortholog_number",
    "gene_paralog_number", "gene_orthomcl_name", "gene_total_hts_snps",
    "gene_hts_nonsynonymous_snps", "gene_hts_noncoding_snps", "gene_hts_stop_codon_snps",
    "gene_hts_nonsyn_syn_ratio", "uniprot_id", "gene_entrez_id", "transcript_length",
    "exon_count", "strand", "cds_length", "tm_count", "molecular_weight", "isoelectric_point",
    "signalp_scores", "signalp_peptide", "annotated_go_function", "annotated_go_process",
    "annotated_go_component", "annotated_go_id_function", "annotated_go_id_process",
    "annotated_go_id_component", "predicted_go_id_function", "predicted_go_id_process",
    "predicted_go_id_component", "ec_numbers", "ec_numbers_derived", "five_prime_utr_length",
    "three_prime_utr_length", "location_text", "gene_previous_ids", "protein_sequence", "cds")

  query_body <- list(
    "answerSpec" = list(
      ## So, using GenesByTaxon or GenesByTaxonGene both fail with utterly spurious crap
      ## about not providing the proper formatting, so since this is the example the pdf
      ## gave me, I will  use it with utterly stupid values.
      "questionName" = jsonlite::unbox("GeneQuestions.GenesByMolecularWeight"),
      "parameters" = list(
        "organism" = jsonlite::unbox(species),
        "min_molecular_weight" = jsonlite::unbox("1"),
        "max_molecular_weight" = jsonlite::unbox("10000000000000000")
        ),
      "filters" = list()),
    "formatting" = list(
      "formatConfig" = list(
        "includeHeader" = jsonlite::unbox("true"),
        "attributes" = field_list,
        "attachmentType" = jsonlite::unbox("plain")),
      "format" = jsonlite::unbox("fullRecord"))
  )
  body <- jsonlite::toJSON(query_body)
  ## The following is a known valid json input.  The formatting of my query body
  ## must be precisely the same as the following format, or some form of error 400 will happen.
  ##tt <- '{"answerSpec": {"questionName": "GeneQuestions.GenesByMolecularWeight",
  ##           "parameters": { "organism": "Leishmania major strain Friedlin",
  ##                           "min_molecular_weight":"10000",
  ##                           "max_molecular_weight":"50000" },
  ##           "filters": [] },
  ##        "formatting": { "formatConfig": { "includeHeader": true,
  ##                        "attributes": [ "primary_key", "organism", "gene_type" ],
  ##                        "attachmentType": "plain" },
  ##         "format": "fullRecord" } }'
  ## body

  ## We should have a valid request now, so send it to the eupathdb server and see what happens...
  result <- httr::POST(api_uri, body=body, httr::content_type("application/json"),
                       httr::timeout(minutes * 60))
  ## Get the content, this will take a while, as the result from eupathdb might be > 50 Mb of stuff.
  cont <- httr::content(result)
  ## Sadly, most of that stuff is completely unwanted.  This is because we are using the
  ## 'fullRecord' format, as it is the only format I have been able to get to work so far.
  ## This format is newline separated fields with entries separated by 4 returns with dashes...
  ## Ergo the following line, which separates the entries by the dashes/returns into individual
  ## strings with the newlines remaining inside them.  So we will need to use some regular
  ## expressions in order to extract the column names and data.
  entries <- strsplit(x=cont, split="\n\n------------------------------------------------------------\n\n")[[1]]
  ## We will read the first entry in order to extract the column names.
  stuff <- read.delim(textConnection(entries[1]), sep="\n", header=FALSE)
  ## My regular expression pattern needs to by greedy in the correct places
  ## because for reasons passing all understanding, some fields have colons inside them...
  mypattern <- "^(.+?)\\: (.+)?$"
  ## If I am going to make column names, I need first to get the first part of stuff: otherstuff
  column_names <- gsub(pattern=mypattern, replacement="\\1", x=stuff[["V1"]], perl=TRUE)
  ## Then get rid of any punctuation, as there is a column '# TM domains' -- that is bad.
  column_names <- gsub(pattern="[[:punct:]]", replacement="", x=column_names)
  ## Get rid of any extraneous spaces from removing punctuation, but since I cannot be certain
  ## that there is no punctuation in the middle of words, just look at the beginning of the strings.
  column_names <- gsub(pattern="^ +", replacement="", x=column_names)
  ## Finally, I do not accept column names with spaces.
  column_names <- gsub(pattern=" ", replacement="_", x=column_names)
  column_names[1] <- "GID"
  tmp <- data.frame(row.names=1:length(entries))
  for (col in column_names) {
    new_col <- rep(NA, times=length(entries))
    tmp <- cbind(tmp, new_col)
  }
  colnames(tmp) <- column_names
  bar <- utils::txtProgressBar(style=3)
  ## Now fill in the data using the other side of my regular expression.
  for (c in 1:length(entries)) {
    pct_done <- c / length(entries)
    setTxtProgressBar(bar, pct_done)
    stuff <- read.delim(textConnection(entries[c]), sep="\n", header=FALSE)
    material <- gsub(pattern="^(.+?)\\: (.+)?$", replacement="\\2", x=stuff[["V1"]])
    tmp[c, ] <- material
  }
  close(bar)
  information <- data.table::as.data.table(tmp)
  return(information)
}

#' Queries one of the EuPathDB APIs using a GET request and returns a dataframe
#' representation of the result.
#'
#' @param provider Name of data provider to query (e.g. 'TriTrypDB')
#' @param species Full name of organism, as used by EuPathDB APIs
#' @param dir  Where to place the data
#' @param prefix  A prefix when writing the data file
#' @param query_args String of additional query arguments
#' @param wadl String specifying API service to be queried
#' @param format String specifying API response type (currently only 'json'
#'        is supported)
#' @return list containing response from API request.
#'
#' More information
#' ----------------
#' 1. http://tritrypdb.org/tritrypdb/serviceList.jsp
#' @author Keith Hughitt
query_eupathdb <- function(provider="TriTrypDB", species="Leishmania major",
                           dir="eupathdb", prefix="table", query_args=NULL,
                           wadl="GeneQuestions/GenesByTaxon", format="json") {
  ## construct API query
  base_url <- sprintf("http://%s.org/webservices/%s.%s?",
                      tolower(provider), wadl, format)
  ## add organism to query arguments
  query_args[["organism"]] <- utils::URLencode(species, reserved=TRUE)
  query_string <- paste(paste(names(query_args), query_args, sep="="), collapse="&")
  request_url <- paste0(base_url, query_string)
  message(sprintf("- Querying %s", request_url))
  result <- NULL
  destfile <- paste0(dir, "/", provider, "_", prefix, ".json")
  if (!file.exists(destfile)) {
    original_options <- options(timeout=300)
    file <- download.file(url=request_url, destfile=destfile, method="curl", quiet=TRUE)
    temp_options <- options(original_options)
  }
  result <- jsonlite::fromJSON(destfile)
  message("- Finished query.")
  return(result)
}

#' Queries one of the EuPathDB APIs for gene data
#'
#' Note that as of version 30, EuPathDB no longer supports table queries for
#' genes, and as such this method must be used instead. Support for tables
#' queries is likely to be returned in future versions of EuPathDB.
#'
#' @param provider Name of data provider to query (e.g. 'TriTrypDB')
#' @param species Full name of organism, as used by EuPathDB APIs
#' @param table Name of the particular table to be retrieved (e.g.
#' 'GoTerms')
#' @param wadl String specifying API service to be queried
#' @param format String specifying API response type (currently only 'json'
#'        is supported)
#' @param overwrite  Overwrite existing data?
#' @param dir  Where to place the downloaded information?
#' @return list containing response from API request.
#' @author Keith Hughitt
retrieve_eupathdb_attributes <- function(provider="TriTrypDB",
                                         species="Leishmania major",
                                         table="GOTerms",
                                         wadl="GeneQuestions/GenesByTaxonGene",
                                         format="json",
                                         overwrite=FALSE,
                                         dir="eupathdb") {
  ## Adding a savefile check because the eupathdb does not always respond in a timely manner.
  savefile <- file.path(dir, paste0(table, "-v", format(Sys.time(), "%Y%m"), ".rda"))
  if (isTRUE(overwrite)) {
    file.remove(savefile)
  }
  if (!file.exists(dir)) {
    dir.create(dir, recursive=TRUE)
  }
  if (file.exists(savefile)) {
    result <- new.env()
    loaded <- load(savefile, envir=result)
    result <- result[["result"]]
    return(result)
  }

  ## query EuPathDB API
  res <- query_eupathdb(
    provider=provider,
    species=species,
    dir=dir,
    prefix=table,
    query_args=list(
      `o-tables`=table,
      `o-fields`="primary_key"),
    wadl=wadl,
    format="json")
  dat <- res[["response"]][["recordset"]][["records"]]
  if (is.null(dat)) {
    message(paste0("Nothing was returned for the ", table, " table."))
    return(NULL)
  }

  message(sprintf("- Parsing %s table for %s.", table, species))
  ## drop genes with no associated table entries
  gene_mask <- sapply(dat[, "tables"], function(x) { length(x[["rows"]][[1]]) > 0})
  dat <- dat[gene_mask, ]
  ## create empty data frame to store result in
  result <- data.frame(stringsAsFactors=FALSE)
  ## if no rows found, return empty data.frame
  if (nrow(dat) == 0) {
    return(result)
  }

  ## fix id field
  dat[["id"]] <- unlist(sapply(dat[["fields"]], function(x) { strsplit(x[, "value"], ",")[1] }))
  message(sprintf("- Parsing %d rows in %s table for %s.", nrow(dat), table, species))
  bar <- utils::txtProgressBar(style=3)
  ## iterate over remaining genes and extract table entries for them
  for (i in 1:nrow(dat)) {
    pct_done <- i / nrow(dat)
    setTxtProgressBar(bar, pct_done)
    ## example entry:
    ##
    ## > dat$tables[[1]]$rows[[1]]$fields[[1]]
    ##         name                      value
    ## 1         go_id                 GO:0007018
    ## 2      ontology         Biological Process
    ## 3  go_term_name microtubule-based movement
    ## 4        source                   Interpro
    ## 5 evidence_code                        IEA
    ## 6        is_not                       <NA>
    table_entries <- dat[["tables"]][[i]]
    rows <- t(sapply(table_entries[["rows"]][[1]][["fields"]], function(x) { x[["value"]] }))
    result <- rbind(result, cbind(dat[["id"]][i], rows))
  }
  close(bar)

  for (col in colnames(result)) {
    if (class(result[[col]]) != "numeric") {
      result[[col]] <- as.character(result[[col]])
    }
  }
  ## set column names for result
  colnames(result) <- c("GID", dat[["tables"]][[1]][["rows"]][[1]][["fields"]][[1]][["name"]])

  if (isTRUE(overwrite) | !file.exists(savefile)) {
    saved <- save(list="result", file=savefile)
  }
  return(result)
}

## EOF