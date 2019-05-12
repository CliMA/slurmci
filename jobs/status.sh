#!/bin/bash

#SBATCH --time=0:05:00     # walltime
#SBATCH --ntasks=1         # number of processor cores (i.e. tasks)
#SBATCH --nodes=1          # number of nodes
#SBATCH --mem-per-cpu=1G   # memory per CPU core
#SBATCH --output=logs/slurm-%j.out

set -euo pipefail

module load julia/1.1.0

julia --project status.jl
