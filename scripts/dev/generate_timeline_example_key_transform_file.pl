# See the NOTICE file distributed with this work for additional information
# regarding copyright ownership.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use strict;
use warnings;

# Transform a Compara resource class into a category name according to the
# memory requirement.

sub get_key_name {
    my $resource_class = shift;

    my $display_name = $resource_class->display_name;
    my $memory_req = $display_name;

    # Convert special names to the standard nomenclature
    $memory_req = '250Mb_job' if $display_name eq 'default';
    $memory_req = '250Mb_job' if $display_name eq 'urgent';
    $memory_req = '2Gb_job' if $display_name eq 'msa';
    $memory_req = '8Gb_job' if $display_name eq 'msa_himem';

    # Remove stuff we don't need
    $memory_req =~ s/_(job|mpi|big_tmp)//g;
    $memory_req =~ s/_\d+(_hour|min|c$)//g;

    # Convert to GBs
    $memory_req =~ s/Gb$//;
    if ($memory_req =~ /^(\d+)Mb$/) {
        $memory_req = $1/1000;
    } elsif ($memory_req =~ /^mem(\d+)$/) {
        $memory_req = $1/1000;
    }

    if ($memory_req < 1) {
        return '<1';
    } elsif ($memory_req <= 4) {
        return '1-4';
    } elsif ($memory_req <= 8) {
        return '5-8';
    } elsif ($memory_req <= 16) {
        return '9-16';
    } elsif ($memory_req <= 32) {
        return '17-32';
    } elsif ($memory_req <= 128) {
        return '33-128';
    } else {
        return 'bigmem';
    }
}

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

Please subscribe to the eHive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss eHive-related questions or to be notified of our updates

=cut

1;
