#!/usr/bin/env perl
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

    # Finding out own path in order to reference own components (including own modules):
use Cwd            ();
use File::Basename ();
BEGIN {
    $ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) );
    unshift @INC, $ENV{'EHIVE_ROOT_DIR'}.'/modules';
}

use DateTime;
use File::Basename;
use File::Copy;
use Getopt::Long;

use Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor;

my $opts = {
    driver => [],
    date    => undef, # this means today
    help => 0,
};
my @args = ('driver=s@', 'date=s', 'help|h');

my $parse = GetOptions($opts, @args);
if(!$parse) {
  print STDERR "Could not parse the given arguments. Please consult the help\n";
  usage();
  exit 1;
}

# Print usage on '-h' command line option
if ($opts->{help}) {
  usage();
  exit;
}

$opts->{driver} = [qw(mysql sqlite pgsql)] unless scalar(@{$opts->{driver}});
$opts->{date} = DateTime->now->ymd('-') unless $opts->{date};

my $code_sql_schema_version = Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor->get_code_sql_schema_version()
    || die "Could not establish code_sql_schema_version, please check that 'EHIVE_ROOT_DIR' environment variable is set correctly\n";

foreach my $driver (@{$opts->{driver}}) {
    -s "$ENV{'EHIVE_ROOT_DIR'}/sql/patch_$opts->{date}.$driver" && die "$ENV{'EHIVE_ROOT_DIR'}/sql/patch_$opts->{date}.$driver already exists ! Remove this file or change the patch date\n";
    system("sed 's/___EXPECTED_SCHEMA_VERSION___/$code_sql_schema_version/' '$ENV{'EHIVE_ROOT_DIR'}/sql/template_patch.$driver' > '$ENV{'EHIVE_ROOT_DIR'}/sql/patch_$opts->{date}.$driver'");
    -s "$ENV{'EHIVE_ROOT_DIR'}/sql/patch_$opts->{date}.$driver" || die "Could not copy $ENV{'EHIVE_ROOT_DIR'}/sql/template_patch.$driver to $ENV{'EHIVE_ROOT_DIR'}/sql/patch_$opts->{date}.$driver\n";
}

sub usage {
    print <<EOT;
Usage:
\t$0 [-date <day_of_the_patch>] [-driver <name_of_first_driver>] [-driver <name_of_second_driver>] ...
\t$0 -h

\t-date\n\t\tdate in ISO format, e.g. 2015-02-14. Defaults to the current date
\t-driver (can be repeated)\n\t\tdriver for which create a patch. Defaults to MySQL, SQLite, and Postgre
\t-h|--help\n\t\tdisplay this help text

EOT
}

