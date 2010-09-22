#
# You may distribute this module under the same terms as perl itself

=pod 

=head1 NAME

  Bio::EnsEMBL::Hive::AnalysisJob

=head1 DESCRIPTION

  An AnalysisJob is the link between the input_id control data, the analysis and
  the rule system.  It also tracks the state of the job as it is processed

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=head1 APPENDIX

  The rest of the documentation details each of the object methods.
  Internal methods are usually preceded with a _

=cut


package Bio::EnsEMBL::Hive::AnalysisJob;

use strict;
use Bio::EnsEMBL::Utils::Argument;  # import 'rearrange()'

use base ('Bio::EnsEMBL::Hive::Params');

sub new {
    my $class = shift @_;

    my $self = bless {}, $class;

    my($dbID, $analysis_id, $input_id, $job_claim, $worker_id, $status, $retry_count, $completed, $runtime_msec, $query_count, $semaphore_count, $semaphored_job_id, $adaptor) =
        rearrange([qw(dbID analysis_id input_id job_claim worker_id status retry_count completed runtime_msec query_count semaphore_count semaphored_job_id adaptor) ], @_);

    $self->dbID($dbID)                          if(defined($dbID));
    $self->analysis_id($analysis_id)            if(defined($analysis_id));
    $self->input_id($input_id)                  if(defined($input_id));
    $self->job_claim($job_claim)                if(defined($job_claim));
    $self->worker_id($worker_id)                if(defined($worker_id));
    $self->status($status)                      if(defined($status));
    $self->retry_count($retry_count)            if(defined($retry_count));
    $self->completed($completed)                if(defined($completed));
    $self->runtime_msec($runtime_msec)          if(defined($runtime_msec));
    $self->query_count($query_count)            if(defined($query_count));
    $self->semaphore_count($semaphore_count)    if(defined($semaphore_count));
    $self->semaphored_job_id($semaphored_job_id) if(defined($semaphored_job_id));
    $self->adaptor($adaptor)                    if(defined($adaptor));

    return $self;
}

sub adaptor {
  my $self = shift;
  $self->{'_adaptor'} = shift if(@_);
  return $self->{'_adaptor'};
}

sub dbID {
  my $self = shift;
  $self->{'_dbID'} = shift if(@_);
  return $self->{'_dbID'};
}

sub input_id {
  my $self = shift;
  $self->{'_input_id'} = shift if(@_);
  return $self->{'_input_id'};
}

sub worker_id {
  my $self = shift;
  $self->{'_worker_id'} = shift if(@_);
  return $self->{'_worker_id'};
}

sub analysis_id {
  my $self = shift;
  $self->{'_analysis_id'} = shift if(@_);
  return $self->{'_analysis_id'};
}

sub job_claim {
  my $self = shift;
  $self->{'_job_claim'} = shift if(@_);
  return $self->{'_job_claim'};
}

sub status {
  my $self = shift;
  $self->{'_status'} = shift if(@_);
  return $self->{'_status'};
}

sub update_status {
  my ($self, $status ) = @_;
  return unless($self->adaptor);
  $self->status($status);
  $self->adaptor->update_status($self);
}

sub retry_count {
  my $self = shift;
  $self->{'_retry_count'} = shift if(@_);
  $self->{'_retry_count'} = 0 unless(defined($self->{'_retry_count'}));
  return $self->{'_retry_count'};
}

sub completed {
  my $self = shift;
  $self->{'_completed'} = shift if(@_);
  return $self->{'_completed'};
}

sub runtime_msec {
  my $self = shift;
  $self->{'_runtime_msec'} = shift if(@_);
  $self->{'_runtime_msec'} = 0 unless(defined($self->{'_runtime_msec'}));
  return $self->{'_runtime_msec'};
}

sub query_count {
  my $self = shift;
  $self->{'_query_count'} = shift if(@_);
  $self->{'_query_count'} = 0 unless(defined($self->{'_query_count'}));
  return $self->{'_query_count'};
}

sub semaphore_count {
  my $self = shift;
  $self->{'_semaphore_count'} = shift if(@_);
  $self->{'_semaphore_count'} = 0 unless(defined($self->{'_semaphore_count'}));
  return $self->{'_semaphore_count'};
}

sub semaphored_job_id {
  my $self = shift;
  $self->{'_semaphored_job_id'} = shift if(@_);
  return $self->{'_semaphored_job_id'};
}

sub stdout_file {
  my $self = shift;
  $self->{'_stdout_file'} = shift if(@_);
  return $self->{'_stdout_file'};
}

sub stderr_file {
  my $self = shift;
  $self->{'_stderr_file'} = shift if(@_);
  return $self->{'_stderr_file'};
}

=head2 autoflow

    Title   :  autoflow
    Function:  Gets/sets flag for whether the job should
               be automatically dataflowed on branch 1 when the job completes.
               If the subclass manually sends a job along branch 1 with dataflow_output_id,
               the autoflow will turn itself off.
    Returns :  boolean (1=default|0)

=cut

sub autoflow {
  my $self = shift;

  $self->{'_autoflow'} = shift if(@_);
  $self->{'_autoflow'} = 1 unless(defined($self->{'_autoflow'}));  

  return $self->{'_autoflow'};
}


##-----------------[indicators to the Worker]--------------------------------


sub lethal_for_worker {     # Job should set this to 1 prior to dying (or before running code that might cause death - such as RunnableDB's compilation)
                            # if it believes that the state of things will not allow the Worker to continue normally.
                            # The Worker will check the flag and commit suicide if it is set to true.
    my $self = shift;
    $self->{'_lethal_for_worker'} = shift if(@_);
    return $self->{'_lethal_for_worker'};
}

sub transient_error {       # Job should set this to 1 prior to dying (or before running code that might cause death)
                            # if it believes that it makes sense to retry the same job without any changes.
                            # It may also set it to 0 prior to dying (or before running code that might cause death)
                            # if it believes that there is no point in re-trying (say, if the parameters are wrong).
                            # The Worker will check the flag and make necessary adjustments to the database state.
    my $self = shift;
    $self->{'_transient_error'} = shift if(@_);
    return $self->{'_transient_error'};
}

sub incomplete {            # Job should set this to 0 prior to throwing if the job is done,
                            # but it wants the thrown message to be recorded with is_error=0.
    my $self = shift;
    $self->{'_incomplete'} = shift if(@_);
    return $self->{'_incomplete'};
}

##-----------------[/indicators to the Worker]-------------------------------


=head2 dataflow_output_id

    Title        :  dataflow_output_id
    Arg[1](req)  :  <string> $output_id 
    Arg[2](opt)  :  <int> $branch_code (optional, defaults to 1)
    Arg[3](opt)  :  <hashref> $create_job_options (optional, defaults to {}, options added to the CreateNewJob method)
    Usage        :  $self->dataflow_output_id($output_id, $branch_code);
    Function:  
      If a RunnableDB(Process) needs to create jobs, this allows it to have jobs 
      created and flowed through the dataflow rules of the workflow graph.
      This 'output_id' becomes the 'input_id' of the newly created job at
      the ends of the dataflow pipes.  The optional 'branch_code' determines
      which dataflow pipe(s) to flow the job through.      

=cut

sub dataflow_output_id {
    my ($self, $output_ids, $branch_code, $create_job_options) = @_;

    $output_ids  ||= [ $self->input_id() ];                                 # replicate the input_id in the branch_code's output by default
    $output_ids    = [ $output_ids ] unless(ref($output_ids) eq 'ARRAY');   # force previously used single values into an arrayref

    $branch_code        ||=  1;     # default branch_code is 1
    $create_job_options ||= {};     # { -block => 1 } or { -semaphore_count => scalar(@fan_job_ids) } or { -semaphored_job_id => $funnel_job_id }

        # this tricky code is responsible for correct propagation of semaphores down the dataflow pipes:
    my $propagate_semaphore = not exists ($create_job_options->{'-semaphored_job_id'});     # CONVENTION: if zero is explicitly supplied, it is a request not to propagate

        # However if nothing is supplied, semaphored_job_id will be propagated from the parent job:
    my $semaphored_job_id = $create_job_options->{'-semaphored_job_id'} ||= $self->semaphored_job_id();

        # if branch_code is set to 1 (explicitly or impliticly), turn off automatic dataflow:
    $self->autoflow(0) if($branch_code==1);

    my @output_job_ids = ();
    my $rules       = $self->adaptor->db->get_DataflowRuleAdaptor->fetch_from_analysis_id_branch_code($self->analysis_id, $branch_code);
    foreach my $rule (@{$rules}) {

        my $substituted_template;
        if(my $template = $rule->input_id_template()) {
            $substituted_template = $self->param_substitute($template);
        }

        my $target_analysis_or_table = $rule->to_analysis();

        foreach my $output_id ($substituted_template ? ($substituted_template) : @$output_ids) {

            if($target_analysis_or_table->can('dataflow')) {

                my $insert_id = $target_analysis_or_table->dataflow( $output_id );

            } else {
                if(my $job_id = $self->adaptor->CreateNewJob(
                    -input_id       => $output_id,
                    -analysis       => $target_analysis_or_table,
                    -input_job_id   => $self->dbID,  # creator_job's id
                    %$create_job_options
                )) {
                    if($semaphored_job_id and $propagate_semaphore) {
                        $self->adaptor->increase_semaphore_count_for_jobid( $semaphored_job_id ); # propagate the semaphore
                    }
                        # only add the ones that were indeed created:
                    push @output_job_ids, $job_id;

                } elsif($semaphored_job_id and !$propagate_semaphore) {
                    $self->adaptor->decrease_semaphore_count_for_jobid( $semaphored_job_id );     # if we didn't succeed in creating the job, fix the semaphore
                }
            }
        }
    }
    return \@output_job_ids;
}


sub print_job {
  my $self = shift;
  my $logic_name = $self->adaptor()
      ? $self->adaptor->db->get_AnalysisAdaptor->fetch_by_dbID($self->analysis_id)->logic_name()
      : '';

  printf("job_id=%d %35s(%5d) retry=%d input_id='%s'\n", 
       $self->dbID,
       $logic_name,
       $self->analysis_id,
       $self->retry_count,
       $self->input_id);
}

1;
