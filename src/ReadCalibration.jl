module YAMLCalibrationFiles

using EasyFITS: FitsHeader

using ScientificDetectors
using YAML, FITSIO
using ScientificDetectors:CalibrationFrameSampler

"""
	fill_filedict!(filedict,catdict,dir)

fill dictionary `filedict` with fitsheader of all files in `dir` according to the keywords in `catdict`
The dictionary  `filedict` key is the filepath.

"""
function fill_filedict!(filedict::Dict{String, FitsHeader},
						catdict::Dict{String, Any},
						dir::String)
	for filename in readdir(dir; join=true, sort=false)
		if !contains(filename,catdict["exclude files"])
			if isfile(filename)
				if endswith(filename,catdict["suffixes"])
					get!(filedict, filename) do
						read(FitsHeader, filename)
					end
				end
			end
		elseif isdir(filename) && filedict["include sub directory"]
			fill_filedict!(catdict,filedict,filename)
		end
	end
end

function fill_filedict!(filedict::Dict{String, FitsHeader},
						catdict::Dict{String, Any},
						dirs::Vector{String})
	for dir in dirs
		fill_filedict!(filedict,catdict,dir)
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
	newlist = filtercat(filelist,keyword,value)

Build a `newlist` dictionnary of all files where `fitsheader[keyword] == value`.
"""
function filtercat(filelist::Dict{String, FitsHeader},
					keyword::String,
					values::Union{Vector{String}, Vector{Bool}, Vector{Integer}, Vector{AbstractFloat}})
	newlist = Dict{String, FitsHeader}()
	for value in values
		merge!(newlist, filtercat(filelist,keyword,value))
	end
	return newlist
end

function filtercat(filelist::Dict{String, FitsHeader},
					keyword::String,
					value::Union{String, Bool, Integer, AbstractFloat, Nothing})
	try tmp = filter(p->p.second[keyword] == value,filelist)
		return  tmp
	catch
		return Dict{String, FitsHeader}()
	end
end

"""
	newlist = filtercat(filelist::Dict{String, FitsHeader},catdict::Dict{String, Any})

Build a `newlist` dictionnary of all files where `fitsheader[keyword] == value` for all keywords contained in `catdict`
"""
function  filterkeyword(filelist::Dict{String, FitsHeader},
						catdict::Dict{String, Any})
	filteredkeywords = "(dir)|(files)|(suffixes)|(include subdirectory)|(exclude files)|(exptime)|(hdu)|(sources)|(roi)"
	keydict =  filter(p->match(Regex(filteredkeywords), p.first) === nothing,catdict)
	if length(keydict)>0
		for (keyword,value) in keydict
			filelist =  filtercat(filelist,keyword,value)
		end
	end
	return filelist
end

function default_calibdict(dir::AbstractString,roi)
	calibdict = Dict{String, Any}()
	calibdict["dir"] = dir
	calibdict["hdu"] = 1
	calibdict["suffixes"] = [".fits", ".fits.gz","fits.Z"]
	calibdict["include subdirectory"] = true
	calibdict["exclude files"] = Vector{String}()
	calibdict["roi"] = roi
	return calibdict
end

function default_category_dict(calibdict::Dict{String, Any})
	filteredkeywords = "(categories)|(title)";
 	catdict  = Dict{String, Any}()
	merge!(catdict,filter(p->match(Regex(filteredkeywords), p.first) === nothing,calibdict));
	return catdict
end

"""
	ReadCalibrationFiles(yaml_file::AbstractString; roi::NTuple{2} = (:,:),  dir=pwd())

Process calibration files according to the YAML configuration file `yaml_file`.

- `roi` keyword can be used to consider only a region of interest of the detector (e.g. `roi=(1:100,1:2:100)`) default `roi=(:,:)`

- `dir` is the directory containing the files. By default `dir=pwd()`. This keyword is overriden by the `dir` in the YAML config file

Return an instance of `CalibrationData` with all information statistics needed to calibrate the detector.
"""
function ReadCalibrationFiles(yaml_file::AbstractString; roi = (:,:),  dir = pwd())

	calibdict = default_calibdict(dir,roi)
	#merge!(calibdict,vararg)
	merge!(calibdict,YAML.load_file(yaml_file; dicttype=Dict{String,Any}))

	filedict = Dict{String, FitsHeader}()

	catarr =  [CalibrationCategory(cata,Meta.parse(value["sources"])) for (cata,value) in calibdict["categories"] ]
	local caldat::CalibrationData{Float64}
	local dataroi::DetectorAxes
	local inds::Tuple{OrdinalRange, OrdinalRange}
	isfirst = true
	width, height = -1, -1

	for (cat,value) in calibdict["categories"]
		catdict =default_category_dict(calibdict)
		merge!(catdict, value)
		fill_filedict!(filedict,calibdict,catdict["dir"])
		haskey(catdict,"files") && fill_filedict!(filedict,calibdict,catdict["files"])
		filescat = filterkeyword(filedict,catdict)
		if !isempty(filescat)
			for (filename,fitshead) in filescat
				hdu = FITS(filename)[catdict["hdu"]] :: ImageHDU
				
				if isfirst
					width, height = size(hdu)
					inds = (Base.OneTo(width)[eval(Meta.parse(catdict["roi"]))[1]],
					Base.OneTo(height)[eval(Meta.parse(catdict["roi"]))[2]])
					dataroi = DetectorAxes(inds)
					caldat = CalibrationData{Float64}(dataroi,catarr)
					isfirst = false
				else
					width == size(hdu,1)|| error("incompatible sizes")
					height == size(hdu,2) || error("incompatible sizes")
				end
				if ndims(hdu)==2
					data = read(hdu, inds...)
					sampler =  CalibrationDataFrame(cat,fitshead[catdict["exptime"]],data;roi=dataroi)
				else
					data = read(hdu, (inds...,Base.OneTo(size(hdu,3)))...)
					
					if size(hdu,3)>1
						sampler = CalibrationFrameSampler(data,cat,fitshead[catdict["exptime"]];roi=dataroi)
					else
						sampler =  CalibrationDataFrame(cat,fitshead[catdict["exptime"]],view(data, :,:, 1);roi=dataroi)
					end
				end
				push!(caldat, sampler)
			end
		end
	end
	return caldat
end

end