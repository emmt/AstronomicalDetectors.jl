# The YAML syntax for AstronomicalDetectors

Instead of manually retrieving files for your categories, you can give a YAML file to
AstronomicalDetectors. This file defines the categories, the sources associated to each category,
and the filters to choose the files associated to each category.

Summary:
- [Structure](#structure)
- [Available Settings](#available-settings)
- [Available Filters](#available-filters)
- [Example with comments](#example-with-comments)

## Structure

```
global settings
global filters
categories
```

### Global Settings

The settings for AstronomicalDetectors. For example the setting `dir`:

```yaml
dir: alice/calibration-files/
```

`dir` is the name of the setting and `alice/calibration-files/` is the value of the setting.
This one tells AstronomicalDetectors the folder in which to look for FITS files.

The setting `exptime` is mandatory.

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

Where you describe the categories. A category has the following structure:

```
categories:
    NAME:
        category settings
        category filters
```
`categories:` is the line announcing the categories section, you write it only once in the file.

`NAME` is the name of the category. We always write them in upper case, to distinguish them from
sources names, but it is not mandatory.

`category settings` are just like `global settings` but they only apply to the current category.
For example if you give the setting `dir: other-folder/`, AstronomicalDetectors will use the
folder `other-folder/`, instead of the one defined globaly.\
In each category the setting `sources` is mandatory.

`category filters` are just like `global filters` but they only apply to the current category. For
exanple if you give the filter `NAXIS1: 1024`, every file in the category must have a header
keyword `NAXIS1` with the value `1024`.

You must indent categories (with spaces, tabs are forbidden).

Any category setting hides any global setting of the same name. It is the same for filters.

## Available Settings

Names of the settings must be in lower case.

### exptime

The setting `exptime` gives a keyword name, that keyword must contain the information of the
integration time.

Type is `String`.

Mandatory (it has no default value).

### sources

The setting `sources` gives the sources (or "currents") present in the files of the category.
For example the category FLATS may contain a dark current and a flat current. This would be
written as:

```yaml
sources: dark + flat
```

We write sources names in mostly lower case, to distinguish them from categories, but it is not
mandatory. However, they must only be composed of ASCII letters, digits, and underscores.\
Any number at the beginning of a source name acts as a coefficient for that source. For example in
`3dark` or in `1.5dark`, the coefficients are `3` and `1.5`. Coefficients are not part of the
sources names.

Only category setting.\
Mandatory for each category (it has no default value).

### dir

The setting `dir` instructs in which folder to look. Absolute and relative paths are accepted.

Type is `String`.

When unspecified, the one given to the Julia function is used, and when also unspecified,
working directory is used.

### include subdirectory

The setting `include subdirectory`, if `true`, instructs to search in the sub folders too.

Type is `Bool`.

When unspecified, `true` is used.

### hdu

The setting `hdu` gives the number of the FITS HeaderDataUnit to use.

Type is `Int`.

When unspecified, `1` is used, which points to the primary HDU.

### suffixes

The setting `suffixes` gives the accepted extensions for the files. Only files whose filename ends
in at least one of the given `String` is kept.

Type is `List of String`.

When unspecified, `[.fits, .fits.gz, .fits.Z]` is used.

### exclude files

The setting `exclude files` gives the substring that makes a filename rejected. Any file whose
filename contains at least one of the given `String` is rejected.

Type is `List of String`

When unspecified, `[]` is used.

### roi

The setting `roi` gives the Region Of Interest of the detector.

Type is `List of String of size 2`. But the `String` is in the form of a Julia `UnitRange`, for
example `100:493`.

When unspecified, the one given to the Julia function is used, and when also unspecified, `[:, :]`
is used, which means the whole array is used.

Only global setting.

### files

The setting `files` gives a list of additional files to take.

They are still subject to the settings `exclude files` and `suffixes`.
A category setting for `files` hides a global setting for `files`.

Type is `List of String`.

When unspecified, `[]` is used.

## Available Filters

You can define the filters on any FITS keyword. Since FITS keywords are upper case, and settings are
lower case, there is no name conflict.

Several filters act as an "AND": all of them must hold to keep the file.

## Single target value

Note that YAML does not impose quotes to define a String. All the following filters have one
String target value:

```yaml
ESO DPR TYPE: DARK
ESO DPR TYPE: DARK,BACKGROUND
ESO DRP TYPE: "DARK,BACKGROUND"
```

The second and third lines are equivalent.

You can also give Bool, Integer, and AbstractFloat values. Complex, empty and null values
are not supported yet.

You can mix different Integer values, like `Int32` and `Int64`, since they will be compared
by `==`. It is the same for AbstractFloat values. However, mixing values of different kinds
(String, Integer, AbstractFloat, Bool) will exclude the file and produce a warning. For example,
asking a `3.0` float for a `3` integer keyword `NAXIS` will be false.

## Multiple target values

You can use YAML arrays to define multiple target values. They are considered as an "OR": at least
one of the target values must hold to keep the file.

For example if your FITS files have two ways of writing the same keyword value:
```yaml
ESO DPR TYPE:  ["LAMP,WAVE", "WAVE,LAMP"]
```
Both "LAMP,WAVE" and "WAVE,LAMP" values are accepted. One of them must hold.

## Date range

For DateTime keywords, you can specify a range of dates. Inferior bound is inclusive and superior
bound is exclusive.

```yaml
DATE-OBS:
    min: 2022-04-01
    max: 2022-04-13T12:24:10.003
```
Only files with 2022-04-01 <= file[DATE-OBS] < 2022-04-13T12:24:10.003 will be kept.

Note that because of the limitations of the YAML library we use, if you use four digits after the
second, the fourth one is truncated. So `2022-04-13T12:24:10.0039` is changed to
`2022-04-13T12:24:10.003`.

## Example with comments

```yaml
# We start to define our global settings

# directory path where files will be looked for
dir:  alice/calibration-files/

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
    dir: alice/wave-calibration-folder  # changing the `dir` setting for this category
    exptime: "SPECIAL DIT KEYWORD"      # changing the `exptime` setting for this category
    ESO DPR TYPE: ["LAMP,WAVE","WAVE,LAMP"]
```
