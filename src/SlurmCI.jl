module SlurmCI

const builddir = "/central/scratchio/spjbyrne/slurmci/sources"
const downloaddir = "/central/scratchio/spjbyrne/slurmci/downloads"
const logdir = "/central/scratchio/spjbyrne/slurmci/logs"

using GitHub, Pidfile, Serialization, OrderedCollections

authenticate() = GitHub.authenticate(String(read("TOKEN")))

const context = "ci/slurmci"

mutable struct SlurmJob
    cmd::Cmd
    options
    id
    status
    elapsed
end
SlurmJob(cmd::Cmd; kwargs...) = SlurmJob(cmd, kwargs,
                                         nothing, nothing, nothing)

"""
    submit!(job::SlurmJob, extrakwargs...)

Submit the `job` as a batch job to slurm. Extra options can be added as keyword arguments.

The `id` field of `job` will be updated.
"""
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


function submit_slurmci_jobs(sha)
    basepath = joinpath(builddir,sha)
    
    jobdict = OrderedDict{String,SlurmJob}()
    status_jobids = String[]

    slurmoutdir = joinpath(logdir, sha)
    
    cd(basepath) do
        isdir(slurmoutdir) || mkdir(slurmoutdir)

        function process_jobset!(job::SlurmJob; deps=String[])
            if !isempty(deps)
                dependency="afterany:$(join(deps,':'))"
                submit!(job,
                        output=joinpath(slurmoutdir,"%j"),
                        dependency=dependency)
            else
                submit!(job,
                        output=joinpath(slurmoutdir, "%j"))
            end
            jobdict[job.id] = job
            return [job.id]
        end    
        function process_jobset!(pair::Pair; deps=String[])
            left, right = pair
            newdeps = process_jobset!(left; deps=deps)
            process_jobset!(right; deps=newdeps)
        end
        function process_jobset!(jobset::Union{AbstractVector,Tuple}; deps=String[])
            newdeps = String[]
            for job in jobset
                append!(newdeps, process_jobset!(job; deps=deps))
            end
            return newdeps
        end
        jobset = include(joinpath(basepath,".slurmci/jobs.jl"))
        process_jobset!(jobset)
    end
    

    submit!(SlurmJob(`jobs/cleanup.sh`);
            env="ALL,CI_SHA=$sha",
            dependency="afterany:$(join(keys(jobdict),':'))")

    save_jobdict(sha, jobdict)
end    


function save_jobdict(sha, jobdict)
    serialize(joinpath(builddir, "$sha/.slurmci/jobdict"), jobdict)
end
function load_jobdict(sha)
    deserialize(joinpath(builddir, "$sha/.slurmci/jobdict"))
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




function generate_summary(jobdict, sha)
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


end # module
