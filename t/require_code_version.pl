#!/usr/bin/env perl

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Version 2.0;

print "Hello, world! We are using Hive version ".Bio::EnsEMBL::Hive::Version->get_code_version."\n";

