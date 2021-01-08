=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Meadow;

=head1 DESCRIPTION

    Meadow is an abstract interface to the queue manager.

    A Meadow knows how to check&change the actual status of Workers on the farm.

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2021] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

  Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::Meadow;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::Configurable');


# -------------------------------------- <versioning of the Meadow interface> -------------------------------------------------------

our $MEADOW_MAJOR_VERSION = '3';                # Make sure you change this number whenever an incompatible change is introduced


sub get_meadow_major_version {

    return $MEADOW_MAJOR_VERSION;               # fetch the declared $MEADOW_MAJOR_VERSION of the interface
}


sub get_meadow_version {
    my $self = shift @_;

    return $self->VERSION // 'unversioned';     # fetch the declared $VERSION of a specific Meadow implementation
}


sub check_version_compatibility {
    my $self = shift @_;

    my $mmv = $self->get_meadow_major_version();
    my $mv  = $self->get_meadow_version();
#    warn "$self :  MVC='$mmv', MV='$mv'\n";

    return ($mv=~/^$mmv\./) ? 1 : 0;
}

# -------------------------------------- </versioning of the Meadow interface> ------------------------------------------------------


=head2 new

    Title   :  new (constructor)
    Function:  Instantiates a new Meadow object

=cut

sub new {
    my ($class, $config) = @_;

    my $self = bless {}, $class;

    $self->config( $config );
    $self->context( [ 'Meadow', $self->type, $self->cached_name ] );

    return $self;
}


=head2 cached_name

    Title   :  cached_name
    Function:  Wrapper around L<name()> that caches its return value.
               This is because (1) it can be expensive to get the name
               (e.g. calling an external command), and (2) the name of a
               Meadow is not expected to change through the life of the
               agent.

=cut

sub cached_name {
    my ($self) = @_;

    my $name;

    unless( ref($self) and $name = $self->{'_name'} ) {

        if($name = $self->name() and ref($self) ) {
            $self->{'_name'} = $name;
        }
    }

    return $name;
}


=head2 type

    Title   :  type
    Function:  The "type" of a Meadow is basically its job management
               system. eHive comes with two Meadows: Platform LSF (type
               "LSF"), and a default fork()-based (type "LOCAL"). Other
               meadows can be implemented provided that they follow the
               right interface.

=cut

sub type {
    my $class = shift @_;

    $class = ref($class) if(ref($class));

    return (reverse split(/::/, $class ))[0];
}


=head2 signature

    Title   :  signature
    Function:  The "signature" of a Meadow is its unique identifier across
               the Valley.

=cut

sub signature {
    my $self = shift @_;

    return $self->type.'/'.$self->cached_name;
}

=head2 pipeline_name

    Title   :  pipeline_name
    Function:  Getter/setter for the name of the current pipeline.
               This method is used by other Meadow methods such as
               L<job_name_prefix()>.

=cut


sub pipeline_name {
    my $self = shift @_;

    if(@_) { # new value is being set (which can be undef)
        $self->{'_pipeline_name'} = shift @_;
    }
    return $self->{'_pipeline_name'};
}


=head2 job_name_prefix

    Title   :  job_name_prefix
    Function:  Tells how the agents (workers) should be generally named. It
               is used to name new agents, and to find our own agents.

=cut

sub job_name_prefix {
    my $self = shift @_;

    return ($self->pipeline_name() ? $self->pipeline_name().'-' : '') . 'Hive-';
}


=head2 job_array_common_name

    Title   :  job_array_common_name
    Function:  More specific version of L<job_name_prefix()> that returns
               the actual name that agents should have at a specific
               beekeeper loop.

=cut

sub job_array_common_name {
    my ($self, $rc_name, $iteration) = @_;

    return $self->job_name_prefix() ."${rc_name}-${iteration}";
}


##
## The methods below must be reimplemented in a sub-class. See Meadow/LOCAL and Meadow/LSF
##

=head2 name

    Title   :  name
    Function:  Returns the name of the Meadow (which excludes the Meadow type)

=cut

sub name {
    my ($self) = @_;

    die "Please use a derived method";
}


=head2 get_current_worker_process_id

    Title   :  get_current_worker_process_id
    Function:  Called by a worker to find its process_id. At any point in
               time, the triple (meadow_type, meadow_name, process_id)
               should be unique

=cut

sub get_current_worker_process_id {
    my ($self) = @_;

    die "Please use a derived method";
}


=head2 count_pending_workers_by_rc_name

    Title   :  count_pending_workers_by_rc_name
    Function:  Called by the scheduler to decide how many more workers to
               submit for each resource-class.

=cut

sub count_pending_workers_by_rc_name {
    my ($self) = @_;

    die "Please use a derived method";
}


=head2 count_running_workers

    Title   :  count_running_workers
    Function:  Called by the scheduler to decide the number of additional
               workers that can be submitted (within the defined
               capacities).

=cut

sub count_running_workers {
    my ($self, $meadow_users_of_interest) = @_;

    die "Please use a derived method";
}


=head2 status_of_all_our_workers

    Title   :  status_of_all_our_workers
    Function:  Returns a hashref that maps workers' process_id to their status.
               Statuses are mainly free-text strings. Only "UNKWN" is a special
               status that beekeeper can understand.
               Typical statuses are "RUN", "PEND", "SSUSP", "UNKWN"

=cut

sub status_of_all_our_workers { # returns a hashref
    my ($self, $meadow_users_of_interest) = @_;

    die "Please use a derived method";
}


=head2 check_worker_is_alive_and_mine

    Title   :  check_worker_is_alive_and_mine
    Function:  Tells whether the given worker lives in the current Meadow
               and belongs to the current user.

=cut

sub check_worker_is_alive_and_mine {
    my ($self, $worker) = @_;

    die "Please use a derived method";
}


=head2 kill_worker

    Title   :  kill_worker
    Function:  Kill a worker.

=cut

sub kill_worker {
    my ($self, $worker, $fast) = @_;

    die "Please use a derived method";
}


=head2 parse_report_source_line

    Title   :  parse_report_source_line
    Function:  Opens and parses a file / command-line to return the
               resource-usage of some workers. Should return a hashref
               where process_id is the key to a hashref composed of:
                 when_died
                 pending_sec
                 exception_status
                 cause_of_death
                 lifespan_sec
                 mem_megs
                 cpu_sec
                 exit_status
                 swap_megs

=cut

sub parse_report_source_line {
    my ($self, $bacct_source_line) = @_;

    warn "\t".ref($self)." does not support resource usage logs\n";

    return;
}


=head2 get_report_entries_for_process_ids

    Title   :  get_report_entries_for_process_ids
    Function:  A higher-level method that gets process_ids as input and
               returns a structure like parse_report_source_line.

=cut

sub get_report_entries_for_process_ids {
    my ($self, @process_ids) = @_;

    warn "\t".ref($self)." does not support resource usage logs\n";

    return;
}

=head2 get_report_entries_for_time_interval

    Title   :  get_report_entries_for_time_interval
    Function:  A higher-level method that gets a time interval as input and
               returns a structure like parse_report_source_line.

=cut

sub get_report_entries_for_time_interval {
    my ($self, $from_time, $to_time, $username) = @_;

    warn "\t".ref($self)." does not support resource usage logs\n";

    return;
}


=head2 submit_workers

    Title   :  submit_workers
    Function:  Submit $required_worker_count workers with the command $worker_cmd

=cut

sub submit_workers {
    my ($self, $worker_cmd, $required_worker_count, $iteration, $rc_name, $rc_specific_submission_cmd_args, $submit_log_subdir) = @_;

    die "Please use a derived method";
}

1;
