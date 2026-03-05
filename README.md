# iSHARC: <ins>I</ins>ntegrating <ins>s</ins>cMultiome data for <ins>h</ins>eterogeneity <ins>a</ins>nd <ins>r</ins>egulatory analysis in <ins>c</ins>ancer (v1.2.0)


## Introduction
This pipeline is designed for automated, end-to-end quality control (QC) and analysis of 10x Genomics scMultiome data (paired snRNA-seq and snATAC-seq data). It was developed by [Yong Zeng](mailto:yzeng@uhn.ca), building on prior contributions from the Mathieu Lupien Lab and incorporating feedback from the scMultiome Working Group at the Princess Margaret Cancer Centre.


### Features
- **Portability**: The pipeline was developed using [Snakemake](https://snakemake.readthedocs.io/en/stable/index.html), which will automatically deploy the execution environments. It supports execution across various cluster engines (e.g., SLURM) or on standalone machines.
- **Flexibility**: The pipeline is versatile, enabling analysis of individual samples as well as the integration of multiple samples from different conditions.


### Citation
Zeng Y, Bahl S, Xu X, Ci X, Keshavarzian T, Yang L, et al. iSHARC: Integrating scMultiome data for heterogeneity and regulatory analysis in cancer. bioRxiv 2025. https://doi.org/10.1101/2025.04.28.651068.


### How it works
This schematic diagram shows you how pipeline will be working:
<img src="figures/scMultiome_workflow.png" alt="Schematic_diagram" style="width:100.0%" />


## Installation

### Download this pipeline
```bash
wget https://github.com/pengweixing/iSHARC/archive/refs/tags/v1.2.0.tar.gz
tar -xzf v1.2.0.tar.gz
```

### Install Singularity
```bash
conda install conda-forge::singularity
```

### Install Snakemake for the current SLURM template

The provided `sbatch_Snakefile_template.sh` uses Snakemake's modern SLURM executor (`--executor slurm`), which requires Snakemake 8+ and the SLURM executor plugin.

```bash
mamba create -n isharc-snakemake -c conda-forge snakemake=9.16.3 snakemake-executor-plugin-slurm
mamba activate isharc-snakemake
```

If you already have an environment, install the same packages into that environment instead.

Alternatively, if Snakemake is already installed in your environment, install the SLURM executor plugin with pip:

```bash
pip install snakemake-executor-plugin-slurm
```

### Configure the input files

The repository provides example templates under `test/`:

- `test/samples_template.tsv`
- `test/samples_integration_template.tsv`
- `test/config_template.yaml`

`samples_template.tsv` defines the per-sample input data. It is a tab-delimited file with the following columns:

- `sample_id`: sample name used by the workflow for output file naming
- `sample_seq_id`: sequencing/library ID used when preparing Cell Ranger ARC input libraries
- `gex_seq_path`: path to the gene expression FASTQ directory
- `atac_seq_path`: path to the ATAC FASTQ directory
- `arc_outs_path`: path to an existing `cellranger-arc count` `outs/` directory when reusing a precomputed ARC result

Example:

```tsv
sample_id	sample_seq_id	gex_seq_path	atac_seq_path	arc_outs_path
sampleA	sampleA	/path/to/sampleA/gex	/path/to/sampleA/atac	false
sampleB	sampleB	/path/to/sampleB/gex	/path/to/sampleB/atac	/path/to/sampleB/arc_count/outs
```

How `arc_perf` affects `samples_template.tsv`:

- When `arc_perf: false`, the workflow starts from FASTQ files. `gex_seq_path` and `atac_seq_path` must point to valid FASTQ directories, and `arc_outs_path` can be set to `false`.
- When `arc_perf: true`, the workflow reuses an existing Cell Ranger ARC result. `arc_outs_path` must point to the existing `outs/` directory, and `gex_seq_path` and `atac_seq_path` are not used by the ARC counting rule.

`samples_integration_template.tsv` defines which samples should be integrated in the multiple-sample workflow. It is also tab-delimited. The required column is:

- `sample_id`: must match the `sample_id` values in `samples_template.tsv`

Example:

```tsv
sample_id
sampleA
sampleB
```

`config_template.yaml` controls the workflow behavior. The main fields are:

- `arc_perf`: `false` to run `cellranger-arc count` from FASTQ, `true` to reuse existing ARC `outs/`
- `arc_ref`: path to the Cell Ranger ARC reference directory
- `samples`: path to `samples_template.tsv`
- `samples_integr`: path to `samples_integration_template.tsv`
- `work_dir`: working directory where outputs will be written
- `containers_dir`: directory containing pre-downloaded `.sif` images, optional but recommended for offline HPC nodes
- `integration`: `True` or `False`; whether to run the multiple-sample integration workflow
- `threads`: CPU threads used by analysis rules
- `future_globals_maxSize`: memory limit for R `future`, in GB
- `cellranger_create_bam`: whether Cell Ranger ARC should create BAM output
- `cellranger_localcores`: CPU cores given to Cell Ranger ARC
- `cellranger_localmem`: memory in GB given to Cell Ranger ARC
- `second_round_filter`: whether to apply the second-round QC filter
- `second_round_cutoffs`: per-metric QC thresholds used in second-round filtering
- `regress_cell_cycle`: whether to regress out cell-cycle effects in RNA analysis
- `clustering_params`: KNN/UMAP/clustering settings used in downstream analysis

A minimal config example:

```yaml
arc_perf: false
arc_ref: /path/to/refdata-cellranger-arc-GRCh38-2024-A
samples: /path/to/samples_template.tsv
samples_integr: /path/to/samples_integration_template.tsv
work_dir: /path/to/workdir
containers_dir: /path/to/iSHARC/containers
integration: True
threads: 12
future_globals_maxSize: 50
cellranger_create_bam: true
cellranger_localcores: 8
cellranger_localmem: 48
```

Use absolute paths in `config.yaml` and the TSV files. This is the most reliable setup for local runs and HPC execution.

Raw-data directory example:

```text
~/Desktop/Projects/isharc/code/data/
├── sampleA/
│   ├── gex/
│   └── atac/
└── sampleB/
    ├── gex/
    └── atac/
```

In this layout:

- `RAWDATA_DIR` can be set to `~/Desktop/Projects/isharc/code/data`
- `gex_seq_path` can be `~/Desktop/Projects/isharc/code/data/sampleA/gex`
- `atac_seq_path` can be `~/Desktop/Projects/isharc/code/data/sampleA/atac`

### Run on a local PC

The workflow can also be run on a local workstation or server. The current rules use `--use-singularity`, so your local machine should provide Singularity or Apptainer.

A minimal local run looks like this:

```bash
SNAKEFILE="/path/to/iSHARC/workflow/Snakefile"
CODE_ROOT="$(cd "$(dirname "$SNAKEFILE")/../.." && pwd)"
REFDATA_DIR="/path/to/refdata-cellranger-arc-GRCh38-2024-A"
RAWDATA_DIR="/path/to/raw_data"

snakemake \
  --snakefile "$SNAKEFILE" \
  --configfile /path/to/config.yaml \
  --config "pipe_dir=$CODE_ROOT/iSHARC" \
  --use-singularity \
  --singularity-args "--bind $CODE_ROOT --bind $RAWDATA_DIR --bind $REFDATA_DIR" \
  --rerun-triggers mtime \
  --cores 12
```

If your local machine does not have internet access, you can pre-download the container images first:

```bash
bash /path/to/iSHARC/workflow/scripts/download_containers.sh /path/to/iSHARC/containers
```

Then set `containers_dir` in your config YAML to that directory.

### Run on SLURM HPC

iSHARC can be run on a SLURM cluster with `sbatch`. The current workflow is configured to run with `--use-singularity`, so the compute nodes must provide Singularity or Apptainer.

Before submission, make sure you have:

- a valid config YAML file with absolute paths
- a valid sample table
- the project code directory available on compute nodes
- the reference directory available on compute nodes
- Singularity or Apptainer available in the job environment
- if compute nodes do not have internet access, pre-download the container images on a login node or another machine with internet access

The repository includes a submission template:

- [template/sbatch_Snakefile_template.sh](./template/sbatch_Snakefile_template.sh)

A minimal SLURM submission looks like this:

```bash
#!/bin/bash
#SBATCH -p all
#SBATCH -t 5-00:00:00
#SBATCH --mem=6G
#SBATCH -c 1
#SBATCH -J isharc
#SBATCH -o isharc_%j.out
#SBATCH -e isharc_%j.err

SNAKEFILE="/path/to/iSHARC/workflow/Snakefile"
PIPE_DIR="$(cd "$(dirname "$SNAKEFILE")/.." && pwd)"
PROFILE="$PIPE_DIR/workflow/profiles/slurm"
SNAKEMAKE_BIN="snakemake"
REFDATA_DIR="/path/to/refdata-cellranger-arc-GRCh38-2024-A"
RAWDATA_DIR="/path/to/raw_data"
CONTAINERS_DIR="/path/to/iSHARC/containers"

cd /path/to/workdir

"$SNAKEMAKE_BIN" \
  --profile "$PROFILE" \
  --snakefile "$SNAKEFILE" \
  --configfile /path/to/config.yaml \
  --config "pipe_dir=$PIPE_DIR" "containers_dir=$CONTAINERS_DIR" \
  --use-singularity \
  --singularity-args "--bind $PIPE_DIR --bind $RAWDATA_DIR --bind $REFDATA_DIR --bind $CONTAINERS_DIR" \
  --rerun-triggers mtime \
  --jobs 20
```

To submit it:

```bash
sbatch run_isharc.slurm
```

If your compute nodes cannot access the internet, download the required container images in advance:

```bash
bash /path/to/iSHARC/workflow/scripts/download_containers.sh /path/to/iSHARC/containers
```

Then set `containers_dir` in your config YAML to that directory. The workflow will automatically use these local `.sif` images when present, and only fall back to `docker://...` when the local image is missing.


For more details about cluster execution, refer to the [Snakemake documentation](https://snakemake.readthedocs.io/en/stable/executing/cluster.html).
