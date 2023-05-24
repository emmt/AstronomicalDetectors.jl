module ReadCalibration

export read_calibration_files_from_yaml

using Dates
using ..Configs
using ..YAMLParsing
using EasyFITS: FitsFile, FitsImageHDU
using ScientificDetectors
using ScientificDetectors.Calibration: prunecalibration
import ScientificDetectors: CalibrationCategory, CalibrationData

"""
    parse_datetime_like_yaml(str; faildate=DateTime(0,1,1)) -> DateTime

Parse a String to a DateTime. Chop off the 4th digit of Milliseconds if present.

A lot of Sphere FITS files use 4 digits for milliseconds, whereas
Julia only supports 3 digits. In this case, we chop off the 4th digit. Rounding would be better,
but we want to do it in the same way that the YAML library do it. If the same String value gets a
different parsed DateTime value in the YAML and in this module, it can make some Configs filters
go wrong.
"""
function parse_datetime_like_yaml(str::AbstractString ; faildate::DateTime=DateTime(0,1,1)
) ::DateTime
    date = tryparse(DateTime, str)
    if date === nothing ; date = tryparse(DateTime, chop(str ; tail=1)) end
    if date === nothing
        @warn string("Could not parse date \"", str, "\", using default date: ", faildate)
        date = faildate
    end
    return date
end

"""
    find_filepaths_by_category(config; basedir=pwd()) -> Dict{String,Vector{String}}

Follow `config` to list candidate files for each category.

A file is candidate if it is in the directory indicated by the `dir` setting (subfolders are
supported if the setting `include_subdirectories` is true), if its suffix is among the ones listed
by setting `suffixes`, and if it do not contains any of the `exclude_files` setting substring list.
A file is also candidate if it is listed explicitely in the `files` setting. The keyword filters 
defined in `config` are *not* checked by this function, but by the functions [`challenge_file`](@ref)
and [`find_and_filter_files_by_category`](@ref). Please note that the paths of config' settings can
be relative. They will thus be resolved from the current working dir, at the time when this
function is called. To modify the directory from which relative paths will be resolved, use 
parameter `basedir`.
"""
function find_filepaths_by_category(config::Config ; basedir::AbstractString=pwd()
) ::Dict{String,Vector{String}}

    filepaths_by_cat = Dict{String,Vector{String}}()
    
    oldpwd = pwd()
    cd(basedir)
    try
        # add categories files (decided by settings `files`, `dir`, `exclude files`, `suffixes`)
        for (name,category) in config.categories

            filepaths_by_cat[name] = String[]

            if isempty(category.files) # if there is no exclusive list of files

                for (currentdir, dirs, files) in walkdir(category.dir ;
                        topdown = true,
                        follow_symlinks = category.follow_symbolic_links,
                        onerror = err -> ())
                        
                    for filename in files
                        any(occursin(filename), category.exclude_files) && continue
                        any(suffix -> endswith(filename, suffix), category.suffixes) || continue
                        filepath = abspath(joinpath(currentdir, filename)) # make path absolute
                        push!(filepaths_by_cat[name], filepath)
                    end
                    
                    category.include_subdirectories || break
                end

            else
                filepaths_by_cat[name] 
                for filepath in category.files
                    absfilepath = abspath(filepath) # make path absolute
                    if isfile(absfilepath) ; push!(filepaths_by_cat[name], absfilepath)
                    else @warn "File from setting `files` not found: $(absfilepath)." end
                end
            end
            
            isempty(filepaths_by_cat[name]) && @warn string(
                "No files found for category ", name, ", even before applying filters.")
        end
    finally
        cd(oldpwd)
    end
    
    all(isempty, values(filepaths_by_cat)) && error(string(
        "Zero files found even before applying filters. Maybe you are in the wrong base ",
        "directory. Try option `basedir` ? Or check the settings, in particular \"dir\", ",
        "\"suffixes\", \"exclude files\", \"include subdirectories\"."))
    
    return filepaths_by_cat
end

"""
    gather_filters_keywords(config) -> Dict{String,Type}
    
Follow `config` to list the keyword names and the types of the filters.

The setting `exptime` is considered as a filter too. The goal is to have the list of the keywords
that we need to read in the FITS files. Then we can collect all needed information in one pass
over the collection of FITS files, this is done in the function
[`find_and_filter_files_by_category`](@ref).

Return a dictionnary where keys are the keyword names, and values are types of the target values
of the filters. Every type is <: [`FilterValue`](@ref).
"""
function gather_filters_keywords(config::Config) ::Dict{String,Type}

    gathered = Dict{String,Type}()
    
    function gather(kwdname, kwdtype)
        if haskey(gathered, kwdname) && gathered[kwdname] != kwdtype
            @warn string("Redefinition of filter keyword's type: ",
                         "from ", gathered[kwdname], " to ", kwdtype, ".")
        end
        gathered[kwdname] = kwdtype
    end
    
    !isempty(config.exptime) && gather(config.exptime, Float64)
    foreach(config.filters) do (kwdname,filter) ; gather(kwdname, eltype(filter)) end
    
    for (name, category) in config.categories
        !isempty(config.exptime) && gather(category.exptime, Float64)
        foreach(category.filters) do (kwdname,filter) ; gather(kwdname, eltype(filter)) end
    end
    
    return gathered
end

"""
    gather_files_infos(filepaths, filters_keywords) -> Dict{String,Dict{String,Any}}

Retrieve the value for each given filter keyword, for each given filepath.

Missing keywords will give `missing` values. A wrong type asked for a keyword will throw an error,
i.e a Logical FITS keyword cannot be asked as an Int. Note that the FITS keyword have no notion
of Float32 or Float64 so asking a Float64 will work as long as the FITS keyword is Real. Be
careful because FITS floats possible values are a different than Julia `Float64` possible values.
DateTime values are parsed by function [`parse_datetime_like_yaml`](@ref).
"""
function gather_files_infos(filepaths::Set{String}, filters_keywords::Dict{String,Type}
) ::Dict{String,Dict{String,Any}}

    files_infos = Dict{String,Dict{String,Any}}()
    
    @info string("Reading ", length(filepaths),
                 " files for header infos (it can take a long time).")
    for filepath in filepaths
        FitsFile(filepath) do file
            primaryhdu = file[1]
            dic = Dict{String,Any}()
            for (kwdname, kwdtype) in filters_keywords
                kwdval =
                    if kwdtype == DateTime
                        str = get(primaryhdu, kwdname, (;value=T->missing)).value(String)
                        ismissing(str) ? missing : parse_datetime_like_yaml(str)
                    else
                        get(primaryhdu, kwdname, (;value=T->missing)).value(kwdtype)
                    end
                dic[kwdname] = kwdval
            end
            files_infos[filepath] = dic
        end
    end
    
    return files_infos
end

"""
    challenge_file(filters, file_infos) -> Tuple{Bool,String}
    
Tests if given keyword values respect the given filters.

Returns `true` and an empty `String` if success. If one keyword is wrong, returns `false`
along with the keyword name. Parameter `file_infos` must contain informations for all given
`filters`.
"""
function challenge_file(filters::Dict{String,ConfigFilter}, file_infos::Dict{String,Any}
) ::Tuple{Bool,String}

    for (keywordname,filter) in filters
        haskey(file_infos, keywordname) || error("File infos has no key $(keywordname).")
        ismissing(file_infos[keywordname]) && return(false, keywordname)
        challenge_filter(filter, file_infos[keywordname]) || return(false, keywordname)
    end
    
    return (true, "") # success
end

"""
    find_and_filter_files_by_category(config; basedir=pwd()) -> Dict{String,Vector{String}}

Find valid files for each category in `config`.

A valid file is a `candidate` one (from function [`find_filepaths_by_category`](@ref) that respects
every filter (see function [`challenge_file`](@ref). Debug prints information about acceptance
of rejection of every candidate file.
"""
function find_and_filter_files_by_category(config::Config ; basedir::AbstractString=pwd()
)::Dict{String,Vector{String}}

    filepaths_by_cat = find_filepaths_by_category(config ; basedir=basedir)
    filters_keywords = gather_filters_keywords(config)
    filepaths_set    = reduce(union, values(filepaths_by_cat) ; init=Set{String}())
    files_infos      = gather_files_infos(filepaths_set, filters_keywords)
    
    for (name,category) in config.categories

        @debug "==================================="
        @debug string("Category ", name)
        @debug "- - - - - - - - - - - - - - - - - -"
        
        isempty(filepaths_by_cat[name]) && begin
            @debug "Zero files to try."
            continue
        end
        
        filter!(filepaths_by_cat[name]) do filepath

            if ismissing(files_infos[filepath][category.exptime])
                @warn string("[x] Missing exptime keyword ", category.exptime,
                                     ", rejected file ", filepath)
                false
            else
                # category filters overwrite global filters
                filters = merge(config.filters, category.filters)
                
                (isvalid, kwdculprit) = challenge_file(filters, files_infos[filepath])
                
                if isvalid ; @debug string("[v] File accepted ", filepath)
                else         @debug string("[x] Filter ", kwdculprit, " rejected file ", filepath)
                end

                isvalid
            end
        end
        @debug string("Category ", name, " kept ", length(filepaths_by_cat[name]), " files.")
        
        isempty(filepaths_by_cat[name]) && @warn string(
            "No files were kept by filters for category ", name, ".")
    end
    
    all(isempty, values(filepaths_by_cat)) && error(string(
        "Zero files kept for the categories. Investigate with debug mode ?"))
    
    return filepaths_by_cat
end

"""
Construct a `CalibrationCategory` from a `ConfigCategory`, by using its `name` and the
setting `sources`.
"""
function CalibrationCategory(name::String, category::ConfigCategory)
    CalibrationCategory(name, category.sources)
end

"""
Construct a `CalibrationData` from a `Config̀`.

Each `ConfigCategory` in `config` will give a
`CalibrationCategory` in `CalibrationData`. The parameter `config` contains the infornation to
find the files to feed to each category. Please note that `config` may contain relative paths, they
will be resolved from the working current dir at the time when this constructor is called. To
modify the directory from which relative paths will be resolved, use parameter `basedir`.
"""
function CalibrationData{T}(config::Config ; basedir::AbstractString=pwd()
) where {T<:AbstractFloat}

    calib_cats = [CalibrationCategory(name,cat) for (name,cat) in config.categories]

    filepaths_by_cats = find_and_filter_files_by_category(config ; basedir=basedir)

    nbfiles = sum(length.(values(filepaths_by_cats)))
    nbfiles > 0 || error("Zero files for calibration.")

    roi = config.roi

    # if width or height is `:` we take the first file and use its size
    if roi[1] isa Colon || roi[2] isa Colon
        for (catname, files) in filepaths_by_cats
            if !isempty(files)
                (width, height) = FitsImageHDU( FitsFile(first(files)), 1 ).data_size[1:2]
                if roi[1] isa Colon ; roi = (1:1:width, roi[2]    ) end
                if roi[2] isa Colon ; roi = (roi[1]   , 1:1:height) end
                break
            end
        end
    end

    detectoraxes = DetectorAxes(roi)

    calibdata = CalibrationData{T}(detectoraxes, calib_cats)
    
    @info string("Reading ", nbfiles, " files for calibration (it can take a long time).")
    for (catname, category) in config.categories
        for filepath in filepaths_by_cats[catname]
            FitsFile(filepath) do file
            
                realdit = file[1][category.exptime].float # from primary hdu
                hdu     = file[category.hdu]
                
                if hdu.data_ndims == 2 || (hdu.data_ndims == 3 && hdu.data_size[3] == 1)
                    matrix = read(Matrix{T}, hdu, (roi..., 1))
                    frame = CalibrationDataFrame(catname, realdit, matrix ; roi=detectoraxes)
                    push!(calibdata, frame)
                    
                elseif hdu.data_ndims == 3 && hdu.data_size[3] >= 2
                    cube = read(Array{T,3}, hdu, (roi..., :))
                    sampler = CalibrationFrameSampler(cube, catname, realdit ; roi=detectoraxes)
                    push!(calibdata, sampler)
                    
                else
                    error(string("File ", filepath, " has incorrect dimensions , ",
                                 hdu.data_size, " , so is excluded from the calibration."))
                end
            end
        end
    end
    
    return calibdata
end

"""
    read_calibration_files_from_yaml(yamlpath::AbstractString, ::Type{T}=Float64; <keyword arguments>) -> CalibrationData{T}

Construct a `CalibrationData` from a YAML config file path.

# Arguments
- `yamlpath::AbstractString`: the path to the YAML config file.
- `::Type{T}=Float64`: the float type to use for calibration.
  Use Float32 if you need speed or space.
- `overwrite_roi::Union{Nothing, NTuple{2,Union{Colon,StepRange{Int,Int}}}}=nothing`: ovewrites the
  roi (Region Of Interest) set in the YAML file. When `nothing`, the roi from the YAML file is
  used. You can give colons (i.e `(:,:)`) to set full view or `StepRanges` to cut (i.e
  `(11:2038,11:1014)`).
- `basedir::AbstractString=pwd()`: Some paths in the YAML may be relative. Thus they will be
  resolved in the current working dir, at the time when calling this function. Set this parameter
  to modify the directory from which relative paths will be resolved.
- `prune::Bool=true`: When `true`, will call the function `prunecalibration` from 
  `ScientificDetectors`, to clean the `CalibrationData` from empty categories.
"""
function read_calibration_files_from_yaml(
    yamlpath ::AbstractString,
    ::Type{T} = Float64
    ;
    overwrite_roi ::Union{Nothing, NTuple{2,Union{Colon,StepRange{Int,Int}}}} = nothing,
    basedir ::AbstractString = pwd(),
    prune   ::Bool = true
) ::CalibrationData{T} where {T<:AbstractFloat}

    config = parse_yaml_file(yamlpath)
    if overwrite_roi !== nothing ; config.roi = overwrite_roi end
    
    data = CalibrationData{T}(config ; basedir=basedir)
    if prune ; data = prunecalibration(data) end
    
    return data
end

end # module