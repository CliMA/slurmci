#!/bin/bash

#SBATCH --time=1:00:00     # walltime
#SBATCH --nodes=1          # number of nodes
#SBATCH --mem-per-cpu=5G   # memory per CPU core

set -euo pipefail
set -x #echo on
hostname

cd ${CI_SRCDIR}

export JULIA_DEPOT_PATH="$(pwd)/.slurmdepot_cpu"
export JULIA_CUDA_USE_BINARYBUILDER=false
export OPENBLAS_NUM_THREADS=1

export CLIMATEMACHINE_SETTINGS_DISABLE_GPU=true
export CLIMATEMACHINE_SETTINGS_FIX_RNG_SEED=true
export CLIMATEMACHINE_SETTINGS_OUTPUT_DIR="${CI_OUTDIR}/${SLURM_JOB_ID}_output"

module purge
module load julia/1.4.2 openmpi/4.0.3 hdf5/1.10.1 netcdf-c/4.6.1

mpiexec julia --color=no --project "$@"
