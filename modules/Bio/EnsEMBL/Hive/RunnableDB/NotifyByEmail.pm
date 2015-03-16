=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::RunnableDB::NotifyByEmail

=head1 SYNOPSIS

    This is a RunnableDB module that implements Bio::EnsEMBL::Hive::Process interface
    and is ran by Workers during the execution of eHive pipelines.
    It is not generally supposed to be instantiated and used outside of this framework.

    Please refer to Bio::EnsEMBL::Hive::Process documentation to understand the basics of the RunnableDB interface.

    Please refer to Bio::EnsEMBL::Hive::PipeConfig::* pipeline configuration files to understand how to configure pipelines.

=head1 DESCRIPTION

    This RunnableDB module will send you a short notification email message per each job.
    You can either dataflow into it, or simply create standalone jobs.

    Note: this module depends heavily on the implementation of your compute farm.
    Sendmail may be unsupported, or supported differently.
    Please make sure it works as intended before using this module in complex pipelines.

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


package Bio::EnsEMBL::Hive::RunnableDB::NotifyByEmail;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Hive::Process');

sub param_defaults {
    return {
            'is_html'    => 0,
            'subject' => 'An automatic message from your pipeline',
    };
}


=head2 fetch_input

    Description : Implements fetch_input() interface method of Bio::EnsEMBL::Hive::Process that is used to read in parameters and load data.
                  Here we have nothing to do.

=cut

sub fetch_input {
}

=head2 run

    Description : Implements run() interface method of Bio::EnsEMBL::Hive::Process that is used to perform the main bulk of the job (minus input and output).
                  Here the actual sending of the email message happens in run() though one may argue it is technically 'output'.

    param('email'):   The email address to send the message to.

    param('subject'): The (optional) 'Subject:' line.

    param('text'):    Text of the email message. It will undergo parameter substitution.

    param('is_html'): Boolean. Whether the content of 'text' is in HTML

    param('*'):       Any other parameters can be freely used for parameter substitution.

=cut

sub run {
    my $self = shift;

    my $email   = $self->param_required('email');
    my $subject = $self->param_required('subject');
    my $text    = $self->param_required('text');

    open(my $sendmail_fh, '|-', "sendmail '$email'");
    print $sendmail_fh "Subject: $subject\n";
    print $sendmail_fh "Content-Type: text/html;\n" if $self->param('is_html');
    print $sendmail_fh "\n";
    print $sendmail_fh "$text\n";
    close $sendmail_fh;
}

=head2 write_output

    Description : Implements write_output() interface method of Bio::EnsEMBL::Hive::Process that is used to deal with job's output after the execution.
                  Here we have nothing to do.

=cut

sub write_output {
}

1;
