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
    Copyright [2016-2023] EMBL-European Bioinformatics Institute

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

use Bio::EnsEMBL::Hive::Utils::Collection;
use Bio::EnsEMBL::Hive::Utils::URL;
use Bio::EnsEMBL::Hive::HivePipeline;


    # global instance to cache HivePipeline objects:
my $_global_Apiary_collection;


sub pipelines_collection {
    my $class   = shift @_;

    return $_global_Apiary_collection ||= Bio::EnsEMBL::Hive::Utils::Collection->new;
}


sub pipelines_except {
    my ($class, $except_pipeline)   = @_;

    my $except_unambig_key  = $except_pipeline->unambig_key;

    return [ grep { $_->unambig_key ne $except_unambig_key } $class->pipelines_collection->list ];
}


sub find_by_url {
    my $class            = shift @_;
    my $url              = shift @_;
    my $default_pipeline = shift @_;
    my $no_die           = shift @_;

    if(my $parsed_url = Bio::EnsEMBL::Hive::Utils::URL::parse( $url )) {

        my $unambig_key     = Bio::EnsEMBL::Hive::Utils::URL::hash_to_unambig_url( $parsed_url );
        my $query_params    = $parsed_url->{'query_params'};
        my $conn_params     = $parsed_url->{'conn_params'};

        my $disconnect_when_inactive    = $conn_params->{'disconnect_when_inactive'};
        my $no_sql_schema_version_check = $conn_params->{'no_sql_schema_version_check'};

        my $hive_pipeline;

        if($unambig_key eq ':///') {

            $hive_pipeline = $default_pipeline;

        } elsif( not ($hive_pipeline = $class->pipelines_collection->find_one_by( 'unambig_key', $unambig_key ) ) ) {

            if($query_params and ($query_params->{'object_type'} eq 'NakedTable') ) {  # do not check schema version when performing table dataflow:
                $no_sql_schema_version_check = 1;
            }

            $hive_pipeline = Bio::EnsEMBL::Hive::HivePipeline->new(         # calling HivePipeline->new() triggers automatic addition to TheApiary
                -url                        => $parsed_url->{'dbconn_part'},
                -disconnect_when_inactive   => $disconnect_when_inactive,
                -no_sql_schema_version_check=> $no_sql_schema_version_check,
            );
        }

        return  $query_params
            ? $hive_pipeline->find_by_query( $query_params, $no_die )
            : $hive_pipeline;

    } else {
        die "Could not parse '$url' as URL";
    }
}


sub fetch_remote_semaphores_controlling_this_one {      # NB! This method has a (potentially unwanted) side-effect of adding @extra_pipelines to TheApiary. Use with caution.
    my ($class, $this_semaphore_or_url, @extra_pipelines) = @_;

    my $this_semaphore_url = ref($this_semaphore_or_url)
                                ? $this_semaphore_or_url->relative_url( 0 )     # turn a semaphore into its global URL
                                : $this_semaphore_or_url;                       # just use the provided URL

    my @remote_controlling_semaphores = ();

    foreach my $remote_pipeline ($class->pipelines_collection->list, @extra_pipelines ) {

        push @remote_controlling_semaphores, @{ $remote_pipeline->hive_dba->get_SemaphoreAdaptor->fetch_all_by_dependent_semaphore_url( $this_semaphore_url ) };
    }

    return \@remote_controlling_semaphores;
}

1;
