.. _ehive-installation-setup:

eHive installation and setup
============================

eHive dependencies
------------------

eHive system depends on the following components that you may need to
download and install first:

#. Perl 5.10 `or higher <http://www.perl.org/get.html>`__
#. A database engine of your choice. eHive keeps its state in a
   database, so you will need

   #. a server installed on the machine where you want to maintain the
      state of your pipeline(s) and
   #. clients installed on the machines where the jobs are to be
      executed.

   At the moment, the following database options are available:

   -  MySQL 5.1 `or higher <https://dev.mysql.com/downloads/>`__.
      **Warning:** eHive is not compatible with MysQL 5.6.20 but is
      with versions 5.6.16 and 5.6.23. We suggest avoiding the
      5.6.[17-22] interval
   -  SQLite 3.6 `or higher <http://www.sqlite.org/download.html>`__
   -  PostgreSQL 9.2 `or higher <https://www.postgresql.org/download/>`__

   The database has to be accessible from all the machines you want to
   run pipelines on, so make sure the SQLite database is on a shared
   filesystem or the MySQL/PostgreSQL database is on a shared network.

#. GraphViz visualization package (includes "dot" executable and
   libraries used by the Perl dependencies).

   #. Check in your terminal that you have "dot" installed
   #. If not, visit `graphviz.org <http://graphviz.org/>`__ to download
      it

#. GnuPlot visualization package (includes "gnuplot" executable and
   libraries used by the Perl dependencies).

   #. Check in your terminal that you have "gnuplot" installed
   #. If not, visit `gnuplot.info <http://www.gnuplot.info/>`__ to
      download it

#. cpanm -- a handy utility to recursively install Perl dependencies.

   #. Check in your terminal that you have "cpanm" installed
   #. If not, visit `cpanmin.us <https://cpanmin.us>`__ to download it
      (just read and follow the instructions in the header of the
      script)


Installing eHive code
---------------------

Check out the repository by cloning it from GitHub:
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

All eHive pipelines will require the ensembl-hive repository, which can
be found on `GitHub <https://github.com/Ensembl/ensembl-hive>`__. As
such it is assumed that `Git <https://git-scm.com/>`__ is installed on
your system, if not follow the instructions
`here <https://help.github.com/articles/set-up-git/>`__

To download the repository, move to a suitable directory and run the
following on the command line:

::

            git clone https://github.com/Ensembl/ensembl-hive.git

This will create ensembl-hive directory with all the code and
documentation.  If you cd into the ensembl-hive directory and do an ls you
should see something like the following:

::

            ls
            Changelog  docs  hive_config.json  modules  README.md  scripts  sql  t

The major directories here are:

:modules:
    This contains all the eHive modules, which are written in Perl
:scripts:
    Has various scripts that are key to initialising, running and
    debugging the pipeline
:sql:
    Contains sql used to build a standard pipeline database


Use cpanm to recursively install the Perl dependencies declared in ensembl-hive/cpanfile
----------------------------------------------------------------------------------------

::

        cd ensembl-hive
        cpanm --installdeps --with-recommends .

If installation of either DBD::mysql or DBD::Pg fails, check that the
corresponding database system (MySQL or PostgreSQL) was installed
correctly.


Optional configuration of the system:
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

You may find it convenient (although it is not necessary) to add
"ensembl-hive/scripts" to your ``$PATH`` variable to make it easier to
run beekeeper.pl and other useful Hive scripts.

-  *using bash syntax:*

   ::

               export PATH=$PATH:$ENSEMBL_CVS_ROOT_DIR/ensembl-hive/scripts

-  *using [t]csh syntax:*

   ::

               set path = ( $path ${ENSEMBL_CVS_ROOT_DIR}/ensembl-hive/scripts )

Also, if you are developing the code and not just running ready
pipelines, you may find it convenient to add "ensembl-hive/modules" to
your ``$PERL5LIB`` variable.

-  *using bash syntax:*

   ::

               export PERL5LIB=${PERL5LIB}:${ENSEMBL_CVS_ROOT_DIR}/ensembl-hive/modules

-  *using [t]csh syntax:*

   ::

               setenv PERL5LIB  ${PERL5LIB}:${ENSEMBL_CVS_ROOT_DIR}/ensembl-hive/modules

The above commands can be added to your ~/.bashrc or ~/.bash_profile, or
~/.cshrc or ~/.tcshrc configuration file to be loaded at startup.
