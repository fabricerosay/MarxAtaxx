module GAME
#using TimerOutputs
import Base.:<<,Base.:>>,Base.:~,Base.:&,Base.:⊻,Base.:|,Base.copy

export Game,
    canPlay,
    play,
    undo,
    isOver,
    score,
    getplayer,
    getboard,
    getround,
    gethash,
    Move,
    gen_moves


const N=7
const NN=N*N
const StateShape=(N,N,3)
const NAME="Attaxx"


struct Square
	sq::Int
end

is_pass(sq::Square)=sq.sq==-1

struct Bitboard
	data::UInt64
end

Base.:<<(b::Bitboard,n)=Bitboard(b.data<<n)
Base.:>>(b::Bitboard,n)=Bitboard(b.data>>n)
Base.:~(b::Bitboard)=Bitboard(~b.data & 0x7f7f7f7f7f7f7f)
Base.:⊻(b1::Bitboard,b2::Bitboard)=Bitboard(b1.data ⊻ b2.data)
Base.:&(b1::Bitboard,b2::Bitboard)=Bitboard(b1.data & b2.data)
Base.:|(b1::Bitboard,b2::Bitboard)=Bitboard(b1.data | b2.data)

Base.iterate(b::Bitboard)=b.data==UInt(0) ? nothing : (Square(trailing_zeros(b.data)),b.data&(b.data-0x1))
Base.iterate(b::Bitboard,state)=state==UInt(0) ? nothing : (Square(trailing_zeros(state)),state &(state-0x1))

Base.count_ones(b::Bitboard)=count_ones(b.data)

function set(b::Bitboard,sq::Square)
	Bitboard(b.data⊻UInt64(1)<<sq.sq)
end

function get(b::Bitboard,sq::Square)
	b.data>>sq.sq & 1
end

Bitboard(sq::Square)=Bitboard(UInt64(1)<<sq.sq)

function singles(b::Bitboard)
	Bitboard((b.data << 1 | b.data << 9 | b.data >> 7 | b.data << 8 | b.data >> 8 |
	b.data >> 1 | b.data >> 9 | b.data << 7) & 0x7f7f7f7f7f7f7f)
end

function singles(sq::Square)
	b=Bitboard(UInt64(1)<<sq.sq)
	return singles(b)
end

function doubles(b::Bitboard)
	Bitboard(((b.data << 2 | b.data << 10 | b.data << 18 | b.data >> 6 | b.data >> 14 | b.data << 17 | b.data >> 15) & 0x7e7e7e7e7e7e7e) |

				((b.data << 16 | b.data >> 16) & 0x7f7f7f7f7f7f7f) |

				((b.data >> 2 | b.data >> 10 | b.data >> 18 | b.data << 6 | b.data << 14 | b.data << 15 | b.data >> 17) & 0x3f3f3f3f3f3f3f)
			 )
end

function doubles(sq::Square)
	b=Bitboard(UInt64(1)<<sq.sq)
	return doubles(b)
end


is_empty(b::Bitboard)=b.data==0
is_full(b::Bitboard)=b.data==0x7f7f7f7f7f7f7f
function test()
	b=Bitboard(0x7f7f7f7f7f7f7f)
	for x in b
		println(doubles(x))
	end
end

struct Board
	bplayer::Bitboard
	bopp::Bitboard
end

mutable struct Game
    board::Board
    player::Int8
    round::Int
    hash::UInt
end

struct Move
    from::Square
    to::Square
end

const PASSMOVE=Move(Square(-1),Square(-1))
const NONEMOVE=Move(Square(-2),Square(-2))

function Game()
	bb=Bitboard(0)
    h=zhash(Square(0),1)
	bb=set(bb,Square(0))
    h⊻=zhash(Square(54),1)
	bb=set(bb,Square(54))
	bw=Bitboard(0)
	bw=set(bw,Square(6))
    h⊻=zhash(Square(6),-1)
	bw=set(bw,Square(48))
    h⊻=zhash(Square(48),-1)
    return Game(
    Board(bb,bw),
    1,
	0,
    h,
    )
end

score(pos,n=0) = abs(sum(pos.board[:,:,1])-sum(pos.board[:,:,2]))
getplayer(pos) = pos.player



function vectorise(game)
    answer=zeros(Int8,98)
    for sq in game.board.bplayer
        answer[LinearRank(sq)]=1
    end
    for sq in game.board.bopp
        answer[LinearRank(sq)+49]=1
    end
    answer
end

function getboard(pos)
    answer = zeros(Int8, N, N, 3, 1)
    for sq in pos.board.bplayer
        i,j=SquareRank(sq)
        answer[i,j,1,1]=1
    end
    for sq in pos.board.bopp
        i,j=SquareRank(sq)
        answer[i,j,2,1]=1
    end

 	answer[:, :, 3, 1] .= pos.player
	# if pos.player==1
	# 	answer[:,:,1,1].=(pos.board[:,:,1,1].-pos.board[:,:,2,1])
	# else
	# 	answer[:,:,1,1].=rot180(pos.board[:,:,2,1].-pos.board[:,:,1,1])
	# end
    return answer
end


gethash(pos) =(deepcopy(pos.board),pos.player,pos.round)#pos.hash
getround(pos) = pos.round

other(x)=-x
index(x)=x==1 ? 1 : 2

function isOver(pos)
	bplayer=pos.board.bplayer
	bopp=pos.board.bopp
	p=count_ones(bplayer)
	o=count_ones(bopp)
	if is_empty(bplayer) || is_empty(bopp)
    	return true,sign((p-o)*pos.player)
	end
	if is_full(bplayer|bopp)
		return true,sign((p-o)*pos.player)
	end
    if nomoves(pos)
        return true,sign((p-o)*pos.player)
    end
	if pos.round>=200
        return true,sign((p-o)*pos.player)
    end
	return false,0
end

@inbounds @inline function play(game, move::Move)

    bplayer=game.board.bplayer
    bopp=game.board.bopp
    sqf=move.from
	sqt=move.to
    if is_pass(sqf)
        # game.player=other(game.player)
        # game.round=game.round+1
        # game.hash⊻=Zobrist[99]
        # game.fifty+=1
        # game.board=Board(bopp,bplayer)
        turned=Bitboard(0)
	else

        if sqf!=sqt
            bplayer⊻=Bitboard(sqf)
            game.hash⊻=zhash(sqf,game.player)
        end
        game.hash⊻=zhash(sqt,game.player)
        bplayer=set(bplayer,sqt)
        turned=singles(sqt) & bopp
        for sq in turned
            game.hash⊻=zhash(sq,game.player)
            game.hash⊻=zhash(sq,other(game.player))
        end
        bopp⊻=turned
        bplayer|=turned
    end
    game.hash⊻=Zobrist[99]
	game.board=Board(bopp,bplayer)
    game.player=other(game.player)
    game.round=game.round+1
    return turned
end

function undo(game,move,u)
    sqf=move.from
	sqt=move.to
    game.round=game.round-1
    game.player=other(game.player)
    bplayer=game.board.bopp
	bopp=game.board.bplayer
    if !is_pass(sqf)
        turned=u
	    if sqf!=sqt
    	    bplayer⊻=Bitboard(sqf)
            game.hash⊻=zhash(sqf,game.player)
	    end
        game.hash⊻=zhash(sqt,game.player)
        bplayer=set(bplayer,sqt)
        for sq in turned
            game.hash⊻=zhash(sq,game.player)
            game.hash⊻=zhash(sq,other(game.player))
        end
	    bopp⊻=turned
	    bplayer⊻=turned
    end
    game.hash⊻=Zobrist[99]
    game.board=Board(bplayer,bopp)
end

function MoveScore(position,move)
    score=move.from==move.to
    cap=singles(move.to)&position.board.bopp
    score+=count_ones(cap)
    score
end



function gen_moves(position,answer,move,sorting=false,sfunc=MoveScore)
    cpt=0
    startsort=1
    if move!=NONEMOVE
        cpt += 1
        answer[1]=move
        startsort=2
    end

    for sq in singles(position.board.bplayer) & ~(position.board.bplayer | position.board.bopp)
		#push!(answer,Move(sq,sq))

        m=Move(sq,sq)
        if m!=move
		    cpt+=1
		    answer[cpt]=m
        end
	end
	for sqf in position.board.bplayer
		for sqt in doubles(sqf) & ~(position.board.bplayer | position.board.bopp)
			#push!(answer,Move(sqf,sqt))
            m=Move(sqf,sqt)
            if m!=move
			    cpt+=1
			    answer[cpt]=m
            end
		end
	end
	if cpt==0
		cpt+=1
		#push!(answer,Move(Square(-1),Square(-1)))
		answer[cpt]=PASSMOVE
    elseif sorting
         @views sort!(answer[startsort:cpt],by=x->-sfunc(position,x))
	end
    cpt
end

struct αMove
	move::Move
	score::Tuple{Int8,Int8}#,Int}
	quiet::Bool
end

function αMoves()
	moves=Vector{GAME.αMove}()
	sizehint!(moves)=200
	moves
end

const αNONEMOVE=αMove(NONEMOVE,(0,0),false)

const αPASSMOVE=αMove(PASSMOVE,(0,0),false)

const PSQT=Int8[6,4,2,2,2,4,6,0,
			4,2,1,1,1,2,4,0,
			2,1,0,0,0,1,2,0,
			2,1,0,0,0,1,2,0,
			2,1,0,0,0,1,2,0,
			4,2,1,1,1,2,4,0,
			6,4,2,2,2,4,6,0,
			0,0,0,0,0,0,0,0]

@inbounds function αgen_moves(position,answer,move)
    cpt=0
	endsort=1
	if move!=αNONEMOVE
		push!(answer,move)
		cpt=1
		endsort=2
	end
    for sq in singles(position.board.bplayer) & ~(position.board.bplayer | position.board.bopp)
        m=Move(sq,sq)
		if m!=move.move
				#scoreht=ht[sq.sq+1,sq.sq+1,position.player==1 ? 1 : 2]
				scorepos=1+count_ones(singles(m.to)&position.board.bopp)
				psqt=PSQT[m.to.sq+1]
				score=(scorepos,psqt)#,scoreht)
				k=cpt
				cpt+=1
				m=αMove(m,score,score[1]<=1)
				push!(answer,m)
				while k>=endsort
					if answer[k].score<score
						answer[k+1]=answer[k]
						answer[k]=m
						k-=1
					else
						break
					end
				end

		end
	end
	for sqf in position.board.bplayer
		for sqt in doubles(sqf) & ~(position.board.bplayer | position.board.bopp)
			m=Move(sqf,sqt)
			if m!=move.move
				#scoreht=ht[sqf.sq+1,sqt.sq+1,position.player==1 ? 1 : 2]
					scorepos=count_ones(singles(m.to)&position.board.bopp)-
						  count_ones(singles(m.from)&position.board.bplayer)
					psqt=PSQT[m.to.sq+1]-PSQT[m.from.sq+1]
					score=(scorepos,psqt)#,scoreht)
					k=cpt
					cpt+=1
					m=αMove(m,score,scorepos<=1)
					push!(answer,m)
					while k>=endsort
						if answer[k].score<score
							answer[k+1]=answer[k]
							answer[k]=m
							k-=1
						else
							break
						end
					end
			end
		end
	end
	if cpt==0
		cpt+=1
		push!(answer,αPASSMOVE)
	end
    cpt
end

function gen_moves(position)
	nmoves=count_moves(position)
	moves=Vector{Move}(undef,nmoves)
	gen_moves(position,moves,NONEMOVE)
	moves
end

function gen_move(position,k)
    move=Move(Square(-1),Square(-1))
    cpt = 0
    for sq in singles(position.board.bplayer) & ~(position.board.bplayer | position.board.bopp)
		move=Move(sq,sq)
		cpt+=1
		if cpt==k
			return move
		end

	end
	for sqf in position.board.bplayer
		for sqt in doubles(sqf) & ~(position.board.bplayer | position.board.bopp)
			move=Move(sqf,sqt)
			cpt+=1
			if cpt==k
				return move
			end
		end
	end
end
#
# function count_moves(position)
#     cpt = 0
# 	empties= ~(position.board.bplayer | position.board.bopp)
#
#     for sq in singles(position.board.bplayer) & empties
# 		cpt+=1
# 	end
# 	for sqf in position.board.bplayer
# 		for sqt in doubles(sqf) & empties
# 			cpt+=1
# 		end
# 	end
# 	cpt+=cpt==0
#     cpt
# end

function count_moves(position)
    cpt = 0
	empties= ~(position.board.bplayer | position.board.bopp)
	s=singles(position.board.bplayer) & empties
    cpt+=count_ones(s)
	for sqf in position.board.bplayer
		cpt+=count_ones(doubles(sqf) & empties)
	end
	cpt+=cpt==0
    cpt
end

function nomoves(position)
    cpt = 0
	empties= ~(position.board.bplayer | position.board.bopp)
	s=singles(position.board.bplayer  | position.board.bopp) & empties
    cpt+=count_ones(s)
	for sqf in (position.board.bplayer  | position.board.bopp)
		cpt+=count_ones(doubles(sqf) & empties)
	end
    cpt==0
end
# function perft(pos,depth,moves,to)
# 	nodes=0
# 	@timeit to "over" if isOver(pos)[1]
# 		return 0
# 	end
# 	@timeit to "count"  if depth==1
# 		return count_moves(pos)
# 	end
#
#
# 	@timeit to "gen" nmoves=gen_moves(pos,moves[depth])
# 	for k in 1:nmoves
# 		@timeit to "play" child=play(pos,moves[depth][k])
# 		 nodes+=perft(child,depth-1,moves,to)#@timeit to "nested"
# 	end
# 	return nodes
# end


SquareRank(sq::Square)=div(sq.sq,8)+1,sq.sq%8+1

function LinearRank(sq::Square)
    i,j=SquareRank(sq)
    return 7*(i-1)+j
end

const Zobrist=rand(UInt,99) ##first 49 white then black  then turn

function zhash(sq::Square,color)
    off=color==1 ? 0 : 49
    Zobrist[LinearRank(sq)+off]
end

function getzhash(game)
    h=UInt(0)
    for sq in game.board.bplayer
        h⊻=zhash(sq,game.player)
    end
    for sq in game.board.bopp
        h⊻=zhash(sq,other(game.player))
    end
    if game.player==-1
        h⊻=Zobrist[99]
    end
    h
end

function SquareToString(sq::Square)
    i,j=SquareRank(sq)
    Char(104-j)*"$i"
end


function MoveToString(move::Move)
    from=move.from
    to=move.to
    if move==PASSMOVE
        return "0000"
    end
    if move==NONEMOVE
        return "NONE"
    end
    if from==to
        return SquareToString(to)
    else
        return SquareToString(from)*SquareToString(to)
    end
end

function StringToMove(s)
	if s[1]=='0' || s[1]=='p'
		return Move(Square(-1),Square(-1))
	end
	if length(s)==2
		j=103-Int(s[1])
		i=parse(Int,s[2])
        sq=Square(8*(i-1)+j)
		return GAME.Move(sq,sq)
	end
    j=103-Int(s[1])
    i=parse(Int,s[2])
    sqf=Square(8*(i-1)+j)
    j=103-Int(s[3])
    i=parse(Int,s[4])
    sqt=Square(8*(i-1)+j)
	return GAME.Move(sqf,sqt)
end

function simul(n)
    game=Game()
    moves=Vector{Move}(undef,200)
    history=[]
    res=zeros(3)
    L=0
    sgle=0
    sgleb=true
    u=0
    for k in 1:n
    while !isOver(game)[1]
        nmoves=gen_moves(game,moves,NONEMOVE)
        @views move=rand(moves[1:nmoves])
        full=count_ones(game.board.bplayer|game.board.bopp)
        try
            @assert game.hash==getzhash(game)
        catch
            print(move,"  ",u)
        end
        if move.from==move.to && PASSMOVE!=move
            sgle+=1
            sgleb=true
        else
            sgleb=false
        end
        u=play(game,move)
        if sgleb
            full2=count_ones(game.board.bplayer|game.board.bopp)
            try @assert full+1==full2
            catch
                return game,move
            end
        end
        push!(history,(move,u))
    end
    f,r=isOver(game)
    L+=game.round
    res[r+2]+=1
    while !isempty(history)
        try
            @assert game.hash==getzhash(game)
        catch
            print(move,"  ",u)
        end
        undo(game,pop!(history)...)
    end
    game=Game()
    end
    return L/n,res/n
end


function simulraw()
    game=Game()
    moves=Vector{Move}(undef,200)
    history=Tuple{Move,Bitboard}[]
    sizehint!(history,200)
    while !isOver(game)[1]
        nmoves=gen_moves(game,moves,NONEMOVE)
        @views move=rand(moves[1:nmoves])

        u=play(game,move)
        push!(history,(move,u))
    end

    while !isempty(history)
        undo(game,pop!(history)...)
    end
end
function fen(board,player,round,uai=false)
	fen=""
	if player==1
		ps=uai ? "x" : "P"
		os=uai ? "o" : "p"
	else
		os=uai ? "x" : "P"
		ps=uai ? "o" : "p"
	end
	for i in 0:6
		cpt=0
		line=""
		for j in 0:6
			ind=Square(8*i+j)
			if get(board.bplayer,ind)!=0
				cpt=cpt>0 ? "$cpt" : ""

					line=ps*cpt*line
					cpt=0
			elseif get(board.bopp,ind)!=0
				cpt=cpt>0 ? "$cpt" : ""

				line=os*cpt*line

				cpt=0
			else
				cpt+=1
			end
		end
		cpt=cpt>0 ? "$cpt" : ""
		line=cpt*line
		cpt=0
		if i>0
			fen=line*"/"*fen
		else
			fen=line
		end
	end
	if player==1
		if uai
			player=" x "
		else
			player=" w "
		end
	else
		if uai
			player=" o "
		else
			player=" b "
		end
	end
	cw=1+div(round,2)
	cb=round-cw+1
	fen=fen*player*"$cb $cw"
end

fen(game::Game)=fen(game.board,game.player,game.round,true)

function gameFromFen(fen)
	fenboard=split(fen," ")
	boardx=Bitboard(0)
	boardo=Bitboard(0)
	line=0
	column=0
	cpt=8*line+column

	for c in reverse(fenboard[1])
		if c=='x'
			boardx=set(boardx,Square(8*line+column))
			column+=1
		elseif c=='o'
			boardo=set(boardo,Square(8*line+column))
			column+=1
		elseif c=='/'
			line+=1
			column=0
		else
			c=parse(Int,c)
			column+=c
		end
	end
	if fenboard[2]=="x"
		bplayer=boardx
		bopp=boardo
		player=1
	else
		bplayer=boardo
		bopp=boardx
		player=-1
	end
	round=parse(Int,fenboard[3])+parse(Int,fenboard[4])-1
	return Game(Board(bplayer,bopp),player,round,rand(UInt))
end

end
