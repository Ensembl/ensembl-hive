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


package Bio::EnsEMBL::Hive::Scripts::StandaloneJob;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Process;
use Bio::EnsEMBL::Hive::GuestProcess;
use Bio::EnsEMBL::Hive::AnalysisJob;
use Bio::EnsEMBL::Hive::HivePipeline;
use Bio::EnsEMBL::Hive::Utils ('load_file_or_module', 'stringify', 'destringify');

sub standaloneJob {
    my ($module_or_file, $input_id, $flags, $flow_into, $language) = @_;

    my $runnable_module = $language ? 'Bio::EnsEMBL::Hive::GuestProcess' : load_file_or_module( $module_or_file );


    my $runnable_object = $runnable_module->new($language, $module_or_file);    # Only GuestProcess will read the arguments
    die "Runnable $module_or_file not created\n" unless $runnable_object;
    $runnable_object->debug($flags->{debug}) if $flags->{debug};
    $runnable_object->execute_writes(not $flags->{no_write});

    my $hive_pipeline = Bio::EnsEMBL::Hive::HivePipeline->new();

    my $dummy_analysis = $hive_pipeline->add_new_or_update( 'Analysis',
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

    $flow_into = $flow_into ? destringify($flow_into) : []; # empty dataflow for branch 1 by default

    # -------------------------------------------- DFR parser cloned from HiveGeneric_conf

        $flow_into   = { 1 => $flow_into } unless(ref($flow_into) eq 'HASH'); # force non-hash into a hash

        my %group_tag_to_funnel_dataflow_rule = ();

        my $semaphore_sign = '->';

        my @all_branch_tags = keys %$flow_into;
        foreach my $branch_tag ((grep {/^[A-Z]$semaphore_sign/} @all_branch_tags), (grep {/$semaphore_sign[A-Z]$/} @all_branch_tags), (grep {!/$semaphore_sign/} @all_branch_tags)) {

            my ($branch_name_or_code, $group_role, $group_tag);

            if($branch_tag=~/^([A-Z])$semaphore_sign(-?\w+)$/) {
                ($branch_name_or_code, $group_role, $group_tag) = ($2, 'funnel', $1);
            } elsif($branch_tag=~/^(-?\w+)$semaphore_sign([A-Z])$/) {
                ($branch_name_or_code, $group_role, $group_tag) = ($1, 'fan', $2);
            } elsif($branch_tag=~/^(-?\w+)$/) {
                ($branch_name_or_code, $group_role, $group_tag) = ($1, '');
            } elsif($branch_tag=~/:/) {
                die "Please use newer '2${semaphore_sign}A' and 'A${semaphore_sign}1' notation instead of '2:1' and '1'\n";
            } else {
                die "Error parsing the group tag '$branch_tag'\n";
            }

            my $funnel_dataflow_rule = undef;    # NULL by default

            if($group_role eq 'fan') {
                unless($funnel_dataflow_rule = $group_tag_to_funnel_dataflow_rule{$group_tag}) {
                    die "No funnel dataflow_rule defined for group '$group_tag'\n";
                }
            }

            my $heirs = $flow_into->{$branch_tag};
            $heirs = [ $heirs ] unless(ref($heirs)); # force scalar into an arrayref first
            $heirs = { map { ($_ => undef) } @$heirs } if(ref($heirs) eq 'ARRAY'); # now force it into a hash if it wasn't

            while(my ($heir_url, $input_id_template_list) = each %$heirs) {

                $input_id_template_list = [ $input_id_template_list ] unless(ref($input_id_template_list) eq 'ARRAY');  # allow for more than one template per analysis

                foreach my $input_id_template (@$input_id_template_list) {

                    my $df_rule = $hive_pipeline->add_new_or_update( 'DataflowRule',
                        'from_analysis'             => $dummy_analysis,
                        'to_analysis_url'           => $heir_url,
                        'branch_code'               => $branch_name_or_code,
                        'funnel_dataflow_rule'      => $funnel_dataflow_rule,
                        'input_id_template'         => $input_id_template,
                    );

                    if($group_role eq 'funnel') {
                        if($group_tag_to_funnel_dataflow_rule{$group_tag}) {
                            die "More than one funnel dataflow_rule defined for group '$group_tag'\n";
                        } else {
                            $group_tag_to_funnel_dataflow_rule{$group_tag} = $df_rule;
                        }
                    }
                } # /for all templates
            } # /for all heirs
        } # /for all branch_tags

    # -------------------------------------------- / DFR parser cloned from HiveGeneric_conf

    $runnable_object->input_job($job);
    $runnable_object->life_cycle();

    $runnable_object->cleanup_worker_temp_directory() unless $flags->{no_cleanup};

    return !$job->died_somewhere()
}


1;
