=pod 

=head1 NAME

Bio::EnsEMBL::Hive::Utils::SQLErrorParser

=head1 DESCRIPTION

A collection of functions that recognize common SQL errors of each parser.

These functions are typically called by DBConnection, CoreDBConnection and StatementHandle.

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


package Bio::EnsEMBL::Hive::Utils::SQLErrorParser;

use strict;
use warnings;


=head2 is_connection_lost

    Description: Return 1 if the error message indicates the connection has been closed without us asking

=cut

sub is_connection_lost {
    my ($driver, $error) = @_;

    if ($driver eq 'mysql') {
        return 1 if $error =~ /MySQL server has gone away/;                     # test by setting "SET SESSION wait_timeout=5;" and waiting for 10sec
        return 1 if $error =~ /Lost connection to MySQL server during query/;   # a variant of the same error

    } elsif ($driver eq 'pgsql') {
        return 1 if $error =~ /server closed the connection unexpectedly/;

    }
    return 0;
}


=head2 is_server_too_busy

    Description: Return 1 if the error message indicates we can't connect to the server because of a lack
                 of resources (incl. available connections)

=cut

sub is_server_too_busy {
    my ($driver, $error) = @_;

    if ($driver eq 'mysql') {
        return 1 if $error =~ /Could not connect to database.+?failed: Too many connections/s;                             # problem on server side (configured with not enough connections)
        return 1 if $error =~ /Could not connect to database.+?failed: Can't connect to \w+? server on '.+?' \(99\)/s;     # problem on client side (cooling down period after a disconnect)
        return 1 if $error =~ /Could not connect to database.+?failed: Can't connect to \w+? server on '.+?' \(110\)/s;    # problem on server side ("Connection timed out"L the server is temporarily dropping connections until it reaches a reasonable load)
        return 1 if $error =~ /Could not connect to database.+?failed: Lost connection to MySQL server at 'reading authorization packet', system error: 0/s;     # problem on server side (server too busy ?)

    }
    return 0;
}


=head2 is_deadlock

    Description: Return 1 if the error message indicates the current transaction had to be aborted because
                 of concurrency issues

=cut

sub is_deadlock {
    my ($driver, $error) = @_;

    if ($driver eq 'mysql') {
        return 1 if $error =~ /Deadlock found when trying to get lock; try restarting transaction/;
        return 1 if $error =~ /Lock wait timeout exceeded; try restarting transaction/;
    }
    return 0;
}


1;
