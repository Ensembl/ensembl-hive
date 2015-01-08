
use strict;
use warnings;

use Test::More;
use Data::Dumper;
use File::Temp qw{tempdir};

use Bio::EnsEMBL::Hive::Utils::Test qw(init_pipeline);

init_pipeline('Bio::EnsEMBL::Hive::PipeConfig::LongMult_conf');


done_testing();
