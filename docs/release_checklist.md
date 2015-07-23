
Checklist to release a new eHive version
========================================

1. Re-draw the schema diagram manually using MySQL Workbench

2. Update the Changelog manually using a text editor

3. Review README.md, install.html and running_eHive_pipelines.html

4. Regenerate docs/hive_schema.html, docs/scripts and docs/doxygen by running make_docs.pl

5. Check all of the above into "master" branch

6. On the "master" branch in README.md file substitute the occurences of "HEAD" in the URLs by "version/x.y" (for rawgit) and commit it.

7. "git branch version/x.y" at this commit (but do not switch to this branch)

8. On the "master" branch revert this commit to retain the "HEAD" references in README.md on "master"

9. On the "master" branch increment the version of Bio::EnsEMBL::Hive::Version to x.(y+1)

