using AstronomicalDetectors
using Test
using AstroFITS
using Dates
using AstronomicalDetectors.YAMLCalibrationFiles
using AstronomicalDetectors.YAMLCalibrationFiles:filtercat

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

@testset "ReadCalibration.jl" begin

    @testset "filtercat single value" begin
        catfiles = Set(["file1"])
        hdr = FitsHeader(
            "QUESTION" => "What is the answer?",
            "ANSWER" => 42,
            "CLEVER" => false,
            "HALF" => 1.5,
            "VOID" => nothing,
            "ESO INFORMATIVE MESSAGE" => "I like my keyword names to be long")
        header_cache = Dict("file1" => hdr)
        @test !isempty(filtercat(catfiles, header_cache, "QUESTION", "What is the answer?"))
        @test !isempty(filtercat(catfiles, header_cache, "ANSWER", 42))
        @test !isempty(filtercat(catfiles, header_cache, "CLEVER", false))
        @test !isempty(filtercat(catfiles, header_cache, "HALF", 1.5e0))
        @test !isempty(filtercat(catfiles, header_cache, "HALF", 1.5f0))
        @test !isempty(filtercat(catfiles, header_cache, "ANSWER", Int8(42)))
        @test !isempty(filtercat(catfiles, header_cache, "ANSWER", UInt64(42)))
        warnmsg = "card type Float64 is != from target value type String in file file1"
        @test_warn warnmsg filtercat(catfiles, header_cache, "HALF", "1.5")
        errormsg = "Complex values not yet implemented"
        @test_throws ErrorException(errormsg) filtercat(catfiles, header_cache, "HALF", 1.5+0im)
        warnmsg = "card type Float64 is != from target value type Int64 in file file1"
        @test_warn warnmsg filtercat(catfiles, header_cache, "HALF", 1)
        warnmsg = "card type Int64 is != from target value type Float64 in file file1"
        @test_warn warnmsg filtercat(catfiles, header_cache, "ANSWER", 42e0)
        errormsg = "unsupported target value type Nothing"
        @test_throws ErrorException(errormsg) filtercat(catfiles, header_cache, "VOID", nothing)
        warnmsg = "card type Nothing is != from target value type String in file file1"
        @test_warn warnmsg filtercat(catfiles, header_cache, "VOID", "something")
        @test !isempty(filtercat(catfiles, header_cache, "ESO INFORMATIVE MESSAGE",
                                       "I like my keyword names to be long"))
    end

    @testset "filtercat several value" begin
        catfiles = Set(["file1"])
        hdr = FitsHeader("GOOD" => 2)
        header_cache = Dict("file1" => hdr)
        @test !isempty(filtercat(catfiles, header_cache, "GOOD", [1, 2]))
        warnmsg = "card type Int64 is != from target value type Float64 in file file1"
        @test_warn warnmsg filtercat(catfiles, header_cache, "GOOD", [1.0, 2.0])
        errormsg = "eltype Any of the Vector target value is not supported"
        @test_throws ErrorException(errormsg) filtercat(catfiles, header_cache, "GOOD", [1, "2"])
    end

    @testset "filtercat date range" begin
        # date range
        catfiles = Set(["TOTO"])
        header_cache = Dict("TOTO" => FitsHeader("DATE" => "2023-11-20T08:00:10.123"))
        keyword = "DATE"
        value = Dict{String,Any}(
            "min" => DateTime("2022-11-20T08:00:10.123"),
            "max" => DateTime("2024-11-20T08:00:10.123"))
        catfiles2 = filtercat(catfiles, header_cache, keyword, value)
        @test catfiles == catfiles2

        # date range with fitsheader date with fourth millisecond in FITS file
        catfiles = Set(["TOTO"])
        header_cache = Dict("TOTO" => FitsHeader("DATE" => "2023-11-20T08:00:10.1234"))
        keyword = "DATE"
        value = Dict{String,Any}(
            "min" => DateTime("2022-11-20T08:00:10.123"),
            "max" => DateTime("2024-11-20T08:00:10.123"))
        catfiles2 = filtercat(catfiles, header_cache, keyword, value)
        @test catfiles == catfiles2

        # date range exclude
        catfiles = Set(["TOTO"])
        header_cache = Dict("TOTO" => FitsHeader("DATE" => "2023-11-20T08:00:10.123"))
        keyword = "DATE"
        value = Dict{String,Any}(
            "min" => DateTime("2022-11-20T08:00:10.123"),
            "max" => DateTime("2023-11-20T08:00:10.123"))
        catfiles2 = filtercat(catfiles, header_cache, keyword, value)
        @test isempty(catfiles2)

        # date range include
        catfiles = Set(["TOTO"])
        header_cache = Dict("TOTO" => FitsHeader("DATE" => "2022-11-20T08:00:10.123"))
        keyword = "DATE"
        value = Dict{String,Any}(
            "min" => DateTime("2022-11-20T08:00:10.123"),
            "max" => DateTime("2023-11-20T08:00:10.123"))
        catfiles2 = filtercat(catfiles, header_cache, keyword, value)
        @test catfiles == catfiles2

        # yaml file, with a test with fourth millisecond
        mktemp()        do pathyaml,fileio
        mktempdir()     do pathdir
        mktemp(pathdir) do pathfits,fileio

            hdr = FitsHeader("DATE" => "2023-11-20T08:00:10.1234", "TIME" => 1.1)
            yaml = """
                   suffixes: [$pathfits]
                   exptime: "TIME"
                   categories:
                     TOTO:
                       DATE:
                           min: 2022-11-20T08:00:10.1234
                           max: 2024-11-20T08:00:10.1234
                       sources: toto
                   """
            write(pathyaml, yaml)
            writefits!(pathfits, hdr, Int[0 0 ; 0 0])
            ReadCalibrationFiles(pathyaml; dir=pathdir)

        end end end
    end

    @testset "ReadCalibrationFiles with example_from_the_doc.yml" begin
        initialdir = pwd()
        try
            mktempdir() do pathdir

                cd(pathdir)

                # build directory structure like in the example
                mkdir("alice")
                mkdir("alice/calibration-files")
                mkdir("alice/calibration-files/subfolder")
                mkdir("alice/wave-calibration-folder")

                hdr1 = FitsHeader("ESO DET SEQ1 DIT" => 1e0, "INSTRUME" => "SPHERE",
                                  "DATE-OBS" => "2022-04-05",
                                  "ESO INS COMB IFLT" => "BB_H", "ESO DPR TYPE" => "FLAT,LAMP")
                writefits!("alice/calibration-files/file1.fits", hdr1, [1;;])

                hdr2 = FitsHeader("ESO DET SEQ1 DIT" => 1e0, "INSTRUME" => "SPHERE",
                                  "DATE-OBS" => "2022-04-05", "ESO DPR TYPE" => "DARK")
                writefits!("alice/calibration-files/subfolder/file2.fits", hdr2, [1;;])

                hdr3 = FitsHeader("SPECIAL DIT KEYWORD" => 1e0, "INSTRUME" => "SPHERE",
                                  "DATE-OBS" => "2022-04-05", "ESO DPR TYPE" => "LAMP,WAVE")
                writefits!("alice/wave-calibration-folder/file3.fits", hdr3, [1;;])

                # put one in a wrong folder to see if it is correctly excluded
                writefits!("alice/calibration-files/file3bis.fits", hdr3, [1;;])

                data = ReadCalibrationFiles(initialdir * "/example_from_the_doc.yml")

                @test "FLAT"       in keys(data.cat_index)
                @test "BACKGROUND" in keys(data.cat_index)
                @test "WAVE"       in keys(data.cat_index)
                @test "flat"       in keys(data.src_index)
                @test "background" in keys(data.src_index)
                @test "wave"       in keys(data.src_index)
                @test data.stat[data.stat_index[("FLAT",1)      ]].n == 1
                @test data.stat[data.stat_index[("BACKGROUND",1)]].n == 1
                @test data.stat[data.stat_index[("WAVE",1)      ]].n == 1
            end
        finally cd(initialdir) end
    end
end
