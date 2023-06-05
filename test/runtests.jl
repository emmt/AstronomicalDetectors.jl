using Test
using EasyFITS
using Dates
using AstronomicalDetectors
using AstronomicalDetectors.Configs
using AstronomicalDetectors.YAMLParsing:
    parse_setting_key, parse_global_setting_value, parse_category_setting_value,
    parse_setting_value, parse_setting_value_sources, parse_setting_value_roi,
    parse_filter, parse_filter_single, parse_filter_multiple, parse_filter_range,
    isa_filter_key, parse_category, parse_yaml_file
using AstronomicalDetectors.ReadCalibration:
    parse_datetime_like_yaml, find_filepaths_by_category, gather_filters_keywords,
    gather_files_infos, challenge_file, find_and_filter_files_by_category,
    read_calibration_files_from_yaml

@testset "AstronomicalDetectors.jl" begin
    # Write your tests here.

    @testset "default_scanner" begin
        mktemp() do path,fileio
            writefits(
                path,
                FitsHeader(
                    "OBJECT"               => "OVNI",
                    "ESO DET SEQ1 REALDIT" => 42e0,
                    "ESO DPR TYPE"         => "OBJECT"),
                [ 1 2 3 ;
                  4 5 6 ;
                  7 8 9 ]
                ; overwrite = true)
            res = nothing
            @test_nowarn res = AstronomicalDetectors.default_scanner(path)
            @test res isa CalibrationInformation
            @test res.dims == (3, 3, 1)
            @test res.Δt == 42e0
            @test res.cat.name == "OVNI"
            @test convert(Expr, res.cat.expr) == :(dark + sky + ovni)
        end
    end

    @testset "read(CalibrationData, Vector{CalibrationInformation})" begin
        mktemp() do pathobject,fileio
            writefits(
                pathobject,
                FitsHeader(
                    "OBJECT"               => "OVNI",
                    "ESO DET SEQ1 REALDIT" => 42e0,
                    "ESO DPR TYPE"         => "OBJECT"),
                [ 1 2 3 ;
                  4 5 6 ;
                  7 8 9 ]
                ; overwrite = true)
            mktemp() do pathdark,fileio
                writefits(
                    pathdark,
                    FitsHeader(
                        "ESO DET SEQ1 REALDIT" => 42e0,
                        "ESO DPR TYPE"         => "DARK"),
                    [ 1 2 3 ;
                      4 5 6 ;
                      7 8 9 ]
                    ; overwrite = true)
                mktemp() do pathsky,fileio
                    writefits(
                        pathsky,
                        FitsHeader(
                            "ESO DET SEQ1 REALDIT" => 42e0,
                            "ESO DPR TYPE"         => "SKY"),
                        [ 1 2 3 ;
                          4 5 6 ;
                          7 8 9 ]
                        ; overwrite = true)
                    calibinfos = [
                        AstronomicalDetectors.default_scanner(pathobject),
                        AstronomicalDetectors.default_scanner(pathdark),
                        AstronomicalDetectors.default_scanner(pathsky)]
                    res = nothing
                    @test_nowarn res = read(CalibrationData{Float32}, calibinfos)
                    @test res isa CalibrationData
                    @test size(res.roi) == (3,3)
                    @test collect(keys(res.stat_index)) ==
                        [("OVNI", 42.0), ("SKY", 42.0), ("DARK", 42.0)]
                    #TODO more tests with more data
                end
            end
        end
    end
end

@testset "Configs" begin
    @testset "config and categories and filters creation" begin
        @test_nowarn Config()
        @test_nowarn ConfigCategory(Config(), :mysource)
        @test_nowarn ConfigFilterSingle(42)
        @test_nowarn ConfigFilterSingle(33.33)
        @test_nowarn ConfigFilterSingle("abc")
        @test_nowarn ConfigFilterSingle(true)
        @test_nowarn ConfigFilterSingle(Date(2000,1,1))
        @test_nowarn ConfigFilterMultiple([42, 42])
        @test_nowarn ConfigFilterMultiple([33.33, 44.44])
        @test_nowarn ConfigFilterMultiple(["abc", "def"])
        @test_nowarn ConfigFilterMultiple([true, false])
        @test_nowarn ConfigFilterMultiple([Date(2000,1,1), DateTime(2000,1,2)])
        @test_nowarn ConfigFilterRange(Date(2000,1,1), Date(2000,1,3))
    end
    @testset "getproperty and inheritance" begin
        config = Config()
        config.exptime = "EXPTIME"
        category = ConfigCategory(config, :mysource)
        @test category.exptime == "EXPTIME"
        category.exptime = "TIMEEXP"
        @test category.exptime == "TIMEEXP"
        category.exptime = nothing
        @test category.exptime == "EXPTIME"
    end
    @testset "challenge_filter" begin
        @test challenge_filter(ConfigFilterSingle(33.33), 33.33)
        @test ! challenge_filter(ConfigFilterSingle(33.33), 44.44)
        @test challenge_filter(ConfigFilterMultiple([33.33, 44.44]), 33.33)
        @test challenge_filter(ConfigFilterMultiple([33.33]), 33.33)
        @test ! challenge_filter(ConfigFilterMultiple([33.33, 44.44]), 55.55)
        @test challenge_filter(ConfigFilterRange(Date(2000,1,1), Date(2000,1,3)), Date(2000,1,1))
        @test challenge_filter(ConfigFilterRange(Date(2000,1,1), Date(2000,1,3)), Date(2000,1,2))
        @test ! challenge_filter(ConfigFilterRange(Date(2000,1,1), Date(2000,1,3)), Date(2000,1,3))
    end
    @testset "eltype" begin
        @test eltype(ConfigFilterSingle(3333e-2)) == Float64
        @test eltype(ConfigFilterMultiple([3333e-2])) == Float64
        @test eltype(ConfigFilterRange(Date(2000,1,1),Date(2000,1,2))) == DateTime
    end
end

@testset "YAMLParsing" begin
    @testset "parse_setting_key" begin
        @test parse_setting_key("exclude files") == :exclude_files
    end
    @testset "parse_global_setting_value" begin
        @test_throws ErrorException parse_global_setting_value(:MDR, nothing)
        @test_throws ErrorException parse_global_setting_value(:filters, nothing)
        @test_throws ErrorException parse_global_setting_value(:exptime, nothing)
        @test parse_global_setting_value(:exptime, "EXPTIME") == "EXPTIME"
    end
    @testset "parse_category_setting_value" begin
        @test_throws ErrorException parse_category_setting_value(:MDR, nothing)
        @test_throws ErrorException parse_category_setting_value(:exptime, 33.33)
        @test parse_category_setting_value(:exptime, nothing) == nothing
        @test parse_category_setting_value(:exptime, "EXPTIME") == "EXPTIME"
    end
    @testset "parse_setting_value" begin
        @test parse_setting_value(:suffixes, ".fits") == [".fits"]
        @test parse_setting_value(:suffixes, [".fits", ".fits.Z"]) == [".fits", ".fits.Z"]
        @test parse_setting_value(:dir, "././toto/../toto") == "toto"
        @test parse_setting_value(:dir, "/toto") == string(Base.Filesystem.path_separator, "toto")
        @test parse_setting_value(:exptime, "EXPTIME") == "EXPTIME"
    end
    @testset "parse_setting_value_sources" begin
        @test parse_setting_value_sources("toto") == :toto
        @test parse_setting_value_sources("toto + tata") == :(toto + tata)
        @test parse_setting_value_sources("toto + tata + tutu") == :(toto + tata + tutu)
        @test parse_setting_value_sources("0.5toto") == :(0.5toto)
    end
    @testset "parse_setting_value_roi" begin
        @test parse_setting_value_roi("(:,:)"      ) == (Colon(), Colon())
        @test parse_setting_value_roi(":,:"        ) == (Colon(), Colon())
        @test parse_setting_value_roi("  :,   :   ") == (Colon(), Colon())
        @test parse_setting_value_roi("(((:,:,)))" ) == (Colon(), Colon())
        @test parse_setting_value_roi("(1:10,2:20)") ==
            (StepRange{Int,Int}(1,1,10), StepRange{Int,Int}(2,1,20))
        @test parse_setting_value_roi("(1:2:10,2:3:20)") ==
            (StepRange{Int,Int}(1,2,10), StepRange{Int,Int}(2,3,20))
        @test parse_setting_value_roi("(:,1:10)"   ) == (Colon(), StepRange{Int,Int}(1,1,10))
        @test parse_setting_value_roi("(1:10,:)"   ) == (StepRange{Int,Int}(1,1,10),Colon())
    end
    @testset "parse_filter" begin
        @test parse_filter("TOTO", 42) == ConfigFilterSingle(42)
        @test parse_filter("TOTO", [42]).acceptedvalues == ConfigFilterMultiple([42]).acceptedvalues
        @test parse_filter("TOTO", Dict{String,Any}("min" => Date(1,1,1), "max" => Date(1,1,2))) ==
            ConfigFilterRange(Date(1,1,1), Date(1,1,2))
    end
    @testset "parse_filter_single" begin
        @test parse_filter_single("TOTO", 42) == ConfigFilterSingle(42)
        @test_throws ErrorException parse_filter_single("TOTO", (42,42))
    end
    @testset "parse_filter_multiple" begin
        @test parse_filter_multiple("TOTO", [42]).acceptedvalues ==
            ConfigFilterMultiple([42]).acceptedvalues
        @test_throws ErrorException parse_filter_multiple("TOTO", [(42,42)])
    end
    @testset "parse_filter_range" begin
        @test parse_filter_range("TOTO",
            Dict{String,Any}("min" => Date(1,1,1), "max" => Date(1,1,2))) ==
            ConfigFilterRange(Date(1,1,1), Date(1,1,2))
        @test_throws MethodError parse_filter_range("TOTO", 42)
        @test_throws ErrorException parse_filter_range("TOTO",
            Dict{String,Any}("min" => Date(1,1,1), "max" => Date(1,1,2), "MDR" => true))
        @test_throws ErrorException parse_filter_range("TOTO",
            Dict{String,Any}("MIN" => Date(1,1,1), "max" => Date(1,1,2)))
        @test_throws ErrorException parse_filter_range("TOTO",
            Dict{String,Any}("min" => 42, "max" => Date(1,1,2)))
    end
    @testset "isa_filter_key" begin
        @test isa_filter_key("TOTO")
        @test isa_filter_key("")
        @test isa_filter_key("123")
        @test isa_filter_key("TOTO123")
        @test isa_filter_key("___TOTO___3244")
        @test isa_filter_key("TOTO")
        @test ! isa_filter_key("tOTO")
    end
    @testset "parse_category (incomplete test set)" begin
        @test_throws ErrorException parse_category(Config(), "TOTO", 42)
        @test_throws ErrorException parse_category(Config(), "TOTO", Dict{String,Any}())
    end
    @testset "parse zoo/ folder" begin
        zoo = isdir("zoo/") ? "zoo/" :
              isfile("../zoo/") ? "../zoo/" :
              error("Cannot find zoo/ folder. Are you in the project root folder ?")
        for yamlpath in filter(endswith(".yaml"), readdir(zoo))
            @test_nowarn parse_yaml_file(joinpath(zoo, yamlpath))
        end
    end
end

@testset "ReadCalibration.parse_datetime_like_yaml" begin
    @test parse_datetime_like_yaml("2023-05-30T15:27:19.449") ==
        DateTime(2023,5,30,15,27,19,449)
    @test parse_datetime_like_yaml("2023-05-30T15:27:19.4499") ==
        DateTime(2023,5,30,15,27,19,449)
    @test parse_datetime_like_yaml("MDR") == DateTime(0,1,1)
end

#TODO: test follow_symbolic_links, which seems to concern only symbolic link to folders
@testset "ReadCalibration.find_filepaths_by_category" begin
    mktempdir() do tmpdir

        rootdir    = joinpath(tmpdir, "rootdir")
        altrootdir = joinpath(tmpdir, "altrootdir")
        subrootdir = joinpath(rootdir, "subrootdir")

        flatpath1 = joinpath(rootdir,    "flat1.fits")
        flatpath2 = joinpath(rootdir,    "flat2.fitsyfits") # bad extension
        flatpath3 = joinpath(rootdir,    "useless-flat3.fits") # excluded by `exclude_files`
        flatpath4 = joinpath(subrootdir, "flat4.fits")      # in sub root dir

        backname1 = "back1.fits"
        # will be adressed by relative path.
        backpath1 = joinpath(rootdir, backname1)
        backpath2 = joinpath(altrootdir, "back2.fits") # in altrootdir, will be adressed by `files`

        darkpath1 = joinpath(altrootdir, "dark1.fits") # will be found by setting `dir`
        # bad extension but ok since `suffixes` is different for category DARK
        darkpath2 = joinpath(altrootdir, "dark2.fitsyfits")

        # [rootdir]
        # |-- flat1.fits
        # |-- flat2.fitsyfits
        # |-- useless-flat3.fits
        # |-- back1.fits
        # |-- [subrootdir]
        #     |-- flat4.fits
        # [altrootdir]
        # |-- back2.fits
        # |-- dark1.fits
        # |-- dark2.fitsyfits

        mkdir(rootdir)
        mkdir(subrootdir)
        mkdir(altrootdir)
        writefits!(flatpath1, FitsHeader("EXPTIME" => 1e0, "CALIBTYPE" => "FLAT"), [111;;])
        writefits!(flatpath2, FitsHeader("EXPTIME" => 1e0, "CALIBTYPE" => "FLAT"), [112;;])
        writefits!(flatpath3, FitsHeader("EXPTIME" => 1e0, "CALIBTYPE" => "FLAT"), [113;;])
        writefits!(flatpath4, FitsHeader("EXPTIME" => 1e0, "CALIBTYPE" => "FLAT"), [114;;])
        writefits!(backpath1,  FitsHeader("EXPTIME" => 1e0, "CALIBTYPE" => "BACK"), [11 ;;])
        writefits!(backpath2,  FitsHeader("EXPTIME" => 1e0, "CALIBTYPE" => "BACK"), [12 ;;])
        writefits!(darkpath1,  FitsHeader("EXPTIME" => 1e0, "CALIBTYPE" => "DARK"), [1  ;;])
        writefits!(darkpath2,  FitsHeader("EXPTIME" => 1e0, "CALIBTYPE" => "DARK"), [2  ;;])

        config = Config()
        config.exptime = "EXPTIME"
        config.exclude_files = ["useless"]

        config.categories["FLAT"] = ConfigCategory(config, :(flat + back + dark))
        config.categories["FLAT"].filters["CALIBTYPE"] = ConfigFilterSingle("FLAT")

        config.categories["BACK"] = ConfigCategory(config, :(back + dark))
        config.categories["BACK"].filters["CALIBTYPE"] = ConfigFilterSingle("BACK")
        config.categories["BACK"].files = [backname1, backpath2] # strict file list
                                           # first path is relative and will become absolute
        config.categories["BACK"].suffixes = [] # no suffixes accepted but it will has no effect
                                                # since we use the setting `files`

        config.categories["DARK"] = ConfigCategory(config, :dark)
        config.categories["DARK"].filters["CALIBTYPE"] = ConfigFilterSingle("DARK")
        config.categories["DARK"].dir = altrootdir # search for fits in `altrootdir` folder
        config.categories["DARK"].suffixes = [".fitsyfits" ; config.suffixes]
                                             # another suffix accepted

        local filesbycats

        @test_nowarn filesbycats = find_filepaths_by_category(config ; basedir=rootdir)

        # flatpath1 present because in root dir
        # flatpath2 absent because bad extension
        # flatpath3 absent because contain substring "useless"
        # flatpath4 present because in sub root dir
        # backpath1 present because in root dir and filters are not applied yet in this step
        @test Set(filesbycats["FLAT"]) ==
            Set([flatpath1, flatpath4, backpath1])

        # backpath1 present because in the setting `files`
        # backpath2 present because backname1 has been made an absolute path
        # all other files absent because not in setting `files`
        @test Set(filesbycats["BACK"]) == Set([backpath1, backpath2])

        # backpath2 and darkpath1 present because in altrootdir
        # darkpath2 present because suffix "fitsyfits" allowed in category DARK
        @test Set(filesbycats["DARK"]) == Set([backpath2, darkpath1, darkpath2])
    end
end

@testset "ReadCalibration.gather_filters_keywords" begin
    config = Config()
    config.filters["TOTO"] = ConfigFilterSingle(42)
    config.filters["TATA"] = ConfigFilterMultiple([3333e-2, 4444e-2])
    config.filters["TUTU"] = ConfigFilterRange(Date(0,1,1), Date(0,1,2))
    config.categories["CAT"] = ConfigCategory(config, :cat)
    config.categories["CAT"].filters["TITI"] = ConfigFilterSingle(true)
    config.categories["CAT"].filters["TOTO"] = ConfigFilterSingle(43)
    @test gather_filters_keywords(config) == Dict{String,Type}(
        "TOTO" => Int, "TATA" => Float64, "TUTU" => DateTime, "TITI" => Bool)
    config.categories["CAT"].filters["TOTO"] = ConfigFilterSingle("WRONG")
    @test_warn "Redefinition of filter keyword's type" gather_filters_keywords(config)
end

@testset "ReadCalibration.gather_files_infos" begin
    filters_keywords = Dict{String,Type}(
        "EXPTIME" => Float64, "DATE" => DateTime, "VERY LONG KKKEEEYYYWWWOOORRRDDDD" => Bool)
    mktempdir() do tmpdir

        filepath1 = joinpath(tmpdir, "file1.fits")
        filepath2 = joinpath(tmpdir, "file2.fits")
        filepaths = Set([filepath1, filepath2])
        hdr1 = FitsHeader(
            "EXPTIME" => 3333e-2, "DATE" => DateTime(0,1,1),
            "VERY LONG KKKEEEYYYWWWOOORRRDDDD" => true)
        hdr2 = FitsHeader("EXPTIME" => 3333f-2)
        writefits!(filepath1, hdr1, [1;;])
        writefits!(filepath2, hdr2, [1;;])

        infos = gather_files_infos(filepaths, filters_keywords)

        @test typeof(infos[filepath1]["EXPTIME"]) == filters_keywords["EXPTIME"]
        @test typeof(infos[filepath1]["DATE"])    == filters_keywords["DATE"]
        @test typeof(infos[filepath1]["VERY LONG KKKEEEYYYWWWOOORRRDDDD"]) ==
            filters_keywords["VERY LONG KKKEEEYYYWWWOOORRRDDDD"]
        @test infos[filepath1]["EXPTIME"]         == hdr1["EXPTIME"].float
        @test infos[filepath1]["DATE"]            == hdr1["DATE"].value(DateTime)
        @test infos[filepath1]["VERY LONG KKKEEEYYYWWWOOORRRDDDD"] ==
            hdr1["VERY LONG KKKEEEYYYWWWOOORRRDDDD"].logical

        @test typeof(infos[filepath2]["EXPTIME"])  == filters_keywords["EXPTIME"]
        @test typeof(infos[filepath2]["DATE"])     == Missing
        @test typeof(infos[filepath2]["VERY LONG KKKEEEYYYWWWOOORRRDDDD"]) == Missing
        # file2 contains EXPTIME as a Float32 so we lost precision. not our fault!
        @test Float32(infos[filepath2]["EXPTIME"]) == hdr2["EXPTIME"].float
        @test ismissing(infos[filepath2]["DATE"])
        @test ismissing(infos[filepath2]["VERY LONG KKKEEEYYYWWWOOORRRDDDD"])
    end
end

@testset "ReadCalibration.challenge_file" begin
    filters = Dict{String,ConfigFilter}()
    filters["TOTO"] = ConfigFilterSingle(42)
    filters["TATA"] = ConfigFilterSingle(33.33)
    filters["TITI"] = ConfigFilterSingle(true)
    filters["TUTU"] = ConfigFilterSingle("abc")
    filters["TUTUTU"] = ConfigFilterMultiple(["abc", "def"])
    filters["TETETE"] = ConfigFilterRange(Date(0,1,1), Date(0,1,3))
    # correct infos
    files_infos1 = Dict{String,Any}()
    files_infos1["TOTO"] = filters["TOTO"].acceptedvalue
    files_infos1["TATA"] = filters["TATA"].acceptedvalue
    files_infos1["TITI"] = filters["TITI"].acceptedvalue
    files_infos1["TUTU"] = filters["TUTU"].acceptedvalue
    files_infos1["TUTUTU"] = filters["TUTUTU"].acceptedvalues[1]
    files_infos1["TETETE"] = filters["TETETE"].rangemin
    @test first(challenge_file(filters, files_infos1))

    # make incorrect infos

    files_infos2 = copy(files_infos1)
    files_infos2["TOTO"] = filters["TOTO"].acceptedvalue + 1
    @test challenge_file(filters, files_infos2) == (false, "TOTO")

    files_infos2 = copy(files_infos1)
    files_infos2["TATA"] = filters["TATA"].acceptedvalue + 0.000001
    @test challenge_file(filters, files_infos2) == (false, "TATA")

    files_infos2 = copy(files_infos1)
    files_infos2["TITI"] = ! filters["TITI"].acceptedvalue
    @test challenge_file(filters, files_infos2) == (false, "TITI")

    files_infos2 = copy(files_infos1)
    files_infos2["TUTU"] = filters["TUTU"].acceptedvalue * 'd'
    @test challenge_file(filters, files_infos2) == (false, "TUTU")

    files_infos2 = copy(files_infos1)
    files_infos2["TUTUTU"] = reduce(*, filters["TUTUTU"].acceptedvalues)
    @test challenge_file(filters, files_infos2) == (false, "TUTUTU")

    files_infos2 = copy(files_infos1)
    files_infos2["TETETE"] = filters["TETETE"].rangemax
    @test challenge_file(filters, files_infos2) == (false, "TETETE")
end

@testset "ReadCalibration.read_calibration_files_from_yaml" begin
    # this also serves as test for CalibrationData and find_and_filter_files_by_category

    yamldata =
"""
exptime: EXPTIME
categories:
    FLAT:
        sources: flat + back
        CALIBTYPE: FLAT
    BACK:
        sources: back
        CALIBTYPE: BACK
        hdu: 2
"""
    mktemp() do yamlpath,yamlfileio
    mktempdir() do tmpdir

        write(yamlpath, yamldata)

        rootpath = joinpath(tmpdir, "rootdir")
        subpath  = joinpath(rootpath, "subdir")
        mkdir(rootpath)
        mkdir(subpath)

        flatpath1 = joinpath(subpath, "flat1.fits")
        flatpath2 = joinpath(subpath, "flat2.fits")

        flatpath3 = joinpath(rootpath, "flat3.fits")

        backpath1 = joinpath(rootpath, "back1.fits")
        backpath2 = joinpath(rootpath, "back2.fits")

        writefits!(flatpath1, FitsHeader("EXPTIME" => 1e0, "CALIBTYPE" => "FLAT"),
                              [101 ; 101 ;; 101 ; 101])
        writefits!(flatpath2, FitsHeader("EXPTIME" => 10e0, "CALIBTYPE" => "FLAT"),
                              [1010 ; 1010 ;; 1010 ; 1010])
        writefits!(flatpath3, FitsHeader("EXPTIME" => 1e0, "CALIBTYPE" => "FLAT"),
                              [103 ; 103 ;; 103 ; 103])

        writefits!(backpath1, FitsHeader("EXPTIME" => 1e0, "CALIBTYPE" => "BACK"),
                              [0;;],
                              FitsHeader(),
                              [1 ; 1 ;; 1 ; 1])
        writefits!(backpath2, FitsHeader("EXPTIME" => 1e0, "CALIBTYPE" => "BACK"),
                              [0;;],
                              FitsHeader(),
                              [3 ; 3 ;; 3 ; 3])

        calib = read_calibration_files_from_yaml(yamlpath ; basedir=rootpath)
        @test Set(keys(calib.src_index)) == Set(["flat", "back"])
        @test Set(keys(calib.cat_index)) == Set(["FLAT", "BACK"])
        @test calib.stat[calib.stat_index[("FLAT",1e0)]].n == 2
        @test calib.stat[calib.stat_index[("FLAT",1e0)]].s[1] == [102 ; 102 ;; 102 ; 102]
        @test calib.stat[calib.stat_index[("FLAT",10e0)]].n == 1
        @test calib.stat[calib.stat_index[("FLAT",10e0)]].s[1] == [1010 ; 1010 ;; 1010 ; 1010]
        @test calib.stat[calib.stat_index[("BACK",1e0)]].n == 2
        @test calib.stat[calib.stat_index[("BACK",1e0)]].s[1] == [2 ; 2 ;; 2 ; 2]

        # change roi, and change basedir, and prune
        msg = "No files were kept by filters for category BACK."
        @test_warn msg (calib = read_calibration_files_from_yaml(yamlpath ;
                               overwrite_roi=(1:1:2, 1:1:1), basedir=subpath, prune=true))
        #TODO: re-enable when `prune` merged in ScientificDetectors:
        # @test Set(keys(calib.src_index)) == Set(["back__and__flat"])
        #TODO: disable when `prune` merged in ScientificDetectors:
        @test Set(keys(calib.src_index)) == Set(["back", "flat"])
        @test Set(keys(calib.cat_index)) == Set(["FLAT"])
        @test calib.stat[calib.stat_index[("FLAT",1e0)]].n == 1
        @test calib.stat[calib.stat_index[("FLAT",1e0)]].s[1] == [101 ; 101 ;;]
        @test calib.stat[calib.stat_index[("FLAT",10e0)]].n == 1
        @test calib.stat[calib.stat_index[("FLAT",10e0)]].s[1] == [1010 ; 1010 ;;]
    end
    end
end

