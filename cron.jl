#!/bin/env julia

using SlurmCI, GitHub
auth = SlurmCI.authenticate()
repo = GitHub.repo("climate-machine/CLIMA", auth=auth)

for branchname in readdir("branches")
    lastsha = String(read(joinpath("branches", branchname)))
    branch = GitHub.branch(repo, branchname, auth=auth)

    # check if new branch
    sha = branch.commit.sha
    if sha == lastsha
        continue
    end

    @info "new job" branchname sha

    # update branch hash on disk
    write(joinpath("branches", branchname), branch.commit.sha)

    if !isdir(joinpath(SlurmCI.builddir, sha))
        # download and extract repository
        isdir(SlurmCI.downloaddir) || mkdir(SlurmCI.downloaddir)
        download("https://api.github.com/repos/climate-machine/CLIMA/tarball/$sha", joinpath(SlurmCI.downloaddir, "$sha.tar.gz"))

        isdir(SlurmCI.builddir) || mkdir(SlurmCI.builddir)
        isdir(joinpath(SlurmCI.builddir, "$sha")) || mkdir(joinpath(SlurmCI.builddir, "$sha"))
        run(`tar -xz -C $(joinpath(SlurmCI.builddir,sha)) --strip-components=1 -f $(joinpath(SlurmCI.downloaddir, "$sha.tar.gz"))`)
    end
    
    if isfile(joinpath(joinpath(SlurmCI.builddir, sha, ".slurmci/jobs.jl")))
        
        SlurmCI.submit_slurmci_jobs(sha)
        
        # set status
        status = GitHub.create_status(repo, sha; auth=auth, params=Dict(
            "state" => "pending",
            "context" => SlurmCI.context))
        
    else
        rm(joinpath(SlurmCI.downloaddir, "$sha.tar.gz"))
        rm(joinpath(SlurmCI.builddir, sha); recursive=true)
    end
end
