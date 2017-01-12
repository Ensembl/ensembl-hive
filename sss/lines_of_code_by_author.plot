set terminal png transparent size 640,240
set size 1.0,1.0

set terminal png transparent size 640,480
set output 'lines_of_code_by_author.png'
set key left top
set xdata time
set timefmt "%s"
set format x "%Y-%m-%d"
set grid y
set ylabel "Lines"
set xtics rotate
set bmargin 6
plot 'lines_of_code_by_author.dat' using 1:2 title "Leo Gordon" w lines, 'lines_of_code_by_author.dat' using 1:3 title "Matthieu Muffato" w lines, 'lines_of_code_by_author.dat' using 1:4 title "Jessica Severin" w lines, 'lines_of_code_by_author.dat' using 1:5 title "ens-bwalts" w lines, 'lines_of_code_by_author.dat' using 1:6 title "Brandon Walts" w lines, 'lines_of_code_by_author.dat' using 1:7 title "Javier Herrero" w lines, 'lines_of_code_by_author.dat' using 1:8 title "Roy Storey" w lines, 'lines_of_code_by_author.dat' using 1:9 title "Dan Staines" w lines, 'lines_of_code_by_author.dat' using 1:10 title "Albert Vilella" w lines, 'lines_of_code_by_author.dat' using 1:11 title "Abel Ureta-Vidal" w lines, 'lines_of_code_by_author.dat' using 1:12 title "Miguel Pignatelli" w lines, 'lines_of_code_by_author.dat' using 1:13 title "Andy Yates" w lines, 'lines_of_code_by_author.dat' using 1:14 title "Will Spooner" w lines, 'lines_of_code_by_author.dat' using 1:15 title "Kathryn Beal" w lines, 'lines_of_code_by_author.dat' using 1:16 title "Ian Longden" w lines, 'lines_of_code_by_author.dat' using 1:17 title "jb16" w lines, 'lines_of_code_by_author.dat' using 1:18 title "emepyc" w lines, 'lines_of_code_by_author.dat' using 1:19 title "Mateus Patricio" w lines, 'lines_of_code_by_author.dat' using 1:20 title "Kevin Howe" w lines, 'lines_of_code_by_author.dat' using 1:21 title "Jan-Hinnerk Vogel" w lines
