#!/bin/bash

#SBATCH --time=01:00:00     # walltime
#SBATCH --nodes=1          # number of nodes
#SBATCH --mem-per-cpu=5G   # memory per CPU core
#SBATCH --gres=gpu:1

set -euo pipefail
set -x #echo on
hostname

cd ${CI_SRCDIR}

export JULIA_DEPOT_PATH="$(pwd)/.slurmdepot/gpu"
export OPENBLAS_NUM_THREADS=1
export UCX_ERROR_SIGNALS="SIGILL,SIGBUS,SIGFPE" # SIGSEGV is used by Julia
export PATH="/groups/esm/common/julia-1.3:/usr/sbin:$PATH"

module load cuda/10.0 openmpi/4.0.3_cuda-10.0

mpiexec julia --color=no --project "$@"
