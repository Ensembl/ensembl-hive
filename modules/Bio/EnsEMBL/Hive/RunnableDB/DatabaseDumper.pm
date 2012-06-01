
=pod 

=head1 NAME

Bio::EnsEMBL::Hive::RunnableDB::DatabaseDumper

=head1 DESCRIPTION

This is a Runnable to dump the tables of a database (by default,
all of them).

The following parameters are accepted:

 - src_db_conn : the connection parameters to the database to be
    dumped (by default, the current eHive database if available)

 - exclude_ehive [boolean=0] : do we exclude the eHive-specific tables
    from the dump

 - table_list [string or array of strings]: the list of tables
    to include in the dump. The '%' wildcard is accepted.

 - exclude_list [boolean=0] : do we consider 'table_list' as a list
    of tables to be excluded from the dump (instead of included)

 - output_file [string] : the file to write the dump to

=head1 SYNOPSIS

standaloneJob.pl RunnableDB/DatabaseDumper.pm -exclude_ehive 1 -exclude_list 1 -table_list "['peptide_align_%']" -src_db_conn mysql://ensro@127.0.0.1:4313/mm14_compara_homology_67 -output_file ~/dump1.sql

=cut

package Bio::EnsEMBL::Hive::RunnableDB::DatabaseDumper;

use strict;

use base ('Bio::EnsEMBL::Hive::Process');


sub fetch_input {
    my $self = shift @_;

    my @tables;
    $self->param('tables', \@tables);
    my @ignores;
    $self->param('ignores', \@ignores);

    my @ehive_tables = qw(worker dataflow_rule analysis analysis_ctrl_rule job job_message job_file analysis_data resource_description analysis_stats analysis_stats_monitor analysis_description monitor msg progress);
    
    $self->input_job->transient_error(0);
    $self->param('output_file') || die 'The parameter "output_file" is mandatory';
    $self->param('output_file', $self->param_substitute($self->param('output_file')));

    if ($self->param('exclude_ehive')) {
        push @ignores, @ehive_tables;
    }

    if ($self->param('exclude_list')) {
        my $table_list = $self->_get_table_list;
        die 'The parameter "table_list" is mandatory' unless $table_list;
        push @ignores, @$table_list;
    } else {
        push @tables, @{$self->_get_table_list || []};
    }

    $self->input_job->transient_error(1);

    my $src_db_conn  = $self->param('src_db_conn');
    my $src_dbc = $src_db_conn ? $self->go_figure_dbc($src_db_conn) : $self->db->dbc;
    $self->param('src_dbc', $src_dbc);
}


# Splits a string into a list of strings
# Ask the database for the list of tables that match the wildcard "%"

sub _get_table_list {
    my $self = shift @_;

    my $table_list = $self->param_substitute($self->param('table_list') || '');
    my @newtables;
    my $dbc = $self->param('src_dbc');
    foreach my $initable (ref($table_list) eq 'ARRAY' ? @$table_list : split($table_list)) {
        if ($initable =~ /%/) {
            $initable =~ s/_/\\_/g;
            my $sth = $dbc->db_handle->table_info(undef, undef, $initable, undef);
            push @newtables, map( {$_->[2]} @{$sth->fetchall_arrayref});
        } else {
            push @newtables, $initable;
        }
    }
    return \@newtables;
}


sub run {
    my $self = shift @_;

    my $src_dbc = $self->param('src_dbc');
    my $tables = $self->param('tables');
    my $ignores = $self->param('ignores');

    my $cmd = 'mysqldump'
        . ' ' . $self->mysql_conn_from_dbc($src_dbc)
        . ' ' . join(' ', @$tables)
        . ' ' . join(' ', map( {'--ignore-table='.$src_dbc->dbname.'.'.$_} @$ignores))
        . ' > ' . $self->param('output_file');

    print "$cmd\n" if $self->debug;
    if(my $return_value = system($cmd)) {
        die "system( $cmd ) failed: $return_value";
    }
}


sub mysql_conn_from_dbc {
    my ($self, $dbc) = @_; 

    return '--host='.$dbc->host.' --port='.$dbc->port." --user='".$dbc->username."' --pass='".$dbc->password."' ".$dbc->dbname;
}


1;
