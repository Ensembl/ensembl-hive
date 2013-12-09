#!/usr/bin/env perl

package Script;

use strict;
use warnings;

    # Finding out own path in order to reference own components (including own modules):
use Cwd            ();
use File::Basename ();
BEGIN {
    $ENV{'EHIVE_ROOT_DIR'} = File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) );
    unshift @INC, $ENV{'EHIVE_ROOT_DIR'}.'/modules';
}


use Getopt::Long;
use Pod::Usage;

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
        'url=s'                 => \$self->{'url'},
        'reg_conf|reg_file=s'   => \$self->{'reg_conf'},
        'reg_type=s'            => \$self->{'reg_type'},
        'reg_alias|reg_name=s'  => \$self->{'reg_alias'},
        'nosqlvc=i'             => \$self->{'nosqlvc'},     # using "=i" instead of "!" for consistency with scripts where it is a propagated option

        'f|format=s'            => \$self->{'format'},
        'o|output=s'            => \$self->{'output'},

        'h|help'                => \$self->{'help'},
    );
}

sub _process_options {
    my ($self) = @_;

    #Check for help
    if($self->{'help'}) {
        pod2usage({-exitvalue => 0, -verbose => 2});
    }

    if($self->{'url'} or $self->{'reg_alias'}) {
        $self->{'dba'} = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new(
            -url                            => $self->{'url'},
            -reg_conf                       => $self->{'reg_conf'},
            -reg_type                       => $self->{'reg_type'},
            -reg_alias                      => $self->{'reg_alias'},
            -no_sql_schema_version_check    => $self->{'nosqlvc'},
        );
    } else {
        pod2usage({
            -message => 'ERROR: Connection parameters (url or reg_conf+reg_alias) need to be specified',
            -exitvalue => 1,
            -verbose => 2
        });
    }
  
    if(! $self->{'output'}) {
        pod2usage({
            -message => 'ERROR: No -output flag given',
            -exitvalue => 1,
            -verbose => 2
        });
    }
  
    if(!$self->{'format'}) {
        if($self->{'output'}=~/\.(\w+)$/) {
            $self->{'format'} = $1;
        } else {
            die "Format was not set and could not guess from ".$self->output().". Please use either way to select it.\n";
        }
    }
}

sub _write_graph {
    my ($self) = @_;

    my $graph = Bio::EnsEMBL::Hive::Utils::Graph->new( $self->{'dba'} );
    my $graphviz = $graph->build();

    my $call = q{as_}.$self->{'format'};

    eval {$graphviz->$call($self->{'output'});};
    if($@) {
        warn $@;
        pod2usage({
            -message => 'Error detected. Check '.$self->{'format'}.' is a valid format. Use a format name as supported by graphviz',
            -exitvalue => 1,
            -verbose => 2
        });
    }
}

__END__

=pod

=head1 NAME

    generate_graph.pl

=head1 SYNOPSIS

    ./generate_graph.pl -url mysql://user:pass@server:port/dbname -output OUTPUT_LOC [-help]

=head1 DESCRIPTION

    This program will generate a graphical representation of your hive pipeline.
    This includes visalising the flow of data from the different analyses, blocking
    rules & table writers. The graph is also coloured to indicate the stage
    an analysis is at. The colours & fonts used can be configured via
    hive_config.json configuration file.

=head1 OPTIONS

B<--url>

    url defining where hive database is located

B<--reg_conf>

    path to a Registry configuration file

B<--reg_alias>

    species/alias name for the Hive DBAdaptor

B<--output>

    Location of the file to write to.
    The file extension (.png , .jpeg , .dot , .gif , .ps) will define the output format.

=head1 EXTERNAL DEPENDENCIES

    GraphViz

=head1 LICENSE

    Copyright [1999-2013] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

