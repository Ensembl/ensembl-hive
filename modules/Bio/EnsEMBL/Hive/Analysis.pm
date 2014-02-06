=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Analysis

=head1 DESCRIPTION

    An Analysis object represents a "stage" of the Hive pipeline that groups together
    all jobs that share the same module and the same common parameters.

    Individual Jobs are said to "belong" to an Analysis.

    Control rules unblock when their condition Analyses are done.

=head1 LICENSE

    Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

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

use Bio::EnsEMBL::Hive::Utils ('stringify');

use base (  'Bio::EnsEMBL::Hive::Storable' );
 

sub logic_name {
    my $self = shift;
    $self->{'_logic_name'} = shift if(@_);
    return $self->{'_logic_name'};
}


sub module {
    my $self = shift;
    $self->{'_module'} = shift if(@_);
    return $self->{'_module'};
}


sub parameters {
    my $self = shift;
    if(@_) {
        my $parameters = shift @_;
        $self->{'_parameters'} = ref($parameters) ? stringify($parameters) : $parameters;
    }
    return $self->{'_parameters'};
}


sub resource_class_id {
    my $self = shift;
    $self->{'_resource_class_id'} = shift if(@_);
    return $self->{'_resource_class_id'};
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

    eval "require $runnable_module_name";
    die "The runnable module '$runnable_module_name' cannot be loaded or compiled:\n$@" if($@);
    die "Problem accessing methods in '$runnable_module_name'. Please check that it inherits from Bio::EnsEMBL::Hive::Process and is named correctly.\n"
        unless($runnable_module_name->isa('Bio::EnsEMBL::Hive::Process'));

    return $runnable_module_name;
}


=head2 process

  Arg [1]    : none
  Example    : $process = $analysis->process;
  Description: construct a Process object from the $analysis->module name
  Returntype : Bio::EnsEMBL::Hive::Process subclass 
  Exceptions : none
  Caller     : general

=cut

sub process {
    my $self = shift;

    my $runnable_object = $self->get_compiled_module_name->new();
    $runnable_object->analysis( $self );

    return $runnable_object;
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
    my $self = shift;

    return undef unless($self->adaptor);

    return $self->adaptor->db->dbc->url . '/analysis?logic_name=' . $self->logic_name;
}


=head2 stats

  Arg [1]    : none
  Example    : $stats = $analysis->stats;
  Description: returns the AnalysisStats object associated with this Analysis
               object.  Does not cache, but pull from database by using the
               Analysis objects adaptor->db.
  Returntype : Bio::EnsEMBL::Hive::AnalysisStats object
  Exceptions : none
  Caller     : general

=cut

sub stats {
    my $self = shift;

    # Not cached internally since we want it to always be in sync with the database.
    # Otherwise the user application would need to be aware of the sync state and send explicit 'sync' calls.

    my $stats = $self->adaptor->db->get_AnalysisStatsAdaptor->fetch_by_analysis_id($self->dbID);
    return $stats;
}


sub toString {
    my $self = shift @_;

    return (ref($self).': '.join(', ', map { $_.'="'.$self->$_().'"' } qw(dbID logic_name module parameters) ));
}

1;

