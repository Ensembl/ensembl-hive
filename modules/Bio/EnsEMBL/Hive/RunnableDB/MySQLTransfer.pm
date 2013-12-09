=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::RunnableDB::MySQLTransfer

=head1 SYNOPSIS

    standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::MySQLTransfer --table meta_foo \
                --src_db_conn mysql://ensadmin:${ENSADMIN_PSW}@127.0.0.1:2913/lg4_compara_homology_merged_64 \
                --dest_db_conn mysql://ensadmin:${ENSADMIN_PSW}@127.0.0.1:2912/lg4_compara_families_64

=head1 DESCRIPTION

    This RunnableDB module lets you copy/merge rows from a table in one database into table with the same name in another.
    There are three modes ('overwrite', 'topup' and 'insertignore') that do it very differently.
    Also, 'where' parameter allows to select subset of rows to be copied/merged over.

=head1 LICENSE

    Copyright [1999-2013] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::RunnableDB::MySQLTransfer;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Utils ('go_figure_dbc');

use base ('Bio::EnsEMBL::Hive::Process');

sub param_defaults {
    return {
        'src_db_conn'   => '',
        'dest_db_conn'  => '',
        'mode'          => 'overwrite',
        'table'         => '',
        'where'         => undef,
        'filter_cmd'    => undef,
    };
}


=head2 fetch_input

    Description : Implements fetch_input() interface method of Bio::EnsEMBL::Hive::Process that is used to read in parameters and load data.
                  Here it parses parameters, creates up to two database handles and finds the pre-execution row counts filtered by '$where'.

    param('src_db_conn'):   connection parameters to the source database (if different from hive_db)

    param('dest_db_conn'):  connection parameters to the destination database (if different from hive_db - at least one of the two will have to be different)

    param('mode'):          'overwrite' (default), 'topup' or 'insertignore'

    param('where'):         filter for rows to be copied/merged.

    param('table'):         table name to be copied/merged.

=cut

sub fetch_input {
    my $self = shift;

    my $src_db_conn  = $self->param('src_db_conn');
    my $dest_db_conn = $self->param('dest_db_conn');

    $self->input_job->transient_error(0);
    if($src_db_conn eq $dest_db_conn) {
        die "Please either specify 'src_db_conn' or 'dest_db_conn' or make them different\n";
    }
    my $table = $self->param('table') or die "Please specify 'table' parameter\n";
    $self->input_job->transient_error(1);

    my $src_dbc     = $src_db_conn  ? go_figure_dbc( $src_db_conn )  : $self->data_dbc;
    my $dest_dbc    = $dest_db_conn ? go_figure_dbc( $dest_db_conn ) : $self->data_dbc;

    $self->param('src_dbc',         $src_dbc);
    $self->param('dest_dbc',        $dest_dbc);

    my $where = $self->param('where');

    $self->param('src_before',  $self->get_row_count($src_dbc,  $table, $where) );

    if($self->param('mode') ne 'overwrite') {
        $self->param('dest_before_all', $self->get_row_count($dest_dbc, $table) );
    }
}

=head2 run

    Description : Implements run() interface method of Bio::EnsEMBL::Hive::Process that is used to perform the main bulk of the job (minus input and output).
                  Here the actual data transfer is attempted.

=cut

sub run {
    my $self = shift;

    my $src_dbc     = $self->param('src_dbc');
    my $dest_dbc    = $self->param('dest_dbc');

    my $mode        = $self->param('mode');
    my $table       = $self->param('table');
    my $where       = $self->param('where');
    my $filter_cmd  = $self->param('filter_cmd');

    my $cmd = 'mysqldump '
                . { 'overwrite' => '', 'topup' => '--no-create-info ', 'insertignore' => '--no-create-info --insert-ignore ' }->{$mode}
                . $self->mysql_conn_from_dbc($src_dbc)
                . " $table "
                . (defined($where) ? "--where '$where' " : '')
                . '| '
                . ($filter_cmd ? "$filter_cmd | " : '')
                . 'mysql '
                . $self->mysql_conn_from_dbc($dest_dbc);

    if(my $return_value = system($cmd)) {   # NB: unfortunately, this code won't catch many errors because of the pipe
        $return_value >>= 8;
        die "system( $cmd ) failed: $return_value";
    }
}

=head2 write_output

    Description : Implements write_output() interface method of Bio::EnsEMBL::Hive::Process that is used to deal with job's output after the execution.
                  Here we compare the number of rows and detect problems.

=cut

sub write_output {
    my $self = shift;

    my $dest_dbc    = $self->param('dest_dbc');

    my $mode        = $self->param('mode');
    my $table       = $self->param('table');
    my $where       = $self->param('where');

    my $src_before  = $self->param('src_before');

    if($mode eq 'overwrite') {
        my $dest_after      = $self->get_row_count($dest_dbc,  $table, $where);

        if($src_before == $dest_after) {
            $self->warning("Successfully copied $src_before '$table' rows");
        } else {
            die "Could not copy '$table' rows: $src_before rows from source copied into $dest_after rows in target\n";
        }
    } else {

        my $dest_row_increase = $self->get_row_count($dest_dbc, $table) - $self->param('dest_before_all');

        if($mode eq 'topup') {
            if($src_before <= $dest_row_increase) {
                $self->warning("Cannot check success/failure in this mode, but the number of '$table' rows in target increased by $dest_row_increase (higher than $src_before)");
            } else {
                die "Could not add rows: $src_before '$table' rows from source copied into $dest_row_increase rows in target\n";
            }
        } elsif($mode eq 'insertignore') {
            $self->warning("Cannot check success/failure in this mode, but the number of '$table' rows in target increased by $dest_row_increase");
        }
    }
}

########################### private subroutines ####################################

sub get_row_count {
    my ($self, $dbc, $table, $where) = @_;

    my $sql = "SELECT count(*) FROM $table" . (defined($where) ? " WHERE $where" : '');

    my $sth = $dbc->prepare($sql);
    $sth->execute();
    my ($row_count) = $sth->fetchrow_array();
    $sth->finish;

    return $row_count;
}

sub mysql_conn_from_dbc {
    my ($self, $dbc) = @_;

    return '--host='.$dbc->host.' --port='.$dbc->port." --user='".$dbc->username."' --pass='".$dbc->password."' ".$dbc->dbname;
}

1;

