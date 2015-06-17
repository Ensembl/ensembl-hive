=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::RunnableDB::SystemCmd

=head1 SYNOPSIS

    standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::SystemCmd --cmd 'ls -1 ${ENSEMBL_CVS_ROOT_DIR}/ensembl-hive/modules/Bio/EnsEMBL/Hive/RunnableDB/*.pm >building_blocks.list'

=head1 DESCRIPTION

    This RunnableDB module acts as a wrapper for shell-level command lines. If you behave you may also use parameter substitution.

    The command can be given using two different syntaxes:

    1) Command line is stored in the input_id() or parameters() as the value corresponding to the 'cmd' key.
        THIS IS THE RECOMMENDED WAY as it allows to pass in other parameters and use the parameter substitution mechanism in its full glory.

    2) Command line is stored in the 'input_id' field of the job table.
        (only works with command lines shorter than 255 bytes).
        This is a legacy syntax. Most people tend to use it not realizing there are other possiblities.

=head1 CONFIGURATION EXAMPLE

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


package Bio::EnsEMBL::Hive::RunnableDB::SystemCmd;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Utils qw(join_command_args);

use Capture::Tiny ':all';

use base ('Bio::EnsEMBL::Hive::Process');


sub param_defaults {
    return {
        return_codes_2_branches => {},      # Hash that maps some of the command return codes to branch numbers
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
 
    my $cmd = $self->param_required('cmd');
    my ($join_needed, $flat_cmd) = join_command_args($cmd);
    # Let's use the array if possible, it saves us from running a shell
    my @cmd_to_run = $join_needed ? $flat_cmd : (ref($cmd) ? @$cmd : $cmd);

    if($self->debug()) {
        use Data::Dumper;
        local $Data::Dumper::Terse = 1;
        local $Data::Dumper::Indent = 0;
        warn "Command given: ", Dumper($cmd), "\n";
        warn "Command to run: ", Dumper(\@cmd_to_run), "\n";
    }

    $self->dbc and $self->dbc->disconnect_when_inactive(1);    # release this connection for the duration of system() call
    my $return_value;
    my $stderr = tee_stderr {
        $return_value = system(@cmd_to_run);
    };
    $self->dbc and $self->dbc->disconnect_when_inactive(0);    # allow the worker to keep the connection open again

    # To be used in write_output()
    $self->param('return_value', $return_value);
    $self->param('stderr', $stderr);
    $self->param('flat_cmd', $flat_cmd);
}


=head2 write_output

    Description : Implements write_output() interface method of Bio::EnsEMBL::Hive::Process that is used to deal with job's output after the execution.
                  Here we take actions based on the command's exit status.

=cut

sub write_output {
    my $self = shift;

    my $return_value = $self->param('return_value');
    my $stderr = $self->param('stderr');
    my $flat_cmd = $self->param('flat_cmd');

    if ($return_value and not ($return_value >> 8)) {
        # The job has been killed. The best is to wait a bit that LSF kills
        # the worker too
        sleep 30;
        # If we reach this point, perhaps it was killed by a user
        die sprintf( "'%s' was killed with code=%d\nstderr is: %s\n", $flat_cmd, $return_value, $stderr);

    } elsif ($return_value) {
        # "Normal" process exit with a non-zero code
        $return_value >>= 8;

        # We create a dataflow event depending on the exit code of the process.
        if (exists $self->param('return_codes_2_branches')->{$return_value}) {
            my $branch_number = $self->param('return_codes_2_branches')->{$return_value};
            $self->dataflow_output_id( $self->input_id, $branch_number );
            $self->input_job->autoflow(0);
            $self->complete_early(sprintf("The command exited with code %d, which is mapped to a dataflow on branch #%d.\n", $return_value, $branch_number));
        }

        if ($stderr =~ /Exception in thread ".*" java.lang.OutOfMemoryError: Java heap space at/) {
            $self->dataflow_output_id( $self->input_id, -1 );
            $self->input_job->autoflow(0);
            $self->complete_early("Java heap space is out of memory.\n");
        }

        die sprintf( "'%s' resulted in an error code=%d\nstderr is: %s\n", $flat_cmd, $return_value, $stderr);
    }
}

1;
