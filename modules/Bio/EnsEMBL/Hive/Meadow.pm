=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Meadow;

=head1 DESCRIPTION

    Meadow is an abstract interface to the queue manager.

    A Meadow knows how to check&change the actual status of Workers on the farm.

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2024] EMBL-European Bioinformatics Institute

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
use Sys::Hostname ('hostname');

use base ('Bio::EnsEMBL::Hive::Configurable');


# -------------------------------------- <versioning of the Meadow interface> -------------------------------------------------------

our $MEADOW_MAJOR_VERSION = '5';                # Make sure you change this number whenever an incompatible change is introduced


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
    my ($class, $config, $name) = @_;

    my $self = bless {}, $class;

    $self->{'_name'} = $name;       # Record the name given to avoid querying the meadow once more
    $self->_init_meadow($config);

    return $self;
}


sub _init_meadow {
    my ($self, $config) = @_;

    $self->config( $config );
    $self->context( [ 'Meadow', $self->type, $self->cached_name ] );
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

    unless( ref($self) and $name = $self->{'_name'} ) {     # unless the name was storable AND stored in the object

        if($name = $self->name() and ref($self) ) {         # ... get the not-yet-stored name and if it is storable
            $self->{'_name'} = $name;                       # ... ... then store it in the object
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


=head2 get_current_hostname

    Title   :  get_current_hostname
    Function:  Returns the "current" hostname (most UNIX-based Meadows will simply use this base method)

=cut

sub get_current_hostname {
    return hostname();
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


=head2 runWorker_path

    Title   :  runWorker_path
    Function:  Getter for the path to runWorker.pl
               This is now set in the JSON config file. When missing or set to null,
               defaults to $EHIVE_ROOT_DIR/scripts

=cut

sub runWorker_path {
    my $self = shift @_;

    my $path = $self->config_get('RunWorkerPath') // $ENV{'EHIVE_ROOT_DIR'}.'/scripts/';
    if ( length($path) ) { 
        $path = $path . '/' unless $path =~ /\/$/; # add "/" as suffix if user forgot
    }
    return $path;
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


=head2 status_of_all_our_workers

    Title   :  status_of_all_our_workers
    Function:  Returns an arrayref of arrayrefs [worker_pid, meadow_user, status, rc_name]
               listing the workers that this Meadow can see.
               Allowed statuses are "RUN", "PEND", "SSUSP", "UNKWN"

=cut

sub status_of_all_our_workers { # returns an arrayref
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


=head2 submit_workers_return_meadow_pids

    Title   :  submit_workers_return_meadow_pids
    Function:  Submit $required_worker_count workers with the command $worker_cmd and return the meadow-specific worker_pids

=cut

sub submit_workers_return_meadow_pids {
    my ($self, $worker_cmd, $required_worker_count, $iteration, $rc_name, $rc_specific_submission_cmd_args, $submit_log_subdir) = @_;

    die "Please use a derived method";
}


=head2 run_on_host

    Title   :  run_on_host
    Function:  Runs an arbitrary commands on the given host. The host is expected to belong to the meadow and be reachable

=cut

sub run_on_host {
    my ($self, $meadow_host, $meadow_user, $command) = @_;
    # By default we trust the network, but this can be switched off in the config file
    my @extra_args = $self->config_get('StrictHostKeyChecking') ? () : qw(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null);
    # Several hard-coded parameters here:
    # - BatchMode=yes disables human interaction (no password asked)
    # - ServerAliveInterval=30 tells ssh that the server must answer within 30 seconds
    # - timeout 3m means that the whole command must complete within 3 minutes
    return system('timeout', '3m', 'ssh', @extra_args, '-o', 'BatchMode=yes', '-o', 'ServerAliveInterval=30', sprintf('%s@%s', $meadow_user, $meadow_host), @$command);
}


=head2 cleanup_temp_directory

    Title   :  cleanup_temp_directory
    Function:  Cleanup the temp directory assigned to the worker

=cut

sub cleanup_temp_directory {
    my ($self, $worker) = @_;

    # The feature can be disabled for this actual meadow
    return unless $self->config_get('CleanupTempDirectoryKilledWorkers');

    print "GarbageCollector:\tCleaning-up ".$worker->temp_directory_name."\n";
    my $rc = $self->run_on_host($worker->meadow_host, $worker->meadow_user, ['rm', '-rf', $worker->temp_directory_name]);
    $worker->worker_say(sprintf("Error: could not clean %s's temp directory '%s': %s\n", $worker->meadow_host, $worker->temp_directory_name, $@)) if $rc;
}

1;
