#
# BioPerl module for DBSQL::Obj
#
# Cared for by Ewan Birney <birney@sanger.ac.uk>
#
# Copyright Ewan Birney
#
# You may distribute this module under the same terms as perl itself

=pod

=head1 NAME

Bio::EnsEMBL::Hive::DBSQL::DBAdaptor

=head1 SYNOPSIS

    $db = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new(
        -user   => 'root',
        -dbname => 'pog',
        -host   => 'caldy',
        -driver => 'mysql',
        );

=head1 DESCRIPTION

  This object represents the handle for a Hive system enabled database

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;

use strict;

use Bio::EnsEMBL::Registry;
use Bio::EnsEMBL::Utils::Argument ('rearrange');

use Bio::EnsEMBL::Hive::URLFactory;
use Bio::EnsEMBL::Hive::DBSQL::DBConnection;
use Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor;

use base ('Bio::EnsEMBL::DBSQL::DBAdaptor');


sub new {
    my ($class, @args) = @_;

    my ($url, $reg_conf, $reg_type, $reg_alias, $no_sql_schema_version_check)
        = rearrange(['URL', 'REG_CONF', 'REG_TYPE', 'REG_ALIAS', 'NO_SQL_SCHEMA_VERSION_CHECK'], @args);

    $url .= ';nosqlvc=1' if($url && $no_sql_schema_version_check);

    my $self;

    if($url) {
        $self = Bio::EnsEMBL::Hive::URLFactory->fetch($url)
            or die "Unable to connect to DBA using url='$url'\n";
    } elsif($reg_alias) {
        Bio::EnsEMBL::Registry->load_all($reg_conf) if($reg_conf);

        $reg_type ||= 'hive';

        $self = Bio::EnsEMBL::Registry->get_DBAdaptor($reg_alias, $reg_type)
            or die "Unable to connect to DBA using reg_conf='$reg_conf', reg_type='$reg_type', reg_alias='$reg_alias'\n";

        if($reg_type ne 'hive') {   # ensure we are getting a Hive adaptor even from a non-Hive Registry entry:
            $self = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( -dbconn => $self->dbc(), -no_sql_schema_version_check => $no_sql_schema_version_check );
        }
    } else {
        $self = $class->SUPER::new(@args)
            or die "Unable to connect to DBA using parameters (".join(', ', @args).")\n"
    }

    unless($no_sql_schema_version_check) {

        my $dbc = $self->dbc();
        $url ||= $dbc->url();

        my $code_sql_schema_version = Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor->get_code_sql_schema_version()
            || die "DB($url) Could not establish code_sql_schema_version, please check that 'EHIVE_ROOT_DIR' environment variable is set correctly";

        my $db_sql_schema_version   = eval { $self->get_MetaAdaptor->fetch_value_by_key( 'hive_sql_schema_version' ); };
        if($@) {
            if($@ =~ /hive_meta.*doesn't exist/) {

                die "\nDB($url) The 'hive_meta' table does not seem to exist in the database yet.\nPlease patch the database up to sql_schema_version '$code_sql_schema_version' and try again.\n";

            } else {

                die "DB($url) $@";
            }

        } elsif(!$db_sql_schema_version) {

            die "\nDB($url) The 'hive_meta' table does not contain 'hive_sql_schema_version' entry.\nPlease investigate.\n";

        } elsif($db_sql_schema_version < $code_sql_schema_version) {


            my $new_patches = Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor->get_sql_schema_patches( $db_sql_schema_version, $dbc->driver )
                || die "DB($url) sql_schema_version mismatch: the database's version is '$db_sql_schema_version' but the code is already '$code_sql_schema_version'.\n"
                      ."Unfortunately we cannot patch the database; you may have to create a new database or agree to run older code\n";

            my $patcher_command = "$ENV{'EHIVE_ROOT_DIR'}/scripts/db_cmd.pl -url $url";

            die "DB($url) sql_schema_version mismatch: the database's version is '$db_sql_schema_version' but the code is already '$code_sql_schema_version'.\n"
               ."Please upgrade the database by applying the following patches:\n\n".join("\n", map { "\t$patcher_command < $_" } @$new_patches)."\n\nand try again.\n";

        } elsif($code_sql_schema_version < $db_sql_schema_version) {

            die "DB($url) sql_schema_version mismatch: the database's version is '$db_sql_schema_version', but your code is still '$code_sql_schema_version'.\n"
               ."Please update the code and try again.\n";
        }
    }

    return $self;
}


sub dbc {
    my $self = shift @_;

    my $dbc = $self->SUPER::dbc( @_ );
    bless $dbc, 'Bio::EnsEMBL::Hive::DBSQL::DBConnection' if( $dbc );

    return $dbc;
}


sub hive_use_triggers {  # getter only, not setter
    my $self = shift @_;

    unless( defined($self->{'_hive_use_triggers'}) ) {
        my $hive_use_triggers = $self->get_MetaAdaptor->fetch_value_by_key( 'hive_use_triggers' );
        $self->{'_hive_use_triggers'} = $hive_use_triggers || 0;
    } 
    return $self->{'_hive_use_triggers'};
}


sub hive_use_param_stack {  # getter only, not setter
    my $self = shift @_;

    unless( defined($self->{'_hive_use_param_stack'}) ) {
        my $hive_use_param_stack = $self->get_MetaAdaptor->fetch_value_by_key( 'hive_use_param_stack' );
        $self->{'_hive_use_param_stack'} = $hive_use_param_stack || 0;
    } 
    return $self->{'_hive_use_param_stack'};
}


sub get_available_adaptors {
 
    my %pairs =  (
            # Core adaptors extended with Hive stuff:
        'MetaContainer'         => 'Bio::EnsEMBL::Hive::DBSQL::MetaContainer',

            # "new" Hive adaptors (sharing the same fetching/storing code inherited from the BaseAdaptor class) :
        'AnalysisCtrlRule'      => 'Bio::EnsEMBL::Hive::DBSQL::AnalysisCtrlRuleAdaptor',
        'DataflowRule'          => 'Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor',
        'ResourceDescription'   => 'Bio::EnsEMBL::Hive::DBSQL::ResourceDescriptionAdaptor',
        'ResourceClass'         => 'Bio::EnsEMBL::Hive::DBSQL::ResourceClassAdaptor',
        'LogMessage'            => 'Bio::EnsEMBL::Hive::DBSQL::LogMessageAdaptor',
        'NakedTable'            => 'Bio::EnsEMBL::Hive::DBSQL::NakedTableAdaptor',
        'Analysis'              => 'Bio::EnsEMBL::Hive::DBSQL::AnalysisAdaptor',
        'Queen'                 => 'Bio::EnsEMBL::Hive::Queen',
        'AnalysisData'          => 'Bio::EnsEMBL::Hive::DBSQL::AnalysisDataAdaptor',
        'Accumulator'           => 'Bio::EnsEMBL::Hive::DBSQL::AccumulatorAdaptor',
        'Meta'                  => 'Bio::EnsEMBL::Hive::DBSQL::MetaAdaptor',

            # "old" Hive adaptors (having their own fetching/storing code) :
        'AnalysisJob'           => 'Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor',
        'AnalysisStats'         => 'Bio::EnsEMBL::Hive::DBSQL::AnalysisStatsAdaptor',
    );
    return \%pairs;
}

1;
