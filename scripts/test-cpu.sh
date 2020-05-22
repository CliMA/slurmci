#!/bin/bash

#SBATCH --time=1:00:00     # walltime
#SBATCH --nodes=1          # number of nodes
#SBATCH --mem-per-cpu=5G   # memory per CPU core

set -euo pipefail
set -x #echo on
hostname

cd ${CI_SRCDIR}

export JULIA_DEPOT_PATH="$(pwd)/.slurmdepot/cpu"
export OPENBLAS_NUM_THREADS=1
export CLIMA_GPU=false
export CLIMATEMACHINE_OUTPUT_DIR="${CI_OUTDIR}/${SLURM_JOB_ID}_output"

module purge
export PATH="/groups/esm/common/julia-1.3:/usr/sbin:$PATH"
module load openmpi/4.0.1 hdf5/1.10.1 netcdf-c/4.6.1

mpiexec julia --color=no --project "$@"
