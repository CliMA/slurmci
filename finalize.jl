using SlurmCI, GitHub

sha = ENV["CI_SHA"]

jobdict = SlurmCI.load_jobdict(sha)
SlurmCI.update_status!(jobdict)

files = Dict("_summary.md" => Dict("content" => SlurmCI.generate_summary(jobdict)))

basepath = "sources/$sha"
slurmoutdir = joinpath(basepath, ".slurmciout")

for jobid in keys(jobdict)
    filename = joinpath(slurmoutdir, jobid)
    files["out_$jobid"] = Dict("content" => String(read(filename)))
end

# authenticate
auth = SlurmCI.authenticate()
repo = GitHub.repo("climate-machine/CLIMA", auth=auth)

# upload gist
params = Dict("files" => files,
              "description" => "SlurmCI $sha",
              "public" => "true")
gist = GitHub.create_gist(;auth=auth, params=params)

# update status
params = Dict("state" => SlurmCI.summary_state(jobdict),
              "context" => SlurmCI.context,
              "target_url" => string(gist.html_url))

status = GitHub.create_status(repo, sha;
                              auth=auth, params=params)
