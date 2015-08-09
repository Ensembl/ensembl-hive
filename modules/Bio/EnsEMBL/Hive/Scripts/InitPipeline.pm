=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

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


package Bio::EnsEMBL::Hive::Scripts::InitPipeline;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::HivePipeline;
use Bio::EnsEMBL::Hive::Utils ('load_file_or_module');


sub init_pipeline {
    my ($file_or_module) = @_;

    my $pipeconfig_package_name = load_file_or_module( $file_or_module );

    my $pipeconfig_object = $pipeconfig_package_name->new();
    die "PipeConfig $pipeconfig_package_name not created\n" unless $pipeconfig_object;
    die "PipeConfig $pipeconfig_package_name is not a Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf\n" unless $pipeconfig_object->isa('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');

    $pipeconfig_object->process_options( 1 );

    $pipeconfig_object->run_pipeline_create_commands();

    my $pipeline = Bio::EnsEMBL::Hive::HivePipeline->new(
                -url => $pipeconfig_object->pipeline_url(),
                -no_sql_schema_version_check => !$pipeconfig_object->is_analysis_topup );

    my $hive_dba = $pipeline->hive_dba()
        or die "HivePipeline could not be created for ".$pipeconfig_object->pipeline_url();

    $pipeconfig_object->add_objects_from_config( $pipeline );

    $pipeline->save_collections();

    print $pipeconfig_object->useful_commands_legend();

    $hive_dba->dbc->disconnect_if_idle;     # This is necessary because the current lack of global DBC caching may leave this DBC connected and prevent deletion of the DB in pgsql mode

    return $hive_dba->dbc->url;
}


1;
