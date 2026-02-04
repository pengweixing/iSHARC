## function developed by Arjun Arkal Rao from https://github.com/satijalab/seurat/issues/2201
## with fix from ktessema  
# Replace: x.divs <- pbuild$layout$panel_params[[1]]$x.major
# With:    x.divs <- pbuild$layout$panel_params[[1]]$x.major %||% pbuild$layout$panel_params[[1]]$x$break_positions()

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
            slot, " slot for the ", assay, " assay: ", paste(bad.features, 
                                                             collapse = ", "))
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
