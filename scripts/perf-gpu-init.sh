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
export PATH="/groups/esm/common/julia-1.3:$PATH"

module load cuda/10.0 openmpi/4.0.1_cuda-10.0

julia --color=no --project -e 'using Pkg; pkg"instantiate"; pkg"build"; pkg"precompile"'
