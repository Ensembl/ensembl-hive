=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2021] EMBL-European Bioinformatics Institute

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

    my $req = HTTP::Request::Common::POST($slack_webhook, ['payload' => JSON::encode_json($payload)]);

    my $ua = LWP::UserAgent->new;
    $ua->timeout(15);
    my $resp = $ua->request($req);

    if ($resp->is_success) {
        # well done
    } else {
        die $resp->status_line;
    }
}


=head2 send_beekeeper_message_to_slack

    Description: A method that is able to parse beekeeper's error messages and
                 make a Slack message. Note that this method *must* be in sync
                 with Queen

=cut

sub send_beekeeper_message_to_slack {
    my ($slack_webhook, $hive_pipeline, $beekeeper_message) = @_;

    my @attachments;
    my $no_jobs_message = '### No jobs left to do ###';
    my $has_failure = 0;
    my $no_jobs_to_run = 0;
    foreach my $reason (split /\n/, $beekeeper_message) {
        if ($reason =~ /Analysis '(.*)' has FAILED  \(failed Jobs: (\d+), tolerance: (.*)\%\)/) {
            $has_failure = 1;
            push @attachments, {
                'color' => 'danger',
                'fallback' => $reason,
                'title' => "Analysis '$1' has failed",
                'text' => "There are $2 failed jobs and the tolerance is $3%",
            };
        } elsif ($reason =~ /$no_jobs_message/) {
            $no_jobs_to_run = 1;
        }
    }

    if ($has_failure) {
        push @attachments, {
            'color' => 'warning',
            'fallback' => $no_jobs_message,
            'title' => 'beekeeper exited',
            'mrkdwn_in' => [ 'text' ],
        };
        if ($no_jobs_to_run) {
            $attachments[-1]->{'text'} = 'No jobs can be run (all _DONE_ or _FAILED_)';
        } else {
            $attachments[-1]->{'text'} = 'There are still some jobs to run, but some analyses are failing and `-keep_alive` has not been given';
        }
    } elsif ($no_jobs_to_run) {
        push @attachments, {
            'color' => 'good',
            'fallback' => $no_jobs_message,
            'title' => 'Pipeline completed',
        };
    } else {
        # Not sure this case is possible
    }

    my $dbc = $hive_pipeline->hive_dba()->dbc();
    my $payload = {
        'text' => sprintf('Message from %s@%s:%s', $hive_pipeline->hive_pipeline_name, $dbc->host, $dbc->port),
        'attachments' => \@attachments,
    };
    send_message_to_slack($slack_webhook, $payload);
}

1;
