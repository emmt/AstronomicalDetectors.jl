module YAMLCalibrationFiles

using AstroFITS
using AstroFITS: FitsFile, FitsHeader, FitsImageHDU, readfits
using ScientificDetectors
using YAML
using ScientificDetectors:CalibrationFrameSampler
using Dates
import ScientificDetectors.Calibration: prunecalibration
using ProgressMeter
using OnlineSampleStatistics


function gather_filepaths(
    paths ::Vector{String}
    ; level::Int=0,
      maxlevel::Int=0,
      suffixes::Vector{String} = [],
      exclude::Vector{String} = [])

    found_files = Set{String}()

    (maxlevel != -1) && (level > maxlevel) && return found_files

    for path in paths
        if isempty(path)
            continue # empty path is allowed, just to be ignored
        elseif isfile(path)
            isempty(suffixes) || any(s -> endswith(path, s), suffixes)  || continue
            isempty(exclude)  || all(s -> !contains(path, s), exclude)  || continue
            push!(found_files, path)
        elseif isdir(path)
            subpaths = readdir(path; join=true, sort=false)
            sub_found_files = gather_filepaths(subpaths; level=level+1, maxlevel, suffixes, exclude)
            union!(found_files, sub_found_files)
        else
            @error "unhandled path \"$path\""
        end
    end
    
    found_files
end

function gather_filepaths_cat(
    cat_config::AbstractDict{String,Any})

    found_files = Set{String}()

    union!(found_files, gather_filepaths([cat_config["dir"]]
                                         ; suffixes = cat_config["suffixes"],
                                           exclude  = cat_config["exclude files"],
                                           level    = 0,
                                           maxlevel = cat_config["include subdirectory"] ? -1 : 1))
                                           # maxlevel = 1, we have one path which is a dir,
                                           # and we want to read it, even
                                           # when `include subdirectory` is false

    union!(found_files, gather_filepaths(cat_config["files"]
                                         ; suffixes = cat_config["suffixes"],
                                           exclude  = cat_config["exclude files"],
                                           level    = 0,
                                           maxlevel = cat_config["include subdirectory"] ? -1 : 1))
                                           # maxlevel is 1, because `files` can contain dir paths
                                           # too, and we want to include their direct content, even
                                           # when `include subdirectory` is false
    found_files
end

contains_any(arg...) = contains(arg...)
endswith_any(arg...) = endswith(arg...)

"""
    contains_any(chain::Union{AbstractString,Vector{AbstractString}}, patterns::Vector{<:AbstractString})

Return `true` if `chain` contains one of the strings in `patterns`.
"""
function contains_any(chain::Union{AbstractString,Vector{<:AbstractString}},
                      patterns::Vector{<:AbstractString})
    for str in patterns
        if contains_any(chain, str)
            return true
        end
    end
    return false
end

"""
    contains_any(chains::Vector{<:AbstractString}, pattern::AbstractString)

Return `true` if one of the strings in `chains` contains `pattern`.
"""
function contains_any(chains::Vector{<:AbstractString}, pattern::AbstractString)
    for chain in chains
        if contains(chain, pattern)
            return true
        end
    end
    return false
end



"""
    endswith_any(chain::Union{AbstractString,Vector{<:AbstractString}}, patterns::Vector{<:AbstractString})

Return `true` if `chain` ends with one of the strings in `patterns`.
"""
function endswith_any(chain::Union{AbstractString,Vector{<:AbstractString}},
                      patterns::Vector{<:AbstractString})
    for str in patterns
        if endswith(chain, str)
            return true
        end
    end
    return false
end

"""
    endswith_any(chains::Vector{<:AbstractString}, pattern::AbstractString)

Return `true` if one of the strings in `chains` ends with `pattern`.
"""
function endswith_any(chains::Vector{<:AbstractString}, pattern::AbstractString)
    for chain in chains
        if endswith(chain, pattern)
            return true
        end
    end
    return false
end


"""
    filterfilename(filelist,name)

Remove all files from `filelist` that do not match the strings in `name`.
"""
function filterfilename(filelist::AbstractDict{String, FitsHeader},name::String)
    return filterfilename(filelist,[name])
end

function filterfilename(filelist::AbstractDict{String, FitsHeader},name::Vector{String})
    pattern =Regex("("*join(name,")|(")*")")
    return filter(p->match(pattern,p.first) !== nothing,filelist)
end

"""
    filtercat(filelist, keyword, targetvalue) -> filteredlist

Creates a filtered list of `filelist`. Only files with card `keyword` with value `value` are kept.
`targettype` serves as a join type between the target value and the header card.
"""
function filtercat_singleval(filelist    ::AbstractDict{String,FitsHeader},
                             keyword     ::String,
                             targetvalue ::T,
                             targettype  ::Type{J};
                             verbose::Bool=false
) where {J, T<:J}

    return filter(filelist) do (filepath, header)
        card = get(header, keyword, nothing)
         if isnothing(card)
            verbose && @info "$filepath rejected because has no keyword $keyword"
            return false
        end
        valtype(card) <: J || begin
            @warn "card type $(valtype(card)) is != from target value type $T in file $filepath"
            return false
        end
        test = card.value(J) == targetvalue
        verbose && (!test) && @info "$filepath rejected because of keyword $keyword"
        return test
    end
end

"""
    filtercat(filelist, keyword, targetvalues) -> filteredlist

Creates a filtered list of `filelist`. If at least one of the values is found, the file is kept.
`targettype` serves as a join type between the target values and the header card.
"""
function filtercat_severalvals(filelist     ::AbstractDict{String,FitsHeader},
                               keyword      ::String,
                               targetvalues ::Vector{T},
                               targettype   ::Type{J};
                               verbose::Bool=false
) where {J, T<:J}

    return filter(filelist) do (filepath, header)
        card = get(header, keyword, nothing)
        if isnothing(card)
            verbose && @info "$filepath rejected because has no keyword $keyword"
            return false
        end
        valtype(card) <: J || begin
            @warn "card type $(valtype(card)) is != from target value type $T in file $filepath"
            return false
        end
        test = card.value(J) in targetvalues
        verbose && (!test) && @info "$filepath rejected because of keyword $keyword"
        return test
    end
end

"""
YAML library parsing of DateTimes is imperfect but we mimic it to stay consistent
"""
function parseDateTimelikeYAML(datestr::String) ::Union{DateTime,Nothing}
    # trying to parse value into a DateTime
    date = tryparse(DateTime, datestr)

    if date == nothing
        # some FITS use four digits for the milliseconds, contrary to the ISO format.
        # we just remove the fourth digit, the YAML library do the same,
        # so it is consistent with the Date values in the YAML file.
        return tryparse(DateTime, chop(datestr))
    else
        return date
    end
end

"""
    filtercat(filelist, keyword, datemin, datemax) -> filteredlist

Creates a filtered list of `filelist`. Only files with datemin <= file[keyword] < datemax are kept.
"""
function filtercat_daterange(filelist ::AbstractDict{String,FitsHeader},
                             keyword ::String,
                             datemin ::Union{Date,DateTime},
                             datemax ::Union{Date,DateTime};
                             verbose::Bool=false
)

    return filter(filelist) do (filepath, header)

        keyword in keys(header) || return false
        cardval = header[keyword].value(String)

        carddate = parseDateTimelikeYAML(cardval)

        carddate == nothing && begin
            @warn "keyword $keyword=$cardval cannot be parsed as DateTime in file $filepath"
            return false
        end
        test = (datemin <= carddate < datemax)
        verbose && (!test) && @info "$filepath rejected because of keyword $keyword"
        return test
    end
end

# supported types for single target values and eltype in vector target values
# also used as join types, see `targettype` in filtercat_singleval()
const SUPPORTED_VALUE_TYPES = [String, Bool, Integer, AbstractFloat]

"""
Filters the `filelist` to keep only files where keyword is of the target value.
Target value can be of several kinds, see the doc.
"""
function filtercat(filelist::AbstractDict{String,FitsHeader},
                   keyword::String,
                   targetvalue::Any;
                   verbose::Bool=false
)

    # case: single value of Complex type (unsupported)
    targetvalue isa Complex && error("Complex values not yet implemented")

    # case: single value of a supported type
    i = findfirst(T -> targetvalue isa T, SUPPORTED_VALUE_TYPES)
    i != nothing && return filtercat_singleval(filelist, keyword,
                                               targetvalue, SUPPORTED_VALUE_TYPES[i]; verbose)

    # case: Vector of values
    targetvalue isa Vector && begin

        #  case Complex eltype (unsupported)
        eltype(targetvalue) isa Complex && error("Complex values not yet implemented")

        # case: supported eltype
        i = findfirst(T -> eltype(targetvalue) <: T, SUPPORTED_VALUE_TYPES)
        i != nothing && return filtercat_severalvals(filelist, keyword,
                                                     targetvalue, SUPPORTED_VALUE_TYPES[i]; verbose)

        # case: fail
        error("for keyword $keyword, eltype $(eltype(targetvalue)) of the Vector target value is not supported")
    end

    # case: Dictionnary
    targetvalue isa AbstractDict && begin

        # case: date range
        ( length(targetvalue) == 2
          && haskey(targetvalue, "min")
          && haskey(targetvalue, "max")
          && targetvalue["min"] isa Union{Date,DateTime}
          && targetvalue["max"] isa Union{Date,DateTime}
        ) && return filtercat_daterange(filelist, keyword, targetvalue["min"], targetvalue["max"]; verbose)

        # case: fail
        error("wrong Dictionnary targetvalue $targetvalue ; only date ranges are supported")
    end

    error(string("unsupported target value type ", typeof(targetvalue)))
end


"""
    newlist = filtercat(filelist::Dict{String, FitsHeader},cat_config::Dict{String, Any})

Build a `newlist` dictionnary of all files where `fitsheader[keyword] == value` for all keywords contained in `cat_config`
"""
function  filterkeyword(filelist::AbstractDict{String, FitsHeader},
                        cat_config::AbstractDict{String, Any};
                        verbose::Bool=false)
    filteredkeywords = "(dir)|(files)|(suffixes)|(include subdirectory)|(exclude files)|(exptime)|(hdu)|(sources)|(roi)|(selected files)"
    keydict =  filter(p->match(Regex(filteredkeywords), p.first) === nothing,cat_config)
    if length(keydict)>0
        for (keyword,value) in keydict
            filelist =  filtercat(filelist,keyword,value; verbose)
        end
    end
    return filelist
end

function get_global_config(dir::AbstractString, roi)
    calibdict = Dict{String, Any}()
    calibdict["dir"] = dir
    calibdict["files"] = String[]
    calibdict["hdu"] = 1
    calibdict["suffixes"] = [".fits", ".fits.gz", ".fits.Z"]
    calibdict["include subdirectory"] = true
    calibdict["exclude files"] = Vector{String}()
    calibdict["roi"] = roi
    calibdict["exptime"] = "EXPTIME"
    return calibdict
end

function get_category_config(global_config::AbstractDict{String, Any}, yaml_cat::AbstractDict{String,Any})
    cat_config = filter(global_config) do (key,val); key != "categories" end 
    merge!(cat_config, yaml_cat)
    cat_config
end

"""
    read_calibration_files(yaml_file::AbstractString, ::Type{T}=Float32; kwds...) -> CalibrationData

Process calibration files according to the YAML configuration file `yaml_file`.

# Keyword parameters
- `reset_selected_files=true`: by default, we will read files given in `dir`, and associate files to categories. However the input YAML is allowed to have existing "selected files" fields in its categories. `reset_selected_files=true` will reset these fields before searching for files.
- `roi=(:,:)`: take only a region of interest of the input FITS files (e.g. `roi=(1:100,1:2:100)`). It's called "roi" because the input files may already have a ROI (some instruments allow it). There is no method to extract the ROI from the input FITS files yet.
- `dir=pwd()`: directory containing the files.This keyword is overriden by the `dir` in the YAML config file.
- `prune=true`: remove empty categories and sources
- `write_result_yaml=""`: if a non-empty path is given, the result YAML (with the fields "selected files" filled) will be written to this path.

Return an instance of `CalibrationData` with all information statistics needed to calibrate the detector.
"""
function read_calibration_files(yaml_file::AbstractString,
                                ::Type{T}=Float32,
                                ; reset_selected_files::Bool=true,
                                  roi = (:,:),
                                  dir = pwd(),
                                  prune::Bool=true,
                                  write_result_yaml::String="",
                                  verbose::Bool=false) where {T<:AbstractFloat}
    yaml = YAML.load_file(normpath(yaml_file); dicttype=Dict{String,Any})
    read_calibration_files!(yaml, T; reset_selected_files, roi, dir, prune, write_result_yaml, verbose)
end

function read_calibration_files!(yaml::AbstractDict,
                                 ::Type{T}=Float32,
                                 ; reset_selected_files::Bool=true,
                                   roi = (:,:),
                                   dir = pwd(),
                                   prune::Bool=true,
                                   write_result_yaml::String="",
                                   verbose::Bool=false) where {T<:AbstractFloat}
    reset_selected_files!(yaml)
    select_files!(yaml; roi, dir, verbose)
    isempty(write_result_yaml) || YAML.write_file(normpath(write_result_yaml), yaml)
    calib_data = yaml_to_calibration_data(yaml, T; roi, dir, prune)
end

function reset_selected_files!(yaml::AbstractDict)
    for (catname,cat) in yaml["categories"]
        delete!(cat, "selected files")
    end
    yaml
end

function select_files!(yaml_file::AbstractString,
              ; roi = (:,:),
                dir = pwd(),
                files = String[],
                include_subdirectory::Bool=true,
                verbose::Bool=false)
    yaml = YAML.load_file(normpath(yaml_file); dicttype=Dict{String,Any})
    select_files!(yaml; roi, dir, files, include_subdirectory, verbose)
end

function select_files!(yaml::AbstractDict,
                       ; roi = (:,:),
                         dir = pwd(),
                         files = String[],
                         include_subdirectory::Bool=true,
                         verbose::Bool=false)

    global_config = get_global_config(dir, repr(roi))
    global_config["files"] = files
    global_config["include subdirectory"] = include_subdirectory
    merge!(global_config, yaml)

    # we keep encountered FITS headers in a cache, so we have at most one I/O call by file
    headers_cache = Dict{String, FitsHeader}()

    for (catname,yaml_cat) in yaml["categories"]
        cat_config = get_category_config(global_config, yaml_cat)
        verbose && @info "starting category \"$catname\""

        cat_filepaths = gather_filepaths_cat(cat_config)
        
        for path in cat_filepaths
            get!(headers_cache, path) do; readfits(FitsHeader, path) end
        end
    
        cat_files = Dict{String,FitsHeader}(path => headers_cache[path] for path in cat_filepaths)
        
        verbose && isempty(cat_files) && @info "no candidate files found for category \"$catname\""
        
        filtered_cat_files = filterkeyword(cat_files, cat_config; verbose)

        verbose && @info "selected files for category \"$catname\":"
        verbose && for filename in keys(filtered_cat_files)
            @info filename
        end

        selected_files = get!(yaml_cat, "selected files", Dict{Float64,Vector{String}}())
        if !isempty(filtered_cat_files)
            for (path, fitshead) in filtered_cat_files
                Δt = Float64(fitshead[cat_config["exptime"]].value())
                selected_files_Δt = get!(selected_files, Δt, String[])
                push!(selected_files_Δt, path)
            end
        end
    end

    yaml
end

function yaml_to_calibration_data(yaml::AbstractDict,
                                  ::Type{T}=Float32
                                  ; roi = (:,:),
                                    dir = pwd(),
                                    prune::Bool=true) where {T<:AbstractFloat}

    global_config = get_global_config(dir, repr(roi))
    merge!(global_config, yaml)
    
    # first pass where we:
    # - count the number of files
    # - resolve roi (the user is allowed to use Colons)
    # - gather calibration categories
    # we use two pass, because ScientificDetectors does not have the
    # method `push!(::CalibrationData, ::CalibrationCategory)` so we have to
    # create every calibration category before adding data
    nb_files = 0
    resolved_roi = nothing
    calib_cats = CalibrationCategory[]
    for (catname, yaml_cat) in yaml["categories"]
        cat_config = get_category_config(global_config, yaml_cat)
        

        for (Δt, fitspaths) in get(yaml_cat, "selected files", [])
            nb_files += length(fitspaths)
            
            if isnothing(resolved_roi)
                fitspath = first(fitspaths)
                datasize = FitsFile(f -> f[cat_config["hdu"]].data_size, fitspath)
                yaml_roi = eval(Meta.parse(cat_config["roi"]))
                inds = (Base.OneTo(datasize[1])[ yaml_roi[1] ],
                        Base.OneTo(datasize[2])[ yaml_roi[2] ])
                resolved_roi = DetectorAxes(inds)
            end
            
            push!(calib_cats, CalibrationCategory(catname, Meta.parse(cat_config["sources"])))
        end
    end

    iszero(nb_files) && throw(ArgumentError("no calibration file"))

    calib_data = CalibrationData{T}(resolved_roi, calib_cats)
    
    # second pass where we read the data from FITS files
    progress = Progress(nb_files; desc="reading calibration files")
    for (catname, yaml_cat) in yaml["categories"]
        cat_config = get_category_config(global_config, yaml_cat)
        
        for (Δt, fitspaths) in get(yaml_cat, "selected files", [])
            for fitspath in fitspaths
                sampler = read_sampler(fitspath, catname, Δt, resolved_roi, T, cat_config["hdu"])
                push!(calib_data, sampler)
            end
            next!(progress)
        end
    end
    finish!(progress)

    if prune
        calib_data = prunecalibration(calib_data)
    end

    calib_data
end

function read_sampler(fitspath::String,
                      catname::String,
                      Δt::Real,
                      roi::DetectorAxes{N},
                      ::Type{T}=Float32,
                      ext::Union{Integer,String}=1,
) where {N,T}
    all(ax -> ax.bin == 1, roi) || error("only bin=1 is handled")
    FitsFile(fitspath) do fits
        hdu = fits[ext]
        
        (hdu isa FitsImageHDU) || argument_error(
            "in FITS file \"$fitspath", HDU \"$ext\" must be an image")

        Δt = T(Δt) # convert to T, because ScientificDetectors allows only this

        if OnlineSampleStatistics.isa_stat_hdu(hdu)
            stat = read(IndependentStatistic, fits; ext)
            # applying roi if needed
            if axes(roi,1) != Base.OneTo(size(stat,1)) || axes(roi,2) != Base.OneTo(size(stat,2))
                stat = build_from_rawmoments(
                    nobs(stat)[axes(roi)...],
                    (get_rawmoments(stat,1)[axes(roi)...],
                     get_rawmoments(stat,2)[axes(roi)...]))
            end
            sampler = CalibrationDataStat{T,N}(catname, Δt, stat, roi)

        else
            if hdu.data_ndims == N
                frame = read(Array{T,N}, hdu, axes(roi)...)
                sampler = CalibrationDataFrame{T,N}(catname, Δt, frame; roi=roi)

            elseif hdu.data_ndims == N+1

                if hdu.data_size[N+1] == 1
                    frame = read(Array{T,N}, hdu, axes(roi)..., 1)
                    sampler = CalibrationDataFrame{T,N}(catname, Δt, frame; roi=roi)

                else
                    cube = read(Array{T,N+1}, hdu, axes(roi)..., :)
                    sampler = CalibrationFrameSampler(cube, catname, Δt; roi=roi)
                end

            else
                throw(DimensionMismatch(string(
                    "in FITS file \"$fitspath\", HDU \"$ext\" has $(hdu.data_ndims) dimensions, ",
                    "whereas we expect $N or $(N+1) dimensions for roi $roi")))
            end
        end
        
        sampler
    end
end

end
