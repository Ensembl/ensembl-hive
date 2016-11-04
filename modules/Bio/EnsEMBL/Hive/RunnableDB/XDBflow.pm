=pod

=head1 NAME

    Bio::EnsEMBL::Hive::RunnableDB::Dummy

=head1 SYNOPSIS

    standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::Dummy -input_id "{}"

    standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::Dummy -input_id "{take_time=>3}"

    standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::Dummy -input_id "{take_time=>'rand(3)+1'}"

=head1 DESCRIPTION

    A job of 'Bio::EnsEMBL::Hive::RunnableDB::Dummy' analysis does not do any work by itself,
    but it benefits from the side-effects that are associated with having an analysis.

    For example, if a dataflow rule is linked to the analysis then
    every job that is created or flown into this analysis will be dataflown further according to this rule.

    param('take_time'):     How much time to spend sleeping (floating point seconds);
                            can be given by a runtime-evaluated formula; useful for testing.

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


package Bio::EnsEMBL::Hive::RunnableDB::XDBflow;

use strict;
use warnings;
use Bio::EnsEMBL::Hive::Utils::PCL;

use base ('Bio::EnsEMBL::Hive::Process');


sub param_defaults {
    return {
        'target_analysis_url'   => '#target_pipeline_url#?logic_name=#target_analysis_name#',     # by default, build the URL out of components
        'target_template'       => undef,
        'target_input_plus'     => 0,
        'target_input_id'       => {},
    };
}


sub run {
    my $self = shift @_;

    my $target_analysis_url     = $self->param_required('target_analysis_url');
    my $target_template         = $self->param('target_template');
    my $target_input_plus       = $self->param('target_input_plus');
    my $analysis                = $self->input_job->analysis;
    my $pipeline                = $self->input_job->analysis->hive_pipeline;

    Bio::EnsEMBL::Hive::Utils::PCL::parse_flow_into($pipeline, $analysis,
        { 1 => { $target_analysis_url => $target_input_plus ? INPUT_PLUS($target_template):$target_template } }
    );
}


sub write_output {
    my $self = shift @_;

    my $target_input_id         = $self->param('target_input_id');

    $self->dataflow_output_id( $target_input_id, 1);
}

1;
