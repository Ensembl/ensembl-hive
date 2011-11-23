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
use Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor;
use Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor;

use base ('Bio::EnsEMBL::Hive::Params');

sub new {
    my $class = shift @_;

    my $self = bless {}, $class;

    my($dbID, $analysis_id, $input_id, $worker_id, $status, $retry_count, $completed, $runtime_msec, $query_count, $semaphore_count, $semaphored_job_id, $adaptor) =
        rearrange([qw(dbID analysis_id input_id worker_id status retry_count completed runtime_msec query_count semaphore_count semaphored_job_id adaptor) ], @_);

    $self->dbID($dbID)                          if(defined($dbID));
    $self->analysis_id($analysis_id)            if(defined($analysis_id));
    $self->input_id($input_id)                  if(defined($input_id));
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

sub dataflow_rules {    # if ever set will prevent the Job from fetching rules from the DB
    my $self                = shift @_;
    my $branch_name_or_code = shift @_;

    my $branch_code = Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor::branch_name_2_code($branch_name_or_code);

    $self->{'_dataflow_rules'}{$branch_code} = shift if(@_);

    return $self->{'_dataflow_rules'}
        ? ( $self->{'_dataflow_rules'}{$branch_code} || [] )
        : $self->adaptor->db->get_DataflowRuleAdaptor->fetch_all_by_from_analysis_id_and_branch_code($self->analysis_id, $branch_code);
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

=head2 warning

    Description:    records a non-error message in 'job_message' table linked to the current job

=cut

sub warning {
    my ($self, $msg) = @_;

    if( my $job_adaptor = $self->adaptor ) {
        $job_adaptor->db->get_JobMessageAdaptor()->register_message($self->dbID, $msg, 0);
    } else {
        print STDERR "Warning: $msg\n";
    }
}

sub fan_cache {     # a self-initializing getter (no setting)
                    # Returns a hash-of-lists { 2 => [list of jobs waiting to be funneled into 2], 3 => [list of jobs waiting to be funneled into 3], etc}
    my $self = shift;

    return $self->{'_fan_cache'} ||= {};
}

=head2 dataflow_output_id

    Title        :  dataflow_output_id
    Arg[1](req)  :  <string> $output_id 
    Arg[2](opt)  :  <int> $branch_name_or_code (optional, defaults to 1)
    Usage        :  $self->dataflow_output_id($output_id, $branch_name_or_code);
    Function:  
      If a RunnableDB(Process) needs to create jobs, this allows it to have jobs 
      created and flowed through the dataflow rules of the workflow graph.
      This 'output_id' becomes the 'input_id' of the newly created job at
      the ends of the dataflow pipes.  The optional 'branch_name_or_code' determines
      which dataflow pipe(s) to flow the job through.      

=cut

sub dataflow_output_id {
    my ($self, $output_ids, $branch_name_or_code, $create_job_options) = @_;

    $output_ids  ||= [ $self->input_id() ];                                 # replicate the input_id in the branch_code's output by default
    $output_ids    = [ $output_ids ] unless(ref($output_ids) eq 'ARRAY');   # force previously used single values into an arrayref

    if($create_job_options) {
        die "Please consider configuring semaphored dataflow from PipeConfig rather than setting it up manually";
    }

        # map branch names to numbers:
    my $branch_code = Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor::branch_name_2_code($branch_name_or_code);

        # if branch_code is set to 1 (explicitly or impliticly), turn off automatic dataflow:
    $self->autoflow(0) if($branch_code == 1);

    my @output_job_ids = ();
    foreach my $rule (@{ $self->dataflow_rules( $branch_name_or_code ) }) {

            # parameter substitution into input_id_template is rule-specific
        my $output_ids_for_this_rule;
        if(my $template = $rule->input_id_template()) {
            $output_ids_for_this_rule = [ eval $self->param_substitute($template) ];
        } else {
            $output_ids_for_this_rule = $output_ids;
        }

        my $target_analysis_or_table = $rule->to_analysis();

        if($target_analysis_or_table->can('dataflow')) {

            $target_analysis_or_table->dataflow( $output_ids_for_this_rule );

        } else {

            if(my $funnel_branch_code = $rule->funnel_branch_code()) {  # a semaphored fan: they will have to wait in cache until the funnel is created

                my $fan_cache_this_branch = $self->fan_cache()->{$funnel_branch_code} ||= [];
                push @$fan_cache_this_branch, map { [$_, $target_analysis_or_table] } @$output_ids_for_this_rule;

            } else {

                my $fan_cache = $self->fan_cache()->{$branch_code};

                if($fan_cache && @$fan_cache) { # a semaphored funnel
                    my $funnel_job_id;
                    if( (my $funnel_job_number = scalar(@$output_ids_for_this_rule)) !=1 ) {

                        $self->transient_error(0);
                        die "Asked to dataflow into $funnel_job_number funnel jobs instead of 1";

                    } elsif($funnel_job_id = Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob(   # if a semaphored funnel job creation succeeded,
                                            -input_id           => $output_ids_for_this_rule->[0],
                                            -analysis           => $target_analysis_or_table,
                                            -prev_job           => $self,
                                            -semaphore_count    => scalar(@$fan_cache),
                    )) {                                                                                    # then create the fan out of the cache:
                        push @output_job_ids, $funnel_job_id;

                        foreach my $pair ( @$fan_cache ) {
                            my ($output_id, $fan_analysis) = @$pair;
                            if(my $job_id = Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob(
                                -input_id           => $output_id,
                                -analysis           => $fan_analysis,
                                -prev_job           => $self,
                                -semaphored_job_id  => $funnel_job_id,      # by passing this parameter we request not to propagate semaphores
                            )) {
                                push @output_job_ids, $job_id;
                            }
                        }
                    } else {
                        die "Could not create a funnel job";
                    }

                    delete $self->fan_cache()->{$branch_code};    # clear the cache

                } else {    # non-semaphored dataflow (but potentially propagating any existing semaphores)

                    foreach my $output_id ( @$output_ids_for_this_rule ) {

                        if(my $job_id = Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor->CreateNewJob(
                            -input_id       => $output_id,
                            -analysis       => $target_analysis_or_table,
                            -prev_job       => $self,
                        )) {
                                # only add the ones that were indeed created:
                            push @output_job_ids, $job_id;
                        }
                    }
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
