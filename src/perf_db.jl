# perf_db.jl
#
# Stores performance data in a database and produces some performance
# graphs and tables.

using UnicodePlots, DataFrames, OrderedCollections, SQLite, Printf

# *_summaries fields:
# sha (commit hash) | fun | timepercent | time | avgncalls | avgd | mind | maxd | nranks
#
# *_metrics fields:
# sha (commit hash) | fun | metricname | mavg | mmin | mmax | nranks

const perf_db_name = "CLIMA_performance.sqlite"
const num_perf_diffs = 5

function store_perf_data(summaries::Dict{String,DataFrame},
                         metrics::Dict{String,DataFrame})
    db = SQLite.DB(joinpath(homedir, perf_db_name))
    for testname in keys(summaries)
        SQLite.load!(summaries[testname], db, "$(testname)_summaries")
    end
    for testname in keys(metrics)
        SQLite.load!(metrics[testname], db, "$(testname)_metrics")
    end
end

function gen_time_plot(sha::String, testname::String, pdf::DataFrame, mdf::DataFrame)
    iob = IOBuffer()
    knames = pdf[!, :fun]
    ktimes = pdf[!, :time]
    perfplt = barplot(knames, ktimes,
                      title="$(testname) GPU kernel total runtime (in us)")
    show(iob, perfplt)
    println(iob, "\n")

    mnames = unique(mdf[!, :mname])
    for mname in mnames
        mmdf = mdf[mdf[!, :mname] .== mname, :]
        knames = mmdf[!, :fun]
        kavgs = mmdf[!, :mavg]
        mplt = barplot(knames, kavgs, title="$(testname) $(mname) average")
        show(iob, mplt)
        println(iob)
    end

    return String(take!(iob))
end

function perf_summary(sha::String, summaries::Dict{String,DataFrame})
    iob = IOBuffer()
    println(iob, "Commit: [`$sha`](https://github.com/climate-machine/CLIMA/commit/$sha)")
    println(iob)
    println(iob, "| test | #kernels | total kernel time (us) |")
    println(iob, "|------|----------|------------------------|")
    testnames = keys(summaries)
    for testname in testnames
        pdf = summaries[testname]
        nfun = length(pdf[!,:fun])
        ttime = @sprintf "%.3f" sum(pdf[!,:time])
        println(iob, "| [$(testname)](#file-$(testname)) | $(nfun) | $(ttime) |")
    end
    String(take!(iob))
end

# use the database to create a table for each test showing the average
# runtime of each kernel over the last few commits
function perf_diff()
    db = SQLite.DB(joinpath(homedir, perf_db_name))

    tblsdf = SQLite.tables(db)
    filter!(tblsdf) do row
        endswith(row[:name], "_summaries") || endswith(row[:name], "_metrics")
    end
    testnames = String[]
    for row in eachrow(tblsdf)
        if endswith(row[:name], "_summaries")
            push!(testnames, row[:name][1:end-10])
        end
    end

    iob = IOBuffer()
    println(iob, "#### Performance Diffs")
    println(iob, "average kernel time (us)")
    println(iob)
    for testname in testnames
        allshas = SQLite.Query(db, "select distinct sha from $(testname)_summaries;") |> DataFrame
        isempty(allshas) && continue
        println(iob, "$(testname)")
        println(iob)

        shas = last(allshas, num_perf_diffs)[!,:sha]
        pdfs = OrderedDict{String,DataFrame}()
        knset = OrderedSet{String}()
        for sha in shas
            pdfs[sha] = SQLite.Query(db, "select fun, avgd from $(testname)_summaries where sha = '$sha';") |> DataFrame
            for fun in pdfs[sha][!, :fun]
                push!(knset, fun)
            end
        end
        hdr = "| kernel |"
        hdru = "|--------|"
        for n = 1:num_perf_diffs-length(shas)
            hdr = hdr * " (none) |"
            hdru = hdru * "--------|"
        end
        for sha in shas
            hdr = hdr * " $(sha[1:7]) |"
            hdru = hdru * "---------|"
        end
        println(iob, hdr)
        println(iob, hdru)
        knames = collect(knset)
        for kname in knames
            str = "| $(kname) |"
            for n = 1:num_perf_diffs-length(shas)
                str = str * " (none) |"
            end
            for sha in shas
                avgdv = pdfs[sha][pdfs[sha][!,:fun] .== kname, :avgd]
                str = str * (length(avgdv) == 1 ? (@sprintf "%.3f" avgdv[1]) : " (none)") * " |"
            end
            println(iob, str)
        end
    end

    String(take!(iob))
end

