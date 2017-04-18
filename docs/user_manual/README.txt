
# By default pandoc maps =head1 to <h1>, =head2 to <h2>, etc. I wanted to shift the headings to place the
# script name as <h1>. I'm using --base-header-level=2 to shift the levels, and --title and --standalone
# together to aadd a title

for i in *.pl
do
  pod2html --noindex --title=$i $i | pandoc --standalone --base-header-level=2 -f html -t rst -o ../docs/user_manual/appendix/scripts/`echo $i | sed 's/pl$/rst/'`
done

