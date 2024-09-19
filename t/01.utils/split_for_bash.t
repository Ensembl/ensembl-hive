#!/usr/bin/env perl

# See the NOTICE file distributed with this work for additional information
# regarding copyright ownership.
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


use strict;
use warnings;

use Test::More;

BEGIN {
    use_ok( 'Bio::EnsEMBL::Hive::Utils', 'split_for_bash' );
}

#########################

# NB: because split_for_bash() returns an ARRAY (not an ARRAYREF), we have to capture the returned value into a pair of [ ]


is_deeply( [ split_for_bash('alpha  beta gamma') ], ['alpha', 'beta', 'gamma'], 'regular by-word split');

is_deeply( [ split_for_bash('alpha "beta gamma " delta ') ], ['alpha', 'beta gamma ', 'delta'], 'some enclosed spaces');

is_deeply( [ split_for_bash(q{alpha -m'beta gamma' -R"select['hello world'] and rusage['hello again']"}) ], ['alpha', '-mbeta gamma', q{-Rselect['hello world'] and rusage['hello again']}], 'remove only the external pair of quotes');

done_testing();
