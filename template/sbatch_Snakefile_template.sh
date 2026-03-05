#!/usr/bin/env bash
#SBATCH -p all
#SBATCH -t 5-00:00:00
#SBATCH --mem=60G
#SBATCH -c 12
#SBATCH -N 1
#SBATCH -J isharc
#SBATCH -o isharc_%j.out
#SBATCH -e isharc_%j.err

set -euo pipefail

###############################################################################
# Update the variables below for your HPC environment.
###############################################################################
SNAKEFILE="/path/to/iSHARC/workflow/Snakefile"
CONFIGFILE="/path/to/config.yaml"
WORKDIR="/path/to/workdir"
REFDATA_DIR="/path/to/refdata-cellranger-arc-GRCh38-2024-A"
RAWDATA_DIR="/path/to/raw_data"
CONTAINERS_DIR="/home/pengwei/Desktop/Projects/isharc/code/iSHARC/containers"

# Number of rule-level jobs Snakemake can submit to Slurm.
JOBS=20
# Optional: run once to clear stale Snakemake lock.
UNLOCK_FIRST=false

PIPE_DIR="$(cd "$(dirname "$SNAKEFILE")/.." && pwd)"

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

snakemake \
  --snakefile "$SNAKEFILE" \
  --configfile "$CONFIGFILE" \
  --config "pipe_dir=$PIPE_DIR" "containers_dir=$CONTAINERS_DIR" \
  --use-singularity \
  --singularity-args "--bind $PIPE_DIR --bind $RAWDATA_DIR --bind $REFDATA_DIR --bind $CONTAINERS_DIR" \
  --rerun-triggers mtime \
  --executor slurm \
  --jobs "$JOBS" \
  --default-resources mem_mb=32000 runtime=1440

# If you activated conda above, uncomment:
# conda deactivate
