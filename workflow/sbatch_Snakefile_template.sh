#!/usr/bin/env bash
#SBATCH -p all
#SBATCH -t 5-00:00:00
#SBATCH --mem=60G
#SBATCH -c 12
#SBATCH -J isharc
#SBATCH -o isharc_%j.out
#SBATCH -e isharc_%j.err

set -euo pipefail

###############################################################################
# Update the variables below for your environment.
###############################################################################
SNAKEFILE="/path/to/iSHARC/workflow/Snakefile"
CONFIGFILE="/path/to/config.yaml"
WORKDIR="/path/to/workdir"
REFDATA_DIR="/path/to/refdata-cellranger-arc-GRCh38-2024-A"
RAWDATA_DIR="/path/to/raw_data"

# true: Snakemake submits per-rule jobs to SLURM (recommended on HPC)
# false: run all workflow steps inside this single SLURM allocation
USE_CLUSTER_MODE=true
JOBS=20
UNLOCK_FIRST=false

CODE_ROOT="$(cd "$(dirname "$SNAKEFILE")/../.." && pwd)"
CLUSTER_CONFIG="$CODE_ROOT/iSHARC/workflow/config/cluster_config.yaml"
CORES="${SLURM_CPUS_PER_TASK:-12}"

# If Snakemake is not already available in your job environment, uncomment:
# source ~/miniconda3/etc/profile.d/conda.sh
# conda activate iSHARC

cd "$WORKDIR"
mkdir -p logs_cluster

if [[ "$UNLOCK_FIRST" == "true" ]]; then
  snakemake \
    --snakefile "$SNAKEFILE" \
    --configfile "$CONFIGFILE" \
    --unlock
fi

if [[ "$USE_CLUSTER_MODE" == "true" ]]; then
  snakemake \
    --snakefile "$SNAKEFILE" \
    --configfile "$CONFIGFILE" \
    --config "pipe_dir=$CODE_ROOT/iSHARC" \
    --use-singularity \
    --singularity-args "--bind $CODE_ROOT --bind $RAWDATA_DIR --bind $REFDATA_DIR" \
    --rerun-triggers mtime \
    --cluster-config "$CLUSTER_CONFIG" \
    --jobs "$JOBS" \
    --cluster "sbatch -p {cluster.partition} -c {cluster.cpus} --mem={cluster.mem} -t {cluster.time} -J {cluster.job_name} -o {cluster.stdout} -e {cluster.stderr}"
else
  snakemake \
    --snakefile "$SNAKEFILE" \
    --configfile "$CONFIGFILE" \
    --config "pipe_dir=$CODE_ROOT/iSHARC" \
    --use-singularity \
    --singularity-args "--bind $CODE_ROOT --bind $RAWDATA_DIR --bind $REFDATA_DIR" \
    --rerun-triggers mtime \
    --cores "$CORES"
fi

# If you activated conda above, uncomment:
# conda deactivate
