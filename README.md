# MarxAtaxx

An Ataxx engine compliant to UAI.

To use it, you must have julia installed (works with julia 1.8.0).
Git clone the repository 
Then the first time you have to type julia --project=/path to MarxAtaxx/  
this will launch julia activating the project. 
Then hit ] and type instantiate (the repl should have turned blue) this will launch the download of dependencies.


julia --project=/path to MarxAtaxx/ --check-bounds=no -O3 --threads=4 /path to MarxAtaxx/src/engine.jl --workers=4

--threads=y set the numbers of threads used by julia (=auto  will launch as many threads as cores)
--workers=x will use x threads for the search(lazy SMP) preferably y>=x
            
