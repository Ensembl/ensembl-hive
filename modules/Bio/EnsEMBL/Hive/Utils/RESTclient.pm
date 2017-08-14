=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2017] EMBL-European Bioinformatics Institute

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

=pod

=head1 NAME

Bio::EnsEMBL::Hive::Utils::RESTclient

=cut

package Bio::EnsEMBL::Hive::Utils::RESTclient;

use strict;
use warnings;
use JSON;


sub GET {
    my ($request_url, $raw_json_output_filename)  = @_;

    my $json_output_string  = `curl $request_url`;

    if($raw_json_output_filename) {
        open(my $fh, ">$raw_json_output_filename");
        print $fh $json_output_string;
        close $fh;
    }

    my $perl_struct         = JSON->new->decode( $json_output_string );

    return $perl_struct;
}


sub POST {
    my ($request_url, $request_data_struct, $raw_json_output_filename)  = @_;

    my $request_data        = JSON->new->encode( $request_data_struct );
    my $json_output_string  = `curl -X POST -H "Content-Type: application/json" -d '$request_data' $request_url`;

    if($raw_json_output_filename) {
        open(my $fh, ">$raw_json_output_filename");
        print $fh $json_output_string;
        close $fh;
    }

    my $perl_struct         = JSON->new->decode( $json_output_string );

    return $perl_struct;
}

1;
