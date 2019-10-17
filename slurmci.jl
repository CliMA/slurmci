#!/bin/env julia
#
# Usage:
#   slurmci.jl <auth-token-filename> <tag> <branch1> [<branch2> ...]
#
# Runs the tests in `CLIMA/slurmci-<tag>.toml` for each <branchN> for commits
# newer than those cached in <homedir>/slurmci.cache.

using GitHub, Pidfile, OrderedCollections, Pkg.TOML

include("src/common.jl")
include("src/slurm_jobs.jl")

function download_and_extract(sha::String)
    if !isdir(joinpath(builddir, sha))
        # download and extract repository
        isdir(downloaddir) || mkdir(downloaddir)
        download("https://api.github.com/repos/climate-machine/CLIMA/tarball/$sha",
                 joinpath(downloaddir, "$sha.tar.gz"))

        isdir(builddir) || mkdir(builddir)
        isdir(joinpath(builddir, sha)) || mkdir(joinpath(builddir, sha))
        run(`tar -xz -C $(joinpath(builddir, sha)) --strip-components=1 -f $(joinpath(downloaddir, "$sha.tar.gz"))`)
    end
end

function load_jobs(sha::String, tag::String)
    entries = TOML.parsefile(joinpath(builddir, sha, "slurmci-$(tag).toml"))

    # TODO: check for malformed entries?

    cpu_tests = get(entries, "cpu", [])
    cpu_gpu_tests = get(entries, "cpu_gpu", [])
    gpu_tests = get(entries, "gpu", [])

    function create_test_job(sname, entry)
        cmd = `$(sname) $(entry["file"])`
        for arg in entry["args"]
            push!(cmd.exec, arg)
        end
        return SlurmJob(cmd, ntasks=entry["n"])
    end

    cpu_jobs = [create_test_job("scripts/$(tag)-cpu.sh", entry) for entry in cpu_tests]
    append!(cpu_jobs,
            [create_test_job("scripts/$(tag)-cpu.sh", entry) for entry in cpu_gpu_tests])
    gpu_jobs = [create_test_job("scripts/$(tag)-gpu.sh", entry) for entry in gpu_tests]
    append!(gpu_jobs,
            [create_test_job("scripts/$(tag)-gpu.sh", entry) for entry in cpu_gpu_tests])

    return cpu_jobs, gpu_jobs
end

function start(args::Vector{String})
    auth_file = args[1]
    tag = args[2]
    branches = args[3:end]

    auth = authenticate(auth_file)
    repo = GitHub.repo("climate-machine/CLIMA", auth=auth)

    # the file `slurmci.cache` holds state -- a dictionary mapping branch name
    # to the sha of the commit last run for that branch
    branchshas = try
        TOML.parsefile(joinpath(homedir, "cache", "$tag.toml"))
    catch e
        Dict{String,String}()
    end

    state_updated = false

    for branchname in branches
        branch = GitHub.branch(repo, branchname, auth=auth)
        sha = branch.commit.sha

        # check if new commit
        lastsha = get(branchshas, branchname, "")
        if sha == lastsha
            continue
        end

        state_updated = true

        @info "new job" branchname sha

        # record the commit hash for this branch
        branchshas[branchname] = branch.commit.sha

        download_and_extract(sha)

        # from the slurmci-<tag>.toml file
        cpu_jobs, gpu_jobs = load_jobs(sha, tag)

        # batch all requested jobs
        jobdict = OrderedDict{String,SlurmJob}()
        batch_jobset!(jobdict, sha, tag, "cpu", cpu_jobs)
        batch_jobset!(jobdict, sha, tag, "gpu", gpu_jobs)

        save_jobdict(sha, jobdict)

        # TODO poll for completion here and finalize directly
        # instead of using this cleanup job
        submit!(SlurmJob(`scripts/$(tag)-cleanup.sh`);
                env="ALL,CI_SHA=$sha,CI_TOKEN=$auth_file",
                dependency="afterany:$(join(keys(jobdict),':'))",
                output=joinpath(slurmoutdir, "%j"))

        # set status
        status = GitHub.create_status(repo, sha; auth=auth, params=Dict(
            "state" => "pending",
            "context" => context))
    end

    if state_updated
        open(joinpath(homedir, "cache", "$tag.toml"), "w") do io
            TOML.print(io, branchshas)
        end
    end
end


@assert length(ARGS) >= 3 """insufficient arguments
Usage:
  cron.jl <auth-token-filename> <tag> <branch1> [<branch2> ...]\n"""

start(ARGS)

