=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2018] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


package Bio::EnsEMBL::Hive::Scripts::PeekJob;

use strict;
use warnings;

use Data::Dumper;

sub peek {
    my ($pipeline, $job_id) = @_;

    my $hive_dba = $pipeline->hive_dba;
    die "Hive's DBAdaptor is not a defined Bio::EnsEMBL::Hive::DBSQL::DBAdaptor\n" unless $hive_dba and $hive_dba->isa('Bio::EnsEMBL::Hive::DBSQL::DBAdaptor');

    # fetch job and populate params
    my $job_adaptor = $hive_dba->get_AnalysisJobAdaptor;
    my $job = $job_adaptor->fetch_by_dbID( $job_id );
    $job->load_parameters;

    my $unsub_params = $job->{'_unsubstituted_param_hash'};
    print Data::Dumper->Dump( [ $unsub_params ], [ qw(*unsubstituted_param_hash) ] );
    
    # my @ordered_params = sort { lc($a) cmp lc($b) } keys %$unsub_params;
    # print "{\n";
    # foreach my $param ( @ordered_params ) {
    #     print "\t'$param' => '" . $unsub_params->{$param} . "',\n";
    # }
    # print "}\n";
}

1;
