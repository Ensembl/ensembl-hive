#!/usr/bin/env perl

# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2019] EMBL-European Bioinformatics Institute
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
use Test::More;
use Test::Warn;
use Test::JSON;
use Capture::Tiny ':all';
use Bio::EnsEMBL::Hive::Utils::Formatter;

BEGIN {
    use_ok( 'Bio::EnsEMBL::Hive::Utils::Formatter' );

}

my $formatter = Bio::EnsEMBL::Hive::Utils::Formatter->new();

#Check correct json, on-fly

$formatter->set_mode('onfly', 1);
$formatter->set_mode('json', 1);
my $testStructure;
$testStructure->{header} = 'Zebrafish';
$testStructure->{heade2} = 'Mole';
$testStructure->{header3}->{type} = 'Mushroom';

my $stdout = capture_stdout {
  $formatter->add_infoHash($testStructure);
};

is_valid_json $stdout;

#Check stacked output mode, text mode, debug mode

$formatter->set_mode('onfly', 0);
$formatter->set_mode('text', 1);
$formatter->set_mode('json', 0);
$formatter->set_mode('error', 0);

$formatter->add_warning('warning');
$formatter->add_error('error');
$formatter->add_info('info');
$formatter->add_warning('warning');

$stdout = capture_stdout {
  $formatter->print_data();
};

print $stdout;
ok(index($stdout, 'error') == -1, 'Error switch off works correctly');
ok(index($stdout, 'info') != -1, 'Text info output works correctly');

$formatter->set_mode('warning', 0);

$stdout = capture_stdout {
  $formatter->print_data();
};

ok(index($stdout, 'warning') == -1, 'Warning switch off works correctly');

#Check custom output function


done_testing();
