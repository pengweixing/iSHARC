################################################################################
## extended analyses based on integrated RNA and ATAC for each individual sample
## The analyses includes:
##      * cell type annotation
##      * Identify cluster specific DEGs and enriched functions
##      * Identify cluster specific DARs and enriched motif/TFs
##      * Gene regulatory network analysis
##
## Contact : Yong Zeng <yong.zeng@uhn.ca>
################################################################################


##############################
### parse and assign arguments
##############################
{
suppressPackageStartupMessages(library("argparse"))

## crash helper: show error + call stack so we can locate failing line
options(error = function() {
  message("ERROR: ", geterrmessage())
  traceback(2)
  quit(status = 1)
})

# create parser object
parser <- ArgumentParser()

## adding parameters
## by default ArgumentParser will add an help option
## run "Rscript main_for_individual_sample.R -h" for help info
parser$add_argument("-s", "--sample_id", required=TRUE,
                    help = "Unique sample ID")
parser$add_argument("-vio", "--vertically_integrated_seurat_object", required=TRUE,
                    help = "the seurat object with vertically integrated ATAC and RNA using WNN")
parser$add_argument("-pipe", "--pipe_dir", required=TRUE,
                    help = "The PATH to iSHARC pipeline, which local dependences included")
parser$add_argument("-t", "--threads", type = "integer", default = 12,
                    help = "Number of cores for the parallelization")
parser$add_argument("-fgm", "--future_globals_maxSize", type = "integer", default = 12,
                    help = "Maximum memory in GB for the future parallelization global variables")



## assigning passing arguments
args <- parser$parse_args()
print(args)

sample_id <- args$sample_id
vio_file <- args$vertically_integrated_seurat_object
pipe_dir <- args$pipe_dir


## output dir
out_dir <- paste0(getwd(), "/individual_samples/", sample_id, "/") ## with forward slash at the end
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

}


############################
### loading required packages
#############################
suppressMessages(library(Seurat))
suppressMessages(library(Signac))
suppressMessages(library(SingleR))
suppressMessages(library(clusterProfiler))
suppressMessages(library(JASPAR2020))
suppressMessages(library(org.Hs.eg.db))
suppressMessages(library(BSgenome.Hsapiens.UCSC.hg38))

suppressMessages(library(dplyr))
suppressMessages(library(tidygraph))
suppressMessages(library(tidyverse))
suppressMessages(library(ggplot2))
suppressMessages(library(ggraph))
suppressMessages(library(TFBSTools))

## enable the Parallelization with the future packages
suppressMessages(library(future))
plan("multicore", workers = args$threads)
options(future.globals.maxSize = args$future_globals_maxSize * 1024^3)


#########################################
## loading packages from the dependencies

##
## loading the KEGG.db from the local, since it will be problematic for clusterProfiler's defaultst KEGG analysis require internet access
## https://github.com/YuLab-SMU/createKEGGdb/tree/master
library(KEGG.db)
## install "dlm", which is required for copykat
library(dlm)
library(copykat)
## load Pando
## require seuratObject < 5.0.0;
library(Pando)
suppressMessages(library(doParallel))       ## parallelization for pando


##############################################################
## annotating the cell clusters with integrated ATAC and RNA
##############################################################
## readin vertically integrated seurat object
scMultiome <- readRDS(vio_file)

## ensure the active.ident is WNN_Clusters
scMultiome  <- SetIdent(scMultiome , value = scMultiome@meta.data$WNN_clusters)

##############################################################
## auto annotation using publicly available reference datasets
## anno_ref <-  BlueprintEncodeData()       ## form package celldex, internet required
ref_rds_candidates <- c("/data/BlueprintEncodeData.RDS")

if (dir.exists("/data")) {
  list.files("/data")
} else {
  message("/data does not exist")
}
ref_rds <- ref_rds_candidates[file.exists(ref_rds_candidates)][1]
if (is.na(ref_rds) || !nzchar(ref_rds)) {
  stop(
    "Cannot find BlueprintEncodeData.RDS. Checked: ",
    paste(ref_rds_candidates, collapse = ", ")
  )
}
anno_ref <- readRDS(ref_rds)

## fetch SCT normalized GEX matrix
expr <- GetAssayData(object = scMultiome, assay = "SCT", layer = "data")

### using ENCODE
expr_anno <- SingleR(test = expr, ref = anno_ref, labels = anno_ref$label.main, clusters =  Idents(scMultiome))

## match cluster labels and annotated labels
idx_m <- match(Idents(scMultiome), rownames(expr_anno))

## add labels scMultiome object
scMultiome[["WNN_clusters_singler_annot"]] <- expr_anno$labels[idx_m]

############################################################
## Distinguish the tumor cells from the normal cells
if(TRUE){
## Using copyKAT  to predicts tumor and normal cells
## RNA-seq data based

old_wd <- getwd()
setwd(out_dir)                                     ## ensure output copykat related results to desired folder

expr_raw <- as.matrix(GetAssayData(object = scMultiome, assay = "RNA", layer = "counts"))
copykat_rds <- paste0(out_dir, sample_id, "_copykat_res.RDS")
if (file.exists(copykat_rds)) {
  copykat_res <- readRDS(copykat_rds)
} else {
  copykat_res <- copykat(rawmat = expr_raw, sam.name = sample_id , id.type = "S", ngene.chr = 5, win.size = 25,
                         KS.cut = 0.1,  distance = "euclidean", norm.cell.names = "", output.seg = "FLASE",
                         plot.genes = "TRUE", genome = "hg20", n.cores = 1)
  saveRDS(copykat_res, copykat_rds)
}

## adding copykat predict labels to the scMultiome metatable
idx_s <- match(rownames(scMultiome@meta.data),copykat_res$prediction$cell.names)

cell_type <- rep("not.predicted", length(idx_s))    ## there are cells will excluded for copykat prediction
cell_type[!is.na(idx_s)] <- copykat_res$prediction$copykat.pred[idx_s[!is.na(idx_s)]]

scMultiome[["WNN_clusters_copykat_annot"]] <- cell_type

setwd(old_wd)  ## restore working directory
}

print("The annotation has been successfully completed!!")


##########################################
# identify cluster-specific genes (DEGs)
## plus one vs other :: cluster markers
## results were add to seuratObject@misc
########################################
{
clusters <- scMultiome@meta.data$WNN_clusters_singler_annot
cluster_cnt <- table(clusters)

DefaultAssay(scMultiome) <- "SCT"
Idents(scMultiome) <- 'WNN_clusters_singler_annot'

sct_deg   <- vector("list", length = length(clusters))
deg_list  <- vector("list", length = length(clusters))
names(sct_deg)  <- clusters
names(deg_list) <- clusters

################
## Identify DEGs
for (i in clusters) {
  print(i)

  n_i <- unname(cluster_cnt[i])
  if (is.na(n_i) || n_i <= 3) {
    sct_deg[i]   <- list(NULL)       
    deg_list[[i]] <- character(0)
    next
  }

  mk <- FindMarkers(
    scMultiome,
    ident.1 = i,          
    ident.2 = NULL,
    min.pct = 0.5,
    logfc.threshold = log(2),
    min.diff.pct = 0.25
  )

  sct_deg[[i]] <- mk

  mk_up <- mk[mk$avg_log2FC > 0, , drop = FALSE]
  if (nrow(mk_up) == 0) {
    deg_list[[i]] <- character(0)
    next
  }

  mk_up <- mk_up[order(mk_up$p_val_adj, mk_up$p_val), , drop = FALSE]
  deg_list[[i]] <- head(rownames(mk_up), 5)
}

names(sct_deg) <- clusters         ##sct_deg_names
deg_list <- unique(deg_list)        ## remove duplicates for the top 5 DEGs
Misc(scMultiome[["SCT"]], slot = "DEGs") <- sct_deg
Misc(scMultiome[["SCT"]], slot = "DEGs_top5") <- deg_list

#################################################################
### Functional enrichment analysis for WNN cluster-specific genes
if(TRUE){
    ## ID convert function
    id_convert <- function(x){

      library(clusterProfiler)

      g_symbol <- rownames(x)
      if(length(g_symbol) <= 10){
        ## requiring at least 10 genes
        g_ezid <- NULL
      } else {
        g_con <- bitr(g_symbol, fromType = "SYMBOL", toType = "ENTREZID", OrgDb="org.Hs.eg.db")
        g_ezid <- g_con$ENTREZID
      }

      return(g_ezid)
    }

    deg_list <- lapply(scMultiome@assays$SCT@misc$DEGs, id_convert)

    ## remove empty elements in the list
    deg_list <- deg_list[lapply(deg_list, length) > 0]

    ## KEGG enrichment
    compKEGG <- compareCluster(geneCluster   = deg_list,
                               fun           = "enrichKEGG",
                               pvalueCutoff  = 0.05,
                               pAdjustMethod = "BH",
                               use_internal_data =T)    ## using local build library "KEGG.db"

    #if(length(compKEGG@compareClusterResult$ID) > 0){
    if(length(compKEGG) > 0){
    p1 <- dotplot(compKEGG, showCategory = 1, title = "KEGG pathway enrichment") + labs(x = "") + scale_x_discrete(guide = guide_axis(angle = 45))
    ggsave(paste0(out_dir, sample_id, "_WNN_clusters_specific_DEGs_KEGG.pdf"), width = 12, height = 8)
    }

     ## GO enrichment
    compGO <- compareCluster(geneCluster   = deg_list ,
                             fun           = "enrichGO",
                             OrgDb='org.Hs.eg.db',
                             pvalueCutoff  = 0.05,
                             pAdjustMethod = "BH")

    #if(length(compGO@compareClusterResult$ID) > 0){
    if(length(compGO) > 0){
    p2 <- dotplot(compGO, showCategory = 2, title = "GO enrichment ") + labs(x = "") + scale_x_discrete(guide = guide_axis(angle = 45))
    ggsave(paste0(out_dir, sample_id, "_WNN_clusters_specific_DEGs_GO.pdf"), width = 12, height = 8)
    }
}



################################################################
## draw heat map for top 5 clusters specifically expressed genes

suppressPackageStartupMessages({
  library(rlang)
  library(grid)
  library(ComplexHeatmap)
  library(circlize)
  library(scales)
})

DoMultiBarHeatmap <- function (object,
                               features = NULL,
                               cells = NULL,
                               group.by = "ident",
                               additional.group.by = NULL,
                               additional.group.sort.by = NULL,
                               cols.use = NULL,
                               group.bar = TRUE,
                               disp.min = -2.5,
                               disp.max = NULL,
                               slot = "scale.data",
                               assay = NULL,
                               label = TRUE,
                               size = 5.5,
                               hjust = 0,
                               angle = 45,
                               raster = TRUE,
                               draw.lines = TRUE,
                               lines.width = NULL,
                               group.bar.height = 0.02,
                               combine = TRUE)
{
  cells <- cells %||% colnames(x = object)
  if (is.numeric(x = cells)) {
    cells <- colnames(x = object)[cells]
  }
  assay <- assay %||% DefaultAssay(object = object)
  DefaultAssay(object = object) <- assay
  features <- features %||% VariableFeatures(object = object)
  features <- unique(x = features)
  disp.max <- disp.max %||% ifelse(test = slot == "scale.data", yes = 2.5, no = 6)

  possible.features <- rownames(x = GetAssayData(object = object, layer = slot))
  if (any(!features %in% possible.features)) {
    bad.features <- features[!features %in% possible.features]
    features <- features[features %in% possible.features]
    if (length(x = features) == 0) {
      stop("No requested features found in the ", slot, " slot for the ", assay, " assay.")
    }
    warning("The following features were omitted as they were not found in the ",
            slot, " slot for the ", assay, " assay: ", paste(bad.features, collapse = ", "))
  }

  if (!is.null(additional.group.sort.by)) {
    if (any(!additional.group.sort.by %in% additional.group.by)) {
      bad.sorts <- additional.group.sort.by[!additional.group.sort.by %in% additional.group.by]
      additional.group.sort.by <- additional.group.sort.by[additional.group.sort.by %in% additional.group.by]
      if (length(x = bad.sorts) > 0) {
        warning("The following additional sorts were omitted as they were not a subset of additional.group.by : ",
                paste(bad.sorts, collapse = ", "))
      }
    }
  }

  data <- as.matrix(x = t(x = GetAssayData(object = object, layer = slot)[features, cells, drop = FALSE]))
  data[data < disp.min] <- disp.min
  data[data > disp.max] <- disp.max

  object <- suppressMessages(expr = StashIdent(object = object, save.name = "ident"))
  group.by <- group.by %||% "ident"
  groups.use <- object[[c(group.by, additional.group.by[!additional.group.by %in% group.by])]][cells, , drop = FALSE]

  plots <- list()
  for (i in group.by) {
    data.group <- data

    if (!is_null(additional.group.by)) {
      additional.group.use <- additional.group.by[additional.group.by != i]
      if (!is_null(additional.group.sort.by)) {
        additional.sort.use <- additional.group.sort.by[additional.group.sort.by != i]
      } else {
        additional.sort.use <- NULL
      }
    } else {
      additional.group.use <- NULL
      additional.sort.use <- NULL
    }

    group.use <- groups.use[, c(i, additional.group.use), drop = FALSE]
    for (colname in colnames(group.use)) {
      if (!is.factor(x = group.use[[colname]])) {
        group.use[[colname]] <- factor(x = group.use[[colname]])
      }
    }

    order_expr <- paste0("order(", paste(c(i, additional.sort.use), collapse = ","), ")")
    group.use <- with(group.use, group.use[eval(parse(text = order_expr)), , drop = FALSE])
    data.group <- data.group[rownames(group.use), , drop = FALSE]

    anno_df <- group.use
    anno_cols <- list()
    for (colname in colnames(anno_df)) {
      if (!is_null(cols.use[[colname]])) {
        levs <- levels(anno_df[[colname]])
        if (!is_null(names(cols.use[[colname]])) && all(levs %in% names(cols.use[[colname]]))) {
          anno_cols[[colname]] <- as.vector(cols.use[[colname]][levs])
        } else {
          if (length(cols.use[[colname]]) < length(levs)) {
            warning("Cannot use provided colors for ", colname, " since there aren't enough colors.")
            anno_cols[[colname]] <- scales::hue_pal()(length(levs))
          } else {
            anno_cols[[colname]] <- as.vector(cols.use[[colname]])[seq_len(length(levs))]
          }
        }
      } else {
        anno_cols[[colname]] <- scales::hue_pal()(length(levels(anno_df[[colname]])))
      }
      names(anno_cols[[colname]]) <- levels(anno_df[[colname]])
    }

    top_anno <- NULL
    if (group.bar) {
      top_anno <- HeatmapAnnotation(
        df = anno_df,
        col = anno_cols,
        which = "column",
        show_annotation_name = label,
        annotation_name_side = "right",
        annotation_name_gp = grid::gpar(fontsize = 8),
        annotation_legend_param = list(
          title_gp = grid::gpar(fontsize = 8),
          labels_gp = grid::gpar(fontsize = 7),
          nrow = 1
        )
      )
    }

    hm <- Heatmap(
      t(data.group),
      name = "Expression",
      cluster_rows = FALSE,
      cluster_columns = FALSE,
      show_column_names = FALSE,
      show_row_names = TRUE,
      top_annotation = top_anno,
      column_title = NULL,
      row_names_gp = grid::gpar(fontsize = size),
      use_raster = raster,
      heatmap_legend_param = list(title_gp = grid::gpar(fontsize = 8), labels_gp = grid::gpar(fontsize = 7)),
      col = circlize::colorRamp2(c(disp.min, 0, disp.max), c("#4DAF4A", "#000000", "#E41A1C"))
    )

    plots[[i]] <- hm
  }

  if (combine) {
    ht <- Reduce(`+`, plots)
    return(draw(ht, heatmap_legend_side = "right", annotation_legend_side = "right"))
  }
  return(plots)
}

if(length(deg_list) > 0) {
# Show we can sort sub-bars
#DoHeatmap(scMultiome, features = deg_list, size = 4, angle = 0)
deg_by_ct <- scMultiome[["SCT"]]@misc$DEGs_top5   # list: each element = top5 vector
features_use <- unlist(deg_by_ct, use.names = FALSE)
features_use <- features_use[!duplicated(features_use)]


options(repr.plot.width = 10)
DoMultiBarHeatmap(scMultiome, features = features_use, assay = 'SCT',
                  group.by='WNN_clusters_singler_annot', label = FALSE,
                  additional.group.by = c('WNN_clusters_copykat_annot', "Phase", 'ATAC_clusters',  'RNA_clusters', 'WNN_clusters'))
               #   additional.group.sort.by = c('WNN_clusters_singler_annot'))
ggsave(paste0(out_dir, sample_id, "_top5_WNN_clusters_specific_DEGs_heatMap.pdf"), width = 16, height = 8.5)
ggsave(paste0(out_dir, sample_id, "_top5_WNN_clusters_specific_DEGs_heatMap.png"), width = 16, height = 8.5)


##############################
## Linking peaks to top 5 DEGs
DefaultAssay(scMultiome) <- "ATAC"
bsgenome <- BSgenome.Hsapiens.UCSC.hg38     ## for GC correction

# first compute the GC content for each peak
scMultiome <- RegionStats(scMultiome, genome = bsgenome)

# link peaks to specified genes
## by computing the correlation between gene expression and accessibility at nearby peaks,
## and correcting for bias due to GC content, overall accessibility, and peak size,
## eg for top 5 DEGs per clusters

## will be saved to scMultiome@assays$ATAC@links
scMultiome <- LinkPeaks(
  object = scMultiome,
  peak.assay = "ATAC",
  expression.assay = "SCT",     ## all genes in SCT is time consuming !!!
  genes.use = scMultiome@misc$SCT_DEGs_top5
)
write.csv(Links(scMultiome), paste0(out_dir, sample_id, "_top5_WNN_clusters_specific_DEGs_linked_peaks.csv"))
}

print("The analysis of WNN clusters specific DEGs has been successfully completed!!")
}


############################################################
# identify cluster-specific DNA accessible regions (DARs)
## plus one vs other :: cluster markers
## results were add to seuratObject@misc
############################################################

# motif matrices from the JASPAR database
pfm <- getMatrixSet(x = JASPAR2020,
                      opts = list(collection = "CORE", species = "Homo sapiens"))
DefaultAssay(scMultiome) <- "ATAC"                      
saveRDS(scMultiome,file = paste0(out_dir, sample_id, "_scMultiome_before_motif.RDS"))
print(scMultiome)
# add motif information to scMultiome
scMultiome <- AddMotifs(object = scMultiome,
                        genome = BSgenome.Hsapiens.UCSC.hg38,
                        pfm = pfm)

### DARs and motif enrichment
clusters <- unique(scMultiome@meta.data$WNN_clusters_singler_annot)
cluster_cnt <- table(clusters)
print(cluster_cnt)

DefaultAssay(scMultiome) <- "ATAC"
atac_dar <- list()
atac_dar_motif <- list()
#top_dar <- list()         ## top DARs for motif enrichment analysis
enriched_motifs <- vector()     ## top 5 per cluster
atac_dar_names <- c()

## identify DARs
## identify DARs
for (i in clusters)
{
  n_i <- unname(cluster_cnt[as.character(i)])

  if(is.na(n_i) || n_i <= 3){

    atac_dar[[i]] <- list()
    atac_dar_motif[[i]] <- list()

  } else {

  ## one vs all others: prefiltering
  atac_dar[[i]] <- FindMarkers(scMultiome, ident.1 =i , ident.2 = NULL,
                              min.pct = 0.05,                ## detected at least 5% frequency in either ident.
                              logfc.threshold = log(2),     ## at least two-fold change between the average expression of comparisons
                              min.diff.pct = 0.25,          ## Pre-filter features whose detection percentages across the two groups are similar
                              test.use = 'LR',              ##  using logistic regression
                              #latent.vars = 'peak_region_fragments'     #meta data missing  ## mitigate the effect of differential sequencing depth
                              )

  ## top DARs for motif enrichment analysis
  idx_top <- atac_dar[[i]]$p_val_adj < 0.005   ## requiring at least 10 RegionStats

  if(nrow(atac_dar[[i]]) == 0 | sum(idx_top) < 10){
    atac_dar_motif[[i]] <- list()
  } else{

  ## only examine top DARs for motif enrichment analysis
  #idx_top <- atac_dar[[i]]$p_val_adj < 0.005
  motif_res <- FindMotifs(object = scMultiome, features = rownames(atac_dar[[i]])[idx_top])

  ## add p.adjust using BH correction, which might miss for early version of FindMotifs
  p.adjust <- p.adjust(motif_res$pvalue, method = "BH")
  motif_res <- data.frame(motif_res, p.adjust)

  motif_en <- motif_res[motif_res$p.adjust < 0.05, ]
  atac_dar_motif[[i]]  <- motif_en

  ## top 5 enriched motifs
  if(nrow(motif_en) > 0){
    idx_top5 <- min(nrow(motif_en), 5)
    enriched_motifs <- c(enriched_motifs, motif_en$motif.name[1:idx_top5])
  } 
  }
  }
}

names(atac_dar) <- names(atac_dar_motif) <-  unique(clusters)
enriched_motifs <- unique(enriched_motifs)        ## enriched_motif name

#################################################
### pull out top 5 motifs per cluster for heatmap
### -log10(p-adj)
{
  L <- length(unique(clusters))
  motif_hm <- matrix(0,  length(clusters), length(enriched_motifs))
  colnames(motif_hm) <- enriched_motifs
  rownames(motif_hm) <- clusters

  for (i in 1:L)
  {
    idx_motif <- match(colnames(motif_hm), atac_dar_motif[[i]]$motif.name)
    if(sum(is.na(idx_motif)) == length(idx_motif)){
      next;} else {
    motif_hm[i, !is.na(idx_motif)] <- -log10(atac_dar_motif[[i]]$p.adjust[idx_motif[!is.na(idx_motif)]])
    }
  }

  ## rm rows are all 0s
  motif_hm[motif_hm < -log10(0.05)] <- 0     ## ensuring motifs are significant
  idx_0 <- rowSums(motif_hm) == 0

  motif_hm <- motif_hm[!idx_0, ]

  ##

}


## unlist(lapply(atac_dar, nrow))
Misc(scMultiome[['ATAC']], slot = "DARs") <- atac_dar
Misc(scMultiome[['ATAC']], slot = "DARs_motif") <- atac_dar_motif
Misc(scMultiome[['ATAC']], slot = "DARs_motif_hm") <- motif_hm

print("The analysis of WNN clusters specific DARs has been successfully completed!!")


################
## output Rdata for GRN stage input
################
saveRDS(scMultiome, file = paste0(out_dir, sample_id, "_extended_pre_grn_seurat_object.RDS"))
write.csv(scMultiome@meta.data,  file = paste0(out_dir, sample_id, "_extended_pre_grn_meta_data.csv"))

print("The pre-GRN extended analyses have been successfully executed !!")
