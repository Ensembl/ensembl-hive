ensembl-hive/scripts $ for i in *pl; do pod2html --noindex --title=$i $i > x.html; pandoc -o ../docs/user_manual/scripts/`echo $i | sed 's/pl$/rst/'` x.html; done

