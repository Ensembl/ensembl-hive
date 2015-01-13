=pod

=head1 NAME

    Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor

=head1 SYNOPSIS

    Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor->get_code_sql_schema_version();

=head1 DESCRIPTION

    This is currently an "objectless" adaptor for finding out the apparent code's SQL schema version

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


package Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor;

use strict;
use warnings;

sub find_all_sql_schema_patches {

    my %all_patches = ();

    if(my $hive_root_dir = $ENV{'EHIVE_ROOT_DIR'} ) {
        foreach my $patch_path ( split(/\n/, `ls -1 $hive_root_dir/sql/patch_20*.*`) ) {
            my ($patch_name, $driver) = ($patch_path=~/^(.+)\.(\w+)$/);

            $driver = 'mysql' if ($driver eq 'sql');    # for backwards compatibility

            $driver = 'script' if ($driver!~/sql/);

            $all_patches{$patch_name}{$driver} = $patch_path;
        }
    } # otherwise will sliently return an empty hash

    return \%all_patches;
}


sub get_sql_schema_patches {
    my ($self, $after_version, $driver) = @_;

    my $all_patches         = $self->find_all_sql_schema_patches();
    my $code_schema_version = $self->get_code_sql_schema_version();

    my @ordered_patches = ();
    foreach my $patch_key ( (sort keys %$all_patches)[$after_version..$code_schema_version-1] ) {
        if(my $sql_patch_path = $all_patches->{$patch_key}{$driver}) {
            push @ordered_patches, $sql_patch_path;
        } elsif(my $script_patch_path = $all_patches->{$patch_key}{'script'}) {
            push @ordered_patches, $script_patch_path;
        } else {
            return;
        }
    }

    return \@ordered_patches;
}


sub get_code_sql_schema_version {
    my ($self) = @_;

    return scalar( keys %{ $self->find_all_sql_schema_patches() } );   # 0 probably means $ENV{'EHIVE_ROOT_DIR'} not set correctly
}

1;

