#!/bin/bash

#SBATCH --time=0:01:00     # walltime
#SBATCH --ntasks=1         # number of processor cores (i.e. tasks)
#SBATCH --nodes=1          # number of nodes
#SBATCH --mem-per-cpu=1G   # memory per CPU core

set -euo pipefail

rm downloads/${CI_SHA}.tar.gz
rm -rf sources/${CI_SHA}
