=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::AnalysisJob

=head1 DESCRIPTION

    An AnalysisJob is the link between the input_id control data, the analysis and
    the rule system.  It also tracks the state of the job as it is processed

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

=head1 APPENDIX

    The rest of the documentation details each of the object methods.
    Internal methods are usually preceded with a _

=cut


package Bio::EnsEMBL::Hive::AnalysisJob;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Utils ('stringify', 'destringify');
use Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor;

use base (  'Bio::EnsEMBL::Hive::Storable', # inherit dbID(), adaptor() and new() methods
            'Bio::EnsEMBL::Hive::Params',   # inherit param management functionality
         );


=head1 AUTOLOADED

    prev_job_id / prev_job

    analysis_id / analysis

=cut


sub input_id {
    my $self = shift;
    if(@_) {
        my $input_id = shift @_;
        $self->{'_input_id'} = ref($input_id) ? stringify($input_id) : $input_id;
    }

    return $self->{'_input_id'};
}

sub param_id_stack {
    my $self = shift;
    $self->{'_param_id_stack'} = shift if(@_);
    $self->{'_param_id_stack'} = '' unless(defined($self->{'_param_id_stack'}));
    return $self->{'_param_id_stack'};
}

sub accu_id_stack {
    my $self = shift;
    $self->{'_accu_id_stack'} = shift if(@_);
    $self->{'_accu_id_stack'} = '' unless(defined($self->{'_accu_id_stack'}));
    return $self->{'_accu_id_stack'};
}

sub role_id {
    my $self = shift;
    $self->{'_role_id'} = shift if(@_);
    return $self->{'_role_id'};
}

sub status {
    my $self = shift;
    $self->{'_status'} = shift if(@_);
    $self->{'_status'} = ( ($self->semaphore_count>0) ? 'SEMAPHORED' : 'READY' ) unless(defined($self->{'_status'}));
    return $self->{'_status'};
}

sub retry_count {
    my $self = shift;
    $self->{'_retry_count'} = shift if(@_);
    $self->{'_retry_count'} = 0 unless(defined($self->{'_retry_count'}));
    return $self->{'_retry_count'};
}

sub when_completed {
    my $self = shift;
    $self->{'_when_completed'} = shift if(@_);
    return $self->{'_when_completed'};
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

sub set_and_update_status {
    my ($self, $status ) = @_;

    $self->status($status);

    if(my $adaptor = $self->adaptor) {
        $adaptor->check_in_job($self);
    }
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

sub accu_hash {
    my $self = shift;
    $self->{'_accu_hash'} = shift if(@_);
    $self->{'_accu_hash'} = {} unless(defined($self->{'_accu_hash'}));
    return $self->{'_accu_hash'};
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


sub died_somewhere {
    my $self = shift;

    $self->{'_died_somewhere'} ||= shift if(@_);    # NB: the '||=' only applies in this case - do not copy around!
    return $self->{'_died_somewhere'} ||=0;
}

##-----------------[/indicators to the Worker]-------------------------------


sub load_parameters {
    my ($self, $runnable_object) = @_;

    my @params_precedence = ();

    push @params_precedence, $runnable_object->param_defaults if($runnable_object);

    if(my $job_adaptor = $self->adaptor) {
        my $job_id          = $self->dbID;
        my $accu_adaptor    = $job_adaptor->db->get_AccumulatorAdaptor;

        $self->accu_hash( $accu_adaptor->fetch_structures_for_job_ids( $job_id )->{ $job_id } );

        push @params_precedence, $job_adaptor->db->get_PipelineWideParametersAdaptor->fetch_param_hash;

        push @params_precedence, $self->analysis->parameters if($self->analysis);

        if( $job_adaptor->db->hive_use_param_stack ) {
            my $input_ids_hash      = $job_adaptor->fetch_input_ids_for_job_ids( $self->param_id_stack, 2, 0 );     # input_ids have lower precedence (FOR EACH ID)
            my $accu_hash           = $accu_adaptor->fetch_structures_for_job_ids( $self->accu_id_stack, 2, 1 );     # accus have higher precedence (FOR EACH ID)
            my %input_id_accu_hash  = ( %$input_ids_hash, %$accu_hash );
            push @params_precedence, @input_id_accu_hash{ sort { $a <=> $b } keys %input_id_accu_hash }; # take a slice. Mmm...
        }
    }

    push @params_precedence, $self->input_id, $self->accu_hash;

    $self->param_init( @params_precedence );
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

    my $input_id                = $self->input_id();
    my $param_id_stack          = $self->param_id_stack();
    my $accu_id_stack           = $self->accu_id_stack();

    my $job_adaptor             = $self->adaptor() || 'Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor';
    my $hive_use_param_stack    = ref($job_adaptor) && $job_adaptor->db->hive_use_param_stack();

    if($hive_use_param_stack) {
        if($input_id and ($input_id ne '{}')) {     # add the parent to the param_id_stack if it had non-trivial extra parameters
            $param_id_stack = ($param_id_stack ? $param_id_stack.',' : '').$self->dbID();
        }
        if(scalar(keys %{$self->accu_hash()})) {    # add the parent to the accu_id_stack if it had "own" accumulator
            $accu_id_stack = ($accu_id_stack ? $accu_id_stack.',' : '').$self->dbID();
        }
    }

    $output_ids  ||= [ $hive_use_param_stack ? {} : $input_id ];            # by default replicate the parameters of the parent in the child
    $output_ids    = [ $output_ids ] unless(ref($output_ids) eq 'ARRAY');   # force previously used single values into an arrayref

    if($create_job_options) {
        die "Please consider configuring semaphored dataflow from PipeConfig rather than setting it up manually";
    }

        # map branch names to numbers:
    my $branch_code = Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor::branch_name_2_code($branch_name_or_code);

        # if branch_code is set to 1 (explicitly or impliticly), turn off automatic dataflow:
    $self->autoflow(0) if($branch_code == 1);

    my @output_job_ids = ();

        # sort rules to make sure the fan rules come before funnel rules for the same branch_code:
    foreach my $rule (sort {($b->funnel_dataflow_rule//0) cmp ($a->funnel_dataflow_rule//0)} @{ $self->analysis->dataflow_rules_by_branch->{$branch_code} || [] }) {

            # parameter substitution into input_id_template is rule-specific
        my $output_ids_for_this_rule;
        if(my $template_string = $rule->input_id_template()) {
            my $template_hash = destringify($template_string);
            $output_ids_for_this_rule = [ map { $self->param_substitute($template_hash, $_) } @$output_ids ];
        } else {
            $output_ids_for_this_rule = $output_ids;
        }

        my $target_analysis_or_table = $rule->to_analysis();

        if($target_analysis_or_table->can('dataflow')) {

            $target_analysis_or_table->dataflow( $output_ids_for_this_rule, $self );

        } else {

            my @common_params = (
                'prev_job'          => $self,
                'analysis'          => $target_analysis_or_table,   # expecting an Analysis
                'param_id_stack'    => $param_id_stack,
                'accu_id_stack'     => $accu_id_stack,
            );

            if( my $funnel_dataflow_rule = $rule->funnel_dataflow_rule ) {    # members of a semaphored fan will have to wait in cache until the funnel is created:

                my $fan_cache_this_branch = $self->fan_cache->{"$funnel_dataflow_rule"} ||= [];
                push @$fan_cache_this_branch, map { Bio::EnsEMBL::Hive::AnalysisJob->new(
                                                        @common_params,
                                                        'input_id'          => $_,
                                                        # semaphored_job_id  => to be set when the $funnel_job has been stored
                                                    ) } @$output_ids_for_this_rule;

            } else {    # either a semaphored funnel or a non-semaphored dataflow:

                my $fan_jobs = delete $self->fan_cache->{"$rule"};   # clear the cache at the same time

                if( $fan_jobs && @$fan_jobs ) { # a semaphored funnel

                    if( (my $funnel_job_count = scalar(@$output_ids_for_this_rule)) !=1 ) {

                        $self->transient_error(0);
                        die "Asked to dataflow into $funnel_job_count funnel jobs instead of 1";

                    } else {
                        my $funnel_job = Bio::EnsEMBL::Hive::AnalysisJob->new(
                                            @common_params,
                                            'input_id'          => $output_ids_for_this_rule->[0],
                                            'semaphore_count'   => scalar(@$fan_jobs),          # "pre-increase" the semaphore count before creating the dependent jobs
                                            'semaphored_job_id' => $self->semaphored_job_id(),  # propagate parent's semaphore if any
                        );

                        my ($funnel_job_id) = @{ $job_adaptor->store_jobs_and_adjust_counters( [ $funnel_job ], 0) };

                        unless($funnel_job_id) {    # apparently it has been created previously, trying to leech to it:

                            if( $funnel_job = $job_adaptor->fetch_by_analysis_id_AND_input_id( $funnel_job->analysis->dbID, $funnel_job->input_id) ) {
                                $funnel_job_id = $funnel_job->dbID;

                                if( $funnel_job->status eq 'SEMAPHORED' ) {
                                    $job_adaptor->increase_semaphore_count_for_jobid( $funnel_job_id, scalar(@$fan_jobs) );    # "pre-increase" the semaphore count before creating the dependent jobs

                                    $job_adaptor->db->get_LogMessageAdaptor->store_job_message($self->dbID, "Discovered and using an existing funnel ".$funnel_job->toString, 0);
                                } else {
                                    die "The funnel job (id=$funnel_job_id) fetched from the database was not in SEMAPHORED status";
                                }
                            } else {
                                die "The funnel job could neither be stored nor fetched";
                            }
                        }

                        foreach my $fan_job (@$fan_jobs) {  # set the funnel in every fan's job:
                            $fan_job->semaphored_job_id( $funnel_job_id );
                        }
                        push @output_job_ids, $funnel_job_id, @{ $job_adaptor->store_jobs_and_adjust_counters( $fan_jobs, 1) };

                    }
                } else {    # non-semaphored dataflow (but potentially propagating any existing semaphores)
                    my @non_semaphored_jobs = map { Bio::EnsEMBL::Hive::AnalysisJob->new(
                                                        @common_params,
                                                        'input_id'          => $_,
                                                        'semaphored_job_id' => $self->semaphored_job_id(),  # propagate parent's semaphore if any
                    ) } @$output_ids_for_this_rule;

                    push @output_job_ids, @{ $job_adaptor->store_jobs_and_adjust_counters( \@non_semaphored_jobs, 0) };
                }
            } # /if funnel

        } # /if (table or analysis)
    } # /foreach my $rule

    return \@output_job_ids;
}


sub toString {
    my $self = shift @_;

    my $analysis_label = $self->analysis
        ? ( $self->analysis->logic_name.'('.$self->analysis_id.')' )
        : '(NULL)';

    return 'Job dbID='.($self->dbID || '(NULL)')." analysis=$analysis_label, input_id='".$self->input_id."', status=".$self->status.", retry_count=".$self->retry_count;
}


1;

