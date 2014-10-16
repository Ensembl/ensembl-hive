
Checklist to release a new eHive version
========================================

1. Re-draw the schema diagram manually using MySQL Workbench

2. Update the Changelog manually using a text editor

3. Review README.md, install.html and running_eHive_pipelines.html,
    change the version number in README.md for the future version (for rawgit)

4. Regenerate docs/hive_schema.html, docs/scripts and docs/doxygen by running make_docs.pl

5. Regenerate docs/scripts/index.html if you have 'tree' installed

6. Check all of the above into master

7. Create a new version/x.y branch

8. After branching make sure *master* will have a new Bio::EnsEMBL::Hive::Version .

