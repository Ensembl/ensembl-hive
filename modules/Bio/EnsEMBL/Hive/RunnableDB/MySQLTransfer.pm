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

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2021] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::RunnableDB::MySQLTransfer;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Utils ('go_figure_dbc', 'stringify');

use base ('Bio::EnsEMBL::Hive::RunnableDB::SystemCmd');

sub param_defaults {
    my $self = shift;
    return {
        %{ $self->SUPER::param_defaults() },

        'src_db_conn'   => '',
        'dest_db_conn'  => '',
        'mode'          => 'overwrite',
        'where'         => undef,
        'filter_cmd'    => undef,
        'renamed_table' => undef,                                       # optional argument - lets you rename the table
        'rename_filter' => 'sed "s/\`#table#\`/\`#renamed_table#\`/" | sed "s/\`#table#_ibfk/\`#renamed_table#_ibfk/"', # NB: only change this if your data contains backticked table name AND you know how to fix it

        # Overrides default values of SystemCmd
        'use_bash_pipefail'         => 1,
        'lock_tables'   => 0,
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

    param('lock_tables'):   [boolean] when 1, lock tables when dumping the source database. Default if not set (or set to 0) is to not lock (runs mysqldump with --skip-lock-tables) 

=cut

sub fetch_input {
    my $self = shift;

    my $src_db_conn  = $self->param('src_db_conn');
    my $dest_db_conn = $self->param('dest_db_conn');

    $self->input_job->transient_error(0);
    if($src_db_conn eq $dest_db_conn) {
        die "Please either specify 'src_db_conn' or 'dest_db_conn' or make them different\n";
    }
    my $table = $self->param_required('table');
    $self->input_job->transient_error(1);

    my $src_dbc     = $src_db_conn  ? go_figure_dbc( $src_db_conn )  : $self->data_dbc;
    my $dest_dbc    = $dest_db_conn ? go_figure_dbc( $dest_db_conn ) : $self->data_dbc;

    $self->param('src_dbc',         $src_dbc);
    $self->param('dest_dbc',        $dest_dbc);

    my $where = $self->param('where');
    my $mode  = $self->param_required('mode');

    $self->param('src_before',  $self->get_row_count($src_dbc,  $table, $where) );

    if($mode ne 'overwrite') {
        $self->_assert_same_table_schema($src_dbc, $dest_dbc, $table);
    }

    my $mode_options = { 'overwrite' => [], 'topup' => [qw(--no-create-info --insert-ignore)], 'insertignore' => [qw(--no-create-info --insert-ignore)] }->{$mode};
    die "Mode '$mode' not recognized. Should be 'overwrite', 'topup' or 'insertignore'\n" unless $mode_options;

    my $lock_tables = $self->param('lock_tables');
    push(@{$mode_options}, '--skip-lock-tables') unless ($lock_tables);

    my $filter_cmd      = $self->param('filter_cmd');

    my $renamed_table   = $self->param('renamed_table');
    my $rename_filter   = $renamed_table && $self->param('rename_filter').' | ';

    # Must be joined because of the pipe
    my $cmd = join(' ',
                @{$src_dbc->to_cmd('mysqldump', $mode_options, undef, undef, 1)},
                $table,
                (defined($where) ? "--where '$where' " : ''),
                '|',
                ($rename_filter || ''),
                ($filter_cmd ? "$filter_cmd | " : ''),
                @{$dest_dbc->to_cmd(undef, undef, undef, undef, 1)}
            );
    $self->param('cmd', $cmd);
}

=head2 write_output

    Description : Implements write_output() interface method of Bio::EnsEMBL::Hive::Process that is used to deal with job's output after the execution.
                  Here we compare the number of rows and detect problems.

=cut

sub write_output {
    my $self = shift;

    # Error processing
    $self->SUPER::write_output();

    my $dest_dbc    = $self->param('dest_dbc');

    my $mode        = $self->param('mode');
    my $table       = $self->param('table');
    my $ren_table   = $self->param('renamed_table') || $table;
    my $where       = $self->param('where');

    my $src_before  = $self->param('src_before');
    my $dest_after  = $self->get_row_count($dest_dbc, $ren_table, $where);

    if($mode eq 'overwrite') {

        if($src_before == $dest_after) {
            $self->warning("Successfully copied $src_before '$table' rows");
        } else {
            die "Could not copy '$table' rows: $src_before rows from source copied into $dest_after rows in target\n";
        }
    } elsif ($mode eq 'topup') {

        if($dest_after >= $src_before) {
            $self->warning("Cannot check success in this mode, but the number of '$ren_table' rows in target is indeed higher than $src_before ($dest_after)");
        } else {
            die "Could not copy '$table' rows: $src_before rows from source copied into $dest_after rows in target\n";
        }

    } else {

        $self->warning("Cannot check success/failure in this mode, but the number of '$ren_table' rows in target increased by ".($dest_after-$src_before));
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

    $dbc->disconnect_if_idle();

    return $row_count;
}

sub _assert_same_table_schema {
    my ($self, $src_dbc, $dest_dbc, $table) = @_;

    my $src_sth = $src_dbc->column_info(undef, undef, $table, '%');
    my $src_schema = $src_sth->fetchall_arrayref;
    $src_sth->finish();

    my $dest_sth = $dest_dbc->column_info(undef, undef, $table, '%');
    my $dest_schema = $dest_sth->fetchall_arrayref;
    $dest_sth->finish();

    die "'$table' has a different schema in the two databases. Do SHOW CREATE TABLE in both databases and compare the outputs." if stringify($src_schema) ne stringify($dest_schema);
}


1;

