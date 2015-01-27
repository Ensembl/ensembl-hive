
use strict;
use warnings;

use Test::More;
use Data::Dumper;
use File::Temp qw{tempdir};

use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline runWorker);

foreach my $long_mult_version (qw(LongMult_conf LongMultWf_conf)) {
    my $hive_dba = init_pipeline('Bio::EnsEMBL::Hive::PipeConfig::'.$long_mult_version, [qw(-hive_driver sqlite -hive_force_init 1)]);
    runWorker($hive_dba, { can_respecialize => 1 });
}

done_testing();
