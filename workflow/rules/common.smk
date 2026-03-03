import os
import pandas as pd

## paths for pipeline and/or reference data
# infer pipeline root from Snakefile location unless explicitly provided
pipe_dir = os.path.abspath(config.get("pipe_dir", os.path.join(workflow.basedir, "..")))
config["pipe_dir"] = pipe_dir

def _resolve_from_pipe_dir(path):
    return path if os.path.isabs(path) else os.path.abspath(os.path.join(pipe_dir, path))

config["work_dir"] = _resolve_from_pipe_dir(config["work_dir"])
config["samples"] = _resolve_from_pipe_dir(config["samples"])
config["samples_integr"] = _resolve_from_pipe_dir(config["samples_integr"])
containers_dir = _resolve_from_pipe_dir(config.get("containers_dir", os.path.join(pipe_dir, "containers")))
config["containers_dir"] = containers_dir

def get_container_image(local_filename, remote_uri):
    local_path = os.path.join(containers_dir, local_filename)
    return local_path if os.path.exists(local_path) else remote_uri

ISHARC_R_CONTAINER = get_container_image(
    "isharc-r_4.4.3_seurat_v2.1.5.sif",
    "docker://pengweixing/isharc-r:4.4.3_seurat_v2.1.5",
)
CELLRANGER_ARC_CONTAINER = get_container_image(
    "docker-cellranger-arc.sif",
    "docker://litd/docker-cellranger-arc",
)

workdir: config["work_dir"]

work_dir = config["work_dir"]
samples_list = config["samples"]
samples_integr = config["samples_integr"]

######################################################
## read in sample and corresponding library file table
SAMPLES = (
    pd.read_csv(config["samples"], sep=r"\s+|,", engine="python")
    .set_index("sample_id", drop=False)
    .sort_index()
)


## read in samples for aggregation
if config["integration"]:
    SAMPLES_INTEGR = (
        pd.read_csv(config["samples_integr"], sep=r"\s+|,", engine="python")
        .set_index("sample_id", drop=False)
        .sort_index()
    )
else:
    SAMPLES_INTEGR = SAMPLES     ## must be defined

#############################################
## get taget outputs based on the config file
## either for individual samples or aggregate
## all samples listed in sample_aggr.tsv !!!
#############################################

def get_rule_all_input():
    if config["integration"]:
        #integrated_rna = "integration/rna/RNA_integrated_by_anchors.RDS",
        #integrated_atac = "integration/atac/ATAC_integrated_by_anchors.RDS",
        ## submit integraton and individual samples analysis all at once
        integrated_rna_atac_harmony =  "integrated_samples/wnn/harmony/RNA_ATAC_integrated_by_WNN.RDS",
        integrated_rna_atac_anchor =  "integrated_samples/wnn/anchor/RNA_ATAC_integrated_by_WNN.RDS",
        integrate_report = "integrated_samples/Integrated_samples_QC_and_Primary_Results.html",
        individual_qc_report = expand("individual_samples/{samples}/{samples}_QC_and_Primary_Results.html", samples = SAMPLES_INTEGR["sample_id"]),
        return integrated_rna_atac_harmony + integrated_rna_atac_anchor + individual_qc_report + integrate_report

    else:         ## process individual sample
        arc_out = expand("arc_count/{samples}/outs/atac_fragments.tsv.gz", samples = SAMPLES["sample_id"]),
        main_out = expand("individual_samples/{samples}/{samples}_extended_seurat_object.RDS", samples = SAMPLES["sample_id"]),
        qc_report = expand("individual_samples/{samples}/{samples}_QC_and_Primary_Results.html", samples = SAMPLES["sample_id"]),

        return arc_out + main_out + qc_report


############################
## other functions for input
#############################

###############################
##  get corresponding bwa_index
def get_cellranger_arc_ref():
    if config["arc_perf"]:
        return ""
    else:
        return config["arc_ref"]


#def get_library(wildcards):
#    return SAMPLES.loc[wildcards.sample]["sample_library"]

def get_sample_seq_id(wildcards):
    return SAMPLES.loc[wildcards.sample]["sample_seq_id"]

def get_gex_seq_path(wildcards):
    return SAMPLES.loc[wildcards.sample]["gex_seq_path"]

def get_atac_seq_path(wildcards):
    return SAMPLES.loc[wildcards.sample]["atac_seq_path"]

def get_arc_outs_path(wildcards):
    return SAMPLES.loc[wildcards.sample]["arc_outs_path"]
