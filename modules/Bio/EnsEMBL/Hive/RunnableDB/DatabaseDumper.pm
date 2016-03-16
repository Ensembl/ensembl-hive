=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::RunnableDB::DatabaseDumper

=head1 SYNOPSIS

    standaloneJob.pl RunnableDB/DatabaseDumper.pm -exclude_ehive 1 -exclude_list 1 \
        -table_list "['peptide_align_%']" -src_db_conn mysql://ensro@127.0.0.1:4313/mm14_compara_homology_67 -output_file ~/dump1.sql

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

 - output_file [string] : the file to write the dump to. If the filename
    ends with ".gz", the file is compressed with "gzip" (default parameters)

 - output_db [string] : URL of a database to write the dump to. In this
    mode, the Runnable acts like MySQLTransfer

 - skip_dump [boolean=0] : set this to 1 to skip the dump

If "table_list" is undefined or maps to an empty list, the list
of tables to be dumped is decided accordingly to "exclude_list" (EL)
and "exclude_ehive" (EH). "exclude_list" controls the whole list of
non-eHive tables.

EL EH    List of tables to dump

0  0  => all the tables
0  1  => all the tables, except the eHive ones
1  0  => all the tables, except the non-eHive ones = only the eHive tables
1  1  => both eHive and non-eHive tables are excluded = nothing is dumped

If "table_list" is defined to non-empty list T, the table of decision is:

EL EH    List of tables to dump

0  0  => all the tables in T + the eHive tables
0  1  => all the tables in T
1  0  => all the tables, except the ones in T
1  1  => all the tables, except the ones in T and the eHive ones

=head1 LICENSE

    Copyright [1999-2016] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::RunnableDB::DatabaseDumper;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Utils ('go_figure_dbc');

use base ('Bio::EnsEMBL::Hive::RunnableDB::SystemCmd');

sub param_defaults {
    return {
        # Which tables to dump. How the options are combined is explained above
        'table_list'    => undef,   # array-ref
        'exclude_ehive' => 0,       # boolean
        'exclude_list'  => 0,       # boolean

        # Input / output
        'src_db_conn'   => undef,   # URL, hash-ref, or Registry name
        'output_file'   => undef,   # String
        'output_db'     => undef,   # URL, hash-ref, or Registry name

        # Other options
        'skip_dump'     => 0,       # boolean

        # SystemCmd's options
        'use_bash_pipefail' => 1,   # We need to make sure the whole command succeeded
    }
}

sub fetch_input {
    my $self = shift @_;

    # The final list of tables
    my @tables = ();
    my @ignores = ();

    # Connection parameters
    my $src_db_conn  = $self->param('src_db_conn');
    my $src_dbc = $src_db_conn ? go_figure_dbc($src_db_conn) : $self->data_dbc;
    $self->param('src_dbc', $src_dbc);

    $self->input_job->transient_error(0);
    die 'Only the "mysql" driver is supported.' if $src_dbc->driver ne 'mysql';

    my @ehive_tables = ();
    {
        ## Only query the list of eHive tables if there is a "hive_meta" table
        my $meta_sth = $src_dbc->db_handle->table_info(undef, undef, 'hive_meta');
        if ($meta_sth->fetchrow_arrayref) {
            my $src_dba = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( -dbconn => $src_dbc, -disconnect_when_inactive => 1, -no_sql_schema_version_check => 1 );
            @ehive_tables = (@{$src_dba->hive_pipeline->list_all_hive_tables}, @{$src_dba->hive_pipeline->list_all_hive_views});
        }
        $meta_sth->finish();
    }
    $self->param('nb_ehive_tables', scalar(@ehive_tables));

    # Get the table list in either "tables" or "ignores"
    my $table_list = $self->_get_table_list($src_dbc, $self->param('table_list') || '');
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

    print "tables: ", scalar(@tables), " ", join('/', @tables), "\n" if $self->debug;
    print "ignores: ", scalar(@ignores), " ", join('/', @ignores), "\n" if $self->debug;

    # We have to exclude everything
    return if ($self->param('exclude_ehive') and $self->param('exclude_list') and scalar(@ignores) == $self->param('nb_ehive_tables'));

    # mysqldump command
    my $output = "";
    if ($self->param('output_file')) {
        if (lc $self->param('output_file') =~ /\.gz$/) {
            $output = sprintf(' | gzip > %s', $self->param('output_file'));
        } else {
            $output = sprintf('> %s', $self->param('output_file'));
        }
    } else {
        $output = join(' ', '|', @{ $self->param('real_output_db')->to_cmd(undef, undef, undef, undef, 1) } );
    };

    # Must be joined because of the redirection / the pipe
    my $cmd = join(' ', 
        @{ $src_dbc->to_cmd('mysqldump', undef, undef, undef, 1) },
        '--skip-lock-tables',
        @tables,
        (map {sprintf('--ignore-table=%s.%s', $src_dbc->dbname, $_)} @ignores),
        $output
    );

    # Check whether the current database has been restored from a snapshot.
    # If it is the case, we shouldn't re-dump and overwrite the file.
    # We also check here the value of the "skip_dump" parameter
    my $completion_signature = sprintf('dump_%d_restored', $self->input_job->dbID < 0 ? 0 : $self->input_job->dbID);

    if ($self->param('skip_dump') or $self->param($completion_signature)) {
        # A command that always succeeds
        $self->param('cmd', 'true');
        if ($self->param('skip_dump')) {
            $self->warning('Skipping the dump because "skip_dump" is defined');
        } else {
            $self->warning("Skipping the dump because this database has been restored from the target dump. We don't want to overwrite it");
        }
    } else {
        # OK, we can dump. We add the signature to the dump, so that the
        # job won't rerun on a restored database
        # We're very lucky that gzipped streams can be concatenated and the
        # output is still valid !
        my $extra_sql = qq{echo "INSERT INTO pipeline_wide_parameters VALUES ('$completion_signature', 1);\n" $output};
        $extra_sql =~ s/>/>>/;
        $self->param('cmd', "$cmd; $extra_sql");
    }
}


# Splits a string into a list of strings
# Ask the database for the list of tables that match the wildcard "%"

sub _get_table_list {
    my ($self, $dbc, $table_list) = @_;

    my @newtables = ();
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


1;
