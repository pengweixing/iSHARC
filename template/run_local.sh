#!/usr/bin/env bash
set -euo pipefail

SNAKEFILE="/home/pengwei/Desktop/Projects/isharc/code/iSHARC/workflow/Snakefile"
CODE_ROOT="$(cd "$(dirname "$SNAKEFILE")/../.." && pwd)"
REFDATA_DIR="/home/pengwei/Desktop/Projects/database/refdata-cellranger-arc-GRCh38-2024-A"

snakemake \
  --snakefile "$SNAKEFILE" \
  --configfile "/home/pengwei/Desktop/Projects/isharc/code/test/config_template.yaml" \
  --config "pipe_dir=$CODE_ROOT/iSHARC" \
  --use-singularity \
  --singularity-args "--bind $CODE_ROOT --bind $CODE_ROOT/data --bind $REFDATA_DIR" \
  --rerun-triggers mtime \
  -j 1 
