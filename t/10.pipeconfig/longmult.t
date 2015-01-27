
use strict;
use warnings;

use Test::More;
use Data::Dumper;
use File::Temp qw{tempdir};

use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline runWorker);


my $dir = tempdir CLEANUP => 1;
chdir $dir;

foreach my $long_mult_version (qw(LongMult_conf LongMultSt_conf LongMultWf_conf)) {
    my $hive_dba = init_pipeline('Bio::EnsEMBL::Hive::PipeConfig::'.$long_mult_version, [qw(-hive_driver sqlite -hive_force_init 1)]);
    runWorker($hive_dba, { can_respecialize => 1 });
    my $results = $hive_dba->dbc->db_handle->selectall_arrayref('SELECT * FROM final_result');
    ok(scalar(@$results), 'There are some results');
    ok($_->[0]*$_->[1] eq $_->[2], sprintf("%s*%s=%s", $_->[0], $_->[1], $_->[0]*$_->[1])) for @$results;
}

done_testing();
