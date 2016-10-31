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

use Getopt::Long;
use LWP::Simple;
use URI;
use Bio::EnsEMBL::Hive::Utils ('script_usage', 'report_versions', 'stringify', 'destringify');

{
    my $self                = {};
    my $help                = 0;
    my $report_versions     = 0;

    GetOptions(
                'server_url|url=s'              => \$self->{'server_url'},
                'analysis_name|logic_name=s'    => \$self->{'analysis_name'},
                'job_parameters|input_id=s'     => \$self->{'job_parameters'},

                    # other commands/options:
                'h|help!'                       => \$help,
                'v|versions!'                   => \$report_versions,
    );

    if($report_versions) {
        report_versions();
        exit(0);
    }

    if($help or !($self->{'server_url'} and $self->{'analysis_name'} and $self->{'job_parameters'})) { script_usage(0); }

    my $uri_object = URI->new( $self->{'server_url'} );
    $uri_object->query_form( 'analysis_name' => $self->{'analysis_name'}, 'job_parameters' => $self->{'job_parameters'} );

    getprint( $uri_object->as_string() );
}


__DATA__

=pod

=head1 NAME

    rpc_client.pl [options]

=head1 DESCRIPTION

    rpc_client.pl is an eHive component script used to test the HTTP connection to rpc_server.pl
    in order to seed a job remotely.

    No pipeline database connection details flow through HTTP:
    you only need to know server_url, analysis_name and job_parameters to seed a job via the server.

=head1 USAGE EXAMPLES

        # Connect using the given RPC URL and seed a job using given analysis_name and job_parameters:
    rpc_client.pl -server_url http://127.0.0.1:54321/seed -analysis_name take_b_apart -job_parameters '{"a_multiplier" => "795015619","b_multiplier" => 327358777}'

=head1 OPTIONS

=head2 Main options:

    -server_url <string>        : the HTTP URL of the rpc_server.pl
    -analysis_name <string>     : must match an existing analysis name
    -job_parameters <string>    : a stringified Perl hash of parameters

=head2 Other options:

    -help                       : print this help
    -versions                   : report both Hive code version and Hive database schema version
    -debug <level>              : turn on debug messages at <level>

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut

