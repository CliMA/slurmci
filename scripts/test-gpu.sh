#!/bin/bash

#SBATCH --time=01:00:00     # walltime
#SBATCH --nodes=1          # number of nodes
#SBATCH --mem-per-cpu=5G   # memory per CPU core
#SBATCH --gres=gpu:1

set -euo pipefail
set -x #echo on
hostname

cd ${CI_SRCDIR}

export JULIA_DEPOT_PATH="$(pwd)/.slurmdepot_gpu"
export JULIA_MPI_BINARY=system
export OPENBLAS_NUM_THREADS=1
export CLIMATEMACHINE_OUTPUT_DIR="${CI_OUTDIR}/${SLURM_JOB_ID}_output"

module purge
module load julia/1.4.2 cuda/10.0 openmpi/4.0.3_cuda-10.0 hdf5/1.10.1 netcdf-c/4.6.1

mpiexec julia --color=no --project "$@"
