#!/bin/env julia
#
# Usage:
#   finalize.jl
#
# Final job for every SlurmCI job set -- requires the environment variable
# CI_SHA to be set to the commit hash of the branch and CI_TOKEN to be set
# to the filename containing the authentication token. Uploads summaries,
# logs, and possibly performance graphs for the jobs to gists and updates
# the Github status.

using SlurmCI, GitHub

include("analyze_perf.jl")

sha = ENV["CI_SHA"]

basepath = joinpath(SlurmCI.builddir, sha)
slurmoutdir = joinpath(SlurmCI.logdir, sha)

jobdict = SlurmCI.load_jobdict(sha)
SlurmCI.update_status!(jobdict)

files = Dict("_summary.md" => Dict("content" => SlurmCI.generate_summary(jobdict, sha)))

for jobid in keys(jobdict)
    filename = joinpath(slurmoutdir, jobid)
    files["out_$jobid"] = Dict("content" => String(read(filename)))
end

# authenticate
auth = SlurmCI.authenticate(ENV["CI_TOKEN"])
repo = GitHub.repo("climate-machine/CLIMA", auth=auth)

# upload gist
params = Dict("files" => files,
              "description" => "SlurmCI $sha",
              "public" => "true")
gist = GitHub.create_gist(;auth=auth, params=params)

# if this was a performance run, generate and upload the performance gist
perf_summaries = analyze_perf(slurmoutdir)
if !isempty(perf_summaries)
    perf_files = Dict("_performance.md" => Dict("content" => perf_summary(perf_summaries, sha)))

    for test_name in keys(perf_summaries)
        if !isempty(perf_summaries[test_name])
            perf_files[test_name] = Dict("content" => gen_time_plot(test_name, perf_summaries[test_name]))
        end
    end

    params = Dict("files" => perf_files,
                  "description" => "PerfCI $sha",
                  "public" => "true")
    gist = GitHub.create_gist(;auth=auth, params=params)
end

# update status
params = Dict("state" => SlurmCI.summary_state(jobdict),
              "context" => SlurmCI.context,
              "target_url" => string(gist.html_url))

status = GitHub.create_status(repo, sha;
                              auth=auth, params=params)
