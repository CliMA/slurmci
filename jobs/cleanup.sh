#!/bin/bash

#SBATCH --time=0:10:00     # walltime
#SBATCH --ntasks=1         # number of processor cores (i.e. tasks)
#SBATCH --nodes=1          # number of nodes
#SBATCH --mem-per-cpu=1G   # memory per CPU core
#SBATCH --output=logs/slurm-%j.out

set -euo pipefail
set -x #echo on

~/julia-1.1.0/bin/julia --project finalize.jl

rm /central/scratchio/spjbyrne/slurmci/downloads/${CI_SHA}.tar.gz
rm -rf /central/scratchio/spjbyrne/slurmci/sources/${CI_SHA}
