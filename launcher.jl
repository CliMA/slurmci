# launcher cron job for set (e.g. test)
#   for each branch
#     - check summary CheckRun (e.g. slurm/test)
#     if it doesn't exist
#       - download and extract tarball
#       - schedule jobs
#       - post CheckRuns
#       - post summary CheckRun

using Pkg.TOML

include("src/common.jl")
include("src/slurm_jobs.jl")

function download_and_extract(tag, sha::String)
    srcdir = joinpath(builddir, tag, sha)
    if !isdir(srcdir)
        # download and extract repository
        mkpath(downloaddir)
        download("https://api.github.com/repos/$reponame/tarball/$sha",
                 joinpath(downloaddir, "$sha.tar.gz"))

        mkpath(srcdir)
        run(`tar -xz -C $srcdir --strip-components=1 -f $(joinpath(downloaddir, "$sha.tar.gz"))`)
    end
end

function load_jobs(sha::String, tag::String)
    srcdir = joinpath(builddir, tag, sha)

    entries = TOML.parsefile(joinpath(srcdir, "slurmci-$(tag).toml"))

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
    privkey_path = args[1] # ~/privkey.pem
    tag = args[2]
    branches = args[3:end]

    repo = Repo(reponame)

    # authenticate
    app_key = MbedTLS.PKContext()
    MbedTLS.parse_key!(app_key, read(privkey_path, String))
    jwt = GitHub.JWTAuth(app_id, app_key)
    inst = GitHub.installation(repo; auth=jwt)
    tok = GitHub.create_access_token(inst; auth=jwt)

    for branchname in branches
        # check if already started
        runs, = GitHub.check_runs(repo, branchname; auth=tok, params=Dict("check_name" => "slurm/$tag"))
        if !isempty(runs)
            continue
        end

        # get SHA
        branch = GitHub.branch(repo, branchname, auth=tok)
        sha = branch.commit.sha
        @info "new job" tag branchname sha

        download_and_extract(tag, sha)

        # from the slurmci-<tag>.toml file
        cpu_jobs, gpu_jobs = load_jobs(sha, tag)

        for (plat, jobs) in ["cpu" => cpu_jobs, "gpu" => gpu_jobs]
            isempty(jobs) && continue

            srcdir = joinpath(builddir, tag, sha)
            slurmoutdir = joinpath(logdir, tag, sha)
            mkpath(slurmoutdir)

            init_job = SlurmJob(`scripts/$(tag)-$(plat)-init.sh`)
            submit!(init_job; env="ALL,CI_SRCDIR=$srcdir,CI_OUTDIR=$slurmoutdir",
                    output=joinpath(slurmoutdir, "%j"))
            
            GitHub.create_check_run(repo, auth=tok, params=GitHub.CheckRun(
                name        = "slurm/$(tag)/$(plat)-init",
                head_sha    = sha,
                external_id = "$(init_job.id)",
                status      = "queued",
                output      = GitHub.Checks.Output(
                    title     = "Initialize $(plat)",
                    summary   = "cmd: `$(init_job.cmd)`\noptions: `$(init_job.options)`\njob id: $(init_job.id)")
            ))
            
            runtests_fn = "scripts/$(tag)-$(plat)-tests.sh"
            if isfile(runtests_fn)
                runtests_job = SlurmJob(`$runtests_fn`)
                submit!(runtests_job; env="ALL,CI_SRCDIR=$srcdir,CI_OUTDIR=$slurmoutdir",
                        output=joinpath(slurmoutdir, "%j"),
                        dependency="afterany:$(init_job.id)")
                GitHub.create_check_run(repo, auth=tok, params=GitHub.CheckRun(
                    name        = "slurm/$(tag)/$(plat)-test",
                    head_sha    = sha,
                    external_id = "$(runtests_job.id)",
                    status      = "queued",
                    output      = GitHub.Checks.Output(
                        title     = "Test $(plat)",
                        summary   = "cmd: `$(runtests_job.cmd)`\noptions: `$(runtests_job.options)`\njob id: $(runtests_job.id)")
                ))
            end
            
            for job in jobs
                submit!(job; env="ALL,CI_SRCDIR=$srcdir,CI_OUTDIR=$slurmoutdir",
                        output=joinpath(slurmoutdir, "%j"),
                        dependency="afterany:$(init_job.id)")

                GitHub.create_check_run(repo, auth=tok, params=GitHub.CheckRun(
                    name        = "slurm/$(tag)/$(plat)-$(basename(job.cmd[2]))",
                    head_sha    = sha,
                    external_id = "$(job.id)",
                    status      = "queued",
                    output      = GitHub.Checks.Output(
                        title     = "Run $(plat) $(basename(job.cmd[2]))",
                        summary   = "cmd: `$(job.cmd)`\noptions: `$(job.options)`\njob id: $(job.id)")
                ))

            end
        end

        GitHub.create_check_run(repo, auth=tok, params=GitHub.CheckRun(
            name        ="slurm/$(tag)",
            head_sha    = sha,
            status      = "queued",
            output      = GitHub.Checks.Output(
                title     = "Summary",
                summary   = "")
        ))
    end
end

@assert length(ARGS) >= 3 """insufficient arguments
Usage:
  launcher.jl <auth-token-filename> <tag> <branch1> [<branch2> ...]\n"""

start(ARGS)

        
