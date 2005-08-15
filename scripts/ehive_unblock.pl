#!/usr/local/ensembl/bin/perl -w

use strict;
use DBI;
use Getopt::Long;
use Bio::EnsEMBL::Hive;

my ($help, $url);

GetOptions('help'           => \$help,
           'url=s'          => \$url,
          );

if ($help) { usage(); }
unless($url) { printf("must specifiy -url\n\n"); usage(); }

my $job = Bio::EnsEMBL::Hive::URLFactory->fetch($url);
unless($job and $job->isa('Bio::EnsEMBL::Hive::AnalysisJob')) {
  printf("Unable to fetch job via url: $url\n\n");
  usage();
}

$job->print_job;
$job->update_status('READY');

exit(0);


#######################
#
# subroutines
#
#######################

sub usage {
  print "ehive_unblock.pl [options]\n";
  print "  -help                  : print this help\n";
  print "  -url <url string>      : url defining hive job\n";
  print "ehive_unblock.pl v1.7\n";
  
  exit(1);  
}


