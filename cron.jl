#!/bin/env julia

import GitHub, Dates

auth = GitHub.authenticate(String(read("TOKEN")))
repo = GitHub.repo("climate-machine/CLIMA", auth=auth)

context = "ci/caltech"

function isjobrunning(jobid)
    String(read(`squeue --noheader --jobs=$jobid`)) != ""
end

function submitjob(script;kwargs...)
    cmd = `sbatch`
    for (kw,val) in kwargs
        if kw == :env
            kw = :export
        end
        push!(cmd.exec, "--$kw=$val")
    end
    push!(cmd.exec, script)
    _,jobid = rsplit(chomp(String(read(cmd))), limit=2)
    return jobid
end

for branchname in readdir("branches")
    lastsha = String(read(joinpath("branches", branchname)))
    branch = GitHub.branch(repo, branchname, auth=auth)

    # check if new branch
    sha = branch.commit.sha
    if sha == lastsha
        continue
    end

    # # check if status has recently been updated (e.g. from another branch)
    # statuses,_ = GitHub.statuses(repo, branch.commit.sha)
    # for status in statuses
    #     if Dates.now(Dates.UTC) - status.updated_at > Dates.Hour(24)
    #         # everything over 24 hours old
    #         break
    #     end
    #     if startswith(status.context, context)
    #         # TODO: store Slurm job number and check status
    #         @goto nextbranch
    #     end
    # end

    # update branch hash on disk
    write(joinpath("branches", branchname), branch.commit.sha)

    # download and extract repository
    isdir("downloads") || mkdir("downloads")
    download("https://api.github.com/repos/climate-machine/CLIMA/tarball/$sha", "downloads/$sha.tar.gz")

    isdir("sources") || mkdir("sources")
    isdir("sources/$sha") || mkdir("sources/$sha")
    run(`tar -xz -C sources/$sha --strip-components=1 -f downloads/$sha.tar.gz`)

    status_jobids = String[]
    for job in ["cpu"]
        jobid = submitjob("jobs/$job.sh"; chdir="sources/$sha")
        status_jobid = submitjob("jobs/status.sh";
                                 dependency="afterany:$jobid",
                                 env="ALL,CI_JOB=$job,CI_JOBID=$jobid,CI_SHA=$sha")

        # set status
        params = Dict("state" => "pending",
                      "context" => "$context/$job",
                      "description" => "jobid $jobid")
        status = GitHub.create_status(repo, sha;
                                      auth=auth, params=params)

        push!(status_jobids, status_jobid)
    end

    submitjob("jobs/cleanup.sh";
              dependency="afterany:$(join(status_jobids,':'))",
              env="ALL,CI_SHA=$sha")
    
    # @label nextbranch
end
