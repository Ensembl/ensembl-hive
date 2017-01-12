=pod 

=head1 NAME

Bio::EnsEMBL::Hive::RunnableDB::LoadIntoTable

=head1 SYNOPSIS

    standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::LoadIntoTable --table meta_foo \
                --src_db_conn mysql://ensadmin:${ENSADMIN_PSW}@127.0.0.1:2913/lg4_compara_homology_merged_64 \
                --dest_db_conn mysql://ensadmin:${ENSADMIN_PSW}@127.0.0.1:2912/lg4_compara_families_64

=head1 DESCRIPTION

    This RunnableDB module lets you copy/merge rows from a table in one database into table with the same name in another.
    There are three modes ('overwrite', 'topup' and 'insertignore') that do it very differently.
    Also, 'where' parameter allows to select subset of rows to be copied/merged over.

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2017] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::RunnableDB::LoadIntoTable;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Utils ('go_figure_dbc', 'stringify');

use base ('Bio::EnsEMBL::Hive::Process');

sub param_defaults {
    return {
        'src_db_conn'   => '',
        'dest_db_conn'  => '',
        'mode'          => 'overwrite',
    };
}

=head2 fetch_input

    Description : Implements fetch_input() interface method of Bio::EnsEMBL::Hive::Process that is used to read in parameters and load data.
                  Here it parses parameters and creates up to two database handles (for the input and output databases).

    param('src_db_conn'):   connection parameters to the source database (if different from hive_db)

    param('dest_db_conn'):  connection parameters to the destination database (if different from hive_db - at least one of the two will have to be different)

    param('mode'):          'overwrite' (default), 'topup' or 'insertignore'

    param('table'):         table name to be copied/merged.

    param('inputquery'):    query that fetches the data to copy over.

=cut

sub fetch_input {
    my $self = shift;

    my $src_db_conn  = $self->param('src_db_conn');
    my $dest_db_conn = $self->param('dest_db_conn');

    if($src_db_conn eq $dest_db_conn) {
        $self->input_job->transient_error(0);
        die "Please either specify 'src_db_conn' or 'dest_db_conn' or make them different\n";
    }

    my $table = $self->param_required('table');
    my $mode  = $self->param_required('mode');
    my $query = $self->param_required('inputquery');

    my $src_dbc     = $src_db_conn  ? go_figure_dbc( $src_db_conn )  : $self->data_dbc;
    my $dest_dbc    = $dest_db_conn ? go_figure_dbc( $dest_db_conn ) : $self->data_dbc;

    $self->param('src_dbc',         $src_dbc);
    $self->param('dest_dbc',        $dest_dbc);
}

=head2 run

    Description : Implements run() interface method of Bio::EnsEMBL::Hive::Process that is used to perform the main bulk of the job (minus input and output).
                  Here we fetch the data from one database and insert them into the other

=cut

sub run {
    my $self = shift;

    my $table = $self->param_required('table');
    my $mode  = $self->param_required('mode');

    my $src_dbc     = $self->param('src_dbc');
    my $dest_dbc    = $self->param('dest_dbc');

    if ($mode eq 'overwrite') {
        $dest_dbc->do('DELETE FROM '.$table);
    }

    my $insert_cmd = $mode eq 'insertignore' ? 'INSERT IGNORE' : 'INSERT';
    my $select_sth = $src_dbc->prepare($self->param_required('inputquery'), { 'mysql_use_result' => 1 });
                     $select_sth->execute();
    my $col_names  = $select_sth->dbi_sth->{NAME};  # This is the new way of reaching DBI's statement handle

    my $select_n   = -1;    # because there is a final void call to detect the end of fetching
    my $insert_sql = sprintf('%s INTO %s (%s) VALUES (%s)', $insert_cmd, $table, join(',', @$col_names), join(',', map {'?'} @$col_names));
    my $insert_sth = $dest_dbc->prepare($insert_sql);
    #my $select_sub = sub { $select_n++; $select_sth->fetchrow_arrayref };
    #my $insert_n   = $insert_sth->execute_for_fetch($select_sub);
    my $insert_n   = $insert_sth->execute_array( { ArrayTupleFetch => $select_sth->dbi_sth } );
       $select_n   = $select_sth->rows;

    $select_sth->finish();
    $insert_sth->finish();

    $self->warning("Fetched $select_n rows and inserted $insert_n rows");
}


1;

