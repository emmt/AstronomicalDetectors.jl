"""

Package `AstronomicalDetectors` deals with the calibration files of
astronomical detectors like those of the VLT/Sphere instrument.

Example of usage:

    using AstronomicalDetectors
    calib_data = read_calibration_files("myconfig.yaml"; dir="mycalibfiles/")

"""
module AstronomicalDetectors

export
    CalibrationData,
    read_calibration_files,
    select_files!,
    yaml_to_calibration_data

using AstroFITS
using ScientificDetectors
using OnlineSampleStatistics
using YAML
using Dates
using ProgressMeter

include("functions.jl")

end # module
