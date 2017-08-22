Build the documentation locally
===============================

Python environment
------------------

The manual is written in RestructuredText_ and is built with Sphinx_. It
relies on a number of Python modules.

Locally, install these two requirements file:

* https://github.com/Ensembl/python-requirements/blob/master/readthedocs/requirements.txt
* https://github.com/Ensembl/ensembl-hive/blob/master/requirements.txt

On the EBI farm, those are already installed and you only need to activate
the `ehive_sphinx` environment with ``pyenv local ehive_sphinx``.

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


.. _RestructuredText: http://docutils.sourceforge.net/rst.html
.. _Sphinx: http://www.sphinx-doc.org/en/stable/
.. _Doxygen: http://www.stack.nl/~dimitri/doxygen/
.. _Graphviz: http://www.graphviz.org/
.. _Pandoc: https://pandoc.org/
.. _Core API: https://github.com/Ensembl/ensembl
