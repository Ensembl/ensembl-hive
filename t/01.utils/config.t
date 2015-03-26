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


use strict;
use warnings;

use Cwd;
use File::Basename;
use Test::More;
use Data::Dumper;

BEGIN {
    use_ok( 'Bio::EnsEMBL::Hive::Utils::Config' );
    
}
#########################

# Need EHIVE_ROOT_DIR to access the default config file
$ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) ) );

my @config_files = Bio::EnsEMBL::Hive::Utils::Config->default_config_files();
# diag "@config_files"; 

cmp_ok(@config_files, '>', 0, 'at least one got returned');
cmp_ok(@config_files, '<', 3, '1 or 2');

my $config = bless {_config_hash => {}}, 'Bio::EnsEMBL::Hive::Utils::Config';

my $json = $ENV{EHIVE_ROOT_DIR}.'/t/test_config.json';

my $simple = $config->load_from_json($json);
isa_ok($simple, 'HASH');
ok(exists($simple->{'Meadow'}), 'exists');

my $simpler = $config->load_from_json($json . '.notexist');
is($simpler, undef, 'undef, but no death');

$config->merge($simple);
my $merged = $config->config_hash;
ok($merged, 'merged hash');


$config = Bio::EnsEMBL::Hive::Utils::Config->new();
ok($config, 'new instance');


my $content = $config->config_hash;

isa_ok($content, 'HASH');
ok(exists($content->{'Meadow'}), 'Ok you are in a forest. Forest? With Heather...');

isa_ok($content->{'Meadow'}, 'HASH');

ok(exists($content->{'Valley'}), 'alpine valley?');

isa_ok($content->{'Valley'}, 'HASH');

ok(exists($content->{'Graph'}), 'lets plot that');

isa_ok($content->{'Graph'}, 'HASH');

ok(exists($content->{'VERSION'}), 'party on');

$config->merge($simple);
my $merged_hash = $config->config_hash;
isa_ok($merged_hash, 'HASH');
ok(exists($merged_hash->{'Meadow'}{'OPENLAVA'}),                               'first level merge');
ok(exists($merged_hash->{'Meadow'}{'OPENLAVA'}{'omics'}),                      'second level merge');
ok(exists($merged_hash->{'Meadow'}{'OPENLAVA'}{'omics'}{'SubmissionOptions'}), 'third level merge');
is($merged_hash->{'Meadow'}{'OPENLAVA'}{'TotalRunningWorkersMax'}, 1000,       'data check');

my $ol_submission_opts = $config->get(qw{Meadow OPENLAVA omics SubmissionOptions});
is($ol_submission_opts, '-q special-branch', 'get() functions');

$config->set(qw{Meadow OPENLAVA TotalRunningWorkersMax}, 20);
my $ol_total = $config->get(qw{Meadow OPENLAVA TotalRunningWorkersMax});
is($ol_total, 20, 'roundtrip set() and get() function');

done_testing();
