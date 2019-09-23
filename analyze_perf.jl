#!/bin/env julia
#

using OrderedCollections, UnicodePlots


mutable struct FunPerfInfo
    name::String
    timepercent::Float64
    time::Float64
    avgncalls::Int64
    avgd::Float64
    mind::Float64
    maxd::Float64
    nranks::Int64
end


function parse_log!(activities::OrderedDict{String,Vector{FunPerfInfo}}, fn::String)
    # load and parse out all "GPU activities" lines
    lns = readlines(fn)
    for i = 1:length(lns)
	wds = split(lns[i], ",")
	wds[1] != "\"GPU activities\"" && continue
	onm = strip(wds[8], '"')
	r = findfirst("ptxcall_", onm)
	s = r == nothing ? 1 : r.stop+1
	nm = onm[s:end]
	activity = FunPerfInfo(nm, parse(Float64, wds[2]), parse(Float64, wds[3]),
			       parse(Int64, wds[4]), parse(Float64, wds[5]),
			       parse(Float64, wds[6]), parse(Float64, wds[7]), 1)
	curr = get(activities, activity.name, Vector{FunPerfInfo}())
	push!(curr, activity)
	activities[activity.name] = curr
    end
end


function condense_activities(activities::OrderedDict{String,Vector{FunPerfInfo}})
    # condense all activities for a kernel into a summary
    summary = OrderedDict{String,FunPerfInfo}()
    for nm in keys(activities)
	curr = activities[nm]
	nm_summary = curr[1]
	n = length(curr)
	for j = 2:n
	    nm_summary.timepercent += curr[j].timepercent
	    nm_summary.time += curr[j].time
	    nm_summary.avgncalls += curr[j].avgncalls
	    nm_summary.avgd += curr[j].avgd
	    nm_summary.mind = min(nm_summary.mind, curr[j].mind)
	    nm_summary.maxd = max(nm_summary.maxd, curr[j].maxd)
	end
	nm_summary.timepercent /= n
	nm_summary.time /= n
	nm_summary.avgncalls = round(Int64, nm_summary.avgncalls/n)
	nm_summary.avgd /= n
	nm_summary.nranks = n
	summary[nm] = nm_summary
    end
    return summary
end


function analyze_perf(dir::String)
    # parse "*.nvplog" in `dir`
    logs = filter(d -> d[end-6:end] == ".nvplog", readdir(dir))
    all_activities = OrderedDict{String,OrderedDict{String,Vector{FunPerfInfo}}}()
    for i = 1:length(logs)
	r = findfirst(".jl", logs[i])
	r == nothing && continue
	test_name = logs[i][1:r.stop]
	activities = get(all_activities, test_name, OrderedDict{String,Vector{FunPerfInfo}}())
        parse_log!(activities, joinpath(dir, logs[i]))
	all_activities[test_name] = activities
    end

    # summarize
    test_summaries = OrderedDict{String,OrderedDict{String,FunPerfInfo}}()
    for test_name in keys(all_activities)
	test_summaries[test_name] = condense_activities(all_activities[test_name])
    end
    return test_summaries
end


function gen_time_plot(test_name::String, summary::OrderedDict{String,FunPerfInfo})
    kernel_names = collect(keys(summary))
    kernel_times = map(k -> k.time, values(summary))
    plt = barplot(kernel_names, kernel_times,
                  title="$(test_name) GPU kernel performance",
                  xlabel="runtime (in ms)")
    iob = IOBuffer()
    show(iob, plt)
    return String(take!(iob))
end


function perf_summary(test_summaries::OrderedDict{String,OrderedDict{String,FunPerfInfo}}, sha)
    iob = IOBuffer()
    println(iob, "Commit: [`$sha`](https://github.com/climate-machine/CLIMA/commit/$sha)")
    println(iob)
    println(iob, "| test | #kernels | total time (ms) |")
    println(iob, "|------|----------|-----------------|")
    for test_name in keys(test_summaries)
	println(iob, "| $(test_name) | $(length(test_summaries[test_name])) | $(sum(map(k -> k.time, values(test_summaries[test_name])))) |")
    end
    String(take!(iob))
end

