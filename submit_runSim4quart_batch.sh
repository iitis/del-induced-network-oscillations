#!/usr/bin/env bash
#SBATCH --job-name=izh_batch
#SBATCH --output=logs/izh_batch_%j.out
#SBATCH --error=logs/izh_batch_%j.err
#SBATCH --time=00:15:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=32G

# Compatibility alias; implementation lives in submit_runSim4quart.sh.
set -euo pipefail
REPO_ROOT="${SLURM_SUBMIT_DIR:-$(pwd)}"
exec bash "${REPO_ROOT}/submit_runSim4quart.sh" "$@"
