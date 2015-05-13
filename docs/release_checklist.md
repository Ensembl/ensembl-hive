
Checklist to release a new eHive version
========================================

1. Re-draw the schema diagram manually using MySQL Workbench

2. Update the Changelog manually using a text editor

3. Review README.md, install.html and running_eHive_pipelines.html

4. Regenerate docs/hive_schema.html, docs/scripts and docs/doxygen by running make_docs.pl

5. Regenerate docs/scripts/index.html if you have 'tree' installed

6. Check all of the above into "master" branch

7. Create a new version/x.y branch

8. On the "version/x.y" branch change the version number in README.md to version/x.y (for rawgit)

9. On the "master" branch increment the version of Bio::EnsEMBL::Hive::Version to x.(y+1)

