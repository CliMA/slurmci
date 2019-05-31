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

    # update branch hash on disk
    write(joinpath("branches", branchname), branch.commit.sha)

    if !isdir("sources/$sha")
        # download and extract repository
        isdir("downloads") || mkdir("downloads")
        download("https://api.github.com/repos/climate-machine/CLIMA/tarball/$sha", "downloads/$sha.tar.gz")

        isdir("sources") || mkdir("sources")
        isdir("sources/$sha") || mkdir("sources/$sha")
        run(`tar -xz -C sources/$sha --strip-components=1 -f downloads/$sha.tar.gz`)
    end
    
    if isfile("sources/$sha/.slurmci/jobs.jl")
        
        SlurmCI.submit_slurmci_jobs(sha)
        
        # set status
        status = GitHub.create_status(repo, sha; auth=auth, params=Dict(
            "state" => "pending",
            "context" => SlurmCI.context))
        
    else
        rm("downloads/$sha.tar.gz")
        rm("sources/$sha"; recursive=true)
    end
end
