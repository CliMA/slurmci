using GitHub

const homedir = "/groups/esm/slurmci"
const builddir = "/central/scratchio/esm/slurmci/sources"
const downloaddir = "/central/scratchio/esm/slurmci/downloads"
const logdir = "/central/scratchio/esm/slurmci/logs"
const context = "ci/slurmci"

#authenticate(auth_file) = GitHub.authenticate(joinpath(homedir, chomp(String(read(auth_file)))))
authenticate(auth_file) = GitHub.authenticate(chomp(String(read(auth_file))))

