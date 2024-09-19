=pod 

=head1 NAME

    TestRunnable::TransactDummy

=head1 DESCRIPTION

    A job of 'TestRunnable::TransactDummy' analysis does not do any work,
    but it sleeps some macroscopic amount of time within a relatively long transaction
    that also performs critical semaphore_count updates.

    We use this TestRunnable within OverloadTest_conf pipeline to study the effects
    of transactional deadlocks and develop a better solution against them.

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


package TestRunnable::TransactDummy;

use strict;
use warnings;
use Time::HiRes ('usleep');

use base ('Bio::EnsEMBL::Hive::Process');

sub param_defaults {

    return {
        'take_time' => 0,   # how much time run() method will spend in sleeping state
    };
}


sub run {
    my $self = shift @_;

    my $take_time = eval $self->param('take_time');
    if($take_time) {
        $self->dbc->run_in_transaction( sub {
            print "Sleeping for '$take_time' seconds...\n";
            usleep( $take_time*1000000 );
            print "Done.\n";
            $self->dataflow_output_id(undef, 1);
        } );
    }
}

1;
