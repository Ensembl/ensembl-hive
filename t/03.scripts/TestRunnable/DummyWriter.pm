=pod

=head1 NAME

TestRunnable::DummyWriter

=head1 DESCRIPTION

A Runnable that prints "Hello world !" to a file (named according to the
"filename" parameter) in the worker's temporary directory, and then gets a
well deserved sleep ("take_time" parameter of the Dummy Runnable).

=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2022] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License
is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package TestRunnable::DummyWriter;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::RunnableDB::Dummy');


sub fetch_input {
    my $self = shift @_;

    my $dir         = $self->worker_temp_directory;
    my $filename    = $self->param_required('filename');

    open(my $fh, '>', "$dir/$filename");
    print $fh "Hello world !\n";
    close($fh);
}

1;
