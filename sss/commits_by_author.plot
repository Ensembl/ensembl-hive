set terminal png transparent size 640,240
set size 1.0,1.0

set terminal png transparent size 640,480
set output 'commits_by_author.png'
set key left top
set xdata time
set timefmt "%s"
set format x "%Y-%m-%d"
set grid y
set ylabel "Commits"
set xtics rotate
set bmargin 6
plot 'commits_by_author.dat' using 1:2 title "Leo Gordon" w lines, 'commits_by_author.dat' using 1:3 title "Matthieu Muffato" w lines, 'commits_by_author.dat' using 1:4 title "Jessica Severin" w lines, 'commits_by_author.dat' using 1:5 title "ens-bwalts" w lines, 'commits_by_author.dat' using 1:6 title "Brandon Walts" w lines, 'commits_by_author.dat' using 1:7 title "Javier Herrero" w lines, 'commits_by_author.dat' using 1:8 title "Roy Storey" w lines, 'commits_by_author.dat' using 1:9 title "Dan Staines" w lines, 'commits_by_author.dat' using 1:10 title "Albert Vilella" w lines, 'commits_by_author.dat' using 1:11 title "Abel Ureta-Vidal" w lines, 'commits_by_author.dat' using 1:12 title "Miguel Pignatelli" w lines, 'commits_by_author.dat' using 1:13 title "Andy Yates" w lines, 'commits_by_author.dat' using 1:14 title "Will Spooner" w lines, 'commits_by_author.dat' using 1:15 title "Kathryn Beal" w lines, 'commits_by_author.dat' using 1:16 title "Ian Longden" w lines, 'commits_by_author.dat' using 1:17 title "jb16" w lines, 'commits_by_author.dat' using 1:18 title "emepyc" w lines, 'commits_by_author.dat' using 1:19 title "Mateus Patricio" w lines, 'commits_by_author.dat' using 1:20 title "Kevin Howe" w lines, 'commits_by_author.dat' using 1:21 title "Jan-Hinnerk Vogel" w lines
