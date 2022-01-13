#!/usr/bin/env perl

use strict;
use warnings;

    # Finding out own path in order to reference own components (including own modules):
use Cwd            ();
use File::Basename ();
BEGIN {
    $ENV{'EHIVE_ROOT_DIR'} ||= File::Basename::dirname( File::Basename::dirname( Cwd::realpath($0) ) );
    unshift @INC, $ENV{'EHIVE_ROOT_DIR'}.'/modules';
}

use Getopt::Long qw(:config pass_through no_auto_abbrev);
use Pod::Usage;

use Bio::EnsEMBL::Hive::HivePipeline;
use Bio::EnsEMBL::Hive::Utils ('load_file_or_module');
use Bio::EnsEMBL::Hive::Utils::Graph;
use Bio::EnsEMBL::Hive::Utils::URL;

Bio::EnsEMBL::Hive::Utils::URL::hide_url_password();

main();


sub main {

    my $self = {};

    GetOptions(
            # connection parameters
        'url=s'                 => \$self->{'url'},
        'reg_conf|reg_file=s'   => \$self->{'reg_conf'},
        'reg_type=s'            => \$self->{'reg_type'},
        'reg_alias|reg_name=s'  => \$self->{'reg_alias'},
        'nosqlvc'               => \$self->{'nosqlvc'}, # using "nosqlvc" instead of "sqlvc!" for consistency with scripts where it is a propagated option

            # json config files
        'config_file=s@'        => \$self->{'config_files'},

        'pipeconfig|pc=s@'      => \$self->{'pipeconfigs'}, # now an array

        'f|format=s'            => \$self->{'format'},
        'o|out|output=s'        => \$self->{'output'},

        'h|help'                => \$self->{'help'},
    );

    if($self->{'help'}) {
        pod2usage({-exitvalue => 0, -verbose => 2});
    }

    if($self->{'url'} or $self->{'reg_alias'}) {
        $self->{'pipeline'} = Bio::EnsEMBL::Hive::HivePipeline->new(
            -url                            => $self->{'url'},
            -reg_conf                       => $self->{'reg_conf'},
            -reg_type                       => $self->{'reg_type'},
            -reg_alias                      => $self->{'reg_alias'},
            -no_sql_schema_version_check    => $self->{'nosqlvc'},
        );

    } else {
        $self->{'pipeline'} = Bio::EnsEMBL::Hive::HivePipeline->new();
        die "A pipeline has to be given, either via -url/-reg* or via -pipeconfig" unless $self->{'pipeconfigs'};
    }

    foreach my $pipeconfig (@{ $self->{'pipeconfigs'} || [] }) {
        my $pipeconfig_package_name = load_file_or_module( $pipeconfig );

        my $pipeconfig_object = $pipeconfig_package_name->new();
        $pipeconfig_object->process_options( 0 );

        $pipeconfig_object->add_objects_from_config( $self->{'pipeline'} );
    }

    if($self->{'output'} or $self->{'format'}) {

        if(!$self->{'format'}) {
            if($self->{'output'}=~/\.(\w+)$/) {
                $self->{'format'} = $1;
            } else {
                die "Format was not set and could not guess from ".$self->{'output'}.". Please use either way to select it.\n";
            }
        }

        if($self->{'format'} eq 'txt') {
            local *STDOUT;

            open (STDOUT, '>', $self->{'output'}); # redirect STDOUT to $self->{'output'}

            $self->{'pipeline'}->print_diagram;     # and capture the Unicode diagram in a text file

        } else {
            my $graph = Bio::EnsEMBL::Hive::Utils::Graph->new(
                $self->{'pipeline'},
                $self->{'config_files'} ? @{ $self->{'config_files'} } : ()
            );
            my $graphviz = $graph->build();

            if( $self->{'format'} eq 'dot' ) {          # If you need to take a look at the intermediate dot file
                $graphviz->dot_input_filename( $self->{'output'} || \*STDOUT);
                $graphviz->as_canon( '/dev/null' );

            } else {
                my $call = 'as_'.$self->{'format'};
                $graphviz->$call($self->{'output'} || \*STDOUT);
            }
        }

    } else {
        $self->{'pipeline'}->print_diagram;

        print "\n";
        print "----------------------------------------------------------\n";
        print "   Did you forget to specify the -output flowchart.png ?  \n";
        print "----------------------------------------------------------\n";
    }
}


__DATA__

=pod

=head1 NAME

generate_graph.pl

=head1 SYNOPSIS

    generate_graph.pl -help

    generate_graph.pl [ -url mysql://user:pass@server:port/dbname | -reg_conf <reg_conf_file> -reg_alias <reg_alias> ] [-pipeconfig TopUp_conf.pm]* -output OUTPUT_LOC

=head1 DESCRIPTION

This program will generate a graphical representation of your eHive pipeline.
This includes visualising the flow of data from the different analyses, blocking
rules and table writers. The graph is also coloured to indicate the stage
an Analysis is at. The colours and fonts used can be configured via
hive_config.json configuration file.

=head1 OPTIONS

=over

=item --url <url>

URL defining where eHive database is located

=item --reg_conf <path>

path to a Registry configuration file

=item --reg_alias <str>

species/alias name for the eHive DBAdaptor

=item --nosqlvc

"No SQL Version Check" - set if you want to force working with a database created by a potentially schema-incompatible API

=item --config_file <path>

Path to JSON eHive config file

=item --pipeconfig <path|module_name>

A pipeline configuration file that can function both as the initial source of pipeline structure or as a top-up config.
This option can now be used multiple times for multiple top-ups.

=item --format <str>

(Optional) specify the output format, or override the output format specified by the output file's extension
(e.g. png, jpeg, dot, gif, ps)

=item --output <path>

Location of the file to write to.
The file extension (.png , .jpeg , .dot , .gif , .ps) will define the output format.

=item --help

Print this help message

=back

=head1 EXTERNAL DEPENDENCIES

=over

=item GraphViz

=back

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2022] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

Please subscribe to the eHive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss eHive-related questions or to be notified of our updates

=cut

