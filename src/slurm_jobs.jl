# slurm_jobs.jl
#
# Encapsulates SLURM-specific functionality -- job representation, submission,
# and status.

using Serialization, OrderedCollections

mutable struct SlurmJob
    cmd::Cmd
    options
    id
    status
    elapsed
end
SlurmJob(cmd::Cmd; kwargs...) = SlurmJob(cmd, kwargs, nothing, nothing, nothing)

function submit!(job::SlurmJob; extrakwargs...)
    sbatchcmd = `/central/slurm/install/current/bin/sbatch`
    for (kw,val) in pairs(job.options)
        if kw == :env
            kw = :export
        end
        push!(sbatchcmd.exec, "--$kw=$val")
    end
    for (kw,val) in extrakwargs
        if kw == :env
            kw = :export
        end
        push!(sbatchcmd.exec, "--$kw=$val")
    end
    append!(sbatchcmd.exec, job.cmd)
    _,jobid = rsplit(chomp(String(read(sbatchcmd))), limit=2)
    job.id = String(jobid)
    return job
end

function batch_jobset!(jobdict, sha, tag, plat, jobs)
    isempty(jobs) && return

    srcdir = joinpath(builddir, sha)
    slurmoutdir = joinpath(logdir, sha)
    isdir(slurmoutdir) || mkdir(slurmoutdir)

    init_job = SlurmJob(`scripts/$(tag)-$(plat)-init.sh`)
    submit!(init_job; env="ALL,CI_SRCDIR=$srcdir,CI_OUTDIR=$slurmoutdir",
            output=joinpath(slurmoutdir, "%j"))
    jobdict[init_job.id] = init_job

    runtests_fn = "scripts/$(tag)-$(plat)-tests.sh"
    if isfile(runtests_fn)
        runtests_job = SlurmJob(`$runtests_fn`)
        submit!(runtests_job; env="ALL,CI_SRCDIR=$srcdir,CI_OUTDIR=$slurmoutdir",
                output=joinpath(slurmoutdir, "%j"),
                dependency="afterany:$(init_job.id)")
        jobdict[runtests_job.id] = runtests_job
    end

    for job in jobs
        submit!(job; env="ALL,CI_SRCDIR=$srcdir,CI_OUTDIR=$slurmoutdir",
                output=joinpath(slurmoutdir, "%j"),
                dependency="afterany:$(init_job.id)")
        jobdict[job.id] = job
    end
end

function save_jobdict(sha, jobdict)
    serialize(joinpath(builddir, "$sha/jobdict"), jobdict)
end
function load_jobdict(sha)
    deserialize(joinpath(builddir, "$sha/jobdict"))
end

function update_status!(job::SlurmJob)
    status,elapsed = split(String(read(`sacct -j $(job.id).batch -o state,elapsed --noheader`)))
    job.status = String(status)
    job.elapsed = String(elapsed)
end
function update_status!(jobdict::OrderedDict)
    for job in values(jobdict)
        update_status!(job)
    end
end

function summary_state(jobdict)
    failed = false
    error = false
    for job in values(jobdict)
        failed = failed || job.status == "FAILED"
        error  = error  || job.status != "COMPLETED"
    end
    failed ? "failure" : error  ? "error" :  "success"
end

function test_summary(jobdict, sha)
    io = IOBuffer()
    println(io, "Commit: [`$sha`](https://github.com/climate-machine/CLIMA/commit/$sha)")
    println(io)
    println(io, "| command | ntasks | jobid | status | elapsed |")
    println(io, "|---------|--------|-------|--------|---------|")
    for job in values(jobdict)

        options = join(["$k=$v" for (k,v) in pairs(job.options)], ", ")

        idlink = status == "" ? job.id : "[$(job.id)](#file-out_$(job.id))"

        statussym =
            job.status == "" ? "" :
            job.status == "COMPLETED" ? "\u2705" :
            job.status == "FAILED" ? "\u274c" :
            "\u26A0"        

        println(io, "| $(job.cmd) | $options | $idlink | $statussym | $(job.elapsed) |")
    end
    String(take!(io))
end

