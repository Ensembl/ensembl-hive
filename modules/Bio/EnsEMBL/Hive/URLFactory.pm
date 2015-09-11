=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::URLFactory

=head1 SYNOPSIS

    $url_string1 = 'mysql://ensadmin:<pass>@ecs2:3362/compara_hive_23c';                 # type=hive by default
    $url_string2 = 'mysql://ensadmin:<pass>@ecs2:3362/ensembl_compara_22_1;type=compara'
    $url_string3 = 'mysql://ensadmin:<pass>@ecs2:3362/ensembl_core_homo_sapiens_22_34;type=core'

    $hive_dba    = Bio::EnsEMBL::Hive::URLFactory->fetch($url_string1);
    $compara_dba = Bio::EnsEMBL::Hive::URLFactory->fetch($url_string2);
    $core_dba    = Bio::EnsEMBL::Hive::URLFactory->fetch($url_string3);

=head1 DESCRIPTION  

    Module to parse URL strings and return EnsEMBL objects.
    At the moment, DBAdaptors as well as Analyses, Jobs and NakedTables are supported.

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


    # global instance to cache connections and limit the number of open DB connections:
my $_URLFactory_global_instance;

package Bio::EnsEMBL::Hive::URLFactory;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Utils::URL;
use Bio::EnsEMBL::Hive::Accumulator;
use Bio::EnsEMBL::Hive::NakedTable;

#use Data::Dumper;

sub new {
    my $class = shift @_;

    unless($_URLFactory_global_instance) {
        $_URLFactory_global_instance = bless {}, $class;
    }
    return $_URLFactory_global_instance;
}

sub DESTROY {
    my ($obj) = @_;

    foreach my $key (keys(%$_URLFactory_global_instance)) {
        $_URLFactory_global_instance->{$key} = undef;
    }
}

=head2 fetch

  Arg[1]     : string $url
  Example    :  $url = 'mysql://user:pass@host:3306/dbname/table_name?tparam_name=tparam_value;type=compara;disconnect_when_inactive=1'
                my $object = Bio::EnsEMBL::Hive::URLFactory->fetch($url);
  Description: parses the URL, connects to appropriate DBAdaptor,
               determines appropriate object_adaptor, fetches the object
  Returntype : blessed instance of the object refered to or a DBAdaptor if simple URL
  Exceptions : none
  Caller     : ?

=cut

sub fetch {
    my $class       = shift @_;
    my $url         = shift @_ or return;
    my $default_dba = shift @_;

    Bio::EnsEMBL::Hive::URLFactory->new();  # make sure global instance is created

    if(my $parsed_url = Bio::EnsEMBL::Hive::Utils::URL::parse( $url )) {

        my $table_name      = $parsed_url->{'table_name'};
        my $tparam_name     = $parsed_url->{'tparam_name'};
        my $tparam_value    = $parsed_url->{'tparam_value'};

        unless($table_name=~/^(analysis|job|accu)$/) {  # do not check schema version version when performing table dataflow:
            $parsed_url->{'conn_params'}{'no_sql_schema_version_check'} = 1;
        }

        my $dba = ($parsed_url->{'dbconn_part'} =~ m{^\w*:///$} )
            ? $default_dba
            : $class->create_cached_dba( @$parsed_url{qw(dbconn_part driver user pass host port dbname conn_params)} );


        if(not $table_name) {
        
            return $dba;

        } elsif($table_name eq 'analysis') {

            return $dba->get_AnalysisAdaptor->fetch_by_url_query($tparam_name, $tparam_value);

        } elsif($table_name eq 'job') {

            return $dba->get_AnalysisJobAdaptor->fetch_by_url_query($tparam_name, $tparam_value);

        } elsif($table_name eq 'accu') {

            return Bio::EnsEMBL::Hive::Accumulator->new(
                    $dba ? (adaptor => $dba->get_AccumulatorAdaptor) : (),
                    struct_name        => $tparam_name,
                    signature_template => $tparam_value,
            );

        } else {

            return Bio::EnsEMBL::Hive::NakedTable->new(
                $dba ? (adaptor => $dba->get_NakedTableAdaptor( 'table_name' => $table_name ) ) : (),
                table_name => $table_name,
                $tparam_value ? (insertion_method => $tparam_value) : (),
            );
        }
    } else {
        warn "Could not parse URL '$url'";
    }
    return;
}


sub create_cached_dba {
    my ($class, $dbconn_part, $driver, $user, $pass, $host, $port, $dbname, $conn_params) = @_;

    my $type                        = $conn_params->{'type'};
    my $disconnect_when_inactive    = $conn_params->{'disconnect_when_inactive'};
    my $no_sql_schema_version_check = $conn_params->{'no_sql_schema_version_check'};

    my $connectionKey = $driver.'://'.($user//'').':'.($pass//'').'@'.($host//'').':'.($port//'').'/'.($dbname//'').';'.$type;
    my $dba = $_URLFactory_global_instance->{$connectionKey};

    unless($dba) {

        my $module = {
            'hive'     => 'Bio::EnsEMBL::Hive::DBSQL::DBAdaptor',
            'compara'  => 'Bio::EnsEMBL::Compara::DBSQL::DBAdaptor',
            'core'     => 'Bio::EnsEMBL::DBSQL::DBAdaptor',
            'pipeline' => 'Bio::EnsEMBL::Pipeline::DBSQL::DBAdaptor',
        }->{$type};

        eval "require $module";

        $_URLFactory_global_instance->{$connectionKey} = $dba =
        $type eq 'hive'
          ? $module->new(
            -url                        => $dbconn_part,
            -disconnect_when_inactive   => $disconnect_when_inactive,
            -no_sql_schema_version_check=> $no_sql_schema_version_check,
        ) : $module->new(
            -driver => $driver,
            -host   => $host,
            -port   => $port,
            -user   => $user,
            -pass   => $pass,
            -dbname => $dbname,
            -species => $dbname,
            -disconnect_when_inactive => $disconnect_when_inactive,
        );
    }
    return $dba;
}

1;
