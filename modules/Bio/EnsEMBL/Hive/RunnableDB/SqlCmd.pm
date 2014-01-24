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
    If you behave you may also use parameter substitution.

    The SQL command(s) can be given using two different syntaxes:

    1) Sql command is stored in the input_id() or parameters() as the value corresponding to the 'sql' key.
        THIS IS THE RECOMMENDED WAY as it allows to pass in other parameters and use the parameter substitution mechanism in its full glory.

    2) Sql command is stored in the 'input_id' field of the job table.
        (only works with sql commands shorter than 255 bytes).
        This is a legacy syntax. Most people tend to use it not realizing there are other possiblities.

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


package Bio::EnsEMBL::Hive::RunnableDB::SqlCmd;

use strict;

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
                  Here it deals with finding the sql command(s), doing parameter substitution, storing the result in a predefined place
                  and optionally connecting to another database (see param('db_conn')).

    param('sql'): The recommended way of passing in the sql command(s).

    param('db_conn'): An optional hash to pass in connection parameters to the database upon which the sql command(s) will have to be run.

    param('*'):   Any other parameters can be freely used for parameter substitution.

=cut

sub fetch_input {
    my $self = shift;

        # First, FIND the sql command
        #
    my $sql = ($self->input_id()!~/^\{.*\}$/)
            ? $self->input_id()                 # assume the sql command is given in input_id
            : $self->param('sql')               # or defined as a hash value (in input_id or parameters)
    or die "Could not find the command defined in param('sql') or input_id()";

        #   Store the sql command array:
        #
    $self->param('sqls', (ref($sql) eq 'ARRAY') ? $sql : [$sql] );  
}


=head2 run

    Description : Implements run() interface method of Bio::EnsEMBL::Hive::Process that is used to perform the main bulk of the job (minus input and output).
                  Here it actually runs the sql command(s).  If a list of commands is given, they are run in succession within the same session
                  (so you can create a temporary tables and use it in another command within the same sql command list).

=cut

sub run {
    my $self = shift;

    my $sqls = $self->param('sqls');
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

