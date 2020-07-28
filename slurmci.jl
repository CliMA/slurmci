#!/bin/env julia
#
# Usage:
#   slurmci.jl <auth-token-filename> <tag> <branch1> [<branch2> ...]
#
# Runs the tests in `ClimateMachine/slurmci-<tag>.toml` for each <branchN> for commits
# newer than those cached in <homedir>/slurmci.cache.

using GitHub, Pidfile, OrderedCollections, Pkg.TOML

include("src/common.jl")
include("src/slurm_jobs.jl")

function download_and_extract(sha::String)
    if !isdir(joinpath(builddir, sha))
        # download and extract repository
        isdir(downloaddir) || mkdir(downloaddir)
        download("https://api.github.com/repos/CliMA/ClimateMachine.jl/tarball/$sha",
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

    exclude = get(entries, "exclude", [])

    function create_test_job(sname, entry)
        cmd = `$(sname) $(entry["file"])`
        for arg in entry["args"]
            push!(cmd.exec, arg)
        end
        slurmargs = get(entry,"slurmargs",String[])
        if haskey(entry, "n")
            push!(slurmargs, "--ntasks=$(entry["n"])")
        end
        if !isempty(exclude)
	    exclude_str = join(exclude, ',')
	    push!(slurmargs, "--exclude=$exclude_str")
	end
        return SlurmJob(cmd, slurmargs)
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
    try
        nargs = length(args)
        auth_file = args[1]
        tag = args[2]
        branches = args[3:end]

        auth = authenticate(auth_file)
        repo = GitHub.repo("CliMA/ClimateMachine.jl", auth=auth)

        # the file `slurmci.cache` holds state -- a dictionary mapping branch name
        # to the sha of the commit last run for that branch
        cachefile = joinpath(homedir, "cache", "$tag.toml")
        branchshas = if isfile(cachefile)
            TOML.parsefile(cachefile)
        else
            Dict{String, String}()
        end

        state_updated = false

        for branchname in branches
            try
                branch = GitHub.branch(repo, branchname, auth=auth)
                sha = branch.commit.sha

                # check if new commit
                lastsha = get(branchshas, branchname, "")
                if sha == lastsha
                    continue
                end

                state_updated = true

                @info "new job" repo=repo branch=branchname sha=sha

                # record the commit hash for this branch
                branchshas[branchname] = branch.commit.sha

                # set status to pending
                status = GitHub.create_status(repo, sha; auth=auth, params=Dict(
                    "context" => context,
                    "state" => "pending",
                    "description" => "download source, prepare job submission"))

                download_and_extract(sha)

                # from the slurmci-<tag>.toml file
                cpu_jobs, gpu_jobs = load_jobs(sha, tag)

                # batch all requested jobs
                jobdict = OrderedDict{String,SlurmJob}()
                batch_jobset!(jobdict, sha, tag, "cpu", cpu_jobs)
                batch_jobset!(jobdict, sha, tag, "gpu", gpu_jobs)

                save_jobdict(sha, jobdict, tag)
                slurmoutdir = joinpath(logdir, sha)
                # TODO poll for completion here and finalize directly
                # instead of using this cleanup job
                submit!(SlurmJob(`scripts/$(tag)-cleanup.sh`);
                        env="ALL,CI_SHA=$sha,CI_TOKEN=$auth_file",
                        dependency="afterany:$(join(keys(jobdict),':'))",
                        output=joinpath(slurmoutdir, "%j"))

                # update status description on sucessful submission
                status = GitHub.create_status(repo, sha; auth=auth, params=Dict(
                    "context" => context,
                    "state" => "pending",
                    "description" => "job submitted"))
            catch
                # catch and save backtrace text from exception during job submission
                errorio = IOBuffer()
                orig_exception = true
                for (exc, bt) in Base.catch_stack()
                    showerror(errorio, exc, bt)
                    if orig_exception
                        # log original error exception for branch
                        @error "slurm ci checkout and job submission" repo=repo branch=branchname sha=sha exception=(exc, bt)
                        orig_exception = false
                    end
                end
                # try and update github services with exception information
                showerror_txt = String(take!(errorio))
                status_params = Dict(
                    "content" => context,
                    "state" => "error",
                    "description" => "error during job submission"
                )
                try
                    # try to post error message gist
                    gist_files = Dict(
                        "files" => Dict("slurmci_error_$sha.txt" => Dict("content" => showerror_txt))
                    )
                    gist_params = Dict(
                        "description" => "Error SlurmCI $branchname $sha",
                        "public" => true,
                        "files" => gist_files,
                    )
                    gist = GitHub.create_gist(;auth=auth, params=params)
                    # link gist url to github status output if successful
                    status_param["target_url"] = String(gist.html_url)
                catch e
                    @error "posting slurm ci submission gist" repo=repo branch=branchname sha=sha exception=e
                end
                # update PR / commit status on failure
                try
                    status = Github.create_status(repo, sha; auth=auth, params=status_params)
                catch e
                    @error "updating slurm ci commit status" repo=repo branch=branchname sha=sha exception=e
                end
            end
        end

        if state_updated
            try
                open(cachefile, "w") do io
                    TOML.print(io, branchshas)
                end
            catch e
                @error "when writing cache file" file=cachefile exception=(e, backtrace())
            end
        end

    catch e
        @error "slurm ci exception" exception=(e, backtrace())
    end
end


@assert length(ARGS) >= 3 """insufficient arguments
Usage:
  slurmci.jl <auth-token-filename> <tag> <branch1> [<branch2> ...]\n"""

start(ARGS)