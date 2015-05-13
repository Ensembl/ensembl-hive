#!/bin/bash
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
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


export PERL5LIB=$PWD/bioperl-live-bioperl-release-1-2-3:$PWD/modules

    # for the t/10.pipeconfig/longmult.t test
export EHIVE_TEST_PIPELINE_URLS='mysql://travis@127.0.0.1/ehive_test_pipeline_db pgsql://postgres@127.0.0.1/ehive_test_pipeline_db'

echo "Running test suite"
if [ "$COVERALLS" = 'true' ]; then
  PERL5OPT="-MDevel::Cover=+ignore,bioperl,+ignore,ensembl-test,-db,$PWD/cover_db/" perl $PWD/scripts/all_tests.pl -verbose t
else
  perl $PWD/scripts/all_tests.pl t
fi

rt=$?
if [ $rt -eq 0 ]; then
  if [ "$COVERALLS" = 'true' ]; then
    echo "Running Devel::Cover coveralls report"
    cover --nosummary -report coveralls
  fi
  exit $?
else
  exit $rt
fi
