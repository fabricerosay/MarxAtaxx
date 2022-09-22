# MarxAtaxx

An Ataxx engine compliant to UAI.

To use it, you must have julia installed (works with julia 1.8.0).
Git clone the repository 
Then the first time you have to type julia --project=/path to MarxAtaxx/  
this will launch julia activating the project. 
Then hit ] and type instantiate (the repl should have turned blue) this will launch the download of dependencies.

<pre>               <font color="#26A269"><b>_</b></font>
   <font color="#12488B"><b>_</b></font>       _ <font color="#C01C28"><b>_</b></font><font color="#26A269"><b>(_)</b></font><font color="#A347BA"><b>_</b></font>     |  Documentation: https://docs.julialang.org
  <font color="#12488B"><b>(_)</b></font>     | <font color="#C01C28"><b>(_)</b></font> <font color="#A347BA"><b>(_)</b></font>    |
   _ _   _| |_  __ _   |  Type &quot;?&quot; for help, &quot;]?&quot; for Pkg help.
  | | | | | | |/ _` |  |
  | | |_| | | | (_| |  |  Version 1.8.1 (2022-09-06)
 _/ |\__&apos;_|_|_|\__&apos;_|  |  Official https://julialang.org/ release
|__/                   |

<font color="#12488B"><b>(@v1.8) pkg&gt; </b></font>instantiate



</pre>

julia --project=/path to MarxAtaxx/ --check-bounds=no -O3 --threads=4 /path to MarxAtaxx/src/engine.jl --workers=4

--threads=y set the numbers of threads used by julia (=auto  will launch as many threads as cores)
--workers=x will use x threads for the search(lazy SMP) preferably y>=x
            
