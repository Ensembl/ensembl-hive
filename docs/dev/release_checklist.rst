Checklist to release a new eHive version
========================================

1. Update the Changelog manually using a text editor

2. Review ``README.md``

3. Check all of the above into "master" branch

In ensembl-hive and all meadows (but not guiHive):

4. git checkout -b version/x.y

5. On the "version/x.y" branch in README.md file substitute the
   occurences of "master" in the URLs by "version/x.y"  and
   commit it. Do the same in docker/Dockerfile and
   docs/rtd_upgrade.sh

6. git checkout master

7. On the "master" branch increment the version of
   Bio::EnsEMBL::Hive::Version to x.(y+1)

8. Merge the "version/x.y" branch ignoring the changes made in 7). Add
   the ``-s ours`` option to ``git merge``

9. Update default branch on GitHub to point to version/x.y
