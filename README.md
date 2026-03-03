# iSHARC: <ins>I</ins>ntegrating <ins>s</ins>cMultiome data for <ins>h</ins>eterogeneity <ins>a</ins>nd <ins>r</ins>egulatory analysis in <ins>c</ins>ancer (v1.0.0)


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
1) Ensure you have a Conda-based Python3 distribution installed (e.g.,the [Miniconda](https://docs.conda.io/en/latest/miniconda.html)). If your Conda version is earlier than v23.10.0, it is recommended to install [Mamba](https://github.com/mamba-org/mamba) for improved performance and reliability

	```bash
	$ conda install -n base -c conda-forge mamba
	```

2) Git clone this pipeline.
	```bash
	$ cd
	$ git clone https://github.com/yzeng-lol/iSHARC
	```

3) Run on a local PC

	The workflow can also be run on a local workstation or server. The current rules use `--use-singularity`, so your local machine should provide Singularity or Apptainer.

	A minimal local run looks like this:

	```bash
	$ SNAKEFILE="/path/to/iSHARC/workflow/Snakefile"
	$ CODE_ROOT="$(cd "$(dirname "$SNAKEFILE")/../.." && pwd)"
	$ REFDATA_DIR="/path/to/refdata-cellranger-arc-GRCh38-2024-A"

	$ snakemake \
	    --snakefile "$SNAKEFILE" \
	    --configfile /path/to/config.yaml \
	    --config "pipe_dir=$CODE_ROOT/iSHARC" \
	    --use-singularity \
	    --singularity-args "--bind $CODE_ROOT --bind $CODE_ROOT/data --bind $REFDATA_DIR" \
	    --rerun-triggers mtime \
	    --cores 12
	```

	If your local machine does not have internet access, you can pre-download the container images first:

	```bash
	$ bash /path/to/iSHARC/workflow/scripts/download_containers.sh /path/to/iSHARC/containers
	```

	Then set `containers_dir` in your config YAML to that directory.

4) Run on SLURM HPC

	iSHARC can be run on a SLURM cluster with `sbatch`. The current workflow is configured to run with `--use-singularity`, so the compute nodes must provide Singularity or Apptainer.

	Before submission, make sure you have:
	- a valid config YAML file with absolute paths
	- a valid sample table
	- the project code directory available on compute nodes
	- the reference directory available on compute nodes
	- Singularity or Apptainer available in the job environment
	- if compute nodes do not have internet access, pre-download the container images on a login node or another machine with internet access

	The repository includes a submission template:
	- [workflow/sbatch_Snakefile_template.sh](./workflow/sbatch_Snakefile_template.sh)

	A minimal SLURM submission looks like this:

	```bash
	#!/bin/bash
	#SBATCH -p all
	#SBATCH -t 5-00:00:00
	#SBATCH --mem=60G
	#SBATCH -c 12
	#SBATCH -J isharc
	#SBATCH -o isharc_%j.out
	#SBATCH -e isharc_%j.err

	source ~/miniconda3/etc/profile.d/conda.sh
	conda activate iSHARC

	SNAKEFILE="/path/to/iSHARC/workflow/Snakefile"
	CODE_ROOT="$(cd "$(dirname "$SNAKEFILE")/../.." && pwd)"
	REFDATA_DIR="/path/to/refdata-cellranger-arc-GRCh38-2024-A"

	cd /path/to/workdir

	snakemake \
	  --snakefile "$SNAKEFILE" \
	  --configfile /path/to/config.yaml \
	  --config "pipe_dir=$CODE_ROOT/iSHARC" \
	  --use-singularity \
	  --singularity-args "--bind $CODE_ROOT --bind $CODE_ROOT/data --bind $REFDATA_DIR" \
	  --rerun-triggers mtime \
	  --cores 12
	```

	To submit it:

	```bash
	$ sbatch run_isharc.slurm
	```

	If your compute nodes cannot access the internet, download the required container images in advance:

	```bash
	bash /path/to/iSHARC/workflow/scripts/download_containers.sh /path/to/iSHARC/containers
	```

	Then set `containers_dir` in your config YAML to that directory. The workflow will automatically use these local `.sif` images when present, and only fall back to `docker://...` when the local image is missing.

	If you want Snakemake to submit each sub-job to SLURM separately, you can use a cluster configuration file such as [workflow/config/cluster_config.yaml](./workflow/config/cluster_config.yaml). A complete command looks like this:

	```bash
	snakemake \
	  --snakefile /path/to/iSHARC/workflow/Snakefile \
	  --configfile /path/to/config.yaml \
	  --config "pipe_dir=$CODE_ROOT/iSHARC" \
	  --use-singularity \
	  --singularity-args "--bind $CODE_ROOT --bind $CODE_ROOT/data --bind $REFDATA_DIR" \
	  --rerun-triggers mtime \
	  --cluster-config /path/to/iSHARC/workflow/config/cluster_config.yaml \
	  --jobs 20 \
	  --cluster "sbatch -p {cluster.partition} -c {cluster.cpus} --mem={cluster.mem} -t {cluster.time} -J {cluster.job_name} -o {cluster.stdout} -e {cluster.stderr}"
	```

	In this mode:
	- `--jobs 20` controls how many SLURM jobs Snakemake may submit in parallel
	- CPU, memory, runtime, partition, and log naming are defined per rule in `cluster_config.yaml`
	- `--use-singularity` and `--singularity-args` are still needed because the workflow uses containerized rules
	- `CODE_ROOT` should be the repository root, and `REFDATA_DIR` should point to your Cell Ranger ARC reference directory

	Notes:
	- `sbatch` is for SLURM. If your cluster uses SLURM, this is the correct submission command.
	- `pipe_dir` should point to the pipeline root inside the repository, typically `.../iSHARC`.
	- `containers_dir` should point to a shared directory containing pre-downloaded `.sif` images if your compute nodes are offline.
	- `--singularity-args` should bind the repository root and any required reference/data directories so containerized rules can see the scripts and references.
	- `--rerun-triggers mtime` is recommended to avoid unnecessary reruns caused by parameter/path metadata changes.
	- If you only want a specific target, append it at the end of the `snakemake` command, for example:

	```bash
	individual_samples/sampleA/sampleA_QC_and_Primary_Results.html
	```

	For more details about cluster execution, refer to the [Snakemake documentation](https://snakemake.readthedocs.io/en/stable/executing/cluster.html).


## Trouble Shooting
For troubleshooting issues related to pipeline installation and execution, please refer to [this document](./assets/Trouble_Shooting.md). This document will be continuously updated to address errors reported by users.
