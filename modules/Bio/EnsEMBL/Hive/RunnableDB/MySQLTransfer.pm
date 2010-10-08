
=pod 

=head1 NAME

Bio::EnsEMBL::Hive::RunnableDB::MySQLTransfer

=head1 SYNOPSIS

This is a RunnableDB module that implements Bio::EnsEMBL::Hive::Process interface
and is ran by Workers during the execution of eHive pipelines.
It is not generally supposed to be instantiated and used outside of this framework.

Please refer to Bio::EnsEMBL::Hive::Process documentation to understand the basics of the RunnableDB interface.

Please refer to Bio::EnsEMBL::Hive::PipeConfig::* pipeline configuration files to understand how to configure pipelines.

=head1 DESCRIPTION

This RunnableDB module lets you copy/merge rows from a table in one database into table with the same name in another.
There are three modes ('overwrite', 'topup' and 'insertignore') that do it very differently.
Also, 'where' parameter allows to select subset of rows to be copied/merged over.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::RunnableDB::MySQLTransfer;

use strict;
use DBI;

use base ('Bio::EnsEMBL::Hive::Process');

=head2 fetch_input

    Description : Implements fetch_input() interface method of Bio::EnsEMBL::Hive::Process that is used to read in parameters and load data.
                  Here it parses parameters, creates up to two database handles and finds the pre-execution row counts filtered by '$where'.

    param('src_db_conn'):   connection parameters to the source database (if different from hive_db)

    param('dest_db_conn'):  connection parameters to the destination database (if different from hive_db - at least one of the two will have to be different)

    param('mode'):          'overwrite' (default), 'topup' or 'insertignore'

    param('where'):         filter for rows to be copied/merged

    param('table'):         table name to be copied/merged

=cut

sub fetch_input {
    my $self = shift;

    my ($src_dbh, $dest_dbh);

    my $src_db_conn  = $self->param('src_db_conn');
    my $dest_db_conn = $self->param('dest_db_conn');

    $self->input_job->transient_error(0);
    if($src_db_conn eq $dest_db_conn) {
        die "Please either specify 'src_db_conn' or 'dest_db_conn' or make them different\n";
    }
    my $table = $self->param('table') or die "Please specify 'table' parameter\n";
    $self->input_job->transient_error(1);

        # Use connection parameters to source database if supplied, otherwise use the current database as default:
        #
    my ($src_dbh, $src_mysql_conn) = $src_db_conn
        ? ( (DBI->connect("DBI:mysql:$src_db_conn->{-dbname}:$src_db_conn->{-host}:$src_db_conn->{-port}", $src_db_conn->{-user}, $src_db_conn->{-pass}, { RaiseError => 1 })
            || die "Couldn't connect to database: " . DBI->errstr) ,
            $self->mysql_conn_from_hash($src_db_conn) )
        : ($self->db->dbc->db_handle, $self->mysql_conn_from_this_dbc );

        # Use connection parameters to destination database if supplied, otherwise use the current database as default:
        #
    my ($dest_dbh, $dest_mysql_conn) = $dest_db_conn
        ? ( (DBI->connect("DBI:mysql:$dest_db_conn->{-dbname}:$dest_db_conn->{-host}:$dest_db_conn->{-port}", $dest_db_conn->{-user}, $dest_db_conn->{-pass}, { RaiseError => 1 })
            || die "Couldn't connect to database: " . DBI->errstr) ,
            $self->mysql_conn_from_hash($dest_db_conn) )
        : ($self->db->dbc->db_handle, $self->mysql_conn_from_this_dbc );

    $self->param('src_dbh',         $src_dbh);
    $self->param('dest_dbh',        $dest_dbh);
    $self->param('src_mysql_conn',  $src_mysql_conn);
    $self->param('dest_mysql_conn', $dest_mysql_conn);

    my $mode = $self->param('mode') || 'overwrite';
        $self->param('mode', $self->param('mode'));
    my $where = $self->param('where') || '';

    $self->param('src_before',  $self->get_row_count($src_dbh,  $table, $where) );

    if($mode ne 'overwrite') {
        $self->param('dest_before_all', $self->get_row_count($dest_dbh, $table) );
    }
}

=head2 run

    Description : Implements run() interface method of Bio::EnsEMBL::Hive::Process that is used to perform the main bulk of the job (minus input and output).
                  Here the actual data transfer is attempted.

=cut

sub run {
    my $self = shift;

    my $filter_cmd      = $self->param('filter_cmd');

    my $src_mysql_conn  = $self->param('src_mysql_conn');
    my $dest_mysql_conn = $self->param('dest_mysql_conn');

    my $mode  = $self->param('mode')  || 'overwrite';
    my $table = $self->param('table');
    my $where = $self->param('where') || '';

    my $cmd = 'mysqldump '
                . { 'overwrite' => '', 'topup' => '--no-create-info ', 'insertignore' => '--no-create-info --insert-ignore ' }->{$mode}
                . "$src_mysql_conn $table "
                . ($where ? "--where '$where' " : '')
                . '| '
                . ($filter_cmd ? "$filter_cmd | " : '')
                . "mysql $dest_mysql_conn";

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

    my $mode  = $self->param('mode');
    my $table = $self->param('table');
    my $where = $self->param('where') || '';

    my $dest_dbh = $self->param('dest_dbh');

    my $src_before      = $self->param('src_before');

    if($mode eq 'overwrite') {
        my $dest_after      = $self->get_row_count($dest_dbh,  $table, $where);

        if($src_before == $dest_after) {
            $self->input_job->incomplete(0);
            die "Successfully copied $src_before '$table' rows\n";
        } else {
            die "Could not copy '$table' rows: $src_before rows from source copied into $dest_after rows in target\n";
        }
    } else {

        my $dest_row_increase = $self->get_row_count($dest_dbh, $table) - $self->param('dest_before_all');

        if($mode eq 'topup') {
            if($src_before == $dest_row_increase) {
                $self->input_job->incomplete(0);
                die "Successfully added $src_before '$table' rows\n";
            } else {
                die "Could not add rows: $src_before '$table' rows from source copied into $dest_row_increase rows in target\n";
            }
        } elsif($mode eq 'insertignore') {
            $self->input_job->incomplete(0);
            die "Cannot check success/failure in this mode, but the number of '$table' rows in target increased by $dest_row_increase\n";
        }
    }
}

########################### private subroutines ####################################

sub get_row_count {
    my ($self, $dbh, $table, $where) = @_;

    my $sql = "SELECT count(*) FROM $table" . ($where ? "WHERE $where" : '');

    my $sth = $dbh->prepare($sql);
    $sth->execute();
    my ($row_count) = $sth->fetchrow_array();
    $sth->finish;

    return $row_count;
}

sub mysql_conn_from_hash {
    my ($self, $db_conn) = @_;

    return "--host=$db_conn->{-host} --port=$db_conn->{-port} --user='$db_conn->{-user}' --pass='$db_conn->{-pass}' $db_conn->{-dbname}";
}

sub mysql_conn_from_this_dbc {
    my ($self) = @_;

    my $dbc = $self->db->dbc();

    return '--host='.$dbc->host.' --port='.$dbc->port." --user='".$dbc->username."' --pass='".$dbc->password."' ".$dbc->dbname;
}

1;

