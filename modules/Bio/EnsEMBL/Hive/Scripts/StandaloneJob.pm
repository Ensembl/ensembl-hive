=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2021] EMBL-European Bioinformatics Institute

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


package Bio::EnsEMBL::Hive::Scripts::StandaloneJob;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::AnalysisJob;
use Bio::EnsEMBL::Hive::GuestProcess;
use Bio::EnsEMBL::Hive::HivePipeline;
use Bio::EnsEMBL::Hive::Process;
use Bio::EnsEMBL::Hive::Utils ('load_file_or_module', 'destringify');
use Bio::EnsEMBL::Hive::Utils::PCL;


sub standaloneJob {
    my ($module_or_file, $input_id, $flags, $flow_into, $language) = @_;

    my $runnable_module = $language ? 'Bio::EnsEMBL::Hive::GuestProcess' : load_file_or_module( $module_or_file );


    my $runnable_object = $runnable_module->new($language, $module_or_file);    # Only GuestProcess will read the arguments
    die "Runnable $module_or_file not created\n" unless $runnable_object;
    $runnable_object->debug($flags->{debug}) if $flags->{debug};
    $runnable_object->execute_writes(not $flags->{no_write});

    my $hive_pipeline = Bio::EnsEMBL::Hive::HivePipeline->new();

    my ($dummy_analysis) = $hive_pipeline->add_new_or_update( 'Analysis',   # NB: add_new_or_update returns a list
        'logic_name'    => 'Standalone_Dummy_Analysis',     # looks nicer when printing out DFRs
        'module'        => ref($runnable_object),
        'dbID'          => -1,
    );

    my $job = Bio::EnsEMBL::Hive::AnalysisJob->new(
        'hive_pipeline' => $hive_pipeline,
        'analysis'      => $dummy_analysis,
        'input_id'      => $input_id,
        'dbID'          => -1,
    );

    $job->load_parameters( $runnable_object );


    if($flow_into) {
        Bio::EnsEMBL::Hive::Utils::PCL::parse_flow_into($hive_pipeline, $dummy_analysis, destringify($flow_into) );
    }

    $runnable_object->input_job($job);
    $runnable_object->life_cycle();

    $runnable_object->cleanup_worker_temp_directory() unless $flags->{no_cleanup};

    return !$job->died_somewhere()
}


1;
