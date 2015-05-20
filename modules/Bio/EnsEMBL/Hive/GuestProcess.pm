=pod

=head1 NAME

Bio::EnsEMBL::Hive::GuestProcess

=head1 SYNOPSIS

This is a variant of Bio::EnsEMBL::Hive::Process that forks into a wrapper that can itself
run jobs (runnables) written in a different language

=head1 DESCRIPTION

Upon initialisation, GuestProcess forks, and the child process executes the wrapper that
will allow running Runnables of the other language. The communication is ensured by two
pipes and is schematically similar to running "| wrapper |", except that GuestProcess
uses non-standard file descriptors, thus allowing the Runnable to still use std{in,out,err}.

The wrapper receives the two file-numbers that it is meant to use (one for reading data
from GuestProcess, and one to send data to GuestProcess). All the messages are passed
around in single-line JSON structures. The protocol is described below using the convention:
    ---> represents a message sent to the child process,
    <--- represents a message sent by the child process

The initialisation (in the constructor) consists in checking that both sides spek the same
version of the protocol:
    <--- { "version": "XXX" }
    ---> "OK"
GuestProcess will bail out if the response is not "OK"

Then, the child process (i.e. the runnable) will send its default parameters to GuestProcess.
This fills the usual param_defaults() section of the Runnable:
    <--- { ... param_defaults ... }
    ---> "OK"

The child process then goes to sleep, waiting for jobs to be seeded. Meanwhile,
GuestProcess enters a number of life_cycle() executions (as triggered by Worker).
Each one first sends a JSON object to the child process to initialize the job parameters
    ---> {
           "input_job": {
             "parameters": { ... the unsubstituted job parameters as compiled by Worker ... },
             // followed by several attributes of the job
             "input_id": { ...  },
             "dbID": XXX,
             "retry_count": XXX
           },
           "execute_writes": [1|0],
           "debug": XXX
         }
    <--- "OK"

From this point, GuestProcess acts as a server, listening to events sent by the child.
Events are JSON objects composed of an "event" field (the name of the event) and a
"content" field (the payload). Events can be of the following kinds (with the expected
response from GuestProcess):

    <--- JOB_STATUS_UPDATE
         // The content is one of "PRE_CLEANUP", "FETCH_INPUT", "RUN", "WRITE_OUTPUT", "POST_CLEANUP"
    ---> "OK"

    <--- WARNING
         // The content is a JSON object:
            {
              "message": "XXX",
              "is_error": [true|false],
            }
    ---> "OK"

    <--- DATAFLOW
         // The content is a JSON object:
            {
              "branch_name_or_code": XXX,
              "output_ids": an array or a hash,
              "params": {
                "substituted": { ... the parameters that are currently substituted ... }
                "unsubstituted": { ... the parameters that have not yet been substituted ... }
              }
            }
    ---> dbIDs of the jobs that have been created

    <--- WORKER_TEMP_DIRECTORY
         // The content is the "worker_temp_directory_name" as defined in the runnable (or null otherwise)
    ---> returns the temporary directory of the worker

    <--- JOB_END
         // The content is a JSON object describing the final state of the job
            {
              "complete": [true|false],
              "job": {
                "autoflow": [true|false],
                "lethal_for_worker": [true|false],
                "transient_error": [true|false],
              },
              "params": {
                "substituted": { ... the parameters that are currently substituted ... }
                "unsubstituted": { ... the parameters that have not yet been substituted ... }
              }
            }
    ---> "OK"


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


package Bio::EnsEMBL::Hive::GuestProcess;

use strict;
use warnings;

use JSON;
use IO::Handle;

use Data::Dumper;

use base ('Bio::EnsEMBL::Hive::Process');


our $VERSION = '0.1';

=head2 get_protocol_version

  Example     : print Bio::EnsEMBL::Hive::GuestProcess->get_protocol_version(), "\n";
  Description : Returns the version number of the communication protocol
  Returntype  : String

=cut

sub get_protocol_version {
    return $VERSION
}



=head2 new

  Arg[1]      : $language: the programming language the external runnable is in
  Arg[2]      : $module: the name of the runnable (usually a package name)
  Example     : Bio::EnsEMBL::Hive::GuestProcess->new();
  Description : Constructor
  Returntype  : Bio::EnsEMBL::Hive::GuestProcess
  Exceptions  : if $language or $module is not defined properly or if the pipes /
                child process could not be created

=cut

sub new {

    my ($class, $language, $module) = @_;

    die "GuestProcess must be told which language to interface with" unless $language;

    my $wrapper = _get_wrapper_for_language($language);
    die "GuestProcess must be told which module to run" unless $module;

    my ($PARENT_RDR, $PARENT_WTR, $CHILD_WTR,$CHILD_RDR);
    pipe($PARENT_RDR, $CHILD_WTR) or die 'Could not create a pipe to send data to the child !';
    pipe($CHILD_RDR,  $PARENT_WTR) or die 'Could not create a pipe to get data from the child !';;

    print STDERR "PARENT_RDR is ", fileno($PARENT_RDR), "\n";
    print STDERR "PARENT_WTR is ", fileno($PARENT_WTR), "\n";
    print STDERR "CHILD_RDR is ", fileno($CHILD_RDR), "\n";
    print STDERR "CHILD_WTR is ", fileno($CHILD_WTR), "\n";

    my $pid;

    if ($pid = fork()) {
        # In the parent
        close $PARENT_RDR;
        close $PARENT_WTR;
        print STDERR "parent is PID $$\n";
    } else {
        die "cannot fork: $!" unless defined $pid;
        # In the child
        close $CHILD_RDR;
        close $CHILD_WTR;
        print STDERR "child is PID $$\n";

        # Do not close the non-standard file descriptors on exec(): the child process will need them !
        use Fcntl;
        my $flags = fcntl($PARENT_RDR, F_GETFD, 0);
        fcntl($PARENT_RDR, F_SETFD, $flags & ~FD_CLOEXEC);
        $flags = fcntl($PARENT_WTR, F_GETFD, 0);
        fcntl($PARENT_WTR, F_SETFD, $flags & ~FD_CLOEXEC);

        exec($wrapper, 'run', $module, fileno($PARENT_RDR), fileno($PARENT_WTR));
    }


    $CHILD_WTR->autoflush(1);

    my $self = bless {}, $class;

    $self->child_out($CHILD_RDR);
    $self->child_in($CHILD_WTR);
    $self->child_pid($pid);
    $self->json_formatter( JSON->new()->indent(0) );

    $self->print_debug('CHECK VERSION NUMBER');
    my $other_version = $self->read_message()->{content};
    if ($other_version ne $VERSION) {
        $self->send_response('NO');
        die "eHive's protocol version is '$VERSION' but the wrapper's is '$other_version'\n";
    } else {
        $self->send_response('OK');
    }

    $self->print_debug("BEFORE READ PARAM_DEFAULTS");
    $self->param_defaults( $self->read_message()->{content} );
    $self->send_response('OK');

    $self->print_debug("INIT DONE");

    return $self;
}


=head2 _get_wrapper_for_language

  Example     : Bio::EnsEMBL::Hive::GuestProcess::_get_wrapper_for_language('python3');
  Description : Finds the wrapper that understands the given language
  Returntype  : String
  Exceptions  : Can die if the wrapper doesn't exist

=cut

sub _get_wrapper_for_language {
    my ($language) = @_;

    my $wrapper = $ENV{'EHIVE_WRAPPER_'.(uc $language)} # User-overriden wrapper
                    || sprintf('%s/wrappers/%s/wrapper', $ENV{'EHIVE_ROOT_DIR'}, $language);  # Embedded wrapper
    if (not -e $wrapper) {
        die "$language is currently not supported\n";
    } elsif (not -s $wrapper) {
        die "The wrapper '$wrapper' is an empty file !\n";
    } elsif (not -x $wrapper) {
        die "No permissions to execute the wrapper '$wrapper'\n";
    }
    return $wrapper;
}


=head2 DESTROY

  Description : Destructor: tells the child to exit by sending an empty JSON object
  Returntype  : none

=cut

sub DESTROY {
    my $self = shift;
    $self->print_debug("DESTROY");
    $self->child_in->print("{}\n");
    #kill('KILL', $self->child_pid);
}


=head2 print_debug

  Example     : $process->print_debug("debug message");
  Description : Prints a message if $self->debug is 2 or above
  Returntype  : none

=cut

sub print_debug {
    my ($self, $msg) = @_;
    print STDERR sprintf("PERL %d: %s\n", $self->child_pid, $msg) if $self->debug > 1;
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
    $self->print_debug("send_message $j");
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
    die "Did not receive any messages" unless defined $s;
    chomp $s;
    $self->print_debug("read_message: $s");
    return $self->json_formatter->decode($s);
}


=head2 wait_for_OK

  Example     : $process->wait_for_OK();
  Description : Wait for the child process to send the OK signal
  Returntype  : none
  Exceptions  : dies if the response is not OK, or anything raised by L<read_message()>

=cut

sub wait_for_OK {
    my $self = shift;
    my $s = $self->read_message();
    die "Response message does not look like a response" if not exists $s->{'response'};
    die "Received response is not OK" if ref($s->{'response'}) or $s->{'response'} ne 'OK';
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
                See the description of this module for details about the protocol
  Returntype  : Hashref
  Exceptions  : none

=cut

sub life_cycle {
    my $self = shift;

    $self->print_debug("LIFE_CYCLE");

    my $job = $self->input_job();
    my $partial_stopwatch = Bio::EnsEMBL::Hive::Utils::Stopwatch->new();
    my %job_partial_timing = ();

    my %struct = (
        input_job => {
            parameters => $job->{_unsubstituted_param_hash},
            input_id => $job->input_id,
            dbID => $job->dbID + 0,
            retry_count => $job->retry_count + 0,
        },
        execute_writes => $self->execute_writes || 0,
        debug => $self->debug || 0,
    );
    $self->print_debug("SEND JOB PARAM");
    $self->send_message(\%struct);
    $self->wait_for_OK();

    # A simple event loop
    while (1) {
        $self->print_debug("WAITING IN LOOP");

        my $msg = $self->read_message;
        my $event = $msg->{event};
        my $content = $msg->{content};
        $self->print_debug("processing event '$event'");

        if ($event eq 'JOB_STATUS_UPDATE') {
            $job_partial_timing{$job->status} = $partial_stopwatch->get_elapsed() if ($job->status ne 'READY') and ($job->status ne 'CLAIMED');
            $self->enter_status(uc $content);
            $partial_stopwatch->restart();
            $self->send_response('OK');

        } elsif ($event eq 'WARNING') {
            $self->warning($content->{message}, $content->{is_error});
            $self->send_response('OK');

        } elsif ($event eq 'DATAFLOW') {
            $job->{_param_hash} = $content->{params}->{substituted};
            $job->{_unsubstituted_param_hash} = $content->{params}->{unsubstituted};
            my $d = $self->dataflow_output_id($content->{output_ids}, $content->{branch_name_or_code});
            $self->send_message($d);

        } elsif ($event eq 'WORKER_TEMP_DIRECTORY') {
            $self->{worker_temp_directory_name} = $content;
            my $wtd = $self->worker_temp_directory;
            $self->send_response($wtd);

        } elsif ($event eq 'JOB_END') {
            # Especially here we need to be careful about boolean values
            # They are coded as JSON::true and JSON::false which have
            # different meanings in text / number contexts
            $job->autoflow($job->autoflow and $content->{job}->{autoflow});
            $job->lethal_for_worker($content->{job}->{lethal_for_worker}+0);
            $job->transient_error($content->{job}->{transient_error}+0);
            $job->{_param_hash} = $content->{params}->{substituted};
            $job->{_unsubstituted_param_hash} = $content->{params}->{unsubstituted};

            # This piece of code is duplicated from Process
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
            } else {
                $job->died_somewhere(1);
            }
            $self->send_response('OK');
            return \%job_partial_timing;
        } else {
            die "Unknown event '$event' coming from the child";
        }
    }
}

=head2 worker_temp_directory_name

  Example     : $process->worker_temp_directory_name();
  Description : Returns the name of the temp directory for this module
                The value in $self is initialized at the WORKER_TEMP_DIRECTORY
                event above and returned to the caller if defined. This allows
                runnables to redefine the name
  Returntype  : string
  Exceptions  : none

=cut

sub worker_temp_directory_name {
    my $self = shift;
    return $self->{worker_temp_directory_name} if $self->{worker_temp_directory_name};
    return $self->SUPER::worker_temp_directory_name();
}




### Summary of Process methods ###

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
