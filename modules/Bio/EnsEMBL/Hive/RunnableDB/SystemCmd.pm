=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::RunnableDB::SystemCmd

=head1 SYNOPSIS

    standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::SystemCmd --cmd 'ls -1 ${ENSEMBL_CVS_ROOT_DIR}/ensembl-hive/modules/Bio/EnsEMBL/Hive/RunnableDB/*.pm >building_blocks.list'

=head1 DESCRIPTION

    This RunnableDB module acts as a wrapper for shell-level command lines. If you behave you may also use parameter substitution.

    The command line must be stored in the parameters() as the value corresponding to the 'cmd' key.
    It allows to pass in other parameters and use the parameter substitution mechanism in its full glory.

    This Runnable also allows the creation of dataflow using JSON stored in an external file.
    Each line of this file contains an optional branch number, followed by a complete JSON serialisation of the parameters (output_id)
    appearing on the same single line. For example, a line to direct dataflow on branch 2 might look like:

          2 {"parameter_name" : "parameter_value"}

    If no branch number is provided, then dataflow of those parameters will occour on the branch number
    passed to SystemCmd in the 'dataflow_branch' parameter, if given. Otherwise, it will default to
    branch 1 (autoflow).

    A sample file is provided at ${EHIVE_ROOT_DIR}/modules/Bio/EnsEMBL/Hive/Examples/SystemCmd/PipeConfig/sample_files/Inject_JSON_Dataflow_example.json

=head1 CONFIGURATION EXAMPLES

    # The following example shows how to configure SystemCmd in a PipeConfig module
    # to create a MySQL snapshot of the Hive database before executing a critical operation.
    #
    # It is a useful incantation when debugging pipelines, similar to setting a breakpoint/savepoint.
    # You will be able to reset your pipeline to the saved point in by un-dumping this file.

        {   -logic_name => 'db_snapshot_before_critical_A',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => {
                'filename'  => $ENV{'HOME'}.'/db_snapshot_before_critical_A',
                'cmd'       => $self->db_cmd().' --executable mysqldump > #filename#',
            },
        },

    # The following example shows how to configure SystemCmd in a PipeConfig module
    # to generate dataflow events based on parameters stored as JSON in a file named "some_parameters.json"

        {  -logic_name => 'inject_parameters_from_file',
           -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
           -parameters => {
                'dataflow_file' => 'some_parameters.json',
                'cmd'           => 'sleep 0', # a command must be provided in the cmd parameter
           },
        },

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


package Bio::EnsEMBL::Hive::RunnableDB::SystemCmd;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::Process');


sub param_defaults {
    return {
        return_codes_2_branches => {},      # Hash that maps some of the command return codes to branch numbers
        'use_bash_pipefail' => 0,           # Boolean. When true, the command will be run with "bash -o pipefail -c $cmd". Useful to capture errors in a command that contains pipes
        'use_bash_errexit'  => 0,           # When the command is composed of multiple commands (concatenated with a semi-colon), use "bash -o errexit" so that a failure will interrupt the whole script
        'dataflow_file'     => undef,       # The path to a file that contains 1 line per dataflow event, in the form of a JSON object
        'dataflow_branch'   => undef,       # The default branch for JSON dataflows
        'timeout'           => undef,       # Maximum runtime of the command
    }
}


=head2 run

    Description : Implements run() interface method of Bio::EnsEMBL::Hive::Process that is used to perform the main bulk of the job (minus input and output).
                  Here it actually runs the command line.

    param('cmd'): The recommended way of passing in the command line. It can be either a string, or an array-ref of strings. The later is safer if some of the
                  arguments contain white-spaces.

    param('*'):   Any other parameters can be freely used for parameter substitution.

=cut

sub run {
    my $self = shift;
 
    my %transferred_options = map {$_ => $self->param($_)} qw(use_bash_pipefail use_bash_errexit timeout);
    my ($return_value, $stderr, $flat_cmd, $stdout, $runtime_msec) = $self->run_system_command($self->param_required('cmd'), \%transferred_options);

    # To be used in write_output()
    $self->param('return_value', $return_value);
    $self->param('stderr', $stderr);
    $self->param('flat_cmd', $flat_cmd);
    $self->param('stdout', $stdout);
    $self->param('runtime_msec', $runtime_msec);
}


=head2 write_output

    Description : Implements write_output() interface method of Bio::EnsEMBL::Hive::Process that is used to deal with job's output after the execution.
                  Here we take actions based on the command's exit status.

=cut

sub write_output {
    my $self = shift;

    my $return_value = $self->param('return_value');

    ## Success
    unless ($return_value) {
        # FIXME branch number
        $self->dataflow_output_ids_from_json($self->param('dataflow_file'), $self->param('dataflow_branch')) if $self->param('dataflow_file');
        return;
    }

    ## Error processing
    my $stderr = $self->param('stderr');
    my $flat_cmd = $self->param('flat_cmd');

    if ($return_value == -1) {
        # system() could not start, or wait() failed
        die sprintf( "Could not start '%s': %s\n", $flat_cmd, $stderr);

    } elsif ($return_value == -2) {
        $self->complete_early_if_branch_connected("The command was aborted because it exceeded the allowed runtime. Flowing to the -2 branch.\n", -2);
        die "The command was aborted because it exceeded the allowed runtime, but there are no dataflow-rules on branch -2.\n";

    # Lower 8 bits indicate the process has been killed and did not complete.
    } elsif ($return_value & 255) {
        # It can happen because of a MEMLIMIT / RUNLIMIT, which we
        # know are not atomic. The best is to wait a bit that LSF kills
        # the worker too
        sleep 30;
        # If we reach this point, it was killed for another reason.
        die sprintf( "'%s' was killed with code=%d\nstderr is: %s\n", $flat_cmd, $return_value, $stderr);

    } else {
        # "Normal" process exit with a non-zero code (in the upper 8 bits)
        $return_value >>= 8;

        # We create a dataflow event depending on the exit code of the process.
        if (ref($self->param('return_codes_2_branches')) and exists $self->param('return_codes_2_branches')->{$return_value}) {
            my $branch_number = $self->param('return_codes_2_branches')->{$return_value};
            $self->complete_early(sprintf("The command exited with code %d, which is mapped to a dataflow on branch #%d.\n", $return_value, $branch_number), $branch_number);
        }

        if ($stderr =~ /Exception in thread ".*" java.lang.OutOfMemoryError: Java heap space at/) {
            $self->complete_early_if_branch_connected("Java heap space is out of memory. A job has been dataflown to the -1 branch.\n", -1);
            die $stderr;
        }

        die sprintf( "'%s' resulted in an error code=%d\nstderr is: %s\n", $flat_cmd, $return_value, $stderr);
    }
}


######################
## Internal methods ##
######################

=head2 complete_early_if_branch_connected

  Arg[1]      : (string) message
  Arg[2]      : (integer) branch number
  Description : Wrapper around complete_early that first checks that the
                branch is connected to something.
  Returntype  : void if the branch is not connected. Otherwise doesn't return

=cut

sub complete_early_if_branch_connected {
    my ($self, $message, $branch_code) = @_;

    # just return if no corresponding gc_dataflow rule has been defined
    return unless $self->input_job->analysis->dataflow_rules_by_branch->{$branch_code};

    $self->complete_early($message, $branch_code);
}

1;
