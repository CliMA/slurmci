# updater cron jobs
#  for each tag
#    - get current heads
#    - get list of active shas
#    for each running sha
#      - get CheckRuns
#      - filter by set/completeness
#      for each CheckRun
#        - get sacct info
#        - get output
#        - if no longer head, kill job
#        - update CheckRun
#      update summary CheckRun
#      if all complete, cleanup

include("src/common.jl")

githubtime(str) = str == "Unknown" ? nothing : TimeZones.utc(ZonedDateTime(DateTime(str), localzone()))

function start(args::Vector{String})
    privkey_path = args[1] # ~/privkey.pem
    # tag = args[2]
    # branches = args[3:end]

    repo = Repo(reponame)

    # authenticate
    app_key = MbedTLS.PKContext()
    MbedTLS.parse_key!(app_key, read(privkey_path, String))
    jwt = GitHub.JWTAuth(app_id, app_key)
    inst = GitHub.installation(repo; auth=jwt)
    tok = GitHub.create_access_token(inst; auth=jwt)

    for (tag, branchnames) in ["test" => ["trying", "staging"], "perf" => ["master"]] # TODO: don't hardcode

        headshas = [GitHub.branch(reponame, branchname, auth=tok).commit.sha for branchname in branchnames]
        currentshas = readdir(joinpath(builddir, tag))

        for sha in currentshas
            sha_cancel = tag == "test" && sha ∉ headshas
            srcdir = joinpath(builddir, tag, sha)
            slurmoutdir = joinpath(logdir, tag, sha)

            runs, = GitHub.check_runs(repo, sha, auth=tok) # do we need to paginate?
            summary_run = findfirst(run -> run.name == "slurm/$tag", runs)
            if summary_run === nothing
                continue
            end
            job_runs = filter(run -> startswith(run.name, "slurm/$tag/"), runs)

            sha_complete = true
            sha_in_progress = false
            sha_failed = false
            sha_cancelled = false

            for run in job_runs
                jobid = run.external_id
                slurm_state, slurm_start, slurm_end = split(String(readchomp(
                    `sacct --allocations --jobs=$(jobid) --format=state,start,end --noheader --parsable2`)), '|')

                run.started_at = githubtime(slurm_start)
                run.completed_at = githubtime(slurm_end)
                if slurm_state == "PENDING"
                    run.status = "queued"
                    sha_complete = false
                    if sha_cancel
                        run(`scancel $jobid`)
                    end
                elseif slurm_state == "RUNNING"
                    run.status = "in_progress"
                    sha_complete = false
                    sha_in_progress = true
                    if sha_cancel
                        run(`scancel $jobid`)
                    end
                elseif slurm_state == "COMPLETED"
                    run.status = "completed"
                    run.conclusion = "success"
                    sha_in_progress = true
                elseif slurm_state == "CANCELLED"
                    run.status = "completed"
                    run.conclusion = "cancelled"
                    sha_in_progress = true
                    sha_cancelled = true
                elseif slurm_state in ("FAILED", "OUT_OF_MEMORY")
                    run.status = "completed"
                    run.conclusion = "failure"
                    sha_in_progress = true
                    sha_failed = true
                else
                    @warn "Unknown Slurm state: $(slurm_state)"
                end

                output = String(read(joinpath(slurmoutdir, jobid)))
                run.output.text = string("```\n", output, "\n```\n")
                GitHub.update_check_run(repo, run, params=run, auth=tok)
            end
            
            if sha_complete
                rm(joinpath(downloaddir, "$sha.tar.gz"))
                rm(srcdir, recursive=true)
            end

            
            summary_run.status =
                sha_complete    ? "completed"   :
                sha_in_progress ? "in_progress" :
                                  "queued"

            summary_run.conclusion =
                sha_failed    ? "failure"   :
                sha_cancelled ? "cancelled" :
                sha_complere  ? "success"   :
                                nothing

            GitHub.update_check_run(repo, summary_run, params=summary_run, auth=tok)
        end
    end
end

@assert length(ARGS) >= 1 """insufficient arguments
Usage:
  updater.jl <auth-token-filename>\n"""

start(ARGS)
