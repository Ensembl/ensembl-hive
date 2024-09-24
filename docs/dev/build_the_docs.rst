Build the documentation
=======================

Python environment
------------------

The manual is written in RestructuredText_ and is built with Sphinx_. It
relies on a number of Python modules.

Locally, install Python dependencies using these two requirements files:

* https://github.com/Ensembl/python-requirements/blob/master/readthedocs/requirements.txt
* https://github.com/Ensembl/ensembl-hive/blob/version/2.6/docs/requirements.txt

Other dependencies
------------------

* Doxygen_ to build the API documentation
* a checkout of the Ensembl `Core API`_, with ``PERL5LIB`` set, to enable
  the Perl Doxygen filter
* Graphviz_ to generate the database diagrams
* Pandoc_ to convert the POD HTML to RestructuredText

Build process
-------------

Once you have all the above dependencies, go to ``ensembl-hive/docs``,
run ``make html`` and open ``_build/html/index.html``.

``make clean`` will cleanup all of ``_build/`` except the Doxygen
documentation, since it takes quite a lot of time to generate. Run ``make
cleaner`` to clean it up as well.

ReadTheDocs
-----------

The ReadTheDocs build works on Docker containers that are reused across
builds from potentially several projects.

1. We extend the environment by fake-installing extra packages. This is
   done by downloading some .deb archives from the Ubuntu repository,
   extracting them in a local directory and setting up the ``PATH`` and
   ``PERL5LIB`` environment variables accordingly.

   This allows us to run all the eHive scripts directly on the ReadTheDocs
   infrastructure, including :ref:`init_pipeline.pl <script-init_pipeline>` or :ref:`generate_graph.pl <script-generate_graph>`

2. ReadTheDocs runs off the main project directory
   ``$PROJECT_DIR/`` which
   contains:

   a. A `virtualenv` python environment under ``envs/$BRANCH_NAME``

   b. The eHive checkout under ``checkouts/$BRANCH_NAME``

   .. list-table:: Environment variables under ReadTheDocs

      * - APPDIR
        - /app
      * - BIN_PATH
        - $PROJECT_DIR/checkouts/envs/$BRANCH_NAME/bin
      * - DEBIAN_FRONTEND
        - noninteractive
      * - HOME
        - /home/docs
      * - HOSTNAME
        - build-5695180-project-72101-ensembl-hive (random name of the
          container)
      * - LANG
        - C.UTF-8
      * - OLDPWD
        - /home/docs
      * - PATH
        - $PROJECT_DIR/checkouts/envs/$BRANCH_NAME/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/docs/miniconda2/bin
      * - PWD
        - $PROJECT_DIR/checkouts/$BRANCH_NAME/docs
      * - READTHEDOCS
        - True
      * - READTHEDOCS_PROJECT
        - ensembl-hive
      * - READTHEDOCS_VERSION
        - experimental-user_manual

   The following commands are run, according to the build log, but
   presumably other things may be run in between!

   ::

       python2.7 -mvirtualenv --no-site-packages --no-download $PROJECT_DIR/envs/$BRANCH_NAME
       python $PROJECT_DIR/envs/$BRANCH_NAME/bin/pip install --use-wheel -U --cache-dir $PROJECT_DIR/.cache/pip sphinx==1.5.3 Pygments==2.2.0 setuptools==28.8.0 docutils==0.13.1 mkdocs==0.15.0 mock==1.0.1 pillow==2.6.1 readthedocs-sphinx-ext<0.6 sphinx-rtd-theme<0.3 alabaster>=0.7,<0.8,!=0.7.5 commonmark==0.5.4 recommonmark==0.4.0
       python $PROJECT_DIR/envs/$BRANCH_NAME/bin/pip install --exists-action=w --cache-dir $PROJECT_DIR/.cache/pip -r$PROJECT_DIR/checkouts/$BRANCH_NAME/requirements.txt
       cat docs/conf.py
       python $PROJECT_DIR/envs/$BRANCH_NAME/bin/sphinx-build -T -E -b readthedocs -d _build/doctrees-readthedocs -D language=en . _build/html
       python $PROJECT_DIR/envs/$BRANCH_NAME/bin/sphinx-build -T -b json -d _build/doctrees-json -D language=en . _build/json
       python $PROJECT_DIR/envs/$BRANCH_NAME/bin/sphinx-build -T -b readthedocssinglehtmllocalmedia -d _build/doctrees-readthedocssinglehtmllocalmedia -D language=en . _build/localmedia
       python $PROJECT_DIR/envs/$BRANCH_NAME/bin/sphinx-build -b latex -D language=en -d _build/doctrees . _build/latex
       pdflatex -interaction=nonstopmode $PROJECT_DIR/checkouts/$BRANCH_NAME/docs/_build/latex/ehive_user_manual.tex
       makeindex -s python.ist ehive_user_manual.idx
       pdflatex -interaction=nonstopmode $PROJECT_DIR/checkouts/$BRANCH_NAME/docs/_build/latex/ehive_user_manual.tex
       mv -f $PROJECT_DIR/checkouts/$BRANCH_NAME/docs/_build/latex/ehive_user_manual.pdf $PROJECT_DIR/artifacts/$BRANCH_NAME/sphinx_pdf/ensembl-hive.pdf
       python $PROJECT_DIR/envs/$BRANCH_NAME/bin/sphinx-build -T -b epub -d _build/doctrees-epub -D language=en . _build/epub
       mv -f $PROJECT_DIR/checkouts/$BRANCH_NAME/docs/_build/epub/eHiveusermanual.epub $PROJECT_DIR/artifacts/$BRANCH_NAME/sphinx_epub/ensembl-hive.epub



.. _RestructuredText: http://docutils.sourceforge.net/rst.html
.. _Sphinx: http://www.sphinx-doc.org/en/stable/
.. _Doxygen: http://www.stack.nl/~dimitri/doxygen/
.. _Graphviz: http://www.graphviz.org/
.. _Pandoc: https://pandoc.org/
.. _Core API: https://github.com/Ensembl/ensembl
