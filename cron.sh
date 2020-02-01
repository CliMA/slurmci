#!/bin/bash
if [[ "$HOSTNAME" != "login1" ]]; then
    exit 0
fi

source /etc/bashrc
export PATH="/groups/esm/common/julia-1.3:$PATH"
cd "$(dirname "$0")"
export SBATCH_RESERVATION=clima
julia --project slurmci.jl "$@" &>> "log/$(date +\%Y-\%m-\%d)"
