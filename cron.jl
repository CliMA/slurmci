#!/bin/env julia
#
# Usage:
#   cron.jl <auth-token-filename> <jobsjl-filename> <branch1> [<branch2> ...]
#
# Stores state in the current working directory.


using SlurmCI, GitHub, Serialization, OrderedCollections


function download_and_extract(sha::String)
    if !isdir(joinpath(SlurmCI.builddir, sha))
        # download and extract repository
        isdir(SlurmCI.downloaddir) || mkdir(SlurmCI.downloaddir)
        download("https://api.github.com/repos/climate-machine/CLIMA/tarball/$sha", joinpath(SlurmCI.downloaddir, "$sha.tar.gz"))

        isdir(SlurmCI.builddir) || mkdir(SlurmCI.builddir)
        isdir(joinpath(SlurmCI.builddir, "$sha")) || mkdir(joinpath(SlurmCI.builddir, "$sha"))
        run(`tar -xz -C $(joinpath(SlurmCI.builddir, sha)) --strip-components=1 -f $(joinpath(SlurmCI.downloaddir, "$sha.tar.gz"))`)
    end
end


"""
    start(args::Vector{String})

Entry point. `args` should be:

    <auth-token-filename> <jobsjl-filename> <branch1> [<branch2> ...]
"""
function start(args::Vector{String})
    auth_file = args[1]
    jobsjl_file = args[2]
    branches = args[3:end]

    @assert isfile(jobsjl_file)

    auth = SlurmCI.authenticate(auth_file)
    repo = GitHub.repo("climate-machine/CLIMA", auth=auth)

    # the file 'branch-shas' holds state -- a dictionary mapping branch name
    # to the sha of the commit last run for that branch
    branchshas = try
        deserialize("branch-shas")
    catch e
        OrderedDict{String,String}()
    end

    state_updated = false

    for branchname in branches
        branch = GitHub.branch(repo, branchname, auth=auth)
        sha = branch.commit.sha

        # check if new commit
        try
            lastsha = branchshas[branchname]
            if sha == lastsha
                continue
            end
        catch e
        end

        state_updated = true

        @info "new job" branchname sha

        # update state -- store commit hash for this branch
        branchshas[branchname] = branch.commit.sha

        download_and_extract(sha)

        # submit all the jobs for this commit
        SlurmCI.submit_slurmci_jobs(auth_file, sha, jobsjl_file)

        # set status
        status = GitHub.create_status(repo, sha; auth=auth, params=Dict(
            "state" => "pending",
            "context" => context))
    end

    state_updated && serialize("branch-shas", branchshas)
end


@assert length(ARGS) >= 3 """insufficient arguments
Usage:
  cron.jl <auth-token-filename> <jobsjl-filename> <branch1> [<branch2> ...]\n"""

start(ARGS)

