#!/bin/bash

#SBATCH --time=0:45:00     # walltime
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

module load cuda/10.0 openmpi/4.0.3_cuda-10.0 hdf5/1.10.1 netcdf-c/4.6.1

julia --color=no --project -e 'using Pkg; pkg"instantiate"; pkg"build"; pkg"precompile"'

cat Manifest.toml
