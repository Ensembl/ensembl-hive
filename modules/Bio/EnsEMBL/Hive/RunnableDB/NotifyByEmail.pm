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

This RunnableDB module will send you a short notification email message per
each job.  You can either dataflow into it, or simply create standalone
jobs.

The main body of the email is expected in the "text" parameter. If the
"is_html" parameter is set, the body is expected to be in HTML.

Attachments such as diagrams, images, PDFs have to be listed in the
'attachments' parameter.

C<format_table> provides a simple method to stringify a table of data. If
you need more options to control the separators, the alignment, etc, have a
look at the very comprehensive L<Text::Table>.

Note: this module uses L<Email::Sender> to send the email, which by default
uses C<sendmail> but has other backends configured. As such, it depends
heavily on the implementation of your compute farm. Please make sure it
works as intended before using this module in complex pipelines.

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2024] EMBL-European Bioinformatics Institute

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

use Email::Stuffer;

use base ('Bio::EnsEMBL::Hive::Process');

sub param_defaults {
    return {
            'is_html'    => 0,
            'subject' => 'An automatic message from your pipeline',
            'attachments' => [],
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

    param('attachments'): Array of paths for files to attach.

    param('*'):       Any other parameters can be freely used for parameter substitution.

=cut

sub run {
    my $self = shift;

    my $email   = $self->param_required('email');
    my $subject = $self->param_required('subject');
    my $text    = $self->param_required('text');
    my $attachments = $self->param('attachments');

    my $msg = Email::Stuffer->from($email)
                            ->to($email)
                            ->subject($subject);

    if ($self->param('is_html')) {
        $msg->html_body($text);
    } else {
        $msg->text_body($text);
    }

    if ($attachments and @$attachments) {
        $msg->attach_file($_) for @$attachments;
    }

    $msg->send();
}

=head2 write_output

    Description : Implements write_output() interface method of Bio::EnsEMBL::Hive::Process that is used to deal with job's output after the execution.
                  Here we have nothing to do.

=cut

sub write_output {
}



######################
## Internal methods ##
######################

# Present data in a nice table, like what mySQL does.


=head2 format_table

The same type of table could be generated with L<Text::Table>:

  my $first_column_name = shift @$columns;
  my $tb = Text::Table->new(\'| ', $first_column_name, (map { +(\' | ', $_) } @$columns), \' |',);
  $tb->load(@$results);
  my $rule = $tb->rule('-', '+');
  return $title . "\n" . $rule . $tb->title() . $rule .  $tb->body() . $rule;

=cut

sub format_table {
    my ($self, $title, $columns, $results) = @_;

    my @lengths;
    foreach (@$columns) {
        push @lengths, length($_) + 2;
    }

    foreach (@$results) {
        for (my $i=0; $i < scalar(@$_); $i++) {
            my $len = length($$_[$i] // 'N/A') + 2;
            $lengths[$i] = $len if $len > $lengths[$i];
        }
    }

    my $table = "$title\n";
    $table .= '+'.join('+', map {'-' x $_ } @lengths).'+'."\n";

    for (my $i=0; $i < scalar(@lengths); $i++) {
        my $column = $$columns[$i];
        my $padding = $lengths[$i] - length($column) - 2;
        $table .= '| '.$column.(' ' x $padding).' ';
    }

    $table .= '|'."\n".'+'.join('+', map {'-' x $_ } @lengths).'+'."\n";

    foreach (@$results) {
        for (my $i=0; $i < scalar(@lengths); $i++) {
            my $value = $$_[$i] // 'N/A';
            my $padding = $lengths[$i] - length($value) - 2;
            $table .= '| '.$value.(' ' x $padding).' ';
        }
        $table .= '|'."\n"
    }

    $table .= '+'.join('+', map {'-' x $_ } @lengths).'+'."\n";

    return $table;
}

1;
