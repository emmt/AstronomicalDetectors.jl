# The YAML syntax for AstronomicalDetectors

Instead of manually retrieving files for your categories, you can give a YAML file to
AstronomicalDetectors. This file defines the categories, the sources associated to each category,
and the filters to choose the files associated to each category.

Summary:

- [Example with comments](#example-with-comments)
- [Structure](#structure)
- [Settings](#settings)
- [Filters](#filters)


## Example with comments

```yaml
# We start to define our global settings

title: "A YAML config example"

# directory path where files will be looked for.
dir:  /home/alice/calibration-files/

# if true, sub directories will be searched too
include subdirectory: true

# only files whose filename ends with at least one of these suffixes will be kept
suffixes: [.fits, .fits.gz,.fits.Z]

# AstronomicalDetectors needs to know the integration time.
# we specify which keyword contains this information.
exptime: "ESO DET SEQ1 DIT"

# We start to define our global filters

# This is a filter that will be applied to every file.
# INSTRUME is a keyword name. SPHERE is the target value.
# Only files whose header have INSTRUME keyword with value SPHERE will be kept.
INSTRUME: SPHERE

# Here we want to restrict the files by a range of DateTime for the keyword DATE-OBS.
DATE-OBS:
    min: 2022-04-01                # inferior bound (inclusive)
    max: 2022-04-13T12:24:10.003   # superior bound (exclusive)

# We start to define our categories

categories:
  FLAT:   # a first category, of name "FLAT"
    sources: background + flat   # two sources : "background" and "flat"
    ESO INS COMB IFLT: BB_H      # a filter for this category
    ESO DPR TYPE: FLAT,LAMP      # another

  BACKGROUND:  # another category, of name "BACKGROUND"
    sources: background
    ESO DPR TYPE: ["DARK", "DARK,BACKGROUND"]   # at least one of these values must hold

  WAVE:
    sources: background + wave
    dir: /home/alice/wave-calibration-folder # changing the `dir` setting for this category
    exptime: "SPECIAL DIT KEYWORD"           # changing the `exptime` setting for this category
    ESO DPR TYPE: ["LAMP,WAVE","WAVE,LAMP"]
```

## Structure

```
global settings
global filters
categories
```

Note that putting global settings and filters in a random order, including after the categories, is
allowed, since the YAML will be parsed to a dictionnary.

### Global Settings

The settings for AstronomicalDetectors. For example the setting `dir`:

```yaml
dir: /home/alice/calibration-files/
```

`dir` is the name of the setting and `/home/alice/calibration-files/` is the value of the setting.
This one tells AstronomicalDetectors the folder in which to look for FITS files.

### Global Filters

A filter consist of a FITS header keyword name and value. For example:

```yaml
INSTRUME: SPHERE
```

`INSTRUME` is the name of the FITS keyword and `SPHERE` is the value of type `String`.

When you specify a filter, AstronomicalDetectors only keeps files respecting that filter. In the
previous example, it means that every kept file has a `INSTRUME` keyword in its header with
the value `SPHERE`.

Several filters act as an "AND": all of them must hold to keep the file.

### Categories

Where you describe the categories.

A category is a "type" of file, in the sense that you can apply
the "pixel-wise mean" on several files of the same category, and it makes sense. For example, you
can compute the mean of several "flat" calibration files with the same exposure conditions and the
same exposure time.\
Your work is to define the list of categories and how to distinguish them. You don't have to
distinguish them by the exposure time: ScientificDetectors will do this for you. It will group the
files by exposure time inside each category you defined.

A category is defined by a name, some AstronomicalDetectors settings, and some filters to decide
which files will belong to the category:

```
categories:
    NAME:
        category settings
        category filters
```

`categories:` is the line announcing the categories section, you write it only once in the file.

`NAME` is the name of the category. We always write them in upper case, to distinguish them from
sources names, but it is not mandatory.

`category settings` are like `global settings` but they only apply to the current category.
For example if you give the setting `dir: /other-folder/`, AstronomicalDetectors will use the
folder `/other-folder/`, instead of the one defined globaly.

`category filters` are just like `global filters` but they only apply to the current category. For
exanple if you give the filter `NAXIS1: 1024`, every file in the category must have a header
keyword `NAXIS1` with the value `1024`.

Any category setting hides any global setting of the same name. It is the same for filters.

In each category the setting `sources` is mandatory. It describes which light currents are present
in the files, and ScientificDetectors will do his best to find the flux of each of these currents.
Typically you can have a "DARK" category with a "dark" source, and a "FLAT" category with sources
"flat + dark", which means each FLAT file has received two currents: one from the lamp ("flat") and
one from the dark current ("dark").

You must indent categories (with spaces, tabs are forbidden in YAML indentation).

## Settings

Names of the settings are case sensitive. They are all in lower case, to distinguish them from
filters which are FITS keywords (upper case).

- **exptime**
  
  Contains a FITS keyword name, that keyword must contain the information of the
exposure time.\
  Type is `String`.\
  Can be present as global and in categories.\
  Mandatory (it has no default value). You can define it globally or in each category.
  ```yaml
  exptime: ESO DET SEQ1 DIT
  ```
- **sources**

  Contains the sources (or "currents") present in the files of the category.
  Type is `String`.
  For example the category FLAT may contain a dark current and a flat current:
  ```yaml
  categories:
      FLAT:
          sources: dark + flat
  ```
  We write sources names in mostly lower case, to distinguish them from categories, but it is not
mandatory. However, they must only be composed of ASCII letters, digits, and underscores.\
  Any number at the beginning of a source name acts as a coefficient for that source. For example in
`3dark` or in `1.5dark`, the coefficients are `3` and `1.5`. Coefficients are not part of the
sources names.
  Can be present in categories.\
  Mandatory (it has no default value).

- **dir**

  Gives in which folder to look.
  Type is `String`.
  Absolute and relative paths are accepted. When using relative path, it will be resolve from the
  current working dir of the calling script. In the API you can specify a `basedir` keyword to
  choose the folder from which to resolve relative paths.\
  Note that the category setting `dir` overwrites the global setting `dir`, don't mistake it as a
  relative path from the global setting `dir`.\
  Can be present as global setting and in categories.\
  Default value is ".".
  ```yaml
  dir: /home/alice/calib-folder
  ```

- **include subdirectories**

  Says if we must look for FITS files recursively in the sub folders of the folder `dir`.\
  Type is `Bool`.\
  Can be present as global setting and in categories.\
  Default is `true`.\
  Aliases are `include subdirectory`, `include_subdirectory`, `include_subdirectories`.
  ```yaml
  include subdirectories: true
  ```

- **hdu**

  Gives the index number of the FITS HeaderDataUnit to use. It can also be the HDUNAME.\
  Type is `Int` or `String`.\
  Can be present as global setting and in categories.\
  Default is `1` (primary HDU).
  ```yaml
  hdu: "DETECTOR_DATA"
  ```

- **suffixes**

  Gives the accepted extensions for the files.\
  Only files whose filename ends in at least one of the given `String` is kept.\
  Type is `List of String` or `String`.\
  Can be present as global setting and in categories.\
  Default is `[.fits, .fits.gz, .fits.Z]`.
  ```yaml
  suffixes: [.fits, ".fitsyfits", .fits.Z]
  suffixes: .fits.gz.Z.zip  # if you only have one you can omit the [ ]
  ```

- **exclude files**

  Gives the substrings that are forbidden in the filenames.\
  Any file whose filename contains at least one of the given `String` is rejected.\
  Type is `List of String` or `String`.\
  Can be present as global setting and in categories.\
  Default is `[]`.
  Aliases are `exclude_files`.
  ```yaml
  exclude files: ["useless", "archive-"]
  ```

- **roi**

  Gives the Region Of Interest of the detector.\
  Defines the inclusive first pixel, the inclusive last pixel, with an optional step whose default
  is `1`. You are restricted to exactly two axes. To express the full axe without having to
  hardwrite the index of its last pixel, you can use `:`.\
  Type is `String`, but it will be parsed in Julia as `NTuple{2,Union{Colon,StepRange{Int,Int}}}`.\
  Can be present as global setting and in categories.\
  Default is `(:,:)` which means full ROI.\
  You can omit the `( )`.\
  ```yaml
  roi: (:, 11:2:2038) # full first axe, and Step range of start 11, step 2, last 2038.
  ```

- **files**

  Gives a strict list of `files` to use.\
  When enabled, the settings `dir`, `suffixes`, `exclude files`, `include subdirectories`,
  and `follow symbolic links`, have no effect on this list of files. However, filters will still
  have to be valid for these files.\
  You can use absolute or relative paths.\
  Type is `List of String` or `String`.\
  Can be present as global setting and in categories. As any other settings, if is defined in a
  category it overwrites the global one.\
  Default is `[]`, when the list is empty, it disables this setting.
  ```yaml
  files: ["/tmp/temp.fits", "../toto/tata.txt"]
  ```
- **follow symbolic links**

  Says if symbolic links to folders should be followed.\
  To be checked, but it seems that for now symbolic links to files are followed, not matter if
  this setting is `true` or `false`.\
  Type is `Bool`.\
  Can be present as global setting and in categories.\
  Default is `false`.
  Aliases are `follow_symbolic_links`.
  ```yaml
  follow symbolic links: true
  ``` 
  
- **title**

  Gives an informative title to the config.\
  It has no effect, it is meant as a label for the user.\
  Type is `String`.\
  Can be present as global setting.\
  Default is an empty string.\
  ```yaml
  title: My super title
  ```

## Filters

You can define the filters on any FITS keyword. Since FITS keywords are upper case, and settings are
lower case, there is no name conflict.

Several filters act as an "AND": all of them must hold to keep the file.

### Filter Single target value

You give a single value that must be exactly matched by the FITS files:

```yaml
CALIB_TYPE: FLAT
```
In the previous example, only files with a keyword `CALIB_TYPE` with value exactly `FLAT` will be
kept.

Note that YAML does not impose quotes to define a String. All the following filters have one
String target value:

```yaml
ESO DPR TYPE: DARK,BACKGROUND
ESO DRP TYPE: "DARK,BACKGROUND"    # both lines are equivalent
```

The types authorized for values are: Integer, String, Float, Bool, DateTime. Complex numbers are
not supported yet.

Be careful when asking Float values. The floating point FITS keywords may not represent any
possible Double Precision value. Conversely, floating point FITS keyword can be non representable
in Double Precision. If needed, we can add an "epsilon" to compare float values, ask for it.

Asking a value of type different from the one in the FITS header will produce an error if the value
is not convertible. A value `1.5` in the FITS header will produce an error if asked as an Integer.

Note that the filters always use the primary header of the FITS files, no matter what is in the
`hdu` setting. Using another HDU is not supported.

### Filter Multiple target values

Similar to Filter Single target value, but a list of possible values of the same type is given.
One of them must hold to validate the filter.

```yaml
ESO DPR TYPE:  ["LAMP,WAVE", "WAVE,LAMP"]
```

### Filter Date range

Defines a DateTime range. Inferior bound is inclusive and superior bound is exclusive.

```yaml
DATE-OBS:
    min: 2022-04-01
    max: 2022-04-13T12:24:10.003
```
Only files with 2022-04-01 <= file[DATE-OBS] < 2022-04-13T12:24:10.003 will be kept.

Note that because of the limitations of the YAML library we use, if you use four digits after the
second, the fourth one is truncated. So `2022-04-13T12:24:10.0039` is changed to
`2022-04-13T12:24:10.003`.


