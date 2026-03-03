#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONTAINERS_DIR="${1:-$PIPE_DIR/containers}"

if command -v apptainer >/dev/null 2>&1; then
  CONTAINER_CMD="apptainer"
elif command -v singularity >/dev/null 2>&1; then
  CONTAINER_CMD="singularity"
else
  echo "Error: neither apptainer nor singularity was found in PATH." >&2
  exit 1
fi

mkdir -p "$CONTAINERS_DIR"

"$CONTAINER_CMD" pull --force "$CONTAINERS_DIR/isharc-r_4.4.3_seurat_v2.1.5.sif" \
  docker://pengweixing/isharc-r:4.4.3_seurat_v2.1.5

"$CONTAINER_CMD" pull --force "$CONTAINERS_DIR/docker-cellranger-arc.sif" \
  docker://litd/docker-cellranger-arc

echo "Downloaded containers to: $CONTAINERS_DIR"
