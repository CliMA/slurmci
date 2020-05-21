#!/bin/bash
if [[ "$HOSTNAME" != "login1" ]]; then
    exit 0
fi

source /etc/bashrc
if [ -f "env.sh" ]; then
    # for setting SBATCH_ and SLURMCI_ vars
    source env.sh
fi
module load julia/1.4.1
cd "$(dirname "$0")"
julia --project slurmci.jl "$@" &>> "log/$(date +\%Y-\%m-\%d)"
