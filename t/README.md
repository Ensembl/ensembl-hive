# Guidelines

* t/01.utils/ is for modules Bio::EnsEMBL::Hive::Utils
* t/02.api/ is to test the objects and their adaptors
* t/03.scripts/ is for the main scripts.
* t/04.meadow/ is for the meadows (Valley, Meadow and its subclasses)
* t/05.runnabledb/ is for the Runnables shipped by default
* t/10.pipeconfig/ is to test the example pipelines
* t/ is for general tests

Run the test-suite with `prove`, e.g. `prove -rv t/`.
`t/perlcritic.t` only runs when the `TEST_AUTHOR` environment variable is set
(following Perl guidelines).

# Database configuration

Some tests require databases. These can be configured with the
`EHIVE_TEST_PIPELINE_URLS` environment variable, e.g.
```export EHIVE_TEST_PIPELINE_URLS='mysql://travis@127.0.0.1/ pgsql://postgres@127.0.0.1/ sqlite:///'```
to only define define servers. Databases are by default named
`${USER}_ehive_test(_${TAGNAME})` where `$TAGNAME` is an optional suffix
added by tests that require multiple databases at once.

If database names are given, e.g.
```export EHIVE_TEST_PIPELINE_URLS='mysql://travis@127.0.0.1/my_database pgsql://postgres@127.0.0.1/my_database sqlite:////path/to/my_database'```
the database will be named `my_database(_${TAGNAME})`

