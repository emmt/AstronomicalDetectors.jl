module YAMLCalibrationFiles

using AstroFITS: FitsFile, FitsHeader, FitsImageHDU
using ScientificDetectors
using YAML
using ScientificDetectors:CalibrationFrameSampler
using Dates
import ScientificDetectors.Calibration: prunecalibration
using ProgressMeter


function find_files(
    paths ::Vector{String}
    ; level::Int=0,
      maxlevel::Int=0,
      suffixes::Vector{String} = [],
      exclude::Vector{String} = [])

    found_files = Set{String}()

    (maxlevel != -1) && (level > maxlevel) && return found_files

    for path in paths
        if isfile(path)
            isempty(suffixes) || any(s -> endswith(path, s), suffixes)  || continue
            isempty(exclude)  || all(s -> !contains(path, s), exclude)  || continue
            push!(found_files, path)
        elseif isdir(path)
            subpaths = readdir(path; join=true, sort=false)
            sub_found_files = find_files(subpaths; level=level+1, maxlevel, suffixes, exclude)
            union!(found_files, sub_found_files)
        else
            @error "unhandled path \"$path\""
        end
    end
    
    return found_files
end

function find_config_files!(
    filecache::Dict{String,FitsHeader},
    config::Dict{String,Any})

    suffixes = config["suffixes"]
    exclude  = config["exclude files"]

    found_files = find_files([config["dir"]]; suffixes, exclude,
        maxlevel = config["include subdirectory"] ? -1 : 0)

    if haskey(config, "files")
        merge!(found_files, find_files(config["files"]; suffixes, exclude,
            maxlevel = config["include subdirectory"] ? -1 : 1))
            # maxlevel can be 1, because `files` can contain dir paths too, and we want to
            # include their direct content, even when `include subdirectory` is false
    end
    
    for file in found_files
        get!(filecache, file) do
            readfits(FitsHeader, file)
        end
    end
    
    return Dict{String,FitsHeader}(path => filecache[path] for path in found_files)
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
function filterfilename(filelist::Dict{String, FitsHeader},name::String)
    return filterfilename(filelist,[name])
end

function filterfilename(filelist::Dict{String, FitsHeader},name::Vector{String})
    pattern =Regex("("*join(name,")|(")*")")
    return filter(p->match(pattern,p.first) !== nothing,filelist)
end

"""
    filtercat(filelist, keyword, targetvalue) -> filteredlist

Creates a filtered list of `filelist`. Only files with card `keyword` with value `value` are kept.
`targettype` serves as a join type between the target value and the header card.
"""
function filtercat_singleval(filelist    ::Dict{String,FitsHeader},
                             keyword     ::String,
                             targetvalue ::T,
                             targettype  ::Type{J}
) ::Dict{String,FitsHeader} where {J, T<:J}

    return filter(filelist) do (filepath, header)
        card = get(header, keyword, nothing)
        card == nothing && return false
        valtype(card) <: J || begin
            @warn "card type $(valtype(card)) is != from target value type $T in file $filepath"
            return false
        end
        return card.value(J) == targetvalue
    end
end

"""
    filtercat(filelist, keyword, targetvalues) -> filteredlist

Creates a filtered list of `filelist`. If at least one of the values is found, the file is kept.
`targettype` serves as a join type between the target values and the header card.
"""
function filtercat_severalvals(filelist     ::Dict{String,FitsHeader},
                               keyword      ::String,
                               targetvalues ::Vector{T},
                               targettype   ::Type{J}
) ::Dict{String,FitsHeader} where {J, T<:J}

    return filter(filelist) do (filepath, header)
        card = get(header, keyword, nothing)
        card == nothing && return false
        valtype(card) <: J || begin
            @warn "card type $(valtype(card)) is != from target value type $T in file $filepath"
            return false
        end
        return card.value(J) in targetvalues
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
function filtercat_daterange(filelist ::Dict{String,FitsHeader},
                             keyword ::String,
                             datemin ::Union{Date,DateTime},
                             datemax ::Union{Date,DateTime}
) ::Dict{String,FitsHeader}

    return filter(filelist) do (filepath, header)

        keyword in keys(header) || return false
        cardval = header[keyword].value(String)

        carddate = parseDateTimelikeYAML(cardval)

        carddate == nothing && begin
            @warn "keyword $keyword=$cardval cannot be parsed as DateTime in file $filepath"
            return false
        end
        return (datemin <= carddate < datemax)
    end
end

# supported types for single target values and eltype in vector target values
# also used as join types, see `targettype` in filtercat_singleval()
const SUPPORTED_VALUE_TYPES = [String, Bool, Integer, AbstractFloat]

"""
Filters the `filelist` to keep only files where keyword is of the target value.
Target value can be of several kinds, see the doc.
"""
function filtercat(filelist::Dict{String,FitsHeader},
                   keyword::String,
                   targetvalue::Any
) ::Dict{String,FitsHeader}

    # case: single value of Complex type (unsupported)
    targetvalue isa Complex && error("Complex values not yet implemented")

    # case: single value of a supported type
    i = findfirst(T -> targetvalue isa T, SUPPORTED_VALUE_TYPES)
    i != nothing && return filtercat_singleval(filelist, keyword,
                                               targetvalue, SUPPORTED_VALUE_TYPES[i])

    # case: Vector of values
    targetvalue isa Vector && begin

        #  case Complex eltype (unsupported)
        eltype(targetvalue) isa Complex && error("Complex values not yet implemented")

        # case: supported eltype
        i = findfirst(T -> eltype(targetvalue) <: T, SUPPORTED_VALUE_TYPES)
        i != nothing && return filtercat_severalvals(filelist, keyword,
                                                     targetvalue, SUPPORTED_VALUE_TYPES[i])

        # case: fail
        error("eltype $(eltype(targetvalue)) of the Vector target value is not supported")
    end

    # case: Dictionnary
    targetvalue isa Dict && begin

        # case: date range
        ( length(targetvalue) == 2
          && haskey(targetvalue, "min")
          && haskey(targetvalue, "max")
          && targetvalue["min"] isa Union{Date,DateTime}
          && targetvalue["max"] isa Union{Date,DateTime}
        ) && return filtercat_daterange(filelist, keyword, targetvalue["min"], targetvalue["max"])

        # case: fail
        error("wrong Dictionnary targetvalue $targetvalue ; only date ranges are supported")
    end

    error(string("unsupported target value type ", typeof(targetvalue)))
end


"""
    newlist = filtercat(filelist::Dict{String, FitsHeader},cat_config::Dict{String, Any})

Build a `newlist` dictionnary of all files where `fitsheader[keyword] == value` for all keywords contained in `cat_config`
"""
function  filterkeyword(filelist::Dict{String, FitsHeader},
                        cat_config::Dict{String, Any};
                        verb::Bool=false)
    filteredkeywords = "(dir)|(files)|(suffixes)|(include subdirectory)|(exclude files)|(exptime)|(hdu)|(sources)|(roi)"
    keydict =  filter(p->match(Regex(filteredkeywords), p.first) === nothing,cat_config)
    if length(keydict)>0
        for (keyword,value) in keydict
            if verb
                initialsize = length(filelist)
            end
            filelist =  filtercat(filelist,keyword,value)
            if verb
                filteredsize = length(filelist)
                @info "from $initialsize files, kept $filteredsize, by filter $keyword=$value"
            end
        end
    end
    return filelist
end

function get_global_config(dir::AbstractString,roi)
    calibdict = Dict{String, Any}()
    calibdict["dir"] = dir
    calibdict["hdu"] = 1
    calibdict["suffixes"] = [".fits", ".fits.gz", ".fits.Z"]
    calibdict["include subdirectory"] = true
    calibdict["exclude files"] = Vector{String}()
    calibdict["roi"] = roi
    calibdict["exptime"] = "EXPTIME"
    return calibdict
end

function get_category_config(global_config::Dict{String, Any})
    filteredkeywords = "(categories)";
    category_config  = Dict{String, Any}()
    merge!(category_config,filter(p->match(Regex(filteredkeywords), p.first) === nothing,global_config));
    return category_config
end

"""
    ReadCalibrationFiles(yaml_file::AbstractString; roi::NTuple{2} = (:,:),  dir=pwd())

Process calibration files according to the YAML configuration file `yaml_file`.

- `roi` keyword can be used to consider only a region of interest of the detector (e.g. `roi=(1:100,1:2:100)`) default `roi=(:,:)`

- `dir` is the directory containing the files. By default `dir=pwd()`. This keyword is overriden by the `dir` in the YAML config file

- `prune`  by default `prune=true` remove empty categories and sources

- `verb`  by default `verb=false` print information about filtering of files in categories

Return an instance of `CalibrationData` with all information statistics needed to calibrate the detector.
"""
function ReadCalibrationFiles(yaml_file::AbstractString,
                              ::Type{T}=Float32;
                              roi = (:,:),
                              dir = pwd(),
                              verb::Bool=false,
                              prune::Bool=true
) where {T}

    high_yaml = YAML.load_file(yaml_file; dicttype=Dict{String,Any})
    
    low_yaml = select_files(high_yaml, roi, dir, verb)
    
    calib_data = CalibrationDataFromYAML(low_yaml, roi, dir, T; prune)

    return calib_data
end

function select_files(high_yaml::AbstractDict,
                      roi = (:,:),
                      dir = pwd(),
                      verb::Bool=false)
    low_yaml = deepcopy(high_yaml)

    global_config = get_global_config(dir, repr(roi))
    merge!(global_config, high_yaml)

    filecache = Dict{String, FitsHeader}()

    for (catname,cat) in low_yaml["categories"]
        cat_config = get_category_config(global_config)
        merge!(cat_config, cat)

        cat_files = find_config_files!(filecache, cat_config)
        verb && @info "category: $catname"
        filtered_cat_files = filterkeyword(cat_files, cat_config; verb=verb)
        verb && (@info keys(filtered_cat_files) ; @info "------------------")
        if !isempty(filtered_cat_files)
            for (filename,fitshead) in filtered_cat_files
                selected_files = get!(cat, "selected files", Dict{Float64,Vector{String}}())
                Δt = Float64(fitshead[cat_config["exptime"]].value())
                selected_files_Δt = get!(selected_files, Δt, String[])
                push!(selected_files_Δt, filename)
            end
        end
    end

    return low_yaml
end

function CalibrationDataFromYAML(yaml::AbstractDict,
                                 roi = (:,:),
                                 dir = pwd(),
                                 ::Type{T}=Float32
                                 ; prune::Bool=true) where {T<:AbstractFloat}

    global_config = get_global_config(dir, repr(roi))
    merge!(global_config, yaml)
    
    # first pass where we:
    # - count the number of files
    # - resolve roi (the user is allowed to use Colons)
    # - gather calibration categories
    # we use two pass, because ScientificDetectors cannot handle pushing new CalibrationCategory
    nb_files = 0
    user_roi = eval(Meta.parse(global_config["roi"]))
    resolved_roi = nothing
    calib_cats = CalibrationCategory[]
    for (catname, yaml_cat) in yaml["categories"]
        cat_config = get_category_config(global_config)
        merge!(cat_config, yaml_cat)
        
        for (Δt, fitspaths) in get(yaml_cat, "selected files", [])
            nb_files += length(fitspaths)
            
            if isnothing(resolved_roi)
                fitspath = first(fitspaths)
                size = FitsFile(f -> f[cat_config["hdu"]].data_size, fitspath)
                inds = ntuple(length(user_roi)) do k
                    Base.OneTo(size[k])[ user_roi[k] ]
                end
                resolved_roi = DetectorAxes(inds)
            end
            
            push!(calib_cats, CalibrationCategory(catname, Meta.parse(cat_config["sources"])))
        end
    end

    isempty(nb_files) && argument_error("`yaml` must give at least one calibration file")

    calib_data = CalibrationData{T}(resolved_roi, calib_cats)
    
    # second pass where we read the data from FITS files
    progress = Progress(nb_files; desc="reading calibration files")
    for (catname, yaml_cat) in yaml["categories"]
        cat_config = get_category_config(global_config)
        merge!(cat_config, yaml_cat)
        
        for (Δt, fitspaths) in get(yaml_cat, "selected files", [])
            for fitspath in fitspaths
                sampler = get_sampler(fitspath, catname, Δt, resolved_roi, T, cat_config["hdu"])
                push!(calib_data, sampler)
            end
            next!(progress)
        end
    end
    finish!(progress)

    if prune
        calib_data = prunecalibration(calib_data)
    end

    return calib_data
end

function get_sampler(fitspath::String,
                     catname::String,
                     Δt::Real,
                     roi::DetectorAxes{N},
                     ::Type{T}=Float32,
                     hdu::Union{Integer,String}=1,
) where {N,T}
    all(ax -> ax.bin == 1, roi) || error("only bin=1 is handled for now")
    FitsFile(fitspath) do fits
        hdu = fits[hdu]
        
        (hdu isa FitsImageHDU) || argument_error(
            "in FITS file \"$fitspath", HDU \"$hdu\" must be an image")

        Δt = T(Δt) # convert to T, because ScientificDetectors allows only this

        if hdu.data_ndims == N
            frame = read(Array{T,N}, hdu, axes(roi)...)
            sampler = CalibrationDataFrame{T,N}(catname, Δt, frame; roi)

        elseif hdu.data_ndims == N+1

            if hdu.data_size[N+1] == 1
                frame = read(Array{T,N}, hdu, axes(roi)..., 1)
                sampler = CalibrationDataFrame{T,N}(catname, Δt, frame; roi)

            else
                cube = read(Array{T,N+1}, hdu, axes(roi)..., :)
                sampler = CalibrationFrameSampler(cube, catname, Δt; roi)
            end

        else
            dimension_mismatch(string(
                "in FITS file \"$fitspath\", HDU \"$hdu\" has $(hdu.data_ndims) dimensions, ",
                "whereas we expect $N or $(N+1) dimensions for roi $roi"))
        end
        
        sampler
    end
end

end
