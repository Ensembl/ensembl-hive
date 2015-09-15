=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::TheApiary

=head1 SYNOPSIS

    my $hive_pipeline = Bio::EnsEMBL::Hive::TheApiary->find_by_url( 'mysql://ensro@compara3/lg4_long_mult' );

    my $final_result_table = Bio::EnsEMBL::Hive::TheApiary->find_by_url( 'mysql://ensro@compara3/lg4_long_mult?table_name=final_result' );

=head1 DESCRIPTION  

    Global cache for HivePipeline objects.

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::TheApiary;

use strict;
use warnings;
use Data::Dumper;

use Bio::EnsEMBL::Hive::Utils::URL;
use Bio::EnsEMBL::Hive::HivePipeline;


    # global instance to cache HivePipeline objects:
my $_global_Apiary_hash;


sub pipelines_collection {
    my $class   = shift @_;

    return $_global_Apiary_hash ||= {};
}


sub find_by_url {
    my $class            = shift @_;
    my $url              = shift @_;
    my $default_pipeline = shift @_;

    if(my $parsed_url = Bio::EnsEMBL::Hive::Utils::URL::parse( $url )) {

        my $real_url        = $parsed_url->{'dbconn_part'};
        my $unambig_url     = $parsed_url->{'unambig_url'};
        my $table_name      = $parsed_url->{'table_name'};
        my $conn_params     = $parsed_url->{'conn_params'};

        my $disconnect_when_inactive    = $conn_params->{'disconnect_when_inactive'};
        my $no_sql_schema_version_check = $conn_params->{'no_sql_schema_version_check'};

        my $hive_pipeline;

        if($parsed_url->{'unambig_url'} eq ':///') {

            $hive_pipeline = $default_pipeline;

        } elsif( not ($hive_pipeline = $class->pipelines_collection->{ $unambig_url }) ) {

            if($table_name and $table_name!~/^(analysis|accu|job)$/) {  # do not check schema version when performing table dataflow:
                $no_sql_schema_version_check = 1;
            }

            $class->pipelines_collection->{ $unambig_url } = $hive_pipeline = Bio::EnsEMBL::Hive::HivePipeline->new(
                -url                        => $real_url,
                -disconnect_when_inactive   => $disconnect_when_inactive,
                -no_sql_schema_version_check=> $no_sql_schema_version_check,
            );
        }

        return  $table_name
            ? $hive_pipeline->find_by_url_query( $parsed_url )
            : $hive_pipeline;

    } else {
        die "Could not parse '$url' as URL";
    }
}


1;
