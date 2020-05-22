using GitHub

const homedir = get(ENV, "SLURMCI_HOMEDIR", "/groups/esm/slurmci")
const workdir = get(ENV, "SLURMCI_WORKDIR", "/central/scratchio/esm/slurmci")
const builddir = joinpath(workdir, "sources")
const downloaddir = joinpath(workdir, "downloads")
const logdir = joinpath(workdir, "logs")

const context = "ci/slurmci"

authenticate(auth_file) = GitHub.authenticate(chomp(String(read(auth_file))))

