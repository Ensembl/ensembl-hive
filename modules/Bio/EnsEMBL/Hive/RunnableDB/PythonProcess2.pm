=pod

=head1 NAME

Bio::EnsEMBL::Hive::RunnableDB::PythonProcess2

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


package Bio::EnsEMBL::Hive::RunnableDB::PythonProcess2;

use strict;
use warnings;

use JSON;
use IPC::Open2;
use IO::Handle;
use Data::Dumper;

use base ('Bio::EnsEMBL::Hive::Process');


our %known_languages = (
    'python3'   => [ 'python3', 'worker.py' ],
);

sub new {

    my $class = shift @_;

    pipe(PARENT_RDR, CHILD_WTR) or die 'Could not create a pipe to send data to the child !';
    pipe(CHILD_RDR,  PARENT_WTR) or die 'Could not create a pipe to get data from the child !';;

    print STDERR "PARENT_RDR is ", fileno(PARENT_RDR), "\n";
    print STDERR "PARENT_WTR is ", fileno(PARENT_WTR), "\n";
    print STDERR "CHILD_RDR is ", fileno(CHILD_RDR), "\n";
    print STDERR "CHILD_WTR is ", fileno(CHILD_WTR), "\n";

    my $pid;

    if ($pid = fork()) {
        # In the parent
        close PARENT_RDR;
        close PARENT_WTR;
        print STDERR "parent is PID $$\n";
    } else {
        die "cannot fork: $!" unless defined $pid;
        # In the child
        close CHILD_RDR;
        close CHILD_WTR;
        print STDERR "child is PID $$\n";

        # Do not close the non-standard file descriptors on exec(): the child process will need them !
        use Fcntl;
        my $flags = fcntl(PARENT_RDR, F_GETFD, 0);
        fcntl(PARENT_RDR, F_SETFD, $flags & ~FD_CLOEXEC);
        $flags = fcntl(PARENT_WTR, F_GETFD, 0);
        fcntl(PARENT_WTR, F_SETFD, $flags & ~FD_CLOEXEC);

        my $language = 'python3';
        #exec($known_languages{$language}->[0], 'worker.py', 'TestRunnable', fileno(PARENT_RDR), fileno(PARENT_WTR));
        exec($known_languages{$language}->[0], sprintf('%s/wrappers/%s/%s', $ENV{'EHIVE_ROOT_DIR'}, $language, $known_languages{$language}->[1]), 'TestRunnable', fileno(PARENT_RDR), fileno(PARENT_WTR));
    }


    CHILD_WTR->autoflush(1);

    my $self = bless {}, $class;

    $self->child_out(*CHILD_RDR);
    $self->child_in(*CHILD_WTR);
    $self->child_pid($pid);
    $self->json_formatter( JSON->new()->indent(0) );

    print STDERR "BEFORE READ PARAM_DEFAULTS\n";
    $self->param_defaults( $self->read_message()->{content} );
    print STDERR "INIT DONE\n";

    return $self;
}



##############
# Attributes #
##############


=head2 child_in

  Example     : my $child_in = $process->child_in();
  Example     : $process->child_in(*CHILD_WTR);
  Description : Getter/Setter for the file handle that allows talking to the
                child process.
  Returntype  : IO::Handle
  Exceptions  : none

=cut

sub child_in {
    my $self = shift;
    $self->{'_child_in'} = shift if @_;
    return $self->{'_child_in'};
}

=head2 child_out

  Example     : my $child_out = $process->child_out();
  Example     : $process->child_out(*CHILD_RDR);
  Description : Getter/Setter for the file handle that allows receiving data
                from the child process.
  Returntype  : IO::Handle
  Exceptions  : none

=cut

sub child_out {
    my $self = shift;
    $self->{'_child_out'} = shift if @_;
    return $self->{'_child_out'};
}

=head2 child_pid

  Example     : my $child_pid = $process->child_pid();
  Example     : $process->child_pid($child_pid);
  Description : Getter/Setter for the process ID of the child
  Returntype  : integer
  Exceptions  : none

=cut

sub child_pid {
    my $self = shift;
    $self->{'_child_pid'} = shift if @_;
    return $self->{'_child_pid'};
}


=head2 json_formatter

  Example     : my $json_formatter = $object_name->json_formatter();
  Example     : $object_name->json_formatter($json_formatter);
  Description : Getter/Setter for the JSON formatter.
  Returntype  : instance of JSON
  Exceptions  : none

=cut

sub json_formatter {
    my $self = shift;
    $self->{'_json_formatter'} = shift if @_;
    return $self->{'_json_formatter'};
}


################################
# Communication with the child #
################################

=head2 send_message

  Example     : $process->send_message($perl_structure);
  Description : Send the Perl structure to the child process via the pipe (and
                serialized in JSON).
  Returntype  : none
  Exceptions  : raised by JSON / IO::Handle

=cut

sub send_message {
    my ($self, $struct) = @_;
    my $j = $self->json_formatter->encode($struct);
    print STDERR "PERL send_message $j\n";
    $self->child_in->print($j."\n");
}


=head2 send_response

  Example     : $process->send_response('OK');
  Description : Wrapper around send_message to send a response to the child.
  Returntype  : none
  Exceptions  : raised by JSON / IO::Handle

=cut

sub send_response {
    my ($self, $response) = @_;
    return $self->send_message({'response' => $response});
}


=head2 read_message

  Example     : my $msg = $process->read_message();
  Description : Wait for and read the next message coming from the child.
                Again, the message itself is serialized and transmitted
                via the pipe
  Returntype  : Perl structure
  Exceptions  : raised by JSON / IO::Handle

=cut

sub read_message {
    my $self = shift;
    my $s = $self->child_out->getline();
    print STDERR "PERL read_message: $s\n";
    return $self->json_formatter->decode($s);
}


###########################
# Hive::Process interface #
###########################


=head2 param_defaults

  Example     : my $param_defaults = $runnable->param_defaults();
  Example     : $runnable->param_defaults($param_defaults);
  Description : Getter/Setter for the default parameters of this runnable.
                Hive only uses it as a getter, but here, we need a setter to
                define the parameters at the Perl layer once they've been
                retrieved from the child process.
  Returntype  : Hashref
  Exceptions  : none

=cut

sub param_defaults {
    my $self = shift;
    $self->{'_param_defaults'} = shift if @_;
    return $self->{'_param_defaults'};
}

=head2 life_cycle

  Example     : my $partial_timings = $runnable->life_cycle();
  Description : Runs the life-cycle of the input job and returns the timings
                of each Runnable method (fetch_input, run, etc).
  Returntype  : Hashref
  Exceptions  : none
  Caller      : general
  Status      : Stable

=cut

sub life_cycle {
    my $self = shift;

    print STDERR "PERL LIFE_CYCLE\n";

    my $job = $self->input_job();
    my $partial_stopwatch = Bio::EnsEMBL::Hive::Utils::Stopwatch->new();
    my %job_partial_timing = ();

    $job->incomplete(1);    # reinforce, in case the life_cycle is not run by a Worker
    $job->autoflow(1);

    my %struct = (
        input_job => {
            parameters => $job->{_unsubstituted_param_hash},
            input_id => $job->input_id,
            dbID => $job->dbID,
            retry_count => $job->retry_count,
        },
        execute_writes => $self->execute_writes || 0,
        debug => $self->debug || 0,
    );
    print STDERR "PERL SEND JOB PARAM\n";
    $self->send_message(\%struct);

    # A simple loop event
    while (1) {
        print STDERR "PERL WAITING IN LOOP\n";

        my $msg = $self->read_message;
        my $event = $msg->{event};
        my $content = $msg->{content};
        print STDERR "PERL processing event '$event'\n";

        if ($event eq 'JOB_STATUS_UPDATE') {
            $job_partial_timing{$job->status} = $partial_stopwatch->get_elapsed() if $job->status ne 'READY';
            $self->enter_status(uc $content);
            $partial_stopwatch->restart();
            $self->send_response('OK');

        } elsif ($event eq 'WARNING') {
            $self->warning($content->{message}, $content->{is_error});
            $self->send_response('OK');

        } elsif ($event eq 'DATAFLOW') {
            my $d = $self->dataflow_output_id($content->{output_ids}, $content->{branch_name_or_code});
            $self->send_message($d);

        } elsif ($event eq 'WORKER_TEMP_DIRECTORY') {
            $self->{worker_temp_directory_name} = $content;
            my $wtd = $self->worker_temp_directory;
            $self->send_response($wtd);

        } elsif ($event eq 'JOB_END') {
            $job->autoflow($content->{autoflow});
            $job->{_param_hash} = $content->{parameters}->{substituted};
            $job->{_unsubstituted_param_hash} = $content->{parameters}->{unsubstituted};

            if ($content->{complete}) {
                if( $self->execute_writes and $job->autoflow ) {    # AUTOFLOW doesn't have its own status so will have whatever previous state of the job
                    $self->say_with_header( ': AUTOFLOW input->output' );
                    $job->dataflow_output_id();
                }

                my @zombie_funnel_dataflow_rule_ids = keys %{$job->fan_cache};
                if( scalar(@zombie_funnel_dataflow_rule_ids) ) {
                    $job->transient_error(0);
                    die "There are cached semaphored fans for which a funnel job (dataflow_rule_id(s) ".join(',',@zombie_funnel_dataflow_rule_ids).") has never been dataflown";
                }

                $job->incomplete(0);
            }

            return \%job_partial_timing;
        } else {
            die "Unknown event '$event' coming from the child";
        }
    }
}

sub worker_temp_directory_name {
    my $self = shift;
    return $self->{worker_temp_directory_name} if $self->{worker_temp_directory_name};
    return $self->SUPER::worker_temp_directory_name();
}

## Have to be redefined
# life_cycle
# param_defaults
# worker_temp_directory_name

## Needed, can be reused from the base class
# worker_temp_directory
# input_job
# execute_writes
# debug
# dataflow_output_id
# enter_status -> worker / say_with_header
# warning
# cleanup_worker_temp_directory

## Invalid in this context
# strict_hash_format
# fetch_input
# run
# write_output
# db
# dbc
# data_dbc
# input_id
# complete_early
# throw


1;
