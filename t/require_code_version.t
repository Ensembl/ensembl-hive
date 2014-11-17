#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Data::Dumper;

eval "use Bio::EnsEMBL::Hive::Version 4.0";
is($@ ? 0 : 1, 0, 'cannot import eHive 4.0');

eval "use Bio::EnsEMBL::Hive::Version 2.0";
is($@ ? 0 : 1, 1, 'can import eHive 2.0');

done_testing()
