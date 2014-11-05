=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::DBAdaptor

=head1 SYNOPSIS

    my $db = Bio::EnsEMBL::Hive::DBSQL::DBAdaptor->new( -url => 'mysql://my_username:my_password@my_hostname:3306/my_hive_database' );

=head1 DESCRIPTION

    This object represents the handle for a Hive system enabled database

=head1 LICENSE

    Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::DBSQL::DBAdaptor;

use strict;

use Bio::EnsEMBL::Hive::Utils ('throw');
use Bio::EnsEMBL::Hive::DBSQL::DBConnection;
use Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor;


sub new {
    my $class = shift @_;
    my %flags = @_;

    my ($dbc, $url, $reg_conf, $reg_type, $reg_alias, $species, $no_sql_schema_version_check)
        = @flags{qw(-dbconn -url -reg_conf -reg_type -reg_alias -species -no_sql_schema_version_check)};

    $url .= ';nosqlvc=1' if($url && $no_sql_schema_version_check);

    if($reg_conf or $reg_alias) {   # need to initialize Registry even if $reg_conf is not really given
        require Bio::EnsEMBL::Registry;
        Bio::EnsEMBL::Registry->load_all($reg_conf);    # if undefined, default reg_conf will be used
    }

    my $self;

    if($url) {

        $dbc = Bio::EnsEMBL::Hive::DBSQL::DBConnection->new(-url => $url)
            or die "Unable to create a DBC using url='$url'";

    } elsif($reg_alias) {

        $reg_type ||= 'hive';

        $self = Bio::EnsEMBL::Registry->get_DBAdaptor($reg_alias, $reg_type)
            or die "Unable to connect to DBA using reg_conf='$reg_conf', reg_type='$reg_type', reg_alias='$reg_alias'\n";

        if($reg_type ne 'hive') {   # ensure we are getting a Hive adaptor even from a non-Hive Registry entry:
            $dbc = $self->dbc;
            $self = undef;
        }
    }

    if($dbc && !$self) {
        $self = bless {}, $class;
        $self->dbc( $dbc );
    }

    unless($no_sql_schema_version_check) {

        my $dbc = $self->dbc();
        my $safe_url = $dbc->url('EHIVE_PASS');

        my $code_sql_schema_version = Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor->get_code_sql_schema_version()
            || die "DB($safe_url) Could not establish code_sql_schema_version, please check that 'EHIVE_ROOT_DIR' environment variable is set correctly";

        my $db_sql_schema_version   = eval { $self->get_MetaAdaptor->fetch_value_by_key( 'hive_sql_schema_version' ); };
        if($@) {
            if($@ =~ /hive_meta.*doesn't exist/) {

                die "\nDB($safe_url) The 'hive_meta' table does not seem to exist in the database yet.\nPlease patch the database up to sql_schema_version '$code_sql_schema_version' and try again.\n";

            } else {

                die "DB($safe_url) $@";
            }

        } elsif(!$db_sql_schema_version) {

            die "\nDB($safe_url) The 'hive_meta' table does not contain 'hive_sql_schema_version' entry.\nPlease investigate.\n";

        } elsif($db_sql_schema_version < $code_sql_schema_version) {

            my $new_patches = Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor->get_sql_schema_patches( $db_sql_schema_version, $dbc->driver )
                || die "DB($safe_url) sql_schema_version mismatch: the database's version is '$db_sql_schema_version' but the code is already '$code_sql_schema_version'.\n"
                      ."Unfortunately we cannot patch the database; you may have to create a new database or agree to run older code\n";

            my $patcher_command = "$ENV{'EHIVE_ROOT_DIR'}/scripts/db_cmd.pl -url $safe_url";

            die "DB($safe_url) sql_schema_version mismatch: the database's version is '$db_sql_schema_version' but the code is already '$code_sql_schema_version'.\n"
               ."Please upgrade the database by applying the following patches:\n\n".join("\n", map { "\t$patcher_command < $_" } @$new_patches)."\n\nand try again.\n";

        } elsif($code_sql_schema_version < $db_sql_schema_version) {

            die "DB($safe_url) sql_schema_version mismatch: the database's version is '$db_sql_schema_version', but your code is still '$code_sql_schema_version'.\n"
               ."Please update the code and try again.\n";
        }
    }

    if($species) {      # [compatibility with core code] store the DBAdaptor in Registry:
        require Bio::EnsEMBL::Registry;
        Bio::EnsEMBL::Registry->add_DBAdaptor( $species, 'hive', $self );
    }

    return $self;
}


sub dbc {
    my $self = shift;

    $self->{'_dbc'} = bless shift, 'Bio::EnsEMBL::Hive::DBSQL::DBConnection' if(@_);

    return $self->{'_dbc'};
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
        'Accumulator'           => 'Bio::EnsEMBL::Hive::DBSQL::AccumulatorAdaptor',
        'Analysis'              => 'Bio::EnsEMBL::Hive::DBSQL::AnalysisAdaptor',
        'AnalysisCtrlRule'      => 'Bio::EnsEMBL::Hive::DBSQL::AnalysisCtrlRuleAdaptor',
        'AnalysisData'          => 'Bio::EnsEMBL::Hive::DBSQL::AnalysisDataAdaptor',
        'AnalysisJob'           => 'Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor',
        'AnalysisStats'         => 'Bio::EnsEMBL::Hive::DBSQL::AnalysisStatsAdaptor',
        'DataflowRule'          => 'Bio::EnsEMBL::Hive::DBSQL::DataflowRuleAdaptor',
        'LogMessage'            => 'Bio::EnsEMBL::Hive::DBSQL::LogMessageAdaptor',
        'Meta'                  => 'Bio::EnsEMBL::Hive::DBSQL::MetaAdaptor',
        'MetaContainer'         => 'Bio::EnsEMBL::Hive::DBSQL::MetaContainer',
        'NakedTable'            => 'Bio::EnsEMBL::Hive::DBSQL::NakedTableAdaptor',
        'ResourceClass'         => 'Bio::EnsEMBL::Hive::DBSQL::ResourceClassAdaptor',
        'ResourceDescription'   => 'Bio::EnsEMBL::Hive::DBSQL::ResourceDescriptionAdaptor',
        'Queen'                 => 'Bio::EnsEMBL::Hive::Queen',
    );
    return \%pairs;
}


sub get_adaptor {
    my $self = shift;
    my $type = shift;

    my $signature = join(':', $type, @_);

    unless( $self->{'_cached_adaptor'}{$signature} ) {
        my $adaptor_package_name = $self->get_available_adaptors()->{$type}
            or throw("Could not find a module corresponding to '$type'");

        eval "require $adaptor_package_name"
        or throw("Could not load or compile module '$adaptor_package_name'");

        $self->{'_cached_adaptor'}{$signature} = $adaptor_package_name->new( $self, @_ );
    }

    return $self->{'_cached_adaptor'}{$signature};
}


sub DESTROY { }   # to simplify AUTOLOAD

sub AUTOLOAD {
    our $AUTOLOAD;

    my $type;
    if ( $AUTOLOAD =~ /^.*::get_(\w+)Adaptor$/ ) {
        $type = $1;
    } elsif ( $AUTOLOAD =~ /^.*::get_(\w+)$/ ) {
        $type = $1;
    } else {
        die "DBAdaptor::AUTOLOAD: Could not interpret the method: $AUTOLOAD";
    }

    my $self = shift;

    return $self->get_adaptor($type, @_);
}

1;

