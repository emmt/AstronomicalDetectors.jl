"""

Package `AstronomicalDetectors` deals with the calibration files of
astronomical detectors like those of the VLT/Sphere instrument.

Example of usage:

    using AstronomicalDetectors, Glob
    list = scan_calibrations(glob("SPHER.2015-12-2*", dir))
    data = read(CalibrationData{Float64}, list; part=(501:580,601:650))
    calib = ReducedCalibration(data)

"""
module AstronomicalDetectors

export
    CalibrationCategory,
    CalibrationData,
    CalibrationInformation,
    ReducedCalibration,
    scan_calibrations

using FITSIO, EasyFITS
using SimpleExpressions
#import SimpleExpressions: compile

using ScientificDetectors
using ScientificDetectors: CalibrationCategory


struct CalibrationInformation
    path::String             # FITS file
    dims::NTuple{3,Int}      # (width,height,nframes)
    Δt::Float64              # exposure time (seconds)
    cat::CalibrationCategory # calibration category
end

"""
    lst = scan_calibrations(args...; scanner=default_scanner, kwds...)

scans calibration data files specified as arguments (file and/or directory
names) and returns a list that can be used by `read(CalibrationData,...)` to
produce an instance of `CalibrationData`.

See [`AstronomicalDetectors.scan_calibration!](@ref) for a
description of available keywords.

Example:

    using AstronomicalDetectors, Glob
    lst = scan_calibrations(glob("SPHER.2015-12-2*", dir))

"""
function scan_calibrations(args::Union{AbstractString,
                                       AbstractVector{<:AbstractString}}...;
                           kdws...)
    # Auxiliary functions for channels that yield filenames.
    function yield_filenames(out::Channel, A::AbstractVector{<:AbstractString})
        for name in A
            yield_filenames(out, name)
        end
    end
    function yield_filenames(out::Channel, name::AbstractString)
        if isfile(name)
            put!(out, name)
        elseif isdir(name)
            for other in readdir(name; join=true, sort=false)
                isfile(other) && put!(out, other)
            end
        end
    end

    # Build a channel that yields all file names.
    chnl = Channel{String}() do out
        for arg in args
            yield_filenames(out, arg)
        end
    end

    # Collect all calibration information.
    list = CalibrationInformation[]
    for filename in chnl
        scan_calibration!(list, filename; kdws...)
    end
    return list
end

"""
    scan_calibration!(dst, filename; scanner=default_scanner, kwds...) -> dst

scans the calibration information if FITS file `filename` and pushes this
information in destination `dst` which is returned.

Keyword `scanner` may be used to specifiy your own method for scanning
calibration information.  The method is called as:

    scanner(filename; kwds...)

and shall return an instance of `CalibrationInformation` for the given file.

All other keywords `kwds...` specified in the call to `scan_calibration!` are
passed to the scanner.  The default scanner accept the following keywords:

- Keyword `exptime` can be set with the name of the FITS card which stores the
  exposure time (in seconds).  By default `exptime="ESO DET SEQ1 REALDIT"`.

- Keyword `category` can be set with the name of the FITS card which stores the
  calibration category.  By default `category = "ESO DPR TYPE"`.

"""
function scan_calibration!(dest::Vector{<:CalibrationInformation},
                           filename::AbstractString;
                           scanner = default_scanner,
                           kwds...)
    isfile(filename) || error("\"", filename, "\" is not a file")
    return push!(dest, scanner(filename; kwds...))
end

# Calibration categories.
#    OBJECT ≈ ESO DPR TYPE  except for science which yields "OBJECT"
#    ESO DPR CATG = SCIENCE or CALIB
#
function default_scanner(filename::AbstractString,
                         hdr::FitsHeader =  read(FitsHeader, filename);
                         exptime::AbstractString = "ESO DET SEQ1 REALDIT",
                         category::AbstractString = "ESO DPR TYPE")

    # Get dimensions.
    naxis = get(Int, hdr, "NAXIS")
    if !(2 ≤ naxis ≤ 3)
        error("other dimensions than 2D and 3D not implemented")
    end
    dims = (get(Int, hdr, "NAXIS1"),
            get(Int, hdr, "NAXIS2"),
            (naxis == 2 ? 1 : get(Int, hdr, "NAXIS3")))

    # Get exposure time.
    Δt = get(Float64, hdr, exptime)

    # Get category of calibration and provide the corresponding linear
    # combination of sources.
    cat = uppercase(strip(get(String, hdr, category)))
    if cat == "DARK"
        expr = :(dark)
    elseif cat == "DARK,BACKGROUND"
        expr = :(dark + background)
    elseif cat == "FLAT,LAMP"
        expr = :(dark + flat)
    elseif cat == "LAMP,WAVE"
        expr = :(dark + wave)
    elseif cat == "OBJECT"
        # Use object's name as source and category.
        cat =  uppercase(strip(get(String, hdr, "OBJECT")))
        object = Symbol(lowercase(cat))
        expr = :(dark + background + sky + $object)
    elseif cat == "SKY"
        expr = :(dark + background + sky)
    else
        error("unknown calibration category: \"", cat, "\" in file \"",
              filename, "\"")
    end
    return CalibrationInformation(filename, dims, Δt,
                                  CalibrationCategory(cat, expr))
end

"""
    read(CalibrationData{T}, lst; part=(:,:))

"""
function Base.read(::Type{CalibrationData},
                   list::AbstractVector{<:CalibrationInformation};
                   kwds...)
    return read(CalibrationData{Float64}, list; kwds...)
end

function Base.read(::Type{CalibrationData{T}},
                   list::AbstractVector{<:CalibrationInformation};
                   part::NTuple{2} = (:,:)) where {T<:AbstractFloat}
    # Get detector size.
    width, height = -1, -1
    first = true
    for item in list
        if first
            width, height = item.dims[1], item.dims[2]
            first = false
        else
            (width, height) == (item.dims[1], item.dims[2]) || error(
                "incompatible sizes")
        end
    end
    inds = (Base.OneTo(width)[part[1]],
            Base.OneTo(height)[part[2]])

    # Build a calibration data frame producer.
    N = 2 # number of dimensions
    roi = DetectorAxes(inds)
    producer = Channel{CalibrationDataFrame{T,N}}() do chn
        for item in list
            hdu = FITS(item.path)[1] :: ImageHDU
            naxis = ndims(hdu)
            width, height, nframes = item.dims
            if naxis == N && nframes == 1
                put!(chn, CalibrationDataFrame{T,N}(item.cat.name, item.Δt,
                                                    read(hdu, inds...);
                                                    roi = roi))
            elseif naxis == N+1
                for j in 1:nframes
                    put!(chn, CalibrationDataFrame{T,N}(item.cat.name, item.Δt,
                                                        read(hdu, inds..., j);
                                                        roi = roi))
                end
            else
                error("other dimensions than ", N, "-D and ",
                      N+1, "-D not implemented")
            end
        end
        close(chn)
    end

    # Load all calibration data.
    dat = CalibrationData{T}(roi, map(x -> x.cat, list))
    for frame in producer
        push!(dat, frame)
    end
    return dat
end

end # module
