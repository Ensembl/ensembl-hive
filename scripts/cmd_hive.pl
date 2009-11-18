#!/usr/local/bin/perl -w

# cmd_hive.pl
#
# Cared for by Albert Vilella <>
#
# Copyright Albert Vilella
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

cmd_hive.pl - DESCRIPTION 

=head1 SYNOPSIS

perl \
/nfs/acari/avilella/src/ensembl_main/ensembl-personal/avilella/hive/cmd_hive.pl \
    -url mysql://user:password@mysqldb:port/name_of_hive_db
    -logic_name example1 -input_id 'echo I.have.$suffix.$tag.and.I.am.baking.one.right.now' \
    -suffix_a apple01 -suffix_b apple05 -tag pies\

cmd_hive.pl -url mysql://ensadmin:ensembl@compara2:5316/avilella_compara_homology_54
    -input_id \ '{ "sequence_id" => "$suffix", "minibatch" => "$suffixn" }' \
    -parameters '{ "fastadb" => "/data/blastdb/Ensembl/family_54/fasta/metazoa_54.pep", "tabfile" => "/data/blastdb/Ensembl/family_54/fasta/metazoa_54.tab" }' \
    -suffix_a 1 -suffix_b 100 -step 9 -hive_capacity 200 -logic_name family_blast_54a \
    -module Bio::EnsEMBL::Compara::RunnableDB::FamilyBlast

=head1 DESCRIPTION

This script is to help load a batch of jobs all belonging to the same analysis,
whose parameters have to be varied over a range of values.

It was initially intended to run jobs wrapped into a script via
Bio::EnsEMBL::Hive::RunnableDB::SystemCmd module,
but is now extended to run any RunnableDB module jobs.

There are three ways of providing the range for the mutable parameter:
    - perl built-in .. range operator (by setting -suffix_a 1234 and -suffix_b 5678 values)
        ** you can create mini-batches by providing the -step value, which will percolate as $suffixn
    - values provided in a file (by setting -inputfile filename)
    - hashed mode

Always use single quotes to protect the values of -input_id and -parameters.

Be careful of using things that don't expand, like apple_01 apple_05
instead of apple01 apple05

Also don't use suffix_a and suffix_b in the reverse order apple05
to apple01 because they expand in things like:
apple54,applf04,applf54,applg04,applg54,applh04,applh54...

If using hashed, call with something like:

[-hashed_a 00:00:00]
[-hashed_b 01:61:67]

=head1 AUTHOR - Albert Vilella

=head2 CONTRIBUTOR - Leo Gordon

=cut


# Let the code begin...

use strict;
use DBI;
use Getopt::Long;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Worker;
#use Bio::EnsEMBL::Hive::Queen;
use Time::HiRes qw(time gettimeofday tv_interval);
#use Data::UUID;

# ok this is a hack, but I'm going to pretend I've got an object here
# by creating a blessed hash ref and passing it around like an object
# this is to avoid using global variables in functions, and to consolidate
# the globals into a nice '$self' package
my $self = bless {};

$self->{'db_conf'} = {};
$self->{'db_conf'}->{'-user'} = 'ensro';
$self->{'db_conf'}->{'-port'} = 3306;

$self->{'analysis_id'} = undef;
$self->{'logic_name'}  = 'cmd_hive_analysis';
$self->{'module'}      = 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd';
$self->{'parameters'}  = '{}';
$self->{'outdir'}      = undef;
$self->{'beekeeper'}   = undef;
$self->{'process_id'}  = undef;

my $conf_file;
my ($help, $host, $user, $pass, $dbname, $port, $adaptor, $url);

GetOptions('help'            => \$help,
           'url=s'           => \$url,
           'conf=s'          => \$conf_file,
           'dbhost=s'        => \$host,
           'dbport=i'        => \$port,
           'dbuser=s'        => \$user,
           'dbpass=s'        => \$pass,
           'dbname=s'        => \$dbname,
           'analysis_id=i'   => \$self->{'analysis_id'},
           'logic_name=s'    => \$self->{'logic_name'},
           'module=s'        => \$self->{'module'},
           'limit=i'         => \$self->{'job_limit'},
           'lifespan=i'      => \$self->{'lifespan'},
           'outdir=s'        => \$self->{'outdir'},
           'bk=s'            => \$self->{'beekeeper'},
           'pid=s'           => \$self->{'process_id'},
           'input_id=s'      => \$self->{'input_id'},
           'parameters=s'    => \$self->{'parameters'},
           'inputfile=s'     => \$self->{'inputfile'},
           'suffix_a=s'      => \$self->{'suffix_a'},
           'suffix_b=s'      => \$self->{'suffix_b'},
           'step=i'          => \$self->{'step'},
           'hashed_a=s'      => \$self->{'hashed_a'},
           'hashed_b=s'      => \$self->{'hashed_b'},
           'tag=s'           => \$self->{'tag'},
           'hive_capacity=s' => \$self->{'hive_capacity'},
           'batch_size=s'    => \$self->{'batch_size'},
           'debug=s'         => \$self->{'debug'},
          );

$self->{'analysis_id'} = shift if(@_);

if ($help) { usage(); }

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
    usage();
  }

  # connect to database specified
  $DBA = new Bio::EnsEMBL::Hive::DBSQL::DBAdaptor(%{$self->{'db_conf'}});
  #$url = $DBA->url();
}
#$DBA->dbc->disconnect_when_inactive(1);

#my $queen = $DBA->get_Queen();
job_creation($self);
exit(0);


#######################
#
# subroutines
#
#######################

sub usage {
  print "cmd_hive.pl [options]\n";
  print "  -help                  : print this help\n";
  print "  -url <url string>      : url defining where hive database is located\n";
  print "  -input_id <cmd string> : command to be executed (or param. hash to be passed to analysis module)\n";
  print "  -suffix_a <tag>        : suffix from here\n";
  print "  -suffix_b <tag>        : suffix to here\n";
  print "  -tag <tag>             : fixed tag in the command line\n"; 
  print "  -logic_name <analysis name>  : logic_name of the analysis\n";
  print "  -module <module name>  : name of the module to be run\n";
  exit(1);
}

sub job_creation {
  my $self = shift;

  my $logic_name = $self->{'logic_name'};
  my $module     = $self->{'module'};
  my $parameters = $self->{'parameters'};
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

  my $stats = $self->{_analysis}->stats;
  $stats->batch_size( $self->{'batch_size'} || 1 );
  $stats->hive_capacity( $self->{'hive_capacity'} || 20 );
  $stats->status('READY');
  $stats->update();

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
    my $tag  = $self->{'tag'};
    my $step = $self->{'step'} || 1;
    my @full_list = $self->{'suffix_a'}..$self->{'suffix_b'};
    while(@full_list) {
        my ($from, $to);
        my $batch_cnt = 1;
        for($from = $to = shift @full_list; $batch_cnt<$step && @full_list; $batch_cnt++) {
            $to = shift @full_list;
        }
            # expanding tags here (now you can substitute $suffix, $suffix2, $suffixn and if you really need it, $tag):
        my $resolved_input_id = $self->{'input_id'};
        $resolved_input_id =~ s/\$suffixn/$batch_cnt/g; # the order of substitutions is important!
        $resolved_input_id =~ s/\$suffix2/$to/g;
        $resolved_input_id =~ s/\$suffix/$from/g;
        $resolved_input_id =~ s/\$tag/$tag/g;

        if(++$count % 100 == 0) {
            print "$resolved_input_id at ",(time()-$starttime)," secs\n";
        }
        $self->create_resolved_input_id_job($resolved_input_id);
    }
  }
  my $total_time = (time()-$starttime);
  print "$count jobs created in $total_time secs\n";
  print("speed : ",($count / $total_time), " jobs/sec\n");
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

1;
