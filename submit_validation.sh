#!/usr/bin/env bash
#SBATCH --job-name=izh_validation
#SBATCH --output=logs/izh_validation_%j.out
#SBATCH --error=logs/izh_validation_%j.err
#SBATCH --time=00:30:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=32G

set -euo pipefail
trap 'echo "ERROR @ line $LINENO: $BASH_COMMAND" >&2' ERR
REPO_ROOT="${SLURM_SUBMIT_DIR:-$(pwd)}"
cd "${REPO_ROOT}"
export SIM_INPUT_FILE="${1:?Usage: sbatch submit_validation.sh INPUT.mat}"
[[ -f "${SIM_INPUT_FILE}" ]] || { echo "Missing input: ${SIM_INPUT_FILE}" >&2; exit 2; }
module load "${MATLAB_MODULE:-trytonp/matlab/R2024b}"
export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-1}"
export MKL_NUM_THREADS="${SLURM_CPUS_PER_TASK:-1}"
echo "Job: ${SLURM_JOB_ID:-NA}; host: $(hostname); start: $(date -Is)"
git rev-parse HEAD
git status --short
sha256sum "${SIM_INPUT_FILE}"
matlab -batch "addpath('tests'); run_task_validation(getenv('SIM_INPUT_FILE'))"
