
Checklist to release a new eHive version
========================================

1. Update doxygen

  Simply run doxygen with the ensembl-hive\_doxygen.conf ?

2. Update the script documentation

  1. Regenerate the HTML files from the PODs

    ````
rm docs/scripts/*
cd scripts/
for i in *.pl
do
    pod2html --noindex --title=$i $i > ../docs/scripts/`echo $i | sed 's/pl$/html/'`
done
    ````

  2. Update the list of scripts in index.html

3. Update the schema diagram

4. Compile and summarize the change-log

5. Update the version number in README.md (for rawgit)

6. Review the installation guide and README.md 

