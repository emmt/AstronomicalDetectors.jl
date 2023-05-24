module Configs

export Config, ConfigCategory,
       ConfigFilter, ConfigFilterSingle, ConfigFilterMultiple, ConfigFilterRange, FilterValue,
       challenge_filter

using Dates

const FilterValue = Union{String,Bool,Int64,Float64,Date,DateTime}

"""
Supertype for filters.
"""
abstract type ConfigFilter end

"""
the sole point of this abstract type is
to permit mutual reference between `Config` and `ConfigCategory`
"""
abstract type AbsConfigCategory end

"""
Describes a calibration by listing categories, along with the settings and filters to associate 
FITS files.

# Fields
- `filters`: list of the keyword filters. They will be checked on every candidate FITS file.
- `categories`: list of `ConfigCategory`. Each will give a `CalibrationCategory`.
- `title`: name of this config. Only informative for the end user.
- `roi`: Region Of Interest on the detector. For full view use colons: `(:,:)`.
- `exptime`: Name of the keyword containing the exposure time (mandatory information for the
  calibration)
- `dir`: Path of the folder where FITS files must be looked for. Can be absolute or relative.
- `hdu`: identifier of the HeaderDataUnit to use in the FITS files. Can be an `Integer` and is thus
  an index of the HDU, or can be a `String` and is therefore an `HDUNAME`. Default is `1`.
- `files`: If non empty, it contains the strict list of paths of FITS files to use. Settings `dir`,
  `suffixes`, `exclude_files`, `include_subdirectories` do not matter anymore. However, `filters`
  are still checked on the files. Paths can be relative or absolute. If an empty list is given,
  this parameter do nothing and the other keywords (`dir`, etc) are used. Default is empty list.
- `suffixes`: Only FITS filenames that ends by at least one of the given suffixes are kept.
  Default is `[".fits", ".fits.gz", ".fits.Z"]`.
- `exclude_files`: Every FITS filename that contains at least one of the given `String` is unkept.
  Default is an empty list.
- `include_subdirectories`: If `true`, the subdirectories of `dir` are also recursively looked for
  FITS files. Default is `true`.
- `follow_symbolic_links`: If `true`, symbolic links are followed. Default is `false`.
"""
mutable struct Config
    filters    ::Dict{String,ConfigFilter}
    categories ::Dict{String,<:AbsConfigCategory} # will always be ConfigCategory
    title      ::String
    roi        ::NTuple{2,Union{Colon,StepRange{Int,Int}}}
    exptime    ::String
    dir        ::String
    hdu           ::Union{Int,String}
    files         ::Vector{String}
    suffixes      ::Vector{String}
    exclude_files ::Vector{String}
    include_subdirectories ::Bool
    follow_symbolic_links  ::Bool
end

"""
Describes a category by a name, settings and keyword filters.

A `ConfigCategory` belongs to a parent `Config` structure. The settings of a category are either
defined or `nothing`. When a setting is `nothing`, the setting of the parent `Config` must be used.
The field `sources` is an expression of the current sources in the files of this category, for
example a category "FLAT" can have sources `flat + background + dark`. The setting `filters` lists
the keyword filters for this category, but the filters of the parent `Config` will be checked too.
If a `ConfigCategory` has a filter for a keyword and the parent config already has a filter for this
keyword, the one of the `ConfigCategory` is used.
"""
mutable struct ConfigCategory <: AbsConfigCategory
    parent_config ::Config
    sources ::Union{Symbol,Expr}
    filters ::Dict{String,ConfigFilter}
    exptime ::Union{Nothing,String}
    dir     ::Union{Nothing,String}
    hdu     ::Union{Nothing,Int,String}
    files         ::Union{Nothing,Vector{String}}
    suffixes      ::Union{Nothing,Vector{String}}
    exclude_files ::Union{Nothing,Vector{String}}
    include_subdirectories ::Union{Nothing,Bool}
    follow_symbolic_links  ::Union{Nothing,Bool}
end

"""
Get a field of `ConfigCategory`, but when it is equal to nothing, use the field of parent `Config`.
"""
function Base.getproperty(category::ConfigCategory, s::Symbol)
    f = getfield(category, s)
    if f === nothing
        if s in fieldnames(Config)
            return getproperty(category.parent_config, s)
        else
            return nothing
        end
    else
        return f
    end
end

"""Default `Config` definition"""
Config() = Config(
        Dict(),   # filters
        Dict{String,ConfigCategory}(), # categories
        "",    # title
        (:,:), # roi,
        "",  # exptime
        ".", # dir
        1,   # hdu
        [],  # files
        [".fits", ".fits.gz", ".fits.Z"], # suffixes,
        [],  # exclude_files
        true, # include_subdirectories
        false) # follow_symbolic_links 

"""Default `ConfigCategory` definition."""
ConfigCategory(parent_config::Config, sources::Union{Symbol,Expr}) = ConfigCategory(
    parent_config, sources, Dict(), fill(nothing, 8)...)

"""
Filter that accepts only values equal to a single one.
"""
struct ConfigFilterSingle{T<:FilterValue} <: ConfigFilter
    acceptedvalue ::T
end

"""
Filter that accepts a value among a given list.
"""
struct ConfigFilterMultiple{T<:FilterValue} <: ConfigFilter
    acceptedvalues ::Vector{T}
end

"""
Filter that accepts a `Date` or `DateTime` between a given `DateTime` range, with minimum bound
inclusive and maximum bound exclusive.
"""
struct ConfigFilterRange <: ConfigFilter
    rangemin ::DateTime  # only date ranges accepted for now
    rangemax ::DateTime
end

"""
    `challenge_filter(configfilter, challenger) -> Bool

Return `true` if the `challenger` value is valid with respect to the given filter.
"""
function challenge_filter(filter::ConfigFilterSingle{T}, challenger::T) ::Bool where {T}
    challenger == filter.acceptedvalue
end
function challenge_filter(filter::ConfigFilterMultiple{T}, challenger::T) ::Bool where {T}
    challenger in filter.acceptedvalues
end
function challenge_filter(filter::ConfigFilterRange, challenger::Union{Date,DateTime}) ::Bool
    filter.rangemin ≤ challenger < filter.rangemax
end

function Base.eltype(::Type{ConfigFilterSingle{T}})   where {T} return T end
function Base.eltype(::Type{ConfigFilterMultiple{T}}) where {T} return T end
function Base.eltype(::Type{ConfigFilterRange})                 return DateTime end

end # module Configs
