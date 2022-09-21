using LoopVectorization
using StaticArrays
using JLD2
using ArgParse

PATH=abspath("src/")
include(PATH*"board.jl")
include(PATH*"search.jl")


function AtaxxServer(actor,nthread)
    game=GAME.Game()
    ready=false
    movecount=0
    pool=TDL.αThreadPool(actor,nthread)
    while true
        line=readline(stdin,keep=true)
        if startswith(line,"uai")
            write(stdout,"id name MarsAtaxx\n")
            write(stdout,"uaiok\n")

        elseif startswith(line,"isready")
            TDL.init!(pool,true)
            write(stdout,"readyok\n")
        elseif  startswith(line,"uainewgame\n")
                game=GAME.Game()
                movecount=0
        elseif  startswith(line,"position")
            #fen=split(line," ")
            if  length(line)==18#startswith(fen,"start")
                game=GAME.Game()
            else
                write(stdout,line[14:end]*"\n")
                game=GAME.gameFromFen(line[14:end])
            end
        elseif startswith(line,"go")
            line=split(line," ")
            if line[2]=="movetime"
                t=parse(Int,line[3])
            else
                if game.player==1
                    t=parse(Int,line[3])
                    inc=parse(Int,line[7])
                else
                    t=parse(Int,line[5])
                    inc=parse(Int,line[9])
                end
                t=min(t/30+inc,t/2)
            end
            result=TDL.SearchResult(GAME.αNONEMOVE,0,0,0)
            TDL.search(game,t/1000,pool,result)
            c,v,depth=result.move.move,result.value,result.depth
            move=GAME.MoveToString(c)
            movecount+=1
            write(stdout,"bestmove "*move*" evaluation $v depth $depth\n")
        elseif startswith(line,"quit")
            break
        end
    end
    return game
end



function truemain()


    s = ArgParseSettings()
    @add_arg_table! s begin
    "--workers"
    arg_type = Int
    default=1
end

parsed_args = parse_args(ARGS, s)

    weights=JLD2.load(PATH*"/weights.jld2")["weights"]

    ev=TDL.TupleEval(weights)
    game=GAME.Game()
    moves=[GAME.αMoves() for k in 1:255]
    stack=TDL.Stack(255)
    TDL.ab_iterative(game,1,ev,stack,moves)
    TDL.init!(stack,true)
    pool=TDL.αThreadPool(ev,1)
    result=TDL.SearchResult(GAME.αNONEMOVE,0,0,0)
    c,v,depth=TDL.search(game,1,pool,result)
    AtaxxServer(ev,parsed_arg["workers"])
end

function julia_main()::Cint
    try
        truemain()
    catch
        Base.invokelatest(Base.display_error, Base.catch_stack())
        return 1
    end
    return 0
end

julia_main()
