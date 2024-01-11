=pod

=head1 NAME

    Bio::EnsEMBL::Hive::Utils::RESTclient

=head1 SYNOPSIS

        # Example without an instance:
    my $task_id_mapping = Bio::EnsEMBL::Hive::Utils::RESTclient->POST(
                                'http://server.address:1234/create_tasks?with=parameters',
                                $extra_data_hash,
                                'intermediate_dump.json'
                        );

        # Example with an instance:
    my $head_node           = Bio::EnsEMBL::Hive::Utils::RESTclient->new( 'http://server.address:1234' );

    my $swarm_id            = $head_node->GET( '/swarm' )->{'ID'};
    my $tasks_struct        = $head_node->GET( '/tasks', "${output_prefix}/${container_prefix}.tasks.json" );
    my $nodes_struct        = $head_node->GET( '/nodes', "${output_prefix}/${container_prefix}.nodes.json" );

=head1 DESCRIPTION

    This module provides a generic REST client interface via GET and POST methods.
    The current implementation is via calling 'curl' external command and capturing its output.

    There is no requirement to instantiate an object when using this module (same methods will work as class methods),
    but if you need to make multiple requests to the same server you may find it convenient to store its base_url in the object.

=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2024] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


package Bio::EnsEMBL::Hive::Utils::RESTclient;

use strict;
use warnings;
use JSON;


sub new {
    my $class = shift @_;

    my $self = bless {}, $class;

    $self->base_url( shift @_ // '' );

    return $self;
}


sub base_url {
    my $self = shift @_;

    $self->{'_base_url'} = shift if(@_);
    return $self->{'_base_url'};
}


sub run_curl_capture_and_parse_result {
    my ($self, $curl_cmd, $raw_json_output_filename) = @_;

    open(my $curl_output_fh, "-|", @$curl_cmd) || die "Could not run '".join(' ',@$curl_cmd)."' : $!, $?";
    my $json_output_string  = <$curl_output_fh>;
    close $curl_output_fh;

    if($raw_json_output_filename) {
        open(my $fh, '>', $raw_json_output_filename);
        print $fh $json_output_string;
        close $fh;
    }

    my $perl_struct     = $json_output_string && JSON->new->decode( $json_output_string );

    return $perl_struct;
}


sub GET {
    my ($self, $request_url, $raw_json_output_filename)  = @_;

    my $base_url        = ref($self) ? $self->base_url : '';
    my $curl_cmd        = ['curl', '-g', '-s', $base_url.$request_url];

    return $self->run_curl_capture_and_parse_result( $curl_cmd, $raw_json_output_filename );
}


sub POST {
    my ($self, $request_url, $request_data_struct, $raw_json_output_filename)  = @_;

    my $base_url        = ref($self) ? $self->base_url : '';
    my $request_data    = JSON->new->encode( $request_data_struct );
    my $curl_cmd        = ['curl', '-g', '-s', '-X', 'POST', '-H', 'Content-Type: application/json', '-d', $request_data, $base_url.$request_url];

    return $self->run_curl_capture_and_parse_result( $curl_cmd, $raw_json_output_filename );
}

1;
