using AstronomicalDetectors
using Test
using EasyFITS

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
    @testset "filtercat(filelist,keyword,value::T)" begin
        filtercat = AstronomicalDetectors.YAMLCalibrationFiles.filtercat
        hdr = FitsHeader(
            "QUESTION" => "What is the answer?",
            "ANSWER" => 42,
            "CLEVER" => false,
            "HALF" => 1.5,
            "VOID" => nothing)
        dict = Dict("file" => hdr)
        @test !isempty(filtercat(dict, "QUESTION", "What is the answer?"))
        @test !isempty(filtercat(dict, "ANSWER", 42))
        @test !isempty(filtercat(dict, "CLEVER", false))
        @test !isempty(filtercat(dict, "HALF", 1.5))
        @test !isempty(filtercat(dict, "VOID", nothing))
        @test isempty(filtercat(dict, "VOID", "something"))
    end
end
