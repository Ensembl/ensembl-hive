=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2024] EMBL-European Bioinformatics Institute

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

=pod

=head1 NAME

Bio::EnsEMBL::Hive::Utils::Slack

=head1 DESCRIPTION

A library to interface eHive with Slack

=cut

package Bio::EnsEMBL::Hive::Utils::Slack;

use strict;
use warnings;

use Exporter 'import';
our @EXPORT_OK = qw(send_message_to_slack send_beekeeper_message_to_slack);


=head2 send_message_to_slack

    Description: A core method to send a message to a Slack webhook.
                 The payload should be a hash-structure that can be encoded in
                 JSON and follows Slack's message structure. See more details at
                 <https://api.slack.com/incoming-webhooks> and
                 <https://api.slack.com/docs/formatting>

=cut

sub send_message_to_slack {
    my ($slack_webhook, $payload) = @_;

    require HTTP::Request::Common;
    require LWP::UserAgent;
    require JSON;

    # Fix the channel name (it *must* start with a hash)
    $payload->{'channel'} = '#'.$payload->{'channel'} if ($payload->{'channel'} || '') =~ /^[^#@]/;

    my $json_payload = JSON::encode_json($payload);
    my $req = HTTP::Request::Common::POST($slack_webhook, ['payload' => $json_payload]);

    my $ua = LWP::UserAgent->new;
    $ua->timeout(15);
    my $resp = $ua->request($req);

    if ($resp->is_success) {
        # well done
    } else {
        # All taken from https://api.slack.com/changelog/2016-05-17-changes-to-errors-for-incoming-webhooks
        if ($resp->code == 400) {
            if ($resp->content eq 'invalid_payload') {
                _pretty_die($resp, 'The data sent in your request cannot be understood as presented; verify your content body matches your content type and is structurally valid'. "\n$json_payload");
            } elsif ($resp->content eq 'user_not_found') {
                _pretty_die($resp, 'The user used in your request does not actually exist' . "\n$json_payload");
            }
        } elsif ($resp->code == 403) {
            if ($resp->content eq 'action_prohibited') {
                _pretty_die($resp, 'The team associated with your request has some kind of restriction on the webhook posting in this context.'. "\n$json_payload");
            }
        } elsif ($resp->code == 404) {
            if ($resp->content eq 'channel_not_found') {
                _pretty_die($resp, sprintf('The channel associated with your request (%s) does not exist', $payload->{'channel'}));
            }
        } elsif ($resp->code == 405) {
            if ($resp->content eq 'channel_is_archived') {
                _pretty_die($resp, sprintf(q{The channel '%s' has been archived and doesn't accept further messages, even from your incoming webhook.}, $payload->{'channel'}));
            }
        } elsif ($resp->code == 500) {
            if ($resp->content eq 'rollup_error') {
                _pretty_die($resp, 'Something strange and unusual happened that was likely not your fault at all.'. "\n$json_payload");
            }
        }
        _pretty_die($resp, $resp->content);
    }
}


=head2 _pretty_die

    Description: Helper method to have uniform error messages

=cut

sub _pretty_die {
    my ($resp, $explanation) = @_;
    die sprintf("Got a %d error (%s): %s\n", $resp->code, $resp->message, $explanation);
}


=head2 send_beekeeper_message_to_slack

    Arg [1]      : $slack_webhook (string URL)
    Arg [2]      : $hive_pipeline (Bio::EnsEMBL::Hive::HivePipeline)
    Arg [3]      : $is_error (non-zero if message should be displayed as an error)
    Arg [4]      : $is_exit (non-zero if message should be displayed as an exit -
                   a non-zero $is_error overrides $is_exit)
    Arg [5]      : $beekeeper_message (string)
    Arg [6]      : (optional) $loop_until (string) beekeeper's loop_until setting
    Description  : Formats and packages a message from the beekeeper, then sends to Slack.

=cut

sub send_beekeeper_message_to_slack {
    my ($slack_webhook, $hive_pipeline, $is_error, $is_exit, $beekeeper_message, $loop_until) = @_;

    my @attachments;
    my $error_fallback = "this beekeeper has detected an error condition";
    my $exit_fallback = "this beekeeper has stopped";

    $beekeeper_message =~ s/###,/###\n/g;
    if ($loop_until) {
        $beekeeper_message .= "\nBeekeeper's loop_until set to '$loop_until'";
    }
    if ($is_error) {
        push @attachments, {
            'color' => 'danger',
            'fallback' => $error_fallback,
            'title' => 'Beekeeper encountered an error',
            'text' => $beekeeper_message,
        }
    } elsif ($is_exit) {
        push @attachments, {
            'color' => 'warning',
            'fallback' => $exit_fallback,
            'title' => 'Beekeeper has exited',
            'text' => $beekeeper_message,
        }
    } else {
        # FIXME: this can never happen because $is_exit is always set to 1
        push @attachments, {
            'color' => 'good',
            'fallback' => 'beekeeper sent a non-error, non-exit message',
            'title' => 'Beekeeper message',
            'text' => $beekeeper_message,
        }
    }

    my $dbc = $hive_pipeline->hive_dba()->dbc();
    my $payload = {
        'text' => sprintf('Message from %s@%s:%s', $hive_pipeline->hive_pipeline_name, $dbc->host, $dbc->port),
        'attachments' => \@attachments,
    };
    send_message_to_slack($slack_webhook, $payload);
}

1;
