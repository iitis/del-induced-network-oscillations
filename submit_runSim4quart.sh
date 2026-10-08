#!/bin/bash
#SBATCH --job-name=izh_batch
#SBATCH --output=logs/izh_batch_%j.out
#SBATCH --error=logs/izh_batch_%j.err
#SBATCH --time=00:15:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=32G

set -e

INPUT_FILE=${1:-input_network.mat}
CONFIG_FUNCTION=${2:-config_publication_example}

mkdir -p logs

echo "Job started on: $(hostname)"
echo "SLURM job ID: ${SLURM_JOB_ID}"
echo "Start time: $(date)"
echo "Input file: ${INPUT_FILE}"
echo "Config function: ${CONFIG_FUNCTION}"

module load trytonp/matlab/R2024b

matlab -batch "run_experiment_batch_cli('${INPUT_FILE}', '${CONFIG_FUNCTION}')"

echo "End time: $(date)"
echo "Job finished."
