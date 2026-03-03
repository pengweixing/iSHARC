################################################################################
## Perform QC and exploration analyses by integrating multiple samples per study
################################################################################

_pipe_dir_in_container = config["pipe_dir"]

## horizontally merge and integrate snRNA-seq data across samples
rule horizontal_integration_of_rna_across_multiple_samples:
    input:
        #samples_integr
        expand("individual_samples/{samples}/{samples}_extended_seurat_object.RDS", samples = SAMPLES_INTEGR["sample_id"])
    output:
        "integrated_samples/rna/RNA_integrated_by_harmony.RDS",
        "integrated_samples/rna/RNA_integrated_by_anchors.RDS"
    #resources:
    #    mem_mb=60000
    params:
        pipe_dir = _pipe_dir_in_container,
        script = f"{config['pipe_dir']}/workflow/scripts/horizontal_integration_of_rna_across_multiple_samples.R",
        integr_list = config["samples_integr"],
        fgm = config["future_globals_maxSize"],
        knn_k = config["clustering_params"]["knn_k"],
        dims_n = config["clustering_params"]["dims_n"],
        comm_res = config["clustering_params"]["comm_res"]
    threads:
        config["threads"]
    log:
        "logs/rna_horizontally_integrated_by_harmony_and_anchors.log"
    container:
        ISHARC_R_CONTAINER
    shell:
        "(Rscript --vanilla {params.script} "
        "   --threads {threads} "
        "   --future_globals_maxSize {params.fgm} "
        "   --knn_k_param {params.knn_k} "
        "   --dimentions_n {params.dims_n} "
        "   --community_resolution {params.comm_res} "
        "   --samples_integration {params.integr_list}) 2> {log}"


## horizontally merge and integrate snATAC-seq data across samples
rule horizontal_integration_of_atac_across_multiple_samples:
    input:
        #samples_integr
        expand("individual_samples/{samples}/{samples}_extended_seurat_object.RDS", samples = SAMPLES_INTEGR["sample_id"])
    output:
        "integrated_samples/atac/ATAC_integrated_by_harmony.RDS",
        "integrated_samples/atac/ATAC_integrated_by_anchors.RDS"
    #resources:
    #    mem_mb=60000
    params:
        script = f"{config['pipe_dir']}/workflow/scripts/horizontal_integration_of_atac_across_multiple_samples.R",
        integr_list = config["samples_integr"],
        fgm = config["future_globals_maxSize"],
        knn_k = config["clustering_params"]["knn_k"],
        dims_n = config["clustering_params"]["dims_n"],
        comm_res = config["clustering_params"]["comm_res"]
    threads:
        config["threads"]
    log:
        "logs/atac_horizontally_integrated_by_harmony_and_anchors.log"
    container:
        ISHARC_R_CONTAINER
    shell:
        "(Rscript --vanilla {params.script} "
        "   --threads {threads} "
        "   --future_globals_maxSize {params.fgm} "
        "   --knn_k_param {params.knn_k} "
        "   --dimentions_n {params.dims_n} "
        "   --community_resolution {params.comm_res} "
        "   --samples_integration {params.integr_list}) 2> {log}"


## Verically integrate horizontally integrated (Harmonized) snRNA-seq and scATAC-seq for multiple samples using WNN
rule vertical_integration_of_multiple_harmonized_samples:
    input:
        integrated_rna = "integrated_samples/rna/RNA_integrated_by_harmony.RDS",
        integrated_atac = "integrated_samples/atac/ATAC_integrated_by_harmony.RDS",
    output:
        "integrated_samples/wnn/harmony/RNA_ATAC_integrated_by_WNN.RDS"
    #resources:
    #    mem_mb=60000
    params:
        pipe_dir = _pipe_dir_in_container,
        script = f"{config['pipe_dir']}/workflow/scripts/vertical_integration_of_multiple_samples.R",
        fgm = config["future_globals_maxSize"],
        knn_k = config["clustering_params"]["knn_k"],
        dims_n = config["clustering_params"]["dims_n"],
        comm_res = config["clustering_params"]["comm_res"]
    threads:
        config["threads"]
    log:
        "logs/harmonized_vertically_integrated_by_WNN.log"
    container:
        ISHARC_R_CONTAINER
    shell:
        "(Rscript --vanilla {params.script} "
        "   --integration_method harmony "
        "   --threads {threads} "
        "   --future_globals_maxSize {params.fgm} "
        "   --knn_k_param {params.knn_k} "
        "   --dimentions_n {params.dims_n} "
        "   --community_resolution {params.comm_res} "
        "   --integrated_rna  {input.integrated_rna} "
        "   --integrated_atac {input.integrated_atac}) 2> {log}"


## Integrate snRNA-seq and scATAC-seq for multiple samples (SEURAT anchors) with WNN
rule vertical_integration_of_multiple_anchored_samples:
    input:
        integrated_rna = "integrated_samples/rna/RNA_integrated_by_anchors.RDS",
        integrated_atac = "integrated_samples/atac/ATAC_integrated_by_anchors.RDS",
    output:
        "integrated_samples/wnn/anchor/RNA_ATAC_integrated_by_WNN.RDS"
    #resources:
    #    mem_mb=60000
    params:
        pipe_dir = _pipe_dir_in_container,
        script = f"{config['pipe_dir']}/workflow/scripts/vertical_integration_of_multiple_samples.R",
        fgm = config["future_globals_maxSize"],
        knn_k = config["clustering_params"]["knn_k"],
        dims_n = config["clustering_params"]["dims_n"],
        comm_res = config["clustering_params"]["comm_res"]
    threads:
        config["threads"]
    log:
        "logs/anchored_vertically_integrated_by_WNN.log"
    container:
        ISHARC_R_CONTAINER
    shell:
        "(Rscript --vanilla {params.script} "
        "   --integration_method anchor "
        "   --threads {threads} "
        "   --future_globals_maxSize {params.fgm} "
        "   --knn_k_param {params.knn_k} "
        "   --dimentions_n {params.dims_n} "
        "   --community_resolution {params.comm_res} "
        "   --integrated_rna  {input.integrated_rna} "
        "   --integrated_atac {input.integrated_atac}) 2> {log}"


############################################
## generate integrated QC report per project
############################################
rule html_report_of_multiple_samples:
    input:
        "integrated_samples/wnn/harmony/RNA_ATAC_integrated_by_WNN.RDS",
        "integrated_samples/wnn/anchor/RNA_ATAC_integrated_by_WNN.RDS"
    output:
        "integrated_samples/Integrated_samples_QC_and_Primary_Results.html"
    #resources:
    #    mem_mb=60000
    params:
        pipe_dir = _pipe_dir_in_container,
        work_dir = config["work_dir"],
        report_rmd_template = f"{config['pipe_dir']}/workflow/scripts/qc_and_primary_results_report_of_multiple_samples.Rmd",
        report_script = f"{config['pipe_dir']}/workflow/scripts/qc_and_primary_results_report_of_multiple_samples.R"
    log:
        "logs/integrated_samples_report.log"
    container:
        ISHARC_R_CONTAINER
    shell:
        ## generating qc report named by sample id
        "(cp {params.report_rmd_template} "
        "    {params.work_dir}/integrated_samples/Integrated_samples_QC_and_Primary_Results.Rmd && "
        "Rscript --vanilla {params.report_script} "
        "  --report_rmd_file {params.work_dir}/integrated_samples/Integrated_samples_QC_and_Primary_Results.Rmd "
        "  --integration_dir {params.work_dir}/integrated_samples) 2> {log}"
