=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Analysis

=head1 DESCRIPTION

    An Analysis object represents a "stage" of the Hive pipeline that groups together
    all jobs that share the same module and the same common parameters.

    Individual Jobs are said to "belong" to an Analysis.

    Control rules unblock when their condition Analyses are done.

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


package Bio::EnsEMBL::Hive::Analysis;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Utils ('stringify');
use Bio::EnsEMBL::Hive::AnalysisCtrlRule;
use Bio::EnsEMBL::Hive::DataflowRule;
use Bio::EnsEMBL::Hive::GuestProcess;

use base ( 'Bio::EnsEMBL::Hive::Cacheable', 'Bio::EnsEMBL::Hive::Storable' );
 

sub unikey {    # override the default from Cacheable parent
    return [ 'logic_name' ];
}


=head1 AUTOLOADED

    resource_class_id / resource_class

=cut


sub logic_name {
    my $self = shift;
    $self->{'_logic_name'} = shift if(@_);
    return $self->{'_logic_name'};
}

sub name {              # a useful synonym
    my $self = shift;

    return $self->logic_name(@_);
}


sub module {
    my $self = shift;
    $self->{'_module'} = shift if(@_);
    return $self->{'_module'};
}

sub language {
    my $self = shift;
    $self->{'_language'} = shift if(@_);
    return $self->{'_language'};
}


sub parameters {
    my $self = shift;
    if(@_) {
        my $parameters = shift @_;
        $self->{'_parameters'} = ref($parameters) ? stringify($parameters) : $parameters;
    }
    return $self->{'_parameters'};
}


sub failed_job_tolerance {
    my $self = shift;
    $self->{'_failed_job_tolerance'} = shift if(@_);
    $self->{'_failed_job_tolerance'} = 0 unless(defined($self->{'_failed_job_tolerance'}));
    return $self->{'_failed_job_tolerance'};
}


sub max_retry_count {
    my $self = shift;
    $self->{'_max_retry_count'} = shift if(@_);
    $self->{'_max_retry_count'} = 3 unless(defined($self->{'_max_retry_count'}));
    return $self->{'_max_retry_count'};
}


sub can_be_empty {
    my $self = shift;
    $self->{'_can_be_empty'} = shift if(@_);
    $self->{'_can_be_empty'} = 0 unless(defined($self->{'_can_be_empty'}));
    return $self->{'_can_be_empty'};
}


sub priority {
    my $self = shift;
    $self->{'_priority'} = shift if(@_);
    $self->{'_priority'} = 0 unless(defined($self->{'_priority'}));
    return $self->{'_priority'};
}


sub meadow_type {
    my $self = shift;
    $self->{'_meadow_type'} = shift if(@_);
    return $self->{'_meadow_type'};
}


sub analysis_capacity {
    my $self = shift;
    $self->{'_analysis_capacity'} = shift if(@_);
    return $self->{'_analysis_capacity'};
}


sub get_compiled_module_name {
    my $self = shift;

    my $runnable_module_name = $self->module
        or die "Analysis '".$self->logic_name."' does not have its 'module' defined";

    if ($self->language) {
        my $wrapper = Bio::EnsEMBL::Hive::GuestProcess::_get_wrapper_for_language($self->language);
        if (system($wrapper, 'compile', $runnable_module_name)) {
            die "The runnable module '$runnable_module_name' cannot be loaded or compiled:\n";
        }
        return 'Bio::EnsEMBL::Hive::GuestProcess';
    }

    eval "require $runnable_module_name";
    die "The runnable module '$runnable_module_name' cannot be loaded or compiled:\n$@" if($@);
    die "Problem accessing methods in '$runnable_module_name'. Please check that it inherits from Bio::EnsEMBL::Hive::Process and is named correctly.\n"
        unless($runnable_module_name->isa('Bio::EnsEMBL::Hive::Process'));

    die "DEPRECATED: the strict_hash_format() method is no longer supported in Runnables - the input_id() in '$runnable_module_name' has to be a hash now.\n"
        if($runnable_module_name->can('strict_hash_format'));

    return $runnable_module_name;
}


=head2 url

  Arg [1]    : none
  Example    : $url = $analysis->url;
  Description: Constructs a URL string for this database connection
               Follows the general URL rules.
  Returntype : string of format
               mysql://<user>:<pass>@<host>:<port>/<dbname>/analysis?logic_name=<name>
  Exceptions : none
  Caller     : general

=cut

sub url {
    my ($self, $ref_dba) = @_;  # if reference dba is the same as 'my' dba, a shorter url is generated

    my $my_dba = $self->adaptor && $self->adaptor->db;
    return ( ($my_dba and $my_dba ne ($ref_dba//'') ) ? $my_dba->dbc->url . '/analysis?logic_name=' : '') . $self->logic_name;
}


sub display_name {
    my ($self, $ref_dba) = @_;  # if reference dba is the same as 'my' dba, a shorter display_name is generated

    my $my_dba = $self->adaptor && $self->adaptor->db;
    return ( ($my_dba and $my_dba ne ($ref_dba//'') ) ? $my_dba->dbc->dbname . '/' : '' ) . $self->logic_name;
}


=head2 stats

  Arg [1]    : none
  Example    : $stats = $analysis->stats;
  Description: returns either the previously cached AnalysisStats object, or if it is missing - pulls a fresh one from the DB.
  Returntype : Bio::EnsEMBL::Hive::AnalysisStats object
  Exceptions : none
  Caller     : general

=cut

sub stats {
    my $self = shift @_;

    my $collection = Bio::EnsEMBL::Hive::AnalysisStats->collection();

    return ($collection && $collection->find_one_by('analysis', $self) )
        || $self->adaptor->db->get_AnalysisStatsAdaptor->fetch_by_analysis_id( $self->dbID );
}


sub jobs_collection {
    my $self = shift @_;

    $self->{'_jobs_collection'} = shift if(@_);

    return $self->{'_jobs_collection'} ||= [];
}


sub control_rules_collection {
    my $self = shift @_;

    my $collection = Bio::EnsEMBL::Hive::AnalysisCtrlRule->collection();

    return $collection
        ? $collection->find_all_by('ctrled_analysis', $self)
        : $self->adaptor->db->get_AnalysisCtrlRuleAdaptor->fetch_all_by_ctrled_analysis_id( $self->dbID );
}


sub dataflow_rules_collection {
    my $self = shift @_;

    my $collection = Bio::EnsEMBL::Hive::DataflowRule->collection();

    return $collection
        ? $collection->find_all_by('from_analysis', $self)
        : $self->adaptor->db->get_DataflowRuleAdaptor->fetch_all_by_from_analysis_id( $self->dbID );
}


sub dataflow_rules_by_branch {
    my $self = shift @_;

    if (not $self->{'_dataflow_rules_by_branch'}) {
        my %dataflow_rules_by_branch = ();
        foreach my $dataflow (@{$self->dataflow_rules_collection}) {
            push @{$dataflow_rules_by_branch{$dataflow->branch_code}}, $dataflow;
        }
        $self->{'_dataflow_rules_by_branch'} = \%dataflow_rules_by_branch;
    }

    return $self->{'_dataflow_rules_by_branch'};
}


sub toString {
    my $self = shift @_;

    return 'Analysis['.($self->dbID // '').']: '.$self->display_name.'->('.join(', ', $self->module.($self->language ? sprintf(' (%s)', $self->language) : ''), $self->parameters, $self->resource_class->name).')';
}

1;

