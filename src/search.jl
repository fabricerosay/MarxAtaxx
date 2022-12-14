module TDL
using ..GAME
using ..LoopVectorization
using ..StaticArrays
using ..JLD2
const N=4
function sq_array()
    sqa=Vector{GAME.Square}()
    d=Dict{GAME.Square,Int}()
    cpt=1
    for sq in GAME.Bitboard(0x7f7f7f7f7f7f7f)
        push!(sqa,sq)
        d[sq]=cpt
        cpt+=1
    end
    reshape(sqa,(7,7)),d
end

const SQA,DSQA=sq_array()

function sym_(b)
    c=similar(b)
    for i in 1:7
        for j in 1:7
            c[i,j]=b[8-i,j]
        end
    end
    c
end

function rot(sq,k)
    ind=DSQA[sq]
    return rotr90(SQA,k)[ind]
end

function sym(sq)
    ind=DSQA[sq]
    return sym_(SQA)[ind]
end



mutable struct TupleEval{T}

    weights::T
	pos::MVector{64,Int32}
	indices::MVector{8*N,Int32}
	local_weights::MVector{8*N,Float32}
end

TupleEval(weights)=TupleEval(weights,MVector{64}(zeros(Int32,64)),MVector{8*N}(zeros(Int32,8*N)),MVector{8*N}(zeros(Float32,8*N)))

function squares4x3()
    f1=SQA[[1,2,3,8,9,10,15,16,17,22,23,24]]
    f2=SQA[[3,4,5,10,11,12,17,18,19,24,25,26]]
    f3=SQA[[17,18,19,24,25,26,31,32,33,38,39,40]]

    feature1=Vector{typeof(tuple(f1...))}()
    feature2=Vector{typeof(tuple(f1...))}()
    feature3=Vector{typeof(tuple(f1...))}()
    for k in 0:3
        push!(feature1,tuple(map(x->rot(x,k),f1)...))
        push!(feature2,tuple(map(x->rot(x,k),f2)...))
        push!(feature3,tuple(map(x->rot(x,k),f3)...))
        push!(feature1,tuple(map(sym,map(x->rot(x,k),f1))...))
        push!(feature2,tuple(map(sym,map(x->rot(x,k),f2))...))
        push!(feature3,tuple(map(sym,map(x->rot(x,k),f3))...))
    end
    reduce(vcat,[feature1,feature2,feature3])
end



function squares4x4()
    f1=SQA[[1,2,3,8,9,10,15,16,17,22,23,24]]
    f2=SQA[[3,4,5,10,11,12,17,18,19,24,25,26]]
    f3=SQA[[17,18,19,24,25,26,31,32,33,38,39,40]]
	f4=SQA[[9,10,11,16,17,18,23,24,25,30,31,32]]
    feature1=Vector{typeof(tuple(f1...))}()
    feature2=Vector{typeof(tuple(f1...))}()
    feature3=Vector{typeof(tuple(f1...))}()
	feature4=Vector{typeof(tuple(f1...))}()
    for k in 0:3
        push!(feature1,tuple(map(x->rot(x,k),f1)...))
        push!(feature2,tuple(map(x->rot(x,k),f2)...))
        push!(feature3,tuple(map(x->rot(x,k),f3)...))
		push!(feature4,tuple(map(x->rot(x,k),f4)...))
        push!(feature4,tuple(map(sym,map(x->rot(x,k),f4))...))
        push!(feature1,tuple(map(sym,map(x->rot(x,k),f1))...))
        push!(feature2,tuple(map(sym,map(x->rot(x,k),f2))...))
        push!(feature3,tuple(map(sym,map(x->rot(x,k),f3))...))
    end
    reduce(vcat,[feature1,feature2,feature3,feature4])
end

const Features=squares4x4()

function init_table_square_feature(N)
    an=zeros(Int32,N*8,64)
    for (k,f) in enumerate(Features)
        for (j,sq) in enumerate(f)
            an[k,sq.sq+1]=3^(j-1)
        end
    end
    MMatrix{N*8,64}(an)

end

const Correspondence=init_table_square_feature(4)


@inbounds function mygemmavx!(C, A, B)
		  @turbo for m ??? axes(A,1)
			  Cm = zero(eltype(B))
			  for k ??? axes(A,2)
				  Cm += A[m,k] * B[k]
			  end
			  C[m] = Cm
		  end
		  C
	  end

@inbounds function _get_features(C,bplayer,bopp)
	for k in eachindex(C)
		C[k]=bplayer>>(k-1)&UInt32(1)+UInt32(2)*(bopp>>(k-1)&UInt32(1))
	end
end

function get_features(C,pos)
	_get_features(C,pos.board.bplayer.data,pos.board.bopp.data)
end

function (m::TupleEval)(pos)
	get_features(m.pos,pos)
	mygemmavx!(m.indices,Correspondence,m.pos)
	@turbo for k ??? axes(m.indices,1)
		m.local_weights[k]=m.weights[m.indices[k]+1,(k-1)>>3+1]
	end
    return tanh(vreduce(+,m.local_weights))
end



struct Entry
    key::UInt
    move::GAME.??Move
    depth::UInt8
    value::Int
    flag::Int
	check::UInt
end

struct HashTable
    size::Int
    data::Vector{Entry}
end

HashTable(n)=HashTable(n,fill(Entry(0,GAME.??NONEMOVE,0,0,0,0),n))

index(tt::HashTable,key)=(key-1)%tt.size+1
HashTable()=HashTable(8388593)

function hashEntry(key,depth,value,flag)
	return key???UInt(depth)???UInt(flag)???(UInt(value+32768))
end

function hashEntry(e::Entry)
	return hashEntry(e.key,e.depth,e.value,e.flag)
end
function put(ht,key,depth,move,value,flag)

    ht.data[index(ht,key)]=Entry(key,move,depth,value,flag,hashEntry(key,depth,value,flag))
end

function retrieve(ht,key)
    entry=ht.data[index(ht,key)]
    if entry.key == key && hashEntry(entry)==entry.check
        move=entry.move
        value=entry.value
        depth=entry.depth
        flag=entry.flag
    else
        move=GAME.??NONEMOVE
        value=0
        depth=0x0
        flag=0x0
    end
    return move,value,flag,depth
end

struct TC
    finish::Float64
end

function TCstart(t)
	if t>=0
    	st=time()
	else
		st=0
	end
    return TC(st+t)
end

function over(tc::TC)
    return time()>=tc.finish && tc.finish>=0
end


mutable struct Stack
    pv::Array{GAME.??Move,2}
    tt::HashTable
	nodes::Int
end

Stack(n)=Stack(fill(GAME.??NONEMOVE,n,n+1),HashTable(),0)

function init!(stack,full=false)
    fill!(stack.pv,GAME.??NONEMOVE)

	nodes=0
    if full
        fill!(stack.tt.data,Entry(0,GAME.??NONEMOVE,0,0,0,0))
    end
end

const CM=10000
const basemarge=round(Int,200*CM/5000)
const ??=round(Int,100*CM/5000)
const ??=[0,0,500,1000,1500,1500,1500,1000,500,0,0] ### tuned for weights 156000 et CM=10000
const MARG=[0,basemarge,2*basemarge,3*basemarge,4*basemarge]
function init_reduction_table()
    lmrtable = zeros(Int, (64, 200))
    for depth in 1:64
        for played in 1:200
            @inbounds lmrtable[depth, played] = floor(Int, 0.6 + log(depth) * log(played)+played/8)
        end
    end
    lmrtable
end
struct PARMPC
	a
	b
	??
end

get_player_index(game)=game.player==1 ? 1 : 2

PATH=@__DIR__




const MPCP=JLD2.load(PATH*"/p04.jld2")["p04"]
const MPCPG=JLD2.load(PATH*"/p_ij.jld2")["p_ij"]
const Depth=[1 2 1 2 3 4 3 4 5 6 5 6 7 8;
			 0 0 0 0 0 0 5 6 7 8 7 8 9 10]
const Reduction=init_reduction_table()




@inbounds function ab(game,eval,??,??,depth,ply,moves,stack,tc,mpc=true)

    if over(tc)
        return 0
    end
	stack.nodes+=1
    f,r=GAME.isOver(game)
    if f
        return  10000*r*game.player
    end
	mcp=mcap(game)
    if depth<=0 || ply>64
        return  round(Int,clamp(eval(game)*CM,-9999,9999))
    end

    move,value,flag,d=retrieve(stack.tt,game.hash)

    if flag==2 && d>=depth
        ??=max(??,value)
        static_eval=value
        if ??>=??
            return ??
        end
    elseif flag==1 && d>=depth
        ??=min(??,value)
        static_eval=value
        move=GAME.??NONEMOVE
        if ??>=??
            return ??
        end
    elseif flag==3 && d>=depth
        return value
    else
        static_eval=round(Int,clamp(eval(game)*CM,-CM,CM))
    end

    ind=div(mcp+49,9)+1

	 phase=div(53-GAME.count_ones(game.board.bplayer|game.board.bopp),10)+1
	 if depth<=4
		 p=MPCP[phase][depth]
		 v=p.a*static_eval+p.b

     	if  ply>=2 &&  depth<=1 && v+1.1*p.??<??
         	return static_eval
     	end
     	if  ply>=2 && depth<=4 && v-1.1*p.??>??#MARG[depth+1]>??
         	return static_eval
     	end
	end


	 	if 3<=depth<=16 && ply>=1 && mpc
			t=1.1
			mid=(??+??)/2
			for tr in 1:2
				Depth[tr,depth-2]==0 && continue
				p=MPCPG[phase][Depth[tr,depth-2]+1,depth+1]
				if static_eval>=mid
					beta=round(Int16,clamp((??-p.b+t*p.??)/p.a,-30000,30000))
					v=ab(game,eval,beta-1,beta,Depth[tr,depth-2],ply,moves,stack,tc,true)
					if v>=beta
						return ??#
					end
				elseif static_eval<=mid
					alpha=round(Int16,clamp((??-p.b-t*p.??)/p.a,-30000,30000))
					v=ab(game,eval,alpha,alpha+1,Depth[tr,depth-2],ply,moves,stack,tc,true)
					if v<=alpha
						return ??
					end
				end
			end
		end

	baseR=1

    nmoves=GAME.??gen_moves(game,moves[ply+1],move)

    bestmove=move
    bestvalue=-100_000



    if GAME.count_ones(game.board.bplayer | game.board.bopp)==48
        baseR=-1
    end
    prev??=??

    for k in 1:nmoves

        cmove=popfirst!(moves[ply+1])


        if k>4  && depth<=1 && cmove.score[1]<=0
            empty!(moves[ply+1])
            break
        end



		R=baseR


        	if k>=2 && cmove.quiet#
            	R+=4
        	elseif  k>=2
            	R+=2
        	end



        u=GAME.play(game,cmove.move)
        v=-ab(game,eval, -??,-??,depth-R,ply+1,moves,stack,tc,mpc)
         if v>bestvalue && R>1
             v=-ab(game,eval,-??,-??,depth-1,ply+1,moves,stack,tc,mpc)
         end
        GAME.undo(game,cmove.move,u)

        if v>bestvalue
            bestvalue=v
            bestmove=cmove
            if v>??

                ??=v
                if ??>=??
                    empty!(moves[ply+1])
                    break
                end
            end
        end
    end

    	if bestvalue<=prev??
        	flag=1
    	elseif bestvalue>=??
        	flag=2

    	else
        	flag=3
    	end

	if !over(tc)
    	put(stack.tt,game.hash,depth,bestmove,bestvalue,flag)
	end
    return bestvalue
end

mutable struct ??Thread
	ev
	stack
	moves
	offset
end

function init!(th::??Thread,full=false)
	init!(th.stack,full)
end



struct ??ThreadPool
	lck::ReentrantLock
	pool::Vector{??Thread}
end

function init!(pool::??ThreadPool,full=false)
	for (k,th) in enumerate(pool.pool)
		init!(th,full&&k==1)
		th.offset=trailing_zeros(k)
	end
end

function ??ThreadPool(ev,n,maxdepth=64)
	pool=??Thread[]
	ht=HashTable()
	for k in 1:n
		stack=Stack(fill(GAME.??NONEMOVE,maxdepth,maxdepth+1),ht,0)
		push!(pool,??Thread(deepcopy(ev),stack,[GAME.??Moves() for j in 1:maxdepth+1],trailing_zeros(k)))
	end
	return ??ThreadPool(ReentrantLock(),pool)
end

mutable struct SearchResult
	move::GAME.??Move
	value::Int16
	depth::Int8
	searchid::Int8
end

function search(game,t,pool,result,maxdepth=64)

	tc=TCstart(t)
	@Threads.threads for k in 1:length(pool.pool)
		search_thread(pool.pool[k],deepcopy(game),tc,result,pool.lck,maxdepth,length(pool.pool))
	end
	return result.move.move,result.value,result.depth
end


function search_thread(thread,game,tc,result,lck,maxdepth,nthread)
	while true

		timeiter=time()
		d=result.depth+thread.offset+1
		d>maxdepth && break
		v=ab(game,thread.ev,-30_000,30_000,d,0,thread.moves,thread.stack,tc,true)
		timeiter=time()-timeiter
		timeleft=tc.finish-time()
		over(tc) && break
		lock(lck)
		try

			if d>result.depth
				bestmove,v,flag,depth=retrieve(thread.stack.tt,game.hash)
				if flag==3 && depth>=d
					result.move=bestmove
					result.value=v
					result.depth=d
				end
			end
			result.searchid=result.searchid%nthread+1
			thread.offset=trailing_zeros(result.searchid)
		finally
			unlock(lck)
		end
	end
end
function ab_iterative(game,t,ev,stack=nothing,moves=nothing;maxdepth=64)

    if moves==nothing
        moves=[GAME.??Moves() for k in 1:maxdepth+1]
    end
    if stack==nothing
        stack=Stack(maxdepth+1)
    end
    local bestmove=GAME.NONEMOVE
    local bestvalue=0
    v=-32768
    depth=0
    tc=TCstart(t)
    tcs=TCstart(1)
    v=ab(game,ev,-Inf,Inf,1,0,moves,stack,tcs,false)
    bestvalue=v
    PV=stack.pv

    bestmove,_,_,_=retrieve(stack.tt,game.hash)#stack.pv[1,1].move
    depth=1
	d=2
    while d<=maxdepth
        timeiter=time()

        v=ab(game,ev,-Inf,Inf,d,0,moves,stack,tc,true)
        timeiter=time()-timeiter
        timeleft=tc.finish-time()
        over(tc) && break
        bestvalue=v
		bestmove,v,_,_=retrieve(stack.tt,game.hash)#stack.pv[1,1].move
		@assert bestvalue==v
		depth=d
		d+=d%2+1
        #(timeleft<=2*timeiter) && break
    end
    return bestmove.move,bestvalue,depth
end

mcap(game)=GAME.count_ones(game.board.bplayer)-GAME.count_ones(game.board.bopp)




end
