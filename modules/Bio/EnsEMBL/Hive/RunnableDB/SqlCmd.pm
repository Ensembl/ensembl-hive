=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::RunnableDB::SqlCmd

=head1 SYNOPSIS

    standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::SqlCmd --db_conn mysql://ensadmin:${ENSADMIN_PSW}@127.0.0.1:2912/lg4_compara_families_64 \
                        --sql "INSERT INTO meta(meta_key,meta_value) VALUES ('Hello', 'world')"

    standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::SqlCmd --db_conn mysql://ensadmin:${ENSADMIN_PSW}@127.0.0.1:2913/lg4_compara_homology_merged_64 \
                        --sql "[ 'CREATE TABLE meta_foo LIKE meta', 'INSERT INTO meta_foo SELECT * FROM meta' ]"

=head1 DESCRIPTION

    This RunnableDB module acts as a wrapper for an SQL command
    run against either the current hive database (default) or against one specified by 'db_conn' parameter
    (--db_conn becomes obligatory in standalone mode, because there is no hive_db).

    The Sql command must be stored in the parameters() as the value corresponding to the 'sql' key.
    It allows to pass in other parameters and use the parameter substitution mechanism in its full glory.

    The Sql command(s) can be wrapped in a global transaction if the "wrap_in_transaction" flag is switched on (off by default)

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


package Bio::EnsEMBL::Hive::RunnableDB::SqlCmd;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::Process');

sub param_defaults {
    return {
        'wrap_in_transaction' => 0,
    }
}


=head2 run

    Description : Implements run() interface method of Bio::EnsEMBL::Hive::Process that is used to perform the main bulk of the job (minus input and output).
                  Here it is a simple decision step based on the "wrap_in_transaction" parameter. If the latter is set, call _exec_sql() in a transaction,
                  otherwise call it directly.

    param('wrap_in_transaction'): Whether or not run the commands in a global transaction

=cut

sub run {
    my $self = shift;

    if ($self->param('wrap_in_transaction')) {
        $self->_run_in_transaction();
    } else {
        $self->_exec_sql();
    }
}


=head2 _run_in_transaction

    Description : Wrapper around _exec_sql() that first sets AutoCommit to 0, and at the end issues a commit() / rollback()
                  command depending on the outcome of _exec_sql().
                  It also has to temporarily set disconnect_when_inactive() to 1 because a value of 0 would cause the
                  DBConnection object to disconnect early, which would rollback the transaction.

=cut

sub _run_in_transaction {
    my $self = shift;

    my $dbc = $self->data_dbc();

    # Save the original value of disconnect_when_inactive()
    my $original_dwi = $dbc->disconnect_when_inactive();
    $dbc->disconnect_when_inactive(0);

    # Save the original value of "AutoCommit"
    my $original_ac = $dbc->db_handle()->{'AutoCommit'};
    $dbc->db_handle()->{'AutoCommit'} = 0;

    eval {
        $self->_exec_sql();
        $dbc->db_handle()->commit();
    };
    my $error = $@;

    #If there is an error then we apply rollbacks
    if($error) {
        eval { $dbc->db_handle()->rollback(); };
    }

    # Restore the original values
    $dbc->db_handle()->{'AutoCommit'} = $original_ac;
    $dbc->disconnect_when_inactive($original_dwi);

    $self->throw("ABORT: Transaction aborted because of error: ${error}") if $error;
}


=head2 _exec_sql

    Description : Actually run the sql command(s).  If a list of commands is given, they are run in succession within the same session
                  (so you can create a temporary tables and use it in another command within the same sql command list).

    param('sql'): Either a scalar SQL command or an array of SQL commands.

    param('db_conn'): An optional hash to pass in connection parameters to the database upon which the sql command(s) will have to be run.

    param('*'):   Any other parameters can be freely used for parameter substitution.

=cut

sub _exec_sql {
    my $self = shift;

    my $sqls = $self->param_required('sql');
    $sqls = [$sqls] if(ref($sqls) ne 'ARRAY');

    my $data_dbc  = $self->data_dbc();

    my %output_id;

    my $counter = 0;
    foreach my $sql (@$sqls) {

         if($self->debug()) {
             warn qq{sql = "$sql"\n};
         }

        $data_dbc->do( $sql ) or die "Could not run '$sql': ".$data_dbc->db_handle->errstr;

        my $insert_id_name  = '_insert_id_'.$counter++;
        my $insert_id_value = $data_dbc->db_handle->last_insert_id(undef, undef, undef, undef);

        $output_id{$insert_id_name} = $insert_id_value;
        $self->param($insert_id_name, $insert_id_value); # for templates
    }

    $self->param('output_id', \%output_id);
}


=head2 write_output

    Description : Implements write_output() interface method of Bio::EnsEMBL::Hive::Process that is used to deal with job's output after the execution.
                  Here we only flow out the insert_ids.

=cut

sub write_output {
    my $self = shift;

    $self->dataflow_output_id( $self->param('output_id'), 2);
}

1;

