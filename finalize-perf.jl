#!/bin/env julia
#
# Usage:
#   finalize-perf.jl
#
# Final job for SlurmCI perf job set -- requires the environment variable
# CI_SHA to be set to the commit hash of the branch and CI_TOKEN to be set
# to the filename containing the authentication token. Uploads performance
# analysis data to a gist.

using GitHub

include("src/common.jl")
include("src/slurm_jobs.jl")
include("src/analyze_perf.jl")
include("src/perf_db.jl")

function start()
    sha = ENV["CI_SHA"]
    auth = authenticate(ENV["CI_TOKEN"])

    jobdict = load_jobdict(sha)
    update_status!(jobdict)

    # generate and upload the performance gist
    summaries, metrics = analyze_perf(sha)
    if !isempty(summaries)
        # store performance data in a database
        store_perf_data(summaries, metrics)

        perf_files = Dict("_performance.md" => Dict("content" =>
                                                    perf_summary(sha, summaries)))

        perf_files["_diffs.md"] = Dict("content" => perf_diff())

        for testname in keys(summaries)
            perf_files[testname] = Dict("content" =>
                                        gen_time_plot(sha, testname,
                                                      summaries[testname],
                                                      metrics[testname]))
        end

        params = Dict("files" => perf_files,
                      "description" => "SlurmCI Perf $sha",
                      "public" => "true")
        gist = GitHub.create_gist(;auth=auth, params=params)
    end
end

start()
