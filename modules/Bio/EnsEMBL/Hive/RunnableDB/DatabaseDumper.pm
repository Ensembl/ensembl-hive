
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

The following table describes how the various options combine:
(T means table_list, EL exclude_list, EH exclude_ehive)
(l+ is the list of included tables, l- of excluded tables)

T EL EH      l+  l-

+  1  0      0   T  = all except T
+  0  0      TH  0  = T and H
0  0  0      0   0  = all
0  1  0      H   0  = H
+  1  1      0   TH = all except T and H
+  0  1      T   H  = T (minus H)
0  0  1      0   H  = all except H
0  1  1      0   0  = nothing

=head1 SYNOPSIS

standaloneJob.pl RunnableDB/DatabaseDumper.pm -exclude_ehive 1 -exclude_list 1 -table_list "['peptide_align_%']" -src_db_conn mysql://ensro@127.0.0.1:4313/mm14_compara_homology_67 -output_file ~/dump1.sql

=cut

package Bio::EnsEMBL::Hive::RunnableDB::DatabaseDumper;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Utils ('go_figure_dbc');

use base ('Bio::EnsEMBL::Hive::Process');

sub fetch_input {
    my $self = shift @_;

    # The final list of tables
    my @tables = ();
    $self->param('tables', \@tables);
    my @ignores = ();
    $self->param('ignores', \@ignores);

    # Would be good to have this from eHive
    my @ehive_tables = qw(hive_meta worker dataflow_rule analysis_base analysis_ctrl_rule job accu log_message job_file analysis_data resource_description analysis_stats analysis_stats_monitor monitor msg progress resource_class);
    $self->param('nb_ehive_tables', scalar(@ehive_tables));

    # Connection parameters
    my $src_db_conn  = $self->param('src_db_conn');
    my $src_dbc = $src_db_conn ? go_figure_dbc($src_db_conn) : $self->data_dbc;
    $self->param('src_dbc', $src_dbc);

    $self->input_job->transient_error(0);
    die 'Only the "mysql" driver is supported.' if $src_dbc->driver ne 'mysql';

    # Get the table list in either "tables" or "ignores"
    my $table_list = $self->_get_table_list;
    print "table_list: ", scalar(@$table_list), " ", join('/', @$table_list), "\n" if $self->debug;

    if ($self->param('exclude_list')) {
        push @ignores, @$table_list;
    } else {
        push @tables, @$table_list;
    }

    # eHive tables are dumped unless exclude_ehive is defined
    if ($self->param('exclude_ehive')) {
        push @ignores, @ehive_tables;
    } elsif (scalar(@$table_list) and not $self->param('exclude_list')) {
        push @tables, @ehive_tables;
    } elsif (not scalar(@$table_list) and $self->param('exclude_list')) {
        push @tables, @ehive_tables;
    }

    # Output file / output database
    $self->param('output_file') || $self->param('output_db') || die 'One of the parameters "output_file" and "output_db" is mandatory';
    unless ($self->param('output_file')) {
        $self->param('real_output_db', go_figure_dbc( $self->param('output_db') ) );
        die 'Only the "mysql" driver is supported.' if $self->param('real_output_db')->driver ne 'mysql';
    }

    $self->input_job->transient_error(1);
}


# Splits a string into a list of strings
# Ask the database for the list of tables that match the wildcard "%"

sub _get_table_list {
    my $self = shift @_;

    my $table_list = $self->param('table_list') || '';
    my @newtables = ();
    my $dbc = $self->param('src_dbc');
    foreach my $initable (ref($table_list) eq 'ARRAY' ? @$table_list : split(' ', $table_list)) {
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

    print "tables: ", scalar(@$tables), " ", join('/', @$tables), "\n" if $self->debug;
    print "ignores: ", scalar(@$ignores), " ", join('/', @$ignores), "\n" if $self->debug;

    # We have to exclude everything
    return if ($self->param('exclude_ehive') and $self->param('exclude_list') and scalar(@$ignores) == $self->param('nb_ehive_tables'));

    # mysqldump command
    my $cmd = join(' ', 
        'mysqldump',
        $self->mysql_conn_from_dbc($src_dbc),
        '--skip-lock-tables',
        @$tables,
        (map {sprintf('--ignore-table=%s.%s', $src_dbc->dbname, $_)} @$ignores),
        $self->param('output_file') ? sprintf('> %s', $self->param('output_file')) : sprintf(' | mysql %s', $self->mysql_conn_from_dbc($self->param('real_output_db'))),
    );
    print "$cmd\n" if $self->debug;

    # We have to skip the dump
    return if ($self->param('skip_dump'));

    # OK, we can dump
    if(my $return_value = system($cmd)) {
        die "system( $cmd ) failed: $return_value";
    }
}


sub mysql_conn_from_dbc {
    my ($self, $dbc) = @_; 

    return '--host='.$dbc->host.' --port='.$dbc->port." --user='".$dbc->username."' --pass='".$dbc->password."' ".$dbc->dbname;
}


1;
