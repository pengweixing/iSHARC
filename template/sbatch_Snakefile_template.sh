#!/usr/bin/env bash
#SBATCH -p all
#SBATCH -t 5-00:00:00
#SBATCH --mem=6G
#SBATCH -c 1
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
SNAKEMAKE_BIN="snakemake"
# Optional: set an explicit Snakemake profile path. Leave empty to use
# "$PIPE_DIR/workflow/profiles/slurm".
PROFILE="${PROFILE:-}"

# Number of rule-level jobs Snakemake can submit to Slurm.
JOBS=20
# Optional: run once to clear stale Snakemake lock.
UNLOCK_FIRST=false

PIPE_DIR="$(cd "$(dirname "$SNAKEFILE")/.." && pwd)"
if [[ -z "${PROFILE:-}" ]]; then
  PROFILE="$PIPE_DIR/workflow/profiles/slurm"
fi

cd "$WORKDIR"
mkdir -p logs_cluster

if [[ "$UNLOCK_FIRST" == "true" ]]; then
  "$SNAKEMAKE_BIN" \
    --snakefile "$SNAKEFILE" \
    --configfile "$CONFIGFILE" \
    --unlock
fi

"$SNAKEMAKE_BIN" \
  --profile "$PROFILE" \
  --snakefile "$SNAKEFILE" \
  --configfile "$CONFIGFILE" \
  --config "pipe_dir=$PIPE_DIR" "containers_dir=$CONTAINERS_DIR" \
  --use-singularity \
  --singularity-args "--bind $PIPE_DIR --bind $RAWDATA_DIR --bind $REFDATA_DIR --bind $CONTAINERS_DIR" \
  --rerun-triggers mtime \
  --jobs "$JOBS"

# If you activated conda above, uncomment:
# conda deactivate
