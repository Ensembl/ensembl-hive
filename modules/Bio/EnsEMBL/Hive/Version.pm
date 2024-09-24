=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Version

=head1 SYNOPSIS

    use Bio::EnsEMBL::Hive::Version 2.7;

=head1 DESCRIPTION

    Version number of the Hive code.

=head1 LICENSE

    See the NOTICE file distributed with this work for additional information
    regarding copyright ownership.

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

  Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::Version;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Meadow;
use Bio::EnsEMBL::Hive::Valley;
use Bio::EnsEMBL::Hive::GuestProcess;
use Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor;

use Exporter 'import';
our @EXPORT_OK = qw(get_code_version report_versions);


our $VERSION = '2.7.0';

sub get_code_version {

    return $VERSION;
}


sub report_versions {
    print "CodeVersion\t".get_code_version()."\n";
    print "CompatibleHiveDatabaseSchemaVersion\t".Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor->get_code_sql_schema_version()."\n";

    print "MeadowInterfaceVersion\t".Bio::EnsEMBL::Hive::Meadow->get_meadow_major_version()."\n";
    my $meadow_class_path = Bio::EnsEMBL::Hive::Valley->meadow_class_path;
    foreach my $meadow_class (sort @{ Bio::EnsEMBL::Hive::Valley->loaded_meadow_drivers }) {
        $meadow_class=~/^${meadow_class_path}::(.+)$/;
        my $meadow_driver   = $1;
        my $meadow_version  = $meadow_class->get_meadow_version;
        my $compatible      = $meadow_class->check_version_compatibility;
        my $status          = $compatible
                                ? ( $meadow_class->name
                                    ? 'available'
                                    : 'unavailable'
                                   )
                                : 'incompatible';
        print '',join("\t", 'Meadow::'.$meadow_driver, $meadow_version, $status)."\n";
    }

    print "GuestLanguageInterfaceVersion\t".Bio::EnsEMBL::Hive::GuestProcess->get_protocol_version()."\n";
    my $registered_wrappers = Bio::EnsEMBL::Hive::GuestProcess->_get_all_registered_wrappers;
    foreach my $language (sort keys %$registered_wrappers) {
        my $status = 'unavailable';
        my $language_version;
        eval {
            $language_version = Bio::EnsEMBL::Hive::GuestProcess::get_wrapper_version($language);
            $status = Bio::EnsEMBL::Hive::GuestProcess->check_version_compatibility($language_version) ? 'available' : 'incompatible';
        };
        if ($@) {
            $status .= " - $@";
            chomp $status;
        }
        print join("\t", "GuestLanguage[$language]", $language_version || 'N/A', $status)."\n";
    }
}


1;
