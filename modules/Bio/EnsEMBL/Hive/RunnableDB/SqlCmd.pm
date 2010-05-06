
=pod 

=head1 NAME

Bio::EnsEMBL::Hive::RunnableDB::SqlCmd

=head1 SYNOPSIS

This is a RunnableDB module that implements Bio::EnsEMBL::Hive::Process interface
and is ran by Workers during the execution of eHive pipelines.
It is not generally supposed to be instantiated and used outside of this framework.

Please refer to Bio::EnsEMBL::Hive::Process documentation to understand the basics of the RunnableDB interface.

Please refer to Bio::EnsEMBL::Hive::PipeConfig::* pipeline configuration files to understand how to configure pipelines.

=head1 DESCRIPTION

This RunnableDB module acts as a wrapper for a (My)SQL command
run against either the current hive database (default) or against one specified by connection parameters.
If you behave you may also use parameter substitution.

The SQL command(s) can be given using three different syntaxes:

1) Sql command is stored in the input_id() or parameters() as the value corresponding to the 'sql' key.
    THIS IS THE RECOMMENDED WAY as it allows to pass in other parameters and use the parameter substitution mechanism in its full glory.

2) Sql command is stored in the 'input_id' field of the analysis_job table.
    (only works with sql commands shorter than 255 bytes).
    This is a legacy syntax. Most people tend to use it not realizing there are other possiblities.

3) A numeric key to the analysis_data table (where the actual sql command is stored)
    is kept in the input_id() or parameters() as the value corresponding to the 'did' key. This allows to overcome the 255 byte limit.
    Well, if you REALLY couldn't fit your sql command into 250~ish bytes, are you sure you can manage big pipelines?
    Just joking :)

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::RunnableDB::SqlCmd;

use strict;
use DBI;
use Bio::EnsEMBL::Hive::DBSQL::AnalysisDataAdaptor;

use base ('Bio::EnsEMBL::Hive::ProcessWithParams');

=head2 strict_hash_format

    Description : Implements strict_hash_format() interface method of Bio::EnsEMBL::Hive::ProcessWithParams that is used to set the strictness level of the parameters' parser.
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

    param('did'): Alternative way of passing in a long sql command that is stored in analysis_data table.
                  Try to avoid long sql commands at all costs, as it makes debugging a nightmare.
                  Keep in mind that parameter substitution mechanism can be used to compose longer strings from shorter ones.

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
    or $self->param('did')                      # or referred to the analysis_data table where longer strings can be stored
            ? $self->db->get_AnalysisDataAdaptor->fetch_by_dbID( $self->param('did') )
            : die "Could not find the command defined in input_id(), param('sql') or param('did')";

        # Perform parameter substitution:
        #
    my @substituted_sqls = ();
    foreach my $unsubst ((ref($sql) eq 'ARRAY') ? @$sql : ($sql) ) {
        push @substituted_sqls, $self->param_substitute($unsubst);
    }
        
        #   Store the substituted sql command array
        #
    $self->param('sqls', \@substituted_sqls);  

        # Use connection parameters to another database if supplied, otherwise use the current database as default:
        #
    if(my $db_conn = $self->param('db_conn')) {

        $self->param('dbc', DBI->connect("DBI:mysql:$db_conn->{-dbname}:$db_conn->{-host}:$db_conn->{-port}", $db_conn->{-user}, $db_conn->{-pass}, { RaiseError => 1 }) );
    } else {
        $self->param('dbc', $self->db->dbc );
    }
}

=head2 run

    Description : Implements run() interface method of Bio::EnsEMBL::Hive::Process that is used to perform the main bulk of the job (minus input and output).
                  Here it actually runs the sql command(s).  If a list of commands is given, they are run in succession within the same session
                  (so you can create a temporary tables and use it in another command within the same sql command list).

=cut

sub run {
    my $self = shift;

    my $dbc  = $self->param('dbc');
    my $sqls = $self->param('sqls');

        # What would be a generic way of indicating an error in (My)SQL statement, that percolates through PerlDBI?
    foreach my $sql (@$sqls) {
        $dbc->do( $sql );
    }
}

=head2 write_output

    Description : Implements write_output() interface method of Bio::EnsEMBL::Hive::Process that is used to deal with job's output after the execution.
                  Here we have nothing to do, as the wrapper is very generic.

=cut

sub write_output {
}

1;

