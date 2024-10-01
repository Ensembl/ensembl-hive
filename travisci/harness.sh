#!/bin/bash

export PERL5LIB=$PERL5LIB:$ENSDIR/ensembl/modules:$TRAVIS_BUILD_DIR/modules

export TEST_AUTHOR=$USER

echo "Running test suite"
if [ "$COVERAGE" = 'true' ]; then
  PERL5OPT="-MDevel::Cover=-db,$TRAVIS_BUILD_DIR/cover_db/" prove -rv t
else
  prove -r t
fi
rt=$?

if [[ $rt -ne 0 ]]; then
   echo "Test main suite failed!"
   exit $rt
fi

(cd wrappers/python3; python3 -m unittest -v eHive.process eHive.params eHive.examples.TestRunnable)
rtp=$?

if [[ $rtp -ne 0 ]]; then
   echo "Python test failed!"
   exit $rtp
fi

if [ "$COVERAGE" = 'true' ]; then
   echo "Running Devel::Cover report"
   if [[ "$EHIVE_TEST_PIPELINE_URLS" == mysql* ]]; then
      # Coveralls only supports 1 report
      cover --nosummary -report coveralls
   fi
   cover --nosummary -report codecov
fi
# ignore any failures from coverage testing. Due to the if, can only reach this
# point if there were no test failures
exit 0
