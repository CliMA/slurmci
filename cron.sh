#!/bin/bash
if [[ "$HOSTNAME" != "login1" ]]; then
    exit 0
fi

source /etc/bashrc
module load julia/1.2.0
cd "$(dirname "$0")"
export SBATCH_RESERVATION=clima
julia --project slurmci.jl "$@" &>> "log/$(date +\%Y-\%m-\%d)"
