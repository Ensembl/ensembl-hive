=pod 

=head1 NAME

    Bio::EnsEMBL::Hive::Utils::URL

=head1 DESCRIPTION

    A Hive-specific URL parser.

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


package Bio::EnsEMBL::Hive::Utils::URL;

use strict;
use warnings;
use Bio::EnsEMBL::Hive::Utils ('stringify');


sub parse {
    my $url = shift @_ or return;

    my ($old_parse, $new_parse,
        $dbconn_part, $url_parts_hash, $table_name, $tparam_name, $tparam_value, $conn_param_string, $query_part);

    # In case the whole URL is quoted (should we do this with double-quotes too ?)
    if( $url=~/^'(.*)'$/ ) {
        $url = $1;
    }

    if( $url=~/^\w+$/ ) {

        $new_parse = {
            'unambig_url'   => ':///',
            'query_params'  => { 'object_type' => 'Analysis', 'logic_name' => $url, },
        };

    } else {

        # Perform environment variable substitution separately with and without curly braces.
        # Make sure expressions stay as they were if we were unable to substitute them.
        #
        $url =~ s/\$(?|\{(\w+)\}|(\w+))/defined($ENV{$1})?"$ENV{$1}":"\$$1"/eg;

        if( ($dbconn_part, @$url_parts_hash{'driver', 'user', 'pass', 'host', 'port', 'dbname'}, $table_name, $tparam_name, $tparam_value, $conn_param_string) =
            $url =~ m{^((\w*)://(?:(\w+)(?:\:([^/\@]*))?\@)?(?:([\w\-\.]+)(?:\:(\d*))?)?/([\w\-\.]*))(?:/(\w+)(?:\?(\w+)=([\w\[\]\{\}]*))?)?((?:;(\w+)=(\w+))*)$} ) {

            my ($dummy, %conn_params) = split(/[;=]/, $conn_param_string // '' );
            my $query_params;
            my $exception_from_OLD_format;

            if($table_name) {
                if($table_name eq 'analysis') {
                    $query_params->{'object_type'}          = 'Analysis';
                    $query_params->{$tparam_name}           = $tparam_value;    # $tparam_name is 'logic_name' or 'dbID', $tparam_value is the analysis_name or dbID
                } elsif($table_name eq 'accu') {
                    $query_params->{'object_type'}          = 'Accumulator';
                    $query_params->{'accu_name'}            = $tparam_name;
                    $query_params->{'accu_address'}         = $tparam_value;
                } elsif($table_name eq 'job') {
                    die "Jobs cannot yet be located by URLs, sorry";
                } else {
                    $query_params->{'object_type'}          = 'NakedTable';
                    $query_params->{'table_name'}           = $table_name;
                    if($tparam_name) {
                        if( $tparam_name eq 'insertion_method' ) {  # extra hint on the OLD format from the insertion_method
                            $query_params->{'insertion_method'} = $tparam_value;
                        } elsif( $tparam_name eq 'table_name' ) {   # hinting this is NEW format with a bipartite dbpath
                            $exception_from_OLD_format = 1;
                        }
                    }
                }
            }

            if($exception_from_OLD_format) {
                warn "OLD URL parser thinks you are using the NEW URL syntax for a remote $query_params->{'object_type'}, so skipping it (it may be wrong!)\n";
            } else {
                my $unambig_url     = hash_to_unambig_url( $url_parts_hash );

                $old_parse = {
                    'dbconn_part'   => $dbconn_part,
                    %$url_parts_hash,
                    'conn_params'   => \%conn_params,
                    'query_params'  => $query_params,
                    'unambig_url'   => $unambig_url,
                };
            }
        } # /if OLD format
    
        if( ($dbconn_part, @$url_parts_hash{'driver', 'user', 'pass', 'host', 'port', 'dbname'}, $query_part, $conn_param_string) =
            $url =~ m{^((\w+)://(?:(\w+)(?:\:([^/\@]*))?\@)?(?:([\w\-\.]+)(?:\:(\d*))?)?(?:/([/~\w\-\.]*))?)?(?:\?(\w+=[\w\[\]\{\}]*(?:&\w+=[\w\[\]\{\}]*)*))?(;\w+=\w+(?:;\w+=\w+)*)?$} ) {

            my ($dummy, %conn_params) = split(/[;=]/, $conn_param_string // '' );
            my $query_params = $query_part ? { split(/[&=]/, $query_part ) } : undef;
            my $exception_from_NEW_format;

            my ($driver, $dbname) = @$url_parts_hash{'driver', 'dbname'};

            if(!$query_params and ($driver eq 'mysql' or $driver eq 'pgsql') and $dbname and $dbname=~m{/}) {   # a special case of multipart dbpath hints at the OLD format (or none at all)

                $query_params = { 'object_type' => 'NakedTable' };
                $exception_from_NEW_format = 1;

            } elsif($query_params and not (my $object_type = $query_params->{'object_type'})) {    # do a bit of guesswork:

                if($query_params->{'logic_name'}) {
                    $object_type = 'Analysis';
                    if($dbname and $dbname=~m{^([/~\w\-\.]*)/analysis$}) {
                        $exception_from_NEW_format = 1;
                    }
                } elsif($query_params->{'job_id'}) {
                    $object_type = 'AnalysisJob';
                } elsif($query_params->{'semaphore_id'}) {
                    $object_type = 'Semaphore';
                } elsif($query_params->{'accu_name'}) { # we don't require $query_params->{'accu_address'} to support scalar accu
                    $object_type = 'Accumulator';
                } elsif($query_params->{'table_name'}) {  # NB: the order is important here, in case table_name is reset for non-NakedTables
                    $object_type = 'NakedTable';
                } elsif($query_params->{'insertion_method'}) {
                    $object_type = 'NakedTable';
                    if($dbname and $dbname=~m{^([/~\w\-\.]*)/(\w+)$}) {
                        $exception_from_NEW_format = 1;
                    }
                }

                $query_params->{'object_type'} = $object_type;
            }

            if($exception_from_NEW_format) {
                warn "NEW URL parser thinks you are using the OLD URL syntax for a remote $query_params->{'object_type'}, so skipping it (it may be wrong!)\n";
            } else {
                my $unambig_url     = hash_to_unambig_url( $url_parts_hash );

                $new_parse = {
                    'dbconn_part'   => $dbconn_part,
                    %$url_parts_hash,
                    'conn_params'   => \%conn_params,
                    'query_params'  => $query_params,
                    'unambig_url'   => $unambig_url,
                };
            }
        } # /if NEW format

    }

    if($new_parse and $old_parse) {
        if(stringify($old_parse) eq stringify($new_parse)) {
            return $new_parse;
        } else {
            warn "The URL '$url' can be parsed ambiguously:\n\t".stringify($old_parse)."\nvs\n\t".stringify($new_parse)."\n). Using the OLD parser at the moment.\nPlease change your URL to match the new format if you see weird behaviour\n\n";
            return $old_parse;
        }
    } elsif($new_parse) {
        return $new_parse;
    } elsif($old_parse) {
        warn "The URL '$url' only works with the old parser, please start using the new syntax as the old parser will soon be deprecated\n\n";
        return $old_parse;
    } else {
        warn "The URL '$url' could not be parsed, please check it\n";
        return;
    }
}


=head2 hash_to_unambig_url

  Arg [1]     : a hash describing (at least) db connection parameters
  Example     : my $unambig_url = hash_to_unambig_url( $url_parts_hash );
  Description : Generates a degenerate URL that omits unnecessary parts (password, default port numbers)
              : but tries to uniquely represent a connection.
  Returntype  : a string

=cut

sub hash_to_unambig_url {
    my $url_parts_hash = shift @_;      # expected to contain the parts from which to build a URL

    my $driver          = $url_parts_hash->{'driver'} // '';
    my $unambig_port    = $url_parts_hash->{'port'}   // { 'mysql' => 3306, 'pgsql' => 5432, 'sqlite' => '' }->{$driver} // '';
    my $unambig_host    = ( $url_parts_hash->{'host'} // '' ) eq 'localhost' ? '127.0.0.1' : ( $url_parts_hash->{'host'} // '' );
    my $unambig_url     = $driver .'://'. ($url_parts_hash->{'user'} ? $url_parts_hash->{'user'}.'@' : '')
                                        . $unambig_host . ( $unambig_port ? ':'.$unambig_port : '') .'/'. ( $url_parts_hash->{'dbname'} // '' );

    return $unambig_url;
}


=head2 hash_to_url

  Arg [1]     : a hash describing a db connection, or accumulator, as generated by parse_url
  Example     : my $parse = parse_url($url1); my $url2 = hash_to_url($parse); 
  Description : Generates a "new-style" URL from a hash containing the parse of a URL
              : (old or new style). In cases where a trailing slash is optional, it leaves
              : off the trailing slash
  Returntype  : a URL as a string

=cut

sub hash_to_url {
    my $parse = shift;

  my $location_part = '';
  if ($parse->{'driver'}) {
    $location_part = join('',
			$parse->{'driver'} // '',
			'://',
			$parse->{'user'} ? $parse->{'user'}.($parse->{'pass'} ? ':' . $parse->{'pass'} : '').'@' : '',
			$parse->{'host'} ? $parse->{'host'}.($parse->{'port'} ? ':' . $parse->{'port'} : '') : '',
			'/',
			$parse->{'dbname'} // '',
		       );
  }
  
        # Query part:
    my $qp_hash = \%{ $parse->{'query_params'} };
    my $object_type = delete $qp_hash->{'object_type'} // '';   # in most cases we don't need object_type in the URL
    my $query_params_part =
        (($object_type  eq 'Analysis') && !$location_part)
            ? $qp_hash->{'logic_name'}
            : (($object_type  eq 'AnalysisJob') && !$location_part)
                ? $qp_hash->{'job_id'}
                : keys %$qp_hash
                    ? '?' . join('&', map { $_.'='.$qp_hash->{$_} } keys %$qp_hash)
                    : '';

        # DBC extra arguments' part:
    my $cp_hash = $parse->{'conn_params'} || {};
    my $conn_params_part = keys %$cp_hash
        ? ';' . join(';', map { $_.'='.$cp_hash->{$_} } keys %$cp_hash)
        : '';

    my $url = $location_part . $query_params_part . $conn_params_part;

    return $url;
}


=head2 hide_url_password

  Description : Check the command-line for -url or -pipeline_url in order to
                replace the password with an environment variable and then
                exec on the new arguments (in which case the function doesn't
                return)
  Returntype  : void or no return

=cut

sub hide_url_password {

    # avoid calling exec whilst in the Perl debugger not to confuse the latter
    # Detect the presence of the debugger with https://www.nntp.perl.org/group/perl.debugger/2004/11/msg55.html
    return if defined &DB::DB;

    # Safeguard to avoid attempting the substitution twice
    # NOTE: the environment is propagated to the children, meaning that the
    # variable, once set by beekeeper.pl, will extend to all its workers,
    # which is fine as long as beekeeper protects the passwords.
    return if $ENV{EHIVE_SANITIZED_ARGS};
    $ENV{EHIVE_SANITIZED_ARGS} = 1;

    # Work on a copy of @ARGV
    my @args = (@ARGV);

    my @new_args;
    # Scan the list of arguments
    while (@args) {
        my $a = shift @args;
        # Search for -url and -pipeline_url (with one or two hyphens)
        if (($a =~ /^--?(pipeline_)?url$/) and @args) {
            my $url = shift @args;
            # Does the next value look like a proper URL ?
            if ($url =~ /^(.*:\/\/\w*:)([^\/\@]*)(\@.*)$/) {
                # Recognized URL
                my $driver_and_user    = $1;
                my $possible_password  = $2;
                my $url_remainder      = $3;
                # Does the password look like an environment variable ?
                if ($possible_password =~ /\$(?|\{(\w+)\}|(\w+))/) {
                    # Does the variable exist ?
                    if (defined($ENV{$1})) {
                        # Already a substituted password -> bail out !
                        return;
                    }
                }
                # Perform the substitution
                my $pass_variable = '_EHIVE_HIDDEN_PASS';
                $ENV{$pass_variable} = $possible_password;
                # Single quotes are needed so that LSF doesn't expand the variable
                $url = q{'} . $driver_and_user .'${'.$pass_variable . '}' . $url_remainder . q{'};
            }
            # Found the URL, let's push the remaining arguments and exec
            push @new_args, $a, $url, @args;
            exec($^X, $0, @new_args);

        } elsif ($a eq '--') {
            # We've reached the end of the parsable options without finding
            # a password -> nothing to do
            return;

        } else {
            push @new_args, $a;
        }
    }
    # If we arrive here it means we couldn't find anything to substitute,
    # so there is nothing to do
}


1;
