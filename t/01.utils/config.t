
use strict;
use warnings;

use Bio::EnsEMBL::Hive::Utils::Test qw(spurt);

use File::Spec::Functions qw{catdir};
use File::Temp qw{tempdir};
use Test::More;
use Data::Dumper;

BEGIN {
    use_ok( 'Bio::EnsEMBL::Hive::Utils::Config' );
    
}
#########################


my @config_files = Bio::EnsEMBL::Hive::Utils::Config->default_config_files();
# diag "@config_files"; 

cmp_ok(@config_files, '>', 0, 'at least one got returned');
cmp_ok(@config_files, '<', 3, '1 or 2');

my $config = bless {_config_hash => {}}, 'Bio::EnsEMBL::Hive::Utils::Config';

my $dir = tempdir CLEANUP => 1;
my $json = catdir $dir, 'test.json';
spurt <<EOF, $json;
{
    "Meadow" : {
        "OPENLAVA"  : {
	    "TotalRunningWorkersMax" : 1000,
	    "omics" : {
		"SubmissionOptions" : "-q special-branch"
	    }
	}
    },
}
EOF

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
