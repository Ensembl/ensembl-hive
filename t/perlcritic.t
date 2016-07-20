# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016] EMBL-European Bioinformatics Institute
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
use Test::Warnings;

use Cwd            ();
use File::Basename ();
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );


if ( not $ENV{TEST_AUTHOR} ) {
  my $msg = 'Author test. Set $ENV{TEST_AUTHOR} to a true value to run.';
  plan( skip_all => $msg );
}

eval {
  require Test::Perl::Critic;
  require Perl::Critic::Utils;
};
if($@) {
  plan( skip_all => 'Test::Perl::Critic required.' );
  note $@;
}

# Configure critic
Test::Perl::Critic->import(-profile => File::Spec->catfile($ENV{EHIVE_ROOT_DIR}, 'perlcriticrc'), -severity => 5, -verbose => 8);

# Needs to run in its own subtest because all_critic_ok defines a plan
# based on the number of files while Test::Warnings adds its own test,
# leading done_testing() to complain the number of tests mismatch.
subtest 'all_critic_ok()', sub {
    all_critic_ok($ENV{EHIVE_ROOT_DIR});
};

done_testing();
