=pod 

=head1 NAME

Bio::EnsEMBL::Hive::RunnableDB::DbCmd

=head1 SYNOPSIS

    standaloneJob.pl Bio::EnsEMBL::Hive::RunnableDB::DbCmd -db_conn mysql://ensro@ens-livemirror/ncbi_taxonomy -input_query "SELECT name FROM ncbi_taxa_name WHERE name_class = 'scientific name' AND taxon_id = 9606" --append '["-N"]' -output_file out.dat

=head1 DESCRIPTION

    This RunnableDB module acts as a wrapper around a database connection. It interfaces with the database the same way as you would
    on the command line (i.e. with redirections and / or pipes to other commands) but with hive parameters instead.
    The database connection is created from the "data_dbc" parameter, if provided, or the current hive database.

=head1 CONFIGURATION EXAMPLE

    #
    # The following examples show how to configure SystemCmd in a PipeConfig module.
    #

    # The most common use-case is to apply a SQL script onto the current database

        {   -logic_name     => 'write_member_counts',
            -module         => 'Bio::EnsEMBL::Hive::RunnableDB::DbCmd',
            -parameters     => {
                'input_file'    => $self->o('ensembl_cvs_root_dir').'/ensembl-compara/scripts/production/populate_member_production_counts_table.sql',
            },
            -flow_into => [ 'notify_pipeline_completed' ],
        },


    # You can also use the advanced parameters to run a query on the
    # database with the db_cmd.pl and pipe its output onto another command
    # e.g. mysql -h... -u... curr_db_name -N -q -e 'select * from mcl_sparse_matrix' | #mcl_bin_dir#/mcxload -abc ...

        {   -logic_name => 'mcxload_matrix',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::DbCmd',
            -parameters => {
                'append'        => [qw(-N -q)],
                'input_query'   => 'select * from mcl_sparse_matrix',
                'command_out'   => [qw(#mcl_bin_dir#/mcxload -abc - -ri max -o #work_dir#/#file_basename#.tcx -write-tab #work_dir#/#file_basename#.itab)],
            },
            -flow_into => [ 'mcl' ],
        },


    # Finally, you can run another executable (like mysqlimport) with its
    # own parameters onto another database (specified by 'db_conn')

        {   -logic_name     => 'populate_method_links_from_file',
            -module         => 'Bio::EnsEMBL::Hive::RunnableDB::DbCmd',
            -parameters     => {
                'db_conn'               => '#rel_db#',
                'method_link_dump_file' => $self->o('method_link_dump_file'),
                'executable'            => 'mysqlimport',
                'append'                => [ '#method_link_dump_file#' ],
            },
            -flow_into      => [ 'load_all_genomedbs' ],
        },

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list: http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::RunnableDB::DbCmd;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Utils qw(join_command_args);

# This runnable is simply a SystemCmd specialized for database commands

use base ('Bio::EnsEMBL::Hive::RunnableDB::SystemCmd');


sub param_defaults {
    my $self = shift;
    return {
        %{$self->SUPER::param_defaults(@_)},
        'executable'    => undef,
        'prepend'       => [],
        'append'        => [],
        'input_file'    => undef,
        'input_query'   => undef,
        'output_file'   => undef,
        'command_in'    => undef,
        'command_out'   => undef,
    }
}


=head2 fetch_input

    Description : Implements fetch_input() interface method of Bio::EnsEMBL::Hive::Process that is used to read in parameters and load data.
                  Here it deals with finding the command line, doing parameter substitution and storing the result in a predefined place.

    param('cmd'): The recommended way of passing in the command line. It can be either a string, or an array-ref of strings. The later is safer if some of the
                  arguments contain white-spaces.

    param('*'):   Any other parameters can be freely used for parameter substitution.

=cut

sub fetch_input {
    my $self = shift;

    # Validate the arguments
    # There can be only 1 input
    if (not $self->param('executable') and not ($self->param('input_file') or $self->param('input_query') or $self->param('command_in'))) {
        die "No input defined (missing 'input_file', 'input_query' and 'command_in')\n";
    } elsif (($self->param('input_file') and ($self->param('input_query') or $self->param('command_in'))) or ($self->param('input_query') and $self->param('command_in'))) {
        die "Only 1 input ('input_file', 'input_query' and 'command_in') can be defined\n";
    }
    # And 1 output
    if ($self->param('output_file') and $self->param('command_out')) {
        die "'output_file' and 'command_out' cannot be set together\n";
    }

    # If there is any of those, system() will need a shell to deal with
    # the pipes / redirections, and we need to hide the passwords
    my $need_a_shell = ($self->param('input_file') or $self->param('command_in') or $self->param('output_file') or $self->param('command_out')) ? 1 : 0;

    my @cmd = @{ $self->data_dbc->to_cmd(
        $self->param('executable'),
        [grep {defined $_} @{$self->param('prepend')}],
        [grep {defined $_} @{$self->param('append')}],
        $self->param('input_query'),
        $need_a_shell,
    ) };

    # Add the input data
    if ($self->param('input_file')) {
        push @cmd, '<', $self->param('input_file');
    } elsif ($self->param('input_query')) {
        # the query as already been fed into @cmd by to_cmd()
    } elsif ($self->param('command_in')) {
        unshift @cmd, (ref($self->param('command_in')) ? @{$self->param('command_in')} : $self->param('command_in')), '|';
    }

    # Add the output data
    if ($self->param('output_file')) {
        push @cmd, '>', $self->param('output_file');
    } elsif ($self->param('command_out')) {
        push @cmd, '|', (ref($self->param('command_out')) ? @{$self->param('command_out')} : $self->param('command_out'));
    }

    if ($need_a_shell) {
        my ($join_needed, $flat_cmd) = join_command_args(\@cmd);
        $flat_cmd =~ s/ '(-p\$EHIVE_TMP_PASSWORD_\d+)' / $1 /g;
        $self->param('cmd', $flat_cmd);
    } else {
        $self->param('cmd', \@cmd);
    }

    if ($self->debug) {
        use Data::Dumper;
        warn "db_cmd command: ", Dumper($self->param('cmd'));
    }
}


1;
