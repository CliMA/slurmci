# slurmci

This is a collection of scripts used to run CI tests on a Slurm cluster.

The basic idea is that it will watch specific branches on the repository: if these change it will download a snapshot, and trigger a bunch of batch jobs (with possible dependencies)
 - If using with [bors](https://bors.tech/), the branches to watch are `staging` and `trying`
 - There is currently no sandboxing: anyone with write access to those branches will be able to trigger jobs with full access to the cluster account.
 - It is currently set up to be run as a cron job: if your cluster has a http endpoint, it would probably be better to use a webhook instead.

# Setting up

1. Create a machine user account on GitHub
  - Give it write access to the repository
  - Generate a token which has access to status updates and gists
  - Save this to a file named `TOKEN` in the top level directory
2. Create a subdirectory named `branches` with an empty file named for each branch to watch.
3. Change the paths to point to your repository in question
  - It is hardcoded to the https://github.com/climate-machine/CLIMA
4. Set up a cron job calling `cron.jl`
5. Create `.slurmci/jobs.jl` file in your repository
  - See https://github.com/climate-machine/CLIMA/blob/master/.slurmci/jobs.jl for an example.

