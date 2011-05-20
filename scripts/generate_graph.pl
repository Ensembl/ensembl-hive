#!/usr/bin/env perl

package Script;

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;

use Bio::EnsEMBL::Hive::URLFactory;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Utils::Graph;
use Bio::EnsEMBL::Hive::Utils::Graph::Config;

my $self = bless({}, __PACKAGE__);

$self->run();

sub run {
  my ($self) = @_;
  $self->_options();
  $self->_process_options();
  $self->_write_graph();
  return;
}

sub _options {
  my ($self) = @_;
  GetOptions(
    'regfile=s'         => \$self->{reg_file},
    'regname=s'         => \$self->{reg_name},
    'url=s'             => \$self->{url},
    'host|dbhost=s'     => \$self->{db_conf}->{'-host'},
    'port|dbport=i'     => \$self->{db_conf}->{'-port'},
    'user|dbuser=s'     => \$self->{db_conf}->{'-user'},
    'password|dbpass=s' => \$self->{db_conf}->{'-pass'},
    'database|dbname=s' => \$self->{db_conf}->{'-dbname'},
    
    'f|format=s'        => \$self->{format},
    'o|output=s'        => \$self->{output},
    'config'            => \$self->{config},
    
    'h|help'            => \$self->{help},
    'm|man'             => \$self->{man},
  );
  return;
}

sub _process_options {
  my ($self) = @_;
  
  #Check for help
  if($self->{help}) {
    pod2usage({-exitvalue => 0, -verbose => 1});
  }
  if($self->{man}) {
    pod2usage({-exitvalue => 0, -verbose => 2});
  }
  
  #Check for DB
  if($self->{reg_file}) {
    Bio::EnsEMBL::Registry->load_all($self->{reg_file});
    $self->{dba} = Bio::EnsEMBL::Registry->get_DBAdaptor($self->{reg_name}, 'hive');
  } 
  elsif($self->{url}) {
    $self->{dba} = Bio::EnsEMBL::Hive::URLFactory->fetch($self->{url}) || die("Unable to connect to $self->{url}\n");
  }
  elsif (    $self->{db_conf}->{'-host'}
          && $self->{db_conf}->{'-user'}
          && $self->{db_conf}->{'-dbname'}) { # connect to database specified
    $self->{dba} = new Bio::EnsEMBL::Hive::DBSQL::DBAdaptor(%{$self->{db_conf}});
  } 
  else {
    pod2usage({
      -message => 'ERROR: Connection parameters (regfile+regname, url or dbhost+dbuser+dbname) need to be specified',
      -exitvalue => 1,
      -verbose => 1
    });
  }
  
  if(! $self->{output}) {
    pod2usage({
      -message => 'ERROR: No -output flag given',
      -exitvalue => 1,
      -verbose => 1
    });
  }
  if(-f $self->{output}) {
    pod2usage({
      -message => "ERROR: $self->{output} already exists. Remove before running this script",
      -exitvalue => 1,
      -verbose => 1
    });
  }
  
  if(!$self->{format}) {
    if($self->{output}=~/\.(\w+)$/) {
        $self->{format} = $1;
    } else {
        die "Format was not set and could not guess from ".$self->output().". Please use either way to select it.\n";
    }
  }
  
  if($self->{config}) {
    if(! -f $self->{config}) {
      pod2usage({
      -message => "ERROR: Cannot find $self->{config}. Check your locations",
      -exitvalue => 1,
      -verbose => 1
    });
    }
    my $hash = do $self->{config};
    $self->{config_hash} = $hash;
  }
    
  return;
}

sub _write_graph {
  my ($self) = @_;
  
  my $config = Bio::EnsEMBL::Hive::Utils::Graph::Config->new();
  if($self->{config_hash}) {
    $config->merge($config);
  }
  
  my $graph = Bio::EnsEMBL::Hive::Utils::Graph->new(-DBA => $self->{dba}, -CONFIG => $config);
  my $graphviz = $graph->build();
  
  my $call = q{as_}.$self->{format};
    
  eval {$graphviz->$call($self->{output});};
  if($@) {
    warn $@;
    pod2usage({
      -message => 'Error detected. Check '.$self->{format}.' is a valid format. Use a format name as supported by graphviz',
      -exitvalue => 1,
      -verbose => 1
    });
  }
  
  return;
}

__END__
=pod

=head1 NAME

generate_graph.pl

=head1 SYNOPSIS

  ./generate_graph.pl -url mysql://user:pass@server:port/dbname -output OUTPUT_LOC [-format FORMAT ] [-help | -man]

=head1 DESCRIPTION

This program will generate a graphical representation of your hive pipeline. 
This includes visalising the flow of data from the different analyses, blocking
rules & table writers. The graph is also coloured to indicate the stage 
an analysis is at. The colours & fonts used can be configured via the 
C<--config> flag but see the option information about how to do this.

=head1 OPTIONS

=over 8

=item B<--format>

The format of the file output. See FORMATS for more information

=item B<--output>

Location of the file to write to. 

=item B<--config>

Perl file which will return a Hash when evaluated. The hash is merged into the
default option set for configuring the graphs produced. See 
L<Bio::EnsEMBL::Hive::Utils::Graph::Config>

=item B<-regfile>

path to a Registry configuration file

=item B<-regname>

species/alias name for the Hive DBAdaptor

=item B<-url> 

url defining where hive database is located

=item B<-host>

mysql database host <machine>

=item B<-port> 

mysql port number

=item B<-user>

mysql connection user <name>

=item B<-password>

mysql connection password <pass>

=item B<-database>

mysql database <name>

=back

=head1 FORMATS

The script supports the same output formats as GraphViz & the accompanying
Perl module do. However here are a list of common output formats you may
want to specify (png is the default).

=over 8

=item png

=item jpeg

=item dot

=item gif

=item ps

=item ps2

=back

=head1 MAINTAINER

$Author: lg4 $

=head1 VERSION

$Revision: 1.3 $

=head1 REQUIREMENTS

=over 8

=item GraphViz

=back

=cut
