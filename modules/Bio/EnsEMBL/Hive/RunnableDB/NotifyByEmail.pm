#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code

=pod 

=head1 NAME

Bio::EnsEMBL::Hive::RunnableDB::NotifyByEmail

=head1 DESCRIPTION

This RunnableDB module will send you a short notification email message per each job.
You can either dataflow into it, or simply create standalone jobs.

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut


package Bio::EnsEMBL::Hive::RunnableDB::NotifyByEmail;

use strict;

use base ('Bio::EnsEMBL::Hive::ProcessWithParams');

sub fetch_input {
    my $self = shift;

    return 1;
}

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

    return 1;
}

sub write_output {
    my $self = shift;

    return 1;
}

1;
