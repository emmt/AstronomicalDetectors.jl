module YAMLParsing

export parse_yaml_file

using YAML
using Dates
using BaseFITS
using ..Configs

"""
    parse_setting_key(rawkey::String) -> Symbol

Change "YAML key style" with spaces, to "Julia Symbol style" with underscores. Modify some keys to
assure retro-compatibility with old YAML files.

This function do *not* check the validity of the key, this is done in functions
[`parse_global_setting_value`](@ref) and [`parse_category_setting_value`](@ref).
"""
function parse_setting_key(rawkey::String) ::Symbol
    if rawkey == "include subdirectory"
        rawkey = "include subdirectories" # retro compat
    end
    return Symbol(replace(rawkey, ' ' => '_'))
end

"""
    parse_global_setting_value(key::Symbol, rawvalue::Any) -> Any

Check the validity of the `key`, parse the `rawvalue`, check its type.
"""
function parse_global_setting_value(key::Symbol, rawvalue::Any) ::Any
    key in fieldnames(Config) || error("Unknown global setting key: $key.")
    key in (:filters, :categories) && error("Forbidden global setting key: $key.")
    value = parse_setting_value(key, rawvalue)
    typeof(value) <: fieldtype(Config, key) || error(string(
        "Value for global setting key \"$key\" has wrong type $(typeof(rawvalue)). ",
        "It should have type $(fieldtype(Config, key))"))
    return value
end

"""
    parse_category_setting_value(key::Symbol, rawvalue::Any) -> Any

Check the validity of the `key`, parse the `rawvalue`, check its type.
"""
function parse_category_setting_value(key::Symbol, rawvalue::Any) ::Any
    key in fieldnames(ConfigCategory) || error("Unknown category setting key: $key.")
    key in (:parent_config, :filters) && error("Forbidden category setting key: $key.")
    value = parse_setting_value(key, rawvalue)
    typeof(value) <: fieldtype(ConfigCategory, key) || error(string(
        "Value for category setting key \"$key\" has wrong type $(typeof(rawvalue)). ",
        "It should have type $(fieldtype(ConfigCategory, key))"))
    return value
end

"""
    parse_setting_value(key::Symbol, rawvalue::Any) -> Any

Modify the `rawvalue`, depending on the `key`.

Check the type for `:roi`, but for other keys the type is *not* checked, this is done in functions
[`parse_global_setting_value`](@ref) and [`parse_category_setting_value`](@ref).
- for `:files`, `:exclude_files`, and `:suffixes`: put `rawvalue` in a `Vector` if not
  already the case.
- for `:dir`, and `:files`: call `normpath` on all their path to ensure the separator is
  compatible with the current Operating System.
- for `:roi` and `:sources`: call parsing functions [`parse_setting_value_roi`](@ref) and
  [`parse_setting_value_sources`](@ref).
For `AbstractFloat` and `Integer` values, put them in "big boxes" `Float64` and `Int64`
like BaseFITS do.
"""
function parse_setting_value(key::Symbol, rawvalue::Any) ::Any
    # put in singleton vector if necessary
    if key in (:files, :exclude_files, :suffixes) && !(rawvalue isa Vector)
        rawvalue = [rawvalue]
    end

    # convert numbers to the same types used in BaseFITS.
    if rawvalue isa AbstractFloat          ; rawvalue = Float64(rawvalue) end
    if rawvalue isa Union{Signed,Unsigned} ; rawvalue = Int64(rawvalue)   end
                    # we don't want to convert Bool

    if     key == :dir     ; rawvalue = normpath.(rawvalue)
    elseif key == :files   ; rawvalue = normpath.(rawvalue)
    elseif key == :roi     ; rawvalue = parse_setting_value_roi(rawvalue)
    elseif key == :sources ; rawvalue = parse_setting_value_sources(rawvalue)
    end
    return rawvalue
end

"""
    parse_setting_value_sources(rawvalue::String) -> Union{Symbol,Expr}

Parse `String` `:sources` value to a `Symbol` or an `Expr`.
"""
function parse_setting_value_sources(rawvalue::String) ::Union{Symbol,Expr}
    sources = Meta.parse(rawvalue)
end

"""
    parse_setting_value_roi(rawvalue::String) -> NTuple{2,Union{Colon,StepRange{Int,Int}}}

Parse `String` `:roi` value to a couple of `Colon` or `StepRange`.

A `Colon` means the full axe is used for Region Of Interest.

# Examples
```jldoctest
julia> AstronomicalDetectors.YAMLParsing.parse_setting_value_roi(":,11:1014")
(Colon(), 11:1:1014)
```
```jldoctest
julia> typeof(AstronomicalDetectors.YAMLParsing.parse_setting_value_roi(":,11:1014"))
Tuple{Colon, StepRange{Int64, Int64}}
```
"""
function parse_setting_value_roi(rawvalue::String) ::NTuple{2,Union{Colon,StepRange{Int,Int}}}
    roi = eval(Meta.parse(rawvalue))
    roi isa Tuple    || error("Invalid type for setting roi: $(typeof(roi)).")
    length(roi) == 2 || error("Invalid number of ranges for setting roi: $(length(roi)).")
    return map(roi) do range
        if     range isa Colon         ; range
        elseif range isa AbstractRange ; StepRange{Int,Int}(range)
        else error("Invalid type for setting roi: $(typeof(roi)).") end
    end
end

"""
    parse_filter(key::String, rawvalue::Any) -> ConfigFilter

Parse the `rawvalue` to a `ConfigFilter`.

the subtype of `ConfigFilter` depends on the type of `rawvalue`. `key` is only used in
warnings messages.
"""
function parse_filter(key::String, rawvalue::Any) ::ConfigFilter
    if     rawvalue isa Dict   ; parse_filter_range(key, rawvalue)
    elseif rawvalue isa Vector ; parse_filter_multiple(key, rawvalue)
    else                         parse_filter_single(key, rawvalue)    end
end

"""
    parse_filter_single(key::String, rawvalue::Any) -> ConfigFilterSingle

Parse the `rawvalue` to a `ConfigFilterSingle`, provided the type of `rawvalue` belongs to
[`FilterValue`](@ref).
"""
function parse_filter_single(key::String, rawvalue::Any) ::ConfigFilterSingle
    if rawvalue isa FilterValue ; return ConfigFilterSingle(rawvalue)
    else error("For ConfigFilterSingle $key, wrong type $(typeof(rawvalue)).") end
end

"""
    parse_filter_multiple(key::String, rawvalue::Any) -> ConfigFilterMultiple

Parse the `rawvalue` to a `ConfigFilterMultiple`, provided the `eltype` of `rawvalue` belongs to
[`FilterValue`](@ref).

`key` is only used in warnings messages.
"""
function parse_filter_multiple(key::String, rawvalue::Vector) ::ConfigFilterMultiple
    if eltype(rawvalue) <: FilterValue ; return ConfigFilterMultiple(rawvalue)
    else error("For ConfigFilterMultiple $key, wrong type Vector{$(eltype(rawvalue))}.") end
end

"""
    parse_filter_range(key::String, rawvalue::Dict) -> ConfigFilterRange

Parse the `rawvalue` to a `ConfigFilterMultiple`, provided `rawvalue` contains the corrects keys
`min` and `max`.

`key` is only used in warnings messages.
"""
function parse_filter_range(key::String, rawvalue::Dict) ::ConfigFilterRange
    if (length(rawvalue) == 2
        && haskey(rawvalue, "min")
        && haskey(rawvalue, "max")
        && rawvalue["min"] isa Union{Date,DateTime}
        && rawvalue["max"] isa Union{Date,DateTime})
       return ConfigFilterRange(rawvalue["min"], rawvalue["max"])
    else
        error(string("For ConfigFilterRange $key, wrong Dictionnary value $rawvalue. ",
                     "Only date ranges with keys \"min\" and \"max\" are accepted."))
    end
end

"""
    isa_filter_key(rawkey::String) -> Bool

Return `true` if `rawkey` is considered a valid FITS keyword.
"""
function isa_filter_key(rawkey::String) ::Bool
    ! (BaseFITS.Parser.try_parse_keyword(rawkey) isa Char)
end

"""
    parse_category(parent_config::Config, name, rawvalue) -> ConfigCategory

Parse `rawvalue` as a `ConfigCategory`. Parse its settings and filters.
"""
function parse_category(parent_config::Config, name::String, rawvalue::Any) ::ConfigCategory

    rawvalue isa Dict{String,Any} || error("Category $name has wrong type: $(typeof(rawvalue)).")

    haskey(rawvalue, "sources") || error("Category $name misses the key \"sources\".")
    sources = parse_setting_value_sources(rawvalue["sources"])

    category = ConfigCategory(parent_config, sources)

    for (rawkey, rawvalue) in rawvalue
        rawkey == "sources" && continue # already parsed

        if isa_filter_key(rawkey)
            category.filters[rawkey] = parse_filter(rawkey, rawvalue)
        else
            key = parse_setting_key(rawkey)
            setproperty!(category, key, parse_category_setting_value(key, rawvalue))
        end
    end
    return category
end

"""
    parse_config(yaml::Dict{String,Any}) -> Config

Parse a `Dict` coming from a YAML file to a `Config`. Parse its settings, filters, and categories.

The YAML must have been loaded with the option `dicttype=Dict{String,Any}` so that the key of
the dict has type `String`.
"""
function parse_config(yaml::Dict{String,Any}) ::Config

    haskey(yaml, "categories") || error("Mandatory \"categories\" section not found.")
    rawcategories = yaml["categories"]

    rawcategories isa Dict{String,Any} || error(
        "Section \"categories\" has wrong type: $(typeof(rawcategories)).")

    isempty(rawcategories) && error("Section \"categories\" must not be empty.")

    config = Config()

    # categories
    for (name, rawvalue) in rawcategories
        haskey(config.categories, name) && error("Two definitions for category $name.")
        config.categories[name] = parse_category(config, name, rawvalue)
    end

    # settings and filters
    for (rawkey,rawvalue) in yaml
        rawkey == "categories" && continue # already parsed

        if isa_filter_key(rawkey)
            config.filters[rawkey] = parse_filter(rawkey, rawvalue)
        else
            key = parse_setting_key(rawkey)
            setproperty!(config, key, parse_global_setting_value(key, rawvalue))
        end
    end

    # check that exptime is defined for every category
    if isempty(config.exptime)
        for (name,category) in categories
            cat.exptime === nothing && error(
                "Category $name has setting \"exptime\" undefined while global ",
                "setting \"exptime\" is empty. You must define at least one.")
        end
    end

    return config
end

"""
    parse_yaml_file(filepath) -> Config

Parse YAML file as a `Config`.
"""
function parse_yaml_file(filepath::AbstractString) ::Config
    # we set the `dicttype` parameter: mandatory for `parse_config` to work
    yaml = YAML.load_file(filepath ; dicttype=Dict{String,Any})
    return parse_config(yaml)
end

end # module YAMLParsing