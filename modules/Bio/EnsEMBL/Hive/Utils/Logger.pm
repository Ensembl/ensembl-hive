=pod

=head1 NAME

    Bio::EnsEMBL::Hive::Utils::Formatter

=head1 DESCRIPTION

    An output printer and formatter
    Modes:
    onfly - immediate print of data, no storage
    json - prints only json passed to function, no any debug-level control, text print also skipped
    custom_output - uses custom function to print formatted text


=head1 LICENSE

    Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
    Copyright [2016-2019] EMBL-European Bioinformatics Institute

    Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software distributed under the License
    is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and limitations under the License.

=head1 CONTACT

    Please subscribe to the Hive mailing list:  http://listserver.ebi.ac.uk/mailman/listinfo/ehive-users  to discuss Hive-related questions or to be notified of our updates

=cut


package Bio::EnsEMBL::Hive::Utils::Logger;

use strict;
use warnings;
use Log::Log4perl;
use JSON;
use Bio::EnsEMBL::Hive::Utils ('throw');


sub init_logger {
    my $class = shift @_;
    my %flags = @_;

    my ($log_level, $json_logfile, $text_logfile, $json_screen, $text_screen)
        = delete @flags{qw(-log_level -json_logfile -text_logfile -json_screen -text_screen)};

    my $textLogging = $log_level ? $log_level : 'DEBUG, ';
    $textLogging = ($text_screen && $text_screen eq '0' && !$text_logfile) ? 'OFF, Screen' : $textLogging;
    $textLogging = $textLogging . ($text_screen && $text_screen ne '0' ? ' Screen, ' : '');
    $textLogging = $textLogging . ($text_logfile ? 'TextLogfile' : '');

    my  $jsonLogging = ($json_screen || $json_logfile) ? 'DEBUG, ' : 'OFF, ';
    $jsonLogging = $jsonLogging . ($json_screen ? ' Screen, ' : '');
    $jsonLogging = $jsonLogging . ($json_logfile ?  'JsonLogfile' : '');

    $text_logfile = $text_logfile // 'text.log';

    $json_logfile = $json_logfile // 'json.log';

    my $conf = qq(
         log4perl.category.Text = $textLogging
         log4perl.category.Json = $jsonLogging

         log4perl.appender.TextLogfile          = Log::Log4perl::Appender::File
         log4perl.appender.TextLogfile.filename = $text_logfile
         log4perl.appender.TextLogfile.layout   = Log::Log4perl::Layout::PatternLayout
         log4perl.appender.TextLogfile.layout.ConversionPattern = \%m

         log4perl.appender.JsonLogfile          = Log::Log4perl::Appender::File
         log4perl.appender.JsonLogfile.filename = $json_logfile
         log4perl.appender.JsonLogfile.layout   = Log::Log4perl::Layout::PatternLayout
         log4perl.appender.JsonLogfile.layout.ConversionPattern = \%m

         log4perl.appender.Screen               = Log::Log4perl::Appender::Screen
         log4perl.appender.Screen.stderr        = 0
         log4perl.appender.Screen.layout        = Log::Log4perl::Layout::PatternLayout
         log4perl.appender.Screen.layout.ConversionPattern = \%m
    );
    Log::Log4perl::init(\$conf);
    return;
}

sub get_jsonLogger() {
    return Log::Log4perl::get_logger("Json");
}

sub get_textLogger() {
    return Log::Log4perl::get_logger("Text");
}

1;
