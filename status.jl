#!/bin/env julia

import GitHub, Dates

auth = GitHub.authenticate(String(read("TOKEN")))
repo = GitHub.repo("climate-machine/CLIMA", auth=auth)

context = "ci/caltech-hpc"

job = ENV["CI_JOB"]
jobid = ENV["CI_JOBID"]
sha = ENV["CI_SHA"]

# check job status
status = strip(String(read(`sacct -j $jobid.batch -o state --noheader`)))

# upload gist
outfile = "sources/$sha/slurm-$jobid.out"
outstr = String(read(outfile))

params = Dict("files" =>
              Dict("output" => Dict("content" => outstr)),              
              "description" => "HPC CI $sha",
              "public" => "true")
gist = GitHub.create_gist(;auth=auth, params=params)

# update status
params = Dict("state" => status == "COMPLETED" ? "success" :
                         status == "FAILED" ? "failure" :
                         "error",
              "context" => "$context/$job",
              "description" => "HPC: job id $jobid",
              "target_url" => string(gist.url))
status = GitHub.create_status(repo, sha;
                              auth=auth, params=params)

