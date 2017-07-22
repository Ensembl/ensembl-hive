Checklist to release a new eHive version
========================================

1. Re-draw the schema diagram manually using MySQL Workbench

2. Update the Changelog manually using a text editor

3. Review ``README.md``

4. Check all of the above into "master" branch

5. git checkout -b version/x.y

6. On the "version/x.y" branch in README.md file substitute the
   occurences of "master" in the URLs by "version/x.y" (for rawgit) and
   commit it. Do the same in docker/Dockerfile

7. git checkout master

8. On the "master" branch increment the version of
   Bio::EnsEMBL::Hive::Version to x.(y+1)

9. Merge the "version/x.y" branch ignoring the changes made in 7). Add
   the ``-s ours`` option to ``git merge``
