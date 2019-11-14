#!/bin/bash

#SBATCH --time=1:00:00     # walltime
#SBATCH --nodes=1          # number of nodes
#SBATCH --mem-per-cpu=4G   # memory per CPU core
#SBATCH --gres=gpu:1

set -euo pipefail
set -x #echo on

cd ${CI_SRCDIR}

export JULIA_DEPOT_PATH="$(pwd)/.slurmdepot/gpu"
export OPENBLAS_NUM_THREADS=1

module load julia/1.2.0 cuda/10.0 openmpi/4.0.1_cuda-10.0

if [ -d "env/gpu" ]; then
    julia --color=no --project=env/gpu test/runtests_gpu.jl
else
    julia --color=no --project test/runtests_gpu.jl
fi
