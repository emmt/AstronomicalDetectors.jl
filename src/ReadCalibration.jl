module YAMLCalibrationFiles

using AstroFITS: FitsFile, FitsHeader, FitsImageHDU
using ScientificDetectors
using YAML
using ScientificDetectors:CalibrationFrameSampler
using Dates
import ScientificDetectors.Calibration: prunecalibration

"""
    fill_catfiles!(filedict,catdict,dir)

fill dictionary `filedict` with fitsheader of all files in `dir` according to the keywords in `catdict`
The dictionary  `filedict` key is the filepath.

"""
function fill_catfiles!(catfiles::Set{String},
                        catdict::Dict{String, Any},
                        header_cache::Dict{String, FitsHeader},
                        dir::String)
    for filename in readdir(dir; join=true, sort=false)
        if !contains(filename,catdict["exclude files"])
            if isfile(filename)
                if endswith(filename,catdict["suffixes"])
                    push!(catfiles, filename)
                    get!(header_cache, filename) do
                        readfits(FitsHeader, filename)
                    end
                end
            elseif isdir(filename) && catdict["include subdirectory"]
                fill_catfiles!(catfiles, catdict, header_cache, filename)
            end
        end
    end
end

function fill_catfiles!(catfiles::Set{String},
                        catdict::Dict{String, Any},
                        header_cache::Dict{String, FitsHeader},
                        dirs::Vector{String})
    for dir in dirs
        fill_catfiles!(catfiles,catdict,header_cache,dir)
    end
end


"""
    contains(chain::Union{AbstractString,Vector{AbstractString}}, pattern::Vector{AbstractString})

Overloading of Base.contains for vectors of string. Return `true` if a `chain`
contains one of the patterns given in `pattern`
"""
function Base.contains(chain::Union{String,Vector{String}}, pattern::Vector{String})
    for str in pattern
        if contains(chain,str)
            return true
        end
    end
    return false
end

"""
    contains(chain::Vector{String}, pattern::String)

Overloading of Base.contains for vectors of string. Return `true` if one of the `chains`
contains `pattern`
"""
function Base.contains(chains::Vector{String}, pattern::AbstractString)
    for chain in chains
        if contains(chain,pattern)
            return true
        end
    end
    return false
end



"""
    endswith(chain::Union{String,Vector{String}}, pattern::Vector{String})

Overloading of Base.endswith for vectors of string. Return `true` if `chain`
ends with one of the patterns given in `pattern`
"""
function Base.endswith(chain::Union{String,Vector{String}}, pattern::Vector{String})
    for str in pattern
        if endswith(chain,str)
            return true
        end
    end
    return false
end

"""
    endswith(chain::Vector{String}, pattern::String)

Overloading of Base.endswith for vectors of string. Return `true` if `chain`
ends with `pattern`
"""
function Base.endswith(chains::Vector{String},pattern::AbstractString)
    for chain in chains
        if endswith(chain,pattern)
            return true
        end
    end
    return false
end

#= commented because unused
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
=#

"""
    filtercat(filelist, keyword, targetvalue) -> filteredlist

Creates a filtered list of `filelist`. Only files with card `keyword` with value `value` are kept.
`targettype` serves as a join type between the target value and the header card.
"""
function filtercat_singleval(catfiles     ::Set{String},
                             header_cache ::Dict{String,FitsHeader},
                             keyword      ::String,
                             targetvalue  ::T,
                             targettype   ::Type{J}
) ::Set{String} where {J, T<:J}

    return filter(catfiles) do filepath
        header = header_cache[filepath]
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
function filtercat_severalvals(catfiles     ::Set{String},
                               header_cache ::Dict{String,FitsHeader},
                               keyword      ::String,
                               targetvalues ::Vector{T},
                               targettype   ::Type{J}
) ::Set{String} where {J, T<:J}

    return filter(catfiles) do filepath
        header = header_cache[filepath]
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
function filtercat_daterange(cafiles::Set{String},
                             header_cache ::Dict{String,FitsHeader},
                             keyword ::String,
                             datemin ::Union{Date,DateTime},
                             datemax ::Union{Date,DateTime}
) ::Set{String}

    return filter(cafiles) do filepath
        header = header_cache[filepath]

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
Filters the `catfiles` to keep only files where keyword is of the target value.
Target value can be of several kinds, see the doc.
"""
function filtercat(catfiles::Set{String},
                   header_cache::Dict{String,FitsHeader},
                   keyword::String,
                   targetvalue::Any
) ::Set{String}

    # case: single value of Complex type (unsupported)
    targetvalue isa Complex && error("Complex values not yet implemented")

    # case: single value of a supported type
    i = findfirst(T -> targetvalue isa T, SUPPORTED_VALUE_TYPES)
    i != nothing && return filtercat_singleval(catfiles, header_cache, keyword,
                                               targetvalue, SUPPORTED_VALUE_TYPES[i])

    # case: Vector of values
    targetvalue isa Vector && begin

        #  case Complex eltype (unsupported)
        eltype(targetvalue) isa Complex && error("Complex values not yet implemented")

        # case: supported eltype
        i = findfirst(T -> eltype(targetvalue) <: T, SUPPORTED_VALUE_TYPES)
        i != nothing && return filtercat_severalvals(catfiles, header_cache, keyword,
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
        ) && return filtercat_daterange(catfiles, header_cache, keyword, targetvalue["min"], targetvalue["max"])

        # case: fail
        error("wrong Dictionnary targetvalue $targetvalue ; only date ranges are supported")
    end

    error(string("unsupported target value type ", typeof(targetvalue)))
end


"""
    newlist = filterkeyword(catfiles::Set{String},catdict::Dict{String, Any},header_cache::Dict{String, FitsHeader})

Filters `catfiles` so that each file respects `fitsheader[keyword] == value` for all keywords contained in `catdict`
"""
function filterkeyword(catfiles::Set{String},
                       catdict::Dict{String, Any},
                       header_cache::Dict{String, FitsHeader};
                       verb::Bool=false)
    filteredkeywords = "(dir)|(files)|(suffixes)|(include subdirectory)|(exclude files)|(exptime)|(hdu)|(sources)|(roi)"
    keydict =  filter(p->match(Regex(filteredkeywords), p.first) === nothing,catdict)
    if length(keydict)>0
        for (keyword,value) in keydict
            if verb
                initialsize = length(catfiles)
            end
            catfiles = filtercat(catfiles,header_cache,keyword,value)
            if verb
                filteredsize = length(catfiles)
                @info "from $initialsize files, kept $filteredsize, by filter $keyword=$value"
            end
        end
    end
    return catfiles
end

function default_calibdict(dir::AbstractString,roi)
    calibdict = Dict{String, Any}()
    calibdict["dir"] = dir
    calibdict["hdu"] = 1
    calibdict["suffixes"] = [".fits", ".fits.gz", ".fits.Z"]
    calibdict["include subdirectory"] = true
    calibdict["exclude files"] = Vector{String}()
    calibdict["roi"] = roi
    return calibdict
end

function default_category_dict(calibdict::Dict{String, Any})
    filteredkeywords = "(categories)";
    catdict  = Dict{String, Any}()
    merge!(catdict,filter(p->match(Regex(filteredkeywords), p.first) === nothing,calibdict));
    return catdict
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
function ReadCalibrationFiles(yaml_file::AbstractString;
                              roi = (:,:),
                              dir = pwd(),
                              prune::Bool=true,
                              verb::Bool=false)

    calibdict = default_calibdict(dir,repr(roi))
    #merge!(calibdict,vararg)
    merge!(calibdict,YAML.load_file(yaml_file; dicttype=Dict{String,Any}))

    header_cache = Dict{String, FitsHeader}()

    catarr =  [CalibrationCategory(cata,Meta.parse(value["sources"])) for (cata,value) in calibdict["categories"] ]
    local caldat::CalibrationData{Float64}
    local dataroi::DetectorAxes
    local inds::Tuple{OrdinalRange, OrdinalRange}
    isfirst = true
    width, height = -1, -1

    for (cat,value) in calibdict["categories"]
        catdict =default_category_dict(calibdict)
        merge!(catdict, value)
        catfiles = Set{String}()
        fill_catfiles!(catfiles,calibdict,header_cache,catdict["dir"])
        haskey(catdict,"files") && fill_catfiles!(catfiles,calibdict,header_cache,catdict["files"])
        verb && @info "category: $cat"
        catfiles = filterkeyword(catfiles, catdict, header_cache; verb=verb)
        verb && (@info keys(catfiles) ; @info "------------------")
        if !isempty(catfiles)
            for filename in catfiles
                fitshead = header_cache[filename]

                FitsFile(filename) do file

                    hdu = file[catdict["hdu"]]

                    if isfirst
                        width, height = hdu.data_size
                        inds = (Base.OneTo(width)[eval(Meta.parse(catdict["roi"]))[1]],
                        Base.OneTo(height)[eval(Meta.parse(catdict["roi"]))[2]])
                        dataroi = DetectorAxes(inds)
                        caldat = CalibrationData{Float64}(dataroi,catarr)
                        isfirst = false
                    else
                        width  == hdu.data_size[1] || error("incompatible sizes")
                        height == hdu.data_size[2] || error("incompatible sizes")
                    end
                    if hdu.data_ndims == 2
                        data = read(hdu, inds...)
                        sampler =  CalibrationDataFrame(cat,fitshead[catdict["exptime"]].float,data;roi=dataroi)
                    else
                        data = read(hdu, (inds...,Base.OneTo(hdu.data_size[3]))...)

                        if hdu.data_size[3] > 1
                            sampler = CalibrationFrameSampler(data,cat,fitshead[catdict["exptime"]].float;roi=dataroi)
                        else
                            sampler =  CalibrationDataFrame(cat,fitshead[catdict["exptime"]].float,view(data, :,:, 1);roi=dataroi)
                        end
                    end
                    push!(caldat, sampler)
                end
            end
        end
    end
    if prune
        caldat = prunecalibration(caldat)
    end

    return caldat
end

end