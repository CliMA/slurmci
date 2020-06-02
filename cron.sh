#!/bin/bash
if [[ "$HOSTNAME" != "login1" ]]; then
    exit 0
fi

source /etc/bashrc

ENV_SCRIPT="$(dirname "$0")/env.sh"
if [ -f "$ENV_SCRIPT" ]; then
    # for setting SBATCH_ and SLURMCI_ vars
    source "$ENV_SCRIPT"
fi
module load julia/1.4.1
cd "$(dirname "$0")"
julia --project slurmci.jl "$@" &>> "log/$(date +\%Y-\%m-\%d)"
