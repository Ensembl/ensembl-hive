=pod 

=head1 NAME

Bio::EnsEMBL::Hive::RunnableDB::SlackNotification

=head1 SYNOPSIS

    This is a RunnableDB module that implements Bio::EnsEMBL::Hive::Process interface
    and is ran by Workers during the execution of eHive pipelines.
    It is not generally supposed to be instantiated and used outside of this framework.

    Please refer to Bio::EnsEMBL::Hive::Process documentation to understand the basics of the RunnableDB interface.

    Please refer to Bio::EnsEMBL::Hive::PipeConfig::* pipeline configuration files to understand how to configure pipelines.

=head1 DESCRIPTION

    This RunnableDB module will send a notification to a Slack channel.
    You can either dataflow into it, or simply create standalone jobs.

    It requires "slack_webhook" to be defined. You can this in the parameters of your Slack team.
    The message itself is defined by the "text" parameter (and optionally by "attachments" too).

=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2021] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::RunnableDB::SlackNotification;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Utils::Slack ('send_message_to_slack');

use base ('Bio::EnsEMBL::Hive::Process');

sub param_defaults {
    return {

        # These parameters have a default value in the webhook, but can be overriden here
        'channel'       => undef,
        'username'      => undef,
        'icon_url'      => undef,
        'icon_emoji'    => undef,   # wins if both icon_* parameters are defined

        # If the sender wants something more fancy than a paragraph
        'attachments'   => undef,
    };
}

sub run {
    my $self = shift;

    my $payload = {};

    # required arguments
    foreach my $k (qw(text)) {
        $payload->{$k} = $self->param_required($k);
    }

    # optional arguments
    foreach my $k (qw(username channel icon_emoji icon_url attachments)) {
        $payload->{$k} = $self->param($k) if $self->param($k);
    }

    send_message_to_slack($self->param_required('slack_webhook'), $payload);
}

1;
