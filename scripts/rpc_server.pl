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
use HTTP::Daemon;
use HTTP::Status;   # FYI: https://en.wikipedia.org/wiki/List_of_HTTP_status_codes
use Bio::EnsEMBL::Hive::Utils ('script_usage', 'report_versions', 'stringify', 'destringify');
use Bio::EnsEMBL::Hive::HivePipeline;

{
    my $self                = {};
    my $help                = 0;
    my $report_versions     = 0;

    $self->{'server_port'}  = 54321;    # this default can be overridden either by a specific port number or 0 for a randomly chosen port

    GetOptions(
                    # eHive pipeline connection parameters:
                'pipeline_url|url=s'            => \$self->{'url'},
                'reg_conf|regfile|reg_file=s'   => \$self->{'reg_conf'},
                'reg_type=s'                    => \$self->{'reg_type'},
                'reg_alias|regname|reg_name=s'  => \$self->{'reg_alias'},
                'nosqlvc=i'                     => \$self->{'nosqlvc'},         # can't use the binary "!" as it is a propagated option

                    # HTTP server parameters:
                'server_host=s'                 => \$self->{'server_host'},
                'server_port=i'                 => \$self->{'server_port'},     # ask for 0 to be given a random port number

                    # other commands/options:
                'h|help!'                       => \$help,
                'v|versions!'                   => \$report_versions,
    );

    if ($help) { script_usage(0); }

    if($report_versions) {
        report_versions();
        exit(0);
    }

    if($self->{'url'} or $self->{'reg_alias'}) {

        $self->{'pipeline'} = Bio::EnsEMBL::Hive::HivePipeline->new(
            -url                            => $self->{'url'},
            -reg_conf                       => $self->{'reg_conf'},
            -reg_type                       => $self->{'reg_type'},
            -reg_alias                      => $self->{'reg_alias'},
            -no_sql_schema_version_check    => $self->{'nosqlvc'},
        );

        $self->{'dba'} = $self->{'pipeline'}->hive_dba();

    } else {
        print "\nERROR : Connection parameters (url or reg_conf+reg_alias) need to be specified\n\n";
        script_usage(1);
    }

    my $daemon = HTTP::Daemon->new(
        $self->{'server_host'} ? ('LocalAddr' => $self->{'server_host'} ) : (),
        $self->{'server_port'} ? ('LocalPort' => $self->{'server_port'} ) : (),
    ) || die "Could not create the server";

    print "Please contact me at: <URL:", $daemon->url, ">\n";
    while (my $c = $daemon->accept) {
        if (my $r = $c->get_request) {
            if($r->method eq 'GET' and $r->uri->path eq '/seed') {
                my %query_form = $r->uri->query_form();

                my $analysis_name   = $query_form{'analysis_name'}  || $query_form{'logic_name'};
                my $job_parameters  = $query_form{'job_parameters'} || $query_form{'input_id'};

                my $response;

                if($analysis_name and $job_parameters) {    # assume all the parameters are given

                    $job_parameters = stringify(destringify($job_parameters));  # enforce the inner quotes to be double

                    my $url         = $self->{'pipeline'}->hive_dba->dbc->url;
                    my $ret_string = `seed_pipeline.pl -url $url -analyses_pattern $analysis_name -input_id '$job_parameters' 2>&1`;

                    if($ret_string=~/^Job\s+(\d+)/) {
                        my $job_id=$1;

                        $response = HTTP::Response->new( RC_OK );           # 200
                        $response->header( "Content-Type" => "text/plain" );
                        $response->content(  "Analysis name:\t\t$analysis_name\n"
                                            ."Job parameters:\t\t$job_parameters\n"
                                            ."Created job_id:\t\t$job_id\n"
                        );
                    } else {
                        $response = HTTP::Response->new( RC_BAD_REQUEST );  # 400
                        $response->header( "Content-Type" => "text/plain" );
                        $response->content(  "Something went wrong, please investigate:\n\n"
                                            ."Analysis name:\t\t$analysis_name\n"
                                            ."Job parameters:\t\t$job_parameters\n"
                                            ."seed_pipeline output:\t\t$ret_string\n"
                        );
                    }

                } else {
                    $response = HTTP::Response->new( RC_OK );               # 200
                    $response->header( "Content-Type" => "text/html" );

                        # ToDo: If we ever decide to switch to a schema-agnostic RESTful server written in another language,
                        #       the list of analysis names can be parsed from:
                        #
                        #           tweak_pipeline.pl -url $url -SHOW 'analysis[%].logic_name' | grep Tweak.Show
                        #
                    my @analyses = $self->{'pipeline'}->collection_of('Analysis')->list();

                    my $callback_url = $daemon->url . 'seed';

                    $response->content(  "<html><head><title>Please pick an analysis to seed</title></head>\n"
                                        ."<body><h1>Please provide the following parameters to seed an eHive job:</h1>\n"
                                        ."<form action='$callback_url' method='get'>\n"
                                        ."Analysis name: <select name='analysis_name'>"
                                        .join( "\n", map { "<option value='". $_->logic_name ."'>". $_->logic_name . "</option>" } @analyses) . "</select><br/>\n"
                                        ."Job parameters: <textarea name='job_parameters' rows=4 cols=64></textarea>\n"
                                        ."<input type='submit' value='Submit'></form>\n"
                                        ."</body></html>\n" );
                }

                $c->send_response( $response );
            } else {
                $c->send_error( RC_FORBIDDEN );                             # 403
            }
        }
        $c->close;
        undef($c);
    }
}


__DATA__

=pod

=head1 NAME

    rpc_server.pl [options]

=head1 DESCRIPTION

    rpc_server.pl is an eHive component script that stays permanently connected to a pipeline database
    and accepts connections as an HTTP server.

    Currently it supports job seeding requests and dispatches them to seed_pipeline.pl script locally.

    No pipeline database connection details flow through HTTP:
    you only need to know server_url, analysis_name and job_parameters to seed a job via the server.

=head1 USAGE EXAMPLES

        # Run the server on the default local interface and use the default port 54321
    rpc_server.pl -pipeline_url mysql://username:secret@hostname:port/ehive_dbname

        # Run the server on the default local interface and use the chosen port 55443
    rpc_server.pl -pipeline_url mysql://username:secret@hostname:port/ehive_dbname -server_port 55443

        # Run the server on the default local interface and use a randomly-generated port number
    rpc_server.pl -pipeline_url mysql://username:secret@hostname:port/ehive_dbname -server_port 0

        # Connect the server to the pipeline database using registry data
    rpc_server.pl -reg_conf </path/to/reg_conf/file> -reg_alias <reg_alias>

=head1 OPTIONS

=head2 Connection parameters:

    -reg_conf <path>            : path to a Registry configuration file
    -reg_alias <string>         : species/alias name for the Hive DBAdaptor
    -reg_type <string>          : type of the registry entry ('hive', 'core', 'compara', etc - defaults to 'hive')
    -pipeline_url <url string>  : the url pointing at the pipeline database
    -nosqlvc <0|1>              : skip sql version check if 1

=head2 HTTP server options:

    -server_host <string>       : desired host name for the server (if there is a choice). `hostname` by default
    -server_port <number>       : desired port number for the server. 54321 by default, 0 to allocate a random port number

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

