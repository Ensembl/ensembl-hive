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
                'url'       => $self->dbconn_2_url( 'pipeline_db' ),
                'filename'  => $ENV{'HOME'}.'/db_snapshot_before_critical_A',
                'cmd'       => 'eval mysqldump `db_cmd.pl -url #url# -to_params` > #filename#',
            },
        },

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


package Bio::EnsEMBL::Hive::RunnableDB::SystemCmd;

use strict;
use warnings;
use base ('Bio::EnsEMBL::Hive::Process');


=head2 strict_hash_format

    Description : Implements strict_hash_format() interface method of Bio::EnsEMBL::Hive::Process that is used to set the strictness level of the parameters' parser.
                  Here we return 0 in order to indicate that neither input_id() nor parameters() is required to contain a hash.

=cut

sub strict_hash_format {
    return 0;
}


=head2 fetch_input

    Description : Implements fetch_input() interface method of Bio::EnsEMBL::Hive::Process that is used to read in parameters and load data.
                  Here it deals with finding the command line, doing parameter substitution and storing the result in a predefined place.

    param('cmd'): The recommended way of passing in the command line.

    param('*'):   Any other parameters can be freely used for parameter substitution.

=cut

sub fetch_input {
    my $self = shift;

        # First, FIND the command line
        #
    my $cmd = ($self->input_id()!~/^\{.*\}$/)
            ? $self->input_id()                 # assume the command line is given in input_id
            : $self->param('cmd')               # or defined as a hash value (in input_id or parameters)
    or die "Could not find the command defined in param('cmd') or input_id()";

        # Store the value with parameter substitutions for the actual execution:
        #
    $self->param('cmd', $cmd);
}


=head2 run

    Description : Implements run() interface method of Bio::EnsEMBL::Hive::Process that is used to perform the main bulk of the job (minus input and output).
                  Here it actually runs the command line.

=cut

sub run {
    my $self = shift;
 
    my $cmd = $self->param('cmd');

    if($self->debug()) {
        warn qq{cmd = "$cmd"\n};
    }

    $self->dbc and $self->dbc->disconnect_when_inactive(1);    # release this connection for the duration of system() call

    if(my $return_value = system($cmd)) {
        $return_value >>= 8;
        die "system( $cmd ) failed: $return_value";
    }

    $self->dbc and $self->dbc->disconnect_when_inactive(0);    # allow the worker to keep the connection open again
}


=head2 write_output

    Description : Implements write_output() interface method of Bio::EnsEMBL::Hive::Process that is used to deal with job's output after the execution.
                  Here we have nothing to do, as the wrapper is very generic.

=cut

sub write_output {
}

1;
