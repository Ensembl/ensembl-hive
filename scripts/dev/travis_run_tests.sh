#!/bin/bash
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2022] EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


export TEST_AUTHOR=$USER

COVERALLS="false"

if [ "$PERLBREW_PERL" = '5.14' ]; then
    echo "Testing with Coveralls"
    COVERALLS="true"
fi

echo "Running test suite"
if [ "$COVERALLS" = 'true' ]; then
  PERL5OPT="-MDevel::Cover=+ignore,deps,+ignore,/usr/bin/psql,+ignore,/home/travis/perl5,-db,$PWD/cover_db/" prove -rv t
else
  prove -r t
fi
rt=$?

(cd wrappers/python3; python3 -m unittest -v eHive.process eHive.params eHive.examples.TestRunnable)
rtp=$?
(cd wrappers/java; mvn "-Dmaven.repo.local=$HOME/deps/maven" test)
rtj=$?

if [[ ($rt -eq 0) && ($rtp -eq 0) && ($rtj -eq 0) ]]; then
  if [ "$COVERALLS" = 'true' ]; then
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
else
  exit 255
fi
