# AstronomicalDetectors [![Build Status](https://travis-ci.com/emmt/AstronomicalDetectors.jl.svg?branch=main)](https://travis-ci.com/emmt/AstronomicalDetectors.jl) [![Build Status](https://ci.appveyor.com/api/projects/status/github/emmt/AstronomicalDetectors.jl?svg=true)](https://ci.appveyor.com/project/emmt/AstronomicalDetectors-jl) [![Coverage](https://codecov.io/gh/emmt/AstronomicalDetectors.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/emmt/AstronomicalDetectors.jl)

`AstronomicalDetectors` is a Julia package to deal with the calibration files
of astronomical detectors like those of the VLT/Sphere instrument.

Example of usage:

```julia
using AstronomicalDetectors, Glob
list = scan_calibrations(glob("SPHER.2015-12-2*", dir))
data = read(CalibrationData{Float64}, list; roi=(501:580,601:650))
calib = ReducedCalibration(data)
```

## YAML configuration file

To deal with the numerous configuration of the different instruments, all calibrations files and keywords can be described in a YAML configuration file (see in the [config zoo folder](zoo)).

Usage:

```julia
using AstronomicalDetectors, ScientificDetectors
data = read_calibration_files_from_yaml("ymlfile.yml"; basedir="path/to/calib/folder")
calib = ReducedCalibration(data)
```

A YAML configuration file can be as follow :

```yaml
suffixes: [.fits, .fits.gz,.fits.Z]
include subdirectories: true
exclude files: M.

exptime: "ESO DET1 SEQ1 DIT"

DATE-OBS:
    min: 2022-04-01
    max: 2022-04-13T12:24:10.003

categories:
  DARK:
    ESO DPR TYPE: DARK
    sources: dark

  FLAT:
    ESO DPR TYPE: FLAT
    ESO ANOTHER KEYWORD: VALUE
    dir: my/flat/folder
    sources: dark + flat

  WAVE:
    exptime: "ESO OTHER DIT"
    ESO DPR TYPE:  ["LAMP,WAVE","WAVE,LAMP"]
    sources: dark + wave
```

The mandatory parts are:

- `exptime` : the FITS keyword containing the integration time
- `categories` : lists all calibration categories (e.g. FLAT, DARK,...)
- `sources` : the sources corresponding to the parent category (mandatory for each category).

In this example, the calibration files are identified by their `ESO DPR TYPE` keyword.  If several values are allowed, they can be given in a array (as for the `WAVE` category in this example). If several keywords are given (as for the `FLAT` category) all of them must be valid. A date range can also be given, as for `DATE-OBS`.

Find more information about YAML configuration in the "doc/" folder.
