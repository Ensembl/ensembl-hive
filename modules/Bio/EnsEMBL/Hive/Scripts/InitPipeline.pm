
package Bio::EnsEMBL::Hive::Scripts::InitPipeline;

use strict;
use warnings;

use Test::More;

use Bio::EnsEMBL::Hive::Process;
use Bio::EnsEMBL::Hive::AnalysisJob;
use Bio::EnsEMBL::Hive::Utils ('load_file_or_module', 'stringify', 'destringify');


sub init_pipeline {
    my ($file_or_module, $do_tests) = @_;

    my $pipeconfig_package_name = load_file_or_module( $file_or_module );
    ok($pipeconfig_package_name, "module '$file_or_module' is loaded") if $do_tests;

    my $pipeconfig_object = $pipeconfig_package_name->new();
    isa_ok($pipeconfig_object, 'Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf') if $do_tests;

    $pipeconfig_object->process_options( 1 );
    pass('Command-line options have been processed') if $do_tests;

    $pipeconfig_object->run_pipeline_create_commands();
    pass('Create commands could be run') if $do_tests;

    my $hive_dba = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( -url => $pipeconfig_object->pipeline_url(), -no_sql_schema_version_check => 1 );
    isa_ok($hive_dba, 'Bio::EnsEMBL::Hive::DBSQL::DBAdaptor', 'hive DBA is correct') if $do_tests;

    $hive_dba->load_collections();
    pass('Database pre-existing content could be loaded') if $do_tests;

    $pipeconfig_object->add_objects_from_config();
    pass('PipeConfig data could be loaded') if $do_tests;

    $hive_dba->save_collections();
    pass('New pipeline could be stored in the database') if $do_tests;

    print $pipeconfig_object->useful_commands_legend();

    return $hive_dba;
}


1;
