#!/usr/bin/env perl

# cmd_hive.pl
#
# Copyright (c) 1999-2010 The European Bioinformatics Institute and
# Genome Research Limited.  All rights reserved.
# 
# You may distribute this module under the same terms as perl itself

use strict;
use warnings;
use DBI;
use Getopt::Long;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Worker;
use Time::HiRes qw(time gettimeofday tv_interval);

# ok this is a hack, but I'm going to pretend I've got an object here
# by creating a blessed hash ref and passing it around like an object
# this is to avoid using global variables in functions, and to consolidate
# the globals into a nice '$self' package
my $self = bless {};

$self->{'db_conf'} = {};
$self->{'db_conf'}->{'-user'} = 'ensro';
$self->{'db_conf'}->{'-port'} = 3306;

# DEFAULT VALUES FOR NEW ANALYSES
my $DEFAULT_LOGIC_NAME    = 'cmd_hive_analysis';
my $DEFAULT_MODULE        = 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd';
my $DEFAULT_PARAMETERS    = '{}';
my $DEFAULT_HIVE_CAPACITY = 20;
my $DEFAULT_BATCH_SIZE    = 1;

my ($help, $host, $user, $pass, $dbname, $port, $adaptor, $url);

GetOptions(
# connection parameters:
           'url=s'             => \$url,
           'host|dbhost=s'     => \$host,
           'port|dbport=i'     => \$port,
           'user|dbuser=s'     => \$user,
           'password|dbpass=s' => \$pass,
           'database|dbname=s' => \$dbname,

# analysis parameters:
           'logic_name=s'      => \$self->{'logic_name'},
           'module=s'          => \$self->{'module'},
           'hive_capacity=s'   => \$self->{'hive_capacity'},
           'batch_size=s'      => \$self->{'batch_size'},
           'input_id=s'        => \$self->{'input_id'},
           'parameters=s'      => \$self->{'parameters'},

# range parameters:
           'inputfile=s'       => \$self->{'inputfile'},
           'suffix_a=s'        => \$self->{'suffix_a'},
           'suffix_b=s'        => \$self->{'suffix_b'},
           'step=i'            => \$self->{'step'},
           'hashed_a=s'        => \$self->{'hashed_a'},
           'hashed_b=s'        => \$self->{'hashed_b'},

# other options:
           'h|help'            => \$help,
           'debug=s'           => \$self->{'debug'},
);

if ($help) { usage(0); }

my $DBA;
if($url) {
  $DBA = Bio::EnsEMBL::Hive::URLFactory->fetch($url);
} else {
  if($host)   { $self->{'db_conf'}->{'-host'}   = $host; }
  if($port)   { $self->{'db_conf'}->{'-port'}   = $port; }
  if($dbname) { $self->{'db_conf'}->{'-dbname'} = $dbname; }
  if($user)   { $self->{'db_conf'}->{'-user'}   = $user; }
  if($pass)   { $self->{'db_conf'}->{'-pass'}   = $pass; }

  unless(defined($self->{'db_conf'}->{'-host'})
         and defined($self->{'db_conf'}->{'-user'})
         and defined($self->{'db_conf'}->{'-dbname'}))
  {
    print "\nERROR : must specify host, user, and database to connect\n\n";
    usage(1);
  }

  # connect to database specified
  $DBA = new Bio::EnsEMBL::Hive::DBSQL::DBAdaptor(%{$self->{'db_conf'}});
  #$url = $DBA->url();
}

job_creation($self);
exit(0);


#######################
#
# subroutines
#
#######################

sub job_creation {
  my $self = shift;

  $self->create_analysis;

  print("$0 -- inserting jobs\n");
  my $starttime = time();
  my $count = 0;
  if (defined($self->{'hashed_a'}) and defined($self->{'hashed_b'})) {
    while (my $resolved_input_id = $self->resolve_suffix()) {
      print STDERR "  $resolved_input_id\n" if ($self->{debug});
      $self->create_resolved_input_id_job($resolved_input_id) unless ($self->{debug});
      if(++$count % 100 == 0) {
        print "$resolved_input_id at ",(time()-$starttime)," secs\n";
      }
    }
  } elsif (defined($self->{'inputfile'})) {
    open FILE, $self->{'inputfile'} or die $!;
    while (<FILE>) {
      chomp $_;
      my $id = $_;
      my $resolved_input_id = $self->{'input_id'};
      $resolved_input_id =~ s/\$inputfile/$id/;
      $self->create_resolved_input_id_job($resolved_input_id);
      print "Job ", $count, " at ",(time()-$starttime)," secs\n" if(++$count % 50 == 0);
    }
    close FILE;
  } elsif(defined($self->{'suffix_a'}) and defined($self->{'suffix_b'})) {
    my $step = $self->{'step'} || 1;
    my @full_list = $self->{'suffix_a'}..$self->{'suffix_b'};
    while(@full_list) {
        my ($from, $to);
        my $batch_cnt = 1;
        for($from = $to = shift @full_list; $batch_cnt<$step && @full_list; $batch_cnt++) {
            $to = shift @full_list;
        }
            # expanding tags here (now you can substitute $suffix, $suffix2, $suffixn):
        my $resolved_input_id = $self->{'input_id'};
        $resolved_input_id =~ s/\$suffixn/$batch_cnt/g; # the order of substitutions is important!
        $resolved_input_id =~ s/\$suffix2/$to/g;
        $resolved_input_id =~ s/\$suffix/$from/g;

        if(++$count % 100 == 0) {
            print "$resolved_input_id at ",(time()-$starttime)," secs\n";
        }
        $self->create_resolved_input_id_job($resolved_input_id);
    }
  } else {
    $self->create_resolved_input_id_job($self->{input_id});
    $count++;
  }
  my $total_time = (time()-$starttime);
  print "$count jobs created in $total_time secs\n";
  print("speed : ",($count / $total_time), " jobs/sec\n");
}


sub create_analysis {
  my ($self) = @_;

  my $logic_name = ( $self->{'logic_name'} || $DEFAULT_LOGIC_NAME );
  my $module     = ( $self->{'module'} || $DEFAULT_MODULE );
  my $parameters = ( $self->{'parameters'} || $DEFAULT_PARAMETERS );
  my $hive_capacity;
  my $batch_size;

  # Try to get the analysis from the DB in case we are simply adding jobs to this analysis
  $self->{_analysis} = $DBA->get_AnalysisAdaptor()->fetch_by_logic_name($logic_name);

  if (!$self->{_analysis}) {
    # No existing analysis with this logic_name. Create a new one.
    print("creating analysis '$logic_name' to be computed using module '$module' with parameters '$parameters'\n");

    $self->{_analysis} = Bio::EnsEMBL::Analysis->new (
        -db              => '',
        -db_file         => '',
        -db_version      => '1',
        -parameters      => $parameters,
        -logic_name      => $logic_name,
        -module          => $module,
      );
    $DBA->get_AnalysisAdaptor()->store($self->{_analysis});

    $hive_capacity = ( $self->{'hive_capacity'} || $DEFAULT_HIVE_CAPACITY );
    $batch_size = ( $self->{'batch_size'} || $DEFAULT_BATCH_SIZE );
  } else {
    # We have found an analysis with the same logic_name.
    # Check that the analysis module is the same
    if ($self->{'module'} and $module ne $self->{_analysis}->module) {
      die "Analysis <$logic_name> exists already and uses module '".$self->{_analysis}->module."'\n";
    }
    # Check that the analysis parameters are the same
    if ($self->{'parameters'} and $parameters ne $self->{_analysis}->parameters) {
      die "Analysis <$logic_name> exists already with parameters '".$self->{_analysis}->parameters."'\n";
    }
    # Set hive_capacity and batch_size if set through the command line only.
    # Keep the current value otherwise
    $hive_capacity = $self->{'hive_capacity'};
    $batch_size = $self->{'batch_size'};
  }

  my $stats = $self->{_analysis}->stats;
  $stats->batch_size( $batch_size ) if (defined($batch_size));
  $stats->hive_capacity( $hive_capacity ) if (defined($hive_capacity));
  $stats->status('READY');
  $stats->update();
}


sub create_resolved_input_id_job {
  my ($self, $resolved_input_id) = @_;

  Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob 
      (
       -input_id       => $resolved_input_id,
       -analysis       => $self->{_analysis},
       -input_job_id   => 0,
      ) unless ($self->{'debug'});
}


sub resolve_suffix {
  my $self = shift;

  my @h_a = split("\:",$self->{'hashed_a'});
  my @h_b = split("\:",$self->{'hashed_b'});
  $self->{_hlevels} = scalar(@h_a);
  my $level = $self->{_hlevels};
  if (!defined($self->{"_a$level"}) || !defined($self->{"_b$level"})) {
    warn("wrong hashed options: $!\n") if ( $self->{_hlevels} != scalar(@h_b));
    foreach my $level (1..$self->{_hlevels}) {
      my $index = $level-1;
      $self->{"_a$level"} = sprintf("%02d", $h_a[$index]) if (!defined($self->{"_a$level"}));
      $self->{"_b$level"} = sprintf("%02d", $h_b[$index]) if (!defined($self->{"_b$level"}));
      $self->{"_h$level"} = sprintf("%02d", $h_a[$index]) if (!defined($self->{"_h$level"}));
      1;
    }
  } else {
    my $levely = $self->{_hlevels};
    my $levelx = 1;
    my $max = '99';
    while ($levelx <= $self->{_hlevels}) {
      if ($self->{"_h$levelx"} == $self->{"_b$levelx"}) {
        # We reached the max for this level
        $max = $self->{"_b$levelx"};
      } else {
        $max = '99';
        while ($levely > 0) {
          if ($self->{"_h$levely"} < $max) {
            $self->{"_h$levely"}++;
            $levely = 0;
          } else {
            $self->{"_h$levely"} = '00';
          }
          # this two lines break the loop
          $levely--;
          $levelx = $self->{_hlevels};
        }
      }
      $levelx++;
    }
  }
  my $hashed_input_id = $self->{'input_id'};
  foreach my $level (1..$self->{_hlevels}) {
    my $value;
    $value = sprintf("%02d", $self->{"_h$level"});
    $hashed_input_id =~ s/(\$h$level)/$value/ge;
    1;
  }
  if (defined($self->{'hashed_input_id'})) {
    if ($self->{'hashed_input_id'} eq $hashed_input_id) {
      # we are at the last one, so return undef
      return undef;
    } else {
      $self->{'hashed_input_id'} = $hashed_input_id;
    }
  } else {
    $self->{'hashed_input_id'} = $hashed_input_id;
  }
  return $hashed_input_id;
}

sub usage {
    my $retvalue = shift @_;

    if(`which perldoc`) {
        system('perldoc', $0);
    } else {
        foreach my $line (<DATA>) {
            if($line!~s/\=\w+\s?//) {
                $line = "\t$line";
            }
            print $line;
        }
    }
    exit($retvalue);
}

__DATA__

=pod

=head1 NAME

    cmd_hive.pl

=head1 USAGE

    cmd_hive.pl -url mysql://user:password@host:port/name_of_hive_db \
        -logic_name example1 -input_id 'echo I.have.$suffix.and.I.am.baking.one.right.now' \
        -suffix_a apple01 -suffix_b apple05

    cmd_hive.pl -url mysql://user:password@host:port/avilella_compara_homology_54 \
        -input_id  '{ "sequence_id" => "$suffix", "minibatch" => "$suffixn" }' \
        -parameters '{ "fastadb" => "/data/blastdb/Ensembl/family_54/fasta/metazoa_54.pep", "tabfile" => "/data/blastdb/Ensembl/family_54/fasta/metazoa_54.tab" }' \
        -suffix_a 1 -suffix_b 100 -step 9 -hive_capacity 200 -logic_name family_blast_54a \
        -module Bio::EnsEMBL::Compara::RunnableDB::FamilyBlast

=head1 DESCRIPTION

    This script helps to load a batch of jobs all belonging to the same analysis,
    whose parameters are given by a range of values.

    By default it will use the 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd'
    to run a script wrapped into eHive jobs, but it will run any RunnableDB module that you specify instead.

    There are three ways of providing the range for the mutable parameter(s):
    - values provided in a file (by setting -inputfile filename)
    - perl built-in .. range operator (by setting -suffix_a 1234 and -suffix_b 5678 values)
        ** you can create mini-batches by providing the -step value, which will percolate as $suffixn
    - hashed mode

=head1 OPTIONS

=head2 Connection parameters

    -url <url string>              : url defining where hive database is located
    -host <machine>                : mysql database host <machine>
    -port <port#>                  : mysql port number
    -user <name>                   : mysql connection user <name>
    -password <pass>               : mysql connection password <pass>
    -database <name>               : mysql database <name>

=head2 Analysis parameters

    -logic_name <analysis_name>    : logic_name of the analysis
    -module <module_name>          : name of the module to be run
    -hive_capacity <hive_capacity> : top limit on the number of jobs of this analysis run at the same time
    -batch_size <batch_size>       : how many jobs can be claimed by a worker at once
    -parameters <parameters_hash>  : hash containing analysis-wide parameters for the module
    -input_id <inputid_hash>       : hash containing job-specific parameters for the module

    Always use single quotes to protect the values of -input_id and -parameters.

=head2 Range parameters (file mode)

    -inputfile <filename>          : filename to take the values from (one per line)

    Contents of each line will be substituted for '$inputfile' pattern in the input_id.

=head2 Range parameters (simple range mode)

    -suffix_a <tag>                : bottom boundary of the range
    -suffix_b <tag>                : top boundary of the range
    -step <step_size>              : desired size of the subrange, may be smaller for last subrange (1 by default)

    The result of range expansion will get chunked into subranges of <step_size> (or 1 if not specified).
    Start of the subrange will be substituted for '$suffix',
    end of the subrange will be substituted for '$suffix2'
    and size of the subrange will be substituted for '$suffixn' pattern in the input_id.

    Be careful of using things that don't expand, like apple_01 apple_05 instead of apple01 apple05

    Also don't use suffix_a and suffix_b in the reverse order apple05 to apple01 because they expand in things like:
    apple54,applf04,applf54,applg04,applg54,applh04,applh54...

=head2 Range parameters (hashed mode)

    -hashed_a <tag_a>              : for example, -hashed_a 00:00:00
    -hashed_b <tag_b>              : for example, -hashed_b 01:61:67

    Please ask Albert about this mode or to provide documentation for it :)

=head2 Other options

    -help                          : print this help

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

