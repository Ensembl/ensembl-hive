#!/usr/bin/env perl

package Script;

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;

use Bio::EnsEMBL::Hive::URLFactory;
use Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Hive::Utils::Graph;

my $self = bless({}, __PACKAGE__);

$self->main();

sub main {
    my ($self) = @_;

    $self->_options();
    $self->_process_options();
    $self->_write_graph();
}

sub _options {
    my ($self) = @_;
    GetOptions(
            # connection parameters
        'reg_conf|regfile=s'    => \$self->{'reg_conf'},
        'reg_alias|regname=s'   => \$self->{'reg_alias'},
        'url=s'                 => \$self->{url},

        'f|format=s'            => \$self->{format},
        'o|output=s'            => \$self->{output},

        'h|help'                => \$self->{help},
        'm|man'                 => \$self->{man},
    );
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
    if($self->{'reg_conf'} and $self->{'reg_alias'}) {
        Bio::EnsEMBL::Registry->load_all($self->{'reg_conf'});
        $self->{dba} = Bio::EnsEMBL::Registry->get_DBAdaptor($self->{'reg_alias'}, 'hive');
    } elsif($self->{url}) {
        $self->{dba} = Bio::EnsEMBL::Hive::URLFactory->fetch($self->{url}) || die("Unable to connect to $self->{url}\n");
    } else {
        pod2usage({
            -message => 'ERROR: Connection parameters (url or reg_conf+reg_alias) need to be specified',
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
  
    if(!$self->{format}) {
        if($self->{output}=~/\.(\w+)$/) {
            $self->{format} = $1;
        } else {
            die "Format was not set and could not guess from ".$self->output().". Please use either way to select it.\n";
        }
    }
}

sub _write_graph {
    my ($self) = @_;

    my $graph = Bio::EnsEMBL::Hive::Utils::Graph->new( $self->{dba} );
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
an analysis is at. The colours & fonts used can be configured via
hive_config.json configuration file.

=head1 OPTIONS

=over 8

=item B<--format>

    The format of the file output. See FORMATS for more information

=item B<--output>

    Location of the file to write to. 

=item B<-reg_conf>

    path to a Registry configuration file

=item B<-reg_alias>

    species/alias name for the Hive DBAdaptor

=item B<-url> 

    url defining where hive database is located

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

=head1 REQUIREMENTS

=over 8

=item GraphViz

=back

=cut
