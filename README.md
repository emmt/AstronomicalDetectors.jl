# AstronomicalDetectors [![Build Status](https://travis-ci.com/emmt/AstronomicalDetectors.jl.svg?branch=main)](https://travis-ci.com/emmt/AstronomicalDetectors.jl) [![Build Status](https://ci.appveyor.com/api/projects/status/github/emmt/AstronomicalDetectors.jl?svg=true)](https://ci.appveyor.com/project/emmt/AstronomicalDetectors-jl) [![Coverage](https://codecov.io/gh/emmt/AstronomicalDetectors.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/emmt/AstronomicalDetectors.jl)


`AstronomicalDetectors` is a Julia package to deal with the calibration files
of astronomical detectors like those of the VLT/Sphere instrument.

Example of usage:

```julia
using AstronomicalDetectors, Glob
list = scan_calibrations(glob("SPHER.2015-12-2*", dir))
data = read(CalibrationData{Float64}, list; part=(501:580,601:650))
calib = ReducedCalibration(data)
```
