#!/usr/bin/env bash
#SBATCH --job-name=izh_hourly
#SBATCH --partition=batch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1

set -euo pipefail
repo="${SLURM_SUBMIT_DIR:?Submit from the repository root}"
cd "$repo"
export CAMPAIGN_RUN="$(realpath -e "${1:?Usage: sbatch ... campaign/submit_hourly_grid.sbatch RUN MODE [TARGET_HOUR] [EXTRAS]}")"
project_runs="$(realpath -e /users/project1/pt01269/runs)"
case "$CAMPAIGN_RUN" in "$project_runs"/*) ;; *) echo "Invalid campaign directory" >&2; exit 2;; esac
export CAMPAIGN_MODE="${2:?Use preflight-all, preflight, continuity, or run}"
export CAMPAIGN_TARGET="${3:-12}"
export CAMPAIGN_EXTRAS="${4:-0}"
git diff --quiet HEAD -- || { echo 'Commit the code before submitting.' >&2; exit 2; }
export CAMPAIGN_REVISION="$(git rev-parse HEAD)"
module load "${MATLAB_MODULE:-trytonp/matlab/R2024b}"
export OMP_NUM_THREADS="${SLURM_CPUS_PER_TASK:-1}"
export MKL_NUM_THREADS="$OMP_NUM_THREADS"
mkdir -p "$CAMPAIGN_RUN/tmp"
export TMPDIR="$CAMPAIGN_RUN/tmp"
if [[ "$CAMPAIGN_MODE" == preflight-all ]]; then
    python3 campaign/grid.py verify --run "$CAMPAIGN_RUN"
    matlab -batch "addpath('campaign'); run_hourly_simulation"
    exit
fi
export CAMPAIGN_ID="${SLURM_ARRAY_TASK_ID:?Specify --array}"
mkdir -p "$CAMPAIGN_RUN/locks"
exec 9>"$CAMPAIGN_RUN/locks/$CAMPAIGN_ID.lock"
flock -n 9 || { echo 'Point already in use' >&2; exit 2; }
python3 campaign/grid.py verify --run "$CAMPAIGN_RUN" --id "$CAMPAIGN_ID"
matlab -batch "addpath('campaign'); run_hourly_simulation"
