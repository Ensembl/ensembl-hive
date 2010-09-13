
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

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

package Bio::EnsEMBL::Hive::RunnableDB::NotifyByEmail;

use strict;

use base ('Bio::EnsEMBL::Hive::Process');

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

    param('*'):       Any other parameters can be freely used for parameter substitution.

=cut

sub run {
    my $self = shift;

    my $email   = $self->param('email')   || die "'email' parameter is obligatory";
    my $subject = $self->param('subject') || "An automatic message from your pipeline";
    my $text    = $self->param('text')    || die "'text' parameter is obligatory";

    #   Run parameter substitutions:
    #
    $text = $self->param_substitute($text);

    open(SENDMAIL, "|sendmail $email");
    print SENDMAIL "Subject: $subject\n";
    print SENDMAIL "\n";
    print SENDMAIL "$text\n";
    close SENDMAIL;
}

=head2 write_output

    Description : Implements write_output() interface method of Bio::EnsEMBL::Hive::Process that is used to deal with job's output after the execution.
                  Here we have nothing to do.

=cut

sub write_output {
}

1;
