
package Bio::EnsEMBL::Hive::Scripts::InitPipeline;

use strict;
use warnings;

use Test::More;

use Bio::EnsEMBL::Hive::Process;
use Bio::EnsEMBL::Hive::AnalysisJob;
use Bio::EnsEMBL::Hive::Utils ('load_file_or_module', 'stringify', 'destringify');


sub init_pipeline {
    my ($file_or_module) = @_;

    my $pipeconfig_package_name = load_file_or_module( $file_or_module );
    die "$file_or_module not loaded\n" unless $pipeconfig_package_name;

    my $pipeconfig_object = $pipeconfig_package_name->new();
    die "PipeConfig $pipeconfig_package_name not created\n" unless $pipeconfig_object;
    die "PipeConfig $pipeconfig_package_name is not a Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf\n" unless $pipeconfig_object->isa('Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf');

    $pipeconfig_object->process_options( 1 );

    $pipeconfig_object->run_pipeline_create_commands();

    my $hive_dba = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( -url => $pipeconfig_object->pipeline_url(), -no_sql_schema_version_check => 1 );
    die "Hive's DBAdaptor could not be created for ".$pipeconfig_object->pipeline_url() unless $hive_dba;

    $hive_dba->load_collections();

    $pipeconfig_object->add_objects_from_config();

    $hive_dba->save_collections();

    print $pipeconfig_object->useful_commands_legend();

    return $hive_dba;
}


1;
