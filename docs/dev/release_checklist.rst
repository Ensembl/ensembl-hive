Checklist to release a new eHive version
========================================

1. Update the Changelog manually using a text editor

2. Review ``README.md``

3. Check all of the above into "main" branch

In ensembl-hive and all meadows (but not guiHive):

4. git checkout -b version/x.y

5. On the "version/x.y" branch in README.md file substitute the
   occurences of "main" in the URLs by "version/x.y"  and
   commit it. Do the same in docker/Dockerfile and
   docs/rtd_upgrade.sh

6. git checkout main

7. On the "main" branch increment the version of
   Bio::EnsEMBL::Hive::Version to x.(y+1)

8. Merge the "version/x.y" branch ignoring the changes made in 7). Add
   the ``-s ours`` option to ``git merge``

9. Update default branch on GitHub to point to version/x.y at
   https://github.com/Ensembl/ensembl-hive/settings/branches

10. On Travis https://travis-ci.org/Ensembl/ensembl-hive/settings add a
    daily build of the new branch

11. On the Docker hub
    https://hub.docker.com/r/ensemblorg/ensembl-hive/~/settings/automated-builds/
    add an automatic build of the new branch

12. On ReadTheDocs https://readthedocs.org/dashboard/ensembl-hive/versions/
    add the new version and set it as default

13. On Coveralls https://coveralls.io/github/Ensembl/ensembl-hive/settings
    click on "sync" to synchronize the list of branches (and the default
    one) with Github.

14. On Codecov https://codecov.io/gh/Ensembl/ensembl-hive/settings set the
    new default branch.

Other repos
===========

Do the same for all the other repos (meadow plugins):
https://github.com/search?q=topic%3Aehive+org%3AEnsembl&type=Repositories

