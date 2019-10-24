#!/bin/bash

#SBATCH --time=01:00:00     # walltime
#SBATCH --nodes=1          # number of nodes
#SBATCH --mem-per-cpu=4G   # memory per CPU core
#SBATCH --gres=gpu:1

set -euo pipefail
set -x #echo on

cd ${CI_SRCDIR}

export JULIA_DEPOT_PATH="$(pwd)/.slurmdepot/gpu"
export OPENBLAS_NUM_THREADS=1

module load julia/1.2.0 cuda/10.0 openmpi/4.0.1_cuda-10.0

mpiexec julia --color=no --project=env/gpu $1
