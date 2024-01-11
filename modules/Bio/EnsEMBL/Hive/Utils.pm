
=pod

=head1 NAME

    Bio::EnsEMBL::Hive::Utils

=head1 SYNOPSIS

        # Example of an import:
    use Bio::EnsEMBL::Hive::Utils 'stringify';
    my $input_id_string = stringify($input_id_hash);

        # Example of inheritance:
    use base ('Bio::EnsEMBL::Hive::Utils', ...);
    my $input_id_string = $self->stringify($input_id_hash);

        # Example of a direct call:
    use Bio::EnsEMBL::Hive::Utils;
    my $input_id_string = Bio::EnsEMBL::Hive::Utils::stringify($input_id_hash);

=head1 DESCRIPTION

    This module provides general utility functions that can be used in different contexts through three different calling mechanisms:

        * import:  another module/script can selectively import methods from this module into its namespace

        * inheritance:  another module can inherit from this one and so implicitly acquire the methods into its namespace
        
        * direct call to a module's method:  another module/script can directly call a method from this module prefixed with this module's name

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


package Bio::EnsEMBL::Hive::Utils;

use strict;
use warnings;
use Carp ('confess');
use Data::Dumper;
use List::Util 'max';
use Scalar::Util qw(looks_like_number);
#use Bio::EnsEMBL::Hive::DBSQL::DBConnection;   # causes warnings that all exported functions have been redefined

use Exporter 'import';
our @EXPORT_OK = qw(stringify destringify dir_revhash parse_cmdline_options find_submodules load_file_or_module split_for_bash go_figure_dbc throw join_command_args whoami timeout print_aligned_fields);

no warnings ('once');   # otherwise the next line complains about $Carp::Internal being used just once
$Carp::Internal{ (__PACKAGE__) }++;


=head2 stringify

    Description: This function takes in a Perl data structure and stringifies it using specific configuration
                 that allows us to store/recreate this data structure according to our specific storage/communication requirements.
                 NOTE: Some recursive structures are not stringified in a way that allows destringification with destringify

    Callers    : Bio::EnsEMBL::Hive::DBSQL::AnalysisJobAdaptor      # stringification of input_id() hash
                 Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf   # stringification of parameters() hash

=cut

sub stringify {
    my $structure = pop @_;

    local $Data::Dumper::Indent    = 0;         # we want everything on one line
    local $Data::Dumper::Terse     = 1;         # and we want it without dummy variable names
    local $Data::Dumper::Sortkeys  = 1;         # make stringification more deterministic
    local $Data::Dumper::Quotekeys = 1;         # conserve some space
    local $Data::Dumper::Useqq     = 1;         # escape the \n and \t correctly
    local $Data::Dumper::Pair      = ' => ';    # make sure we always produce Perl-parsable structures, no matter what is set externally
    local $Data::Dumper::Maxdepth  = 0;         # make sure nobody can mess up stringification by setting a lower Maxdepth
    local $Data::Dumper::Deepcopy  = 1;         # avoid self-references in case the same structure is reused within params
    local $Data::Dumper::Sparseseen= 1;         # optimized "seen" hash of scalars

    return Dumper($structure);
}

=head2 destringify

    Description: This function takes in a string that may or may not contain a stingified Perl structure.
                 If it seems to contain a hash/array/quoted_string, the contents is evaluated, otherwise it is returned "as is".
                 This function is mainly used to read values from 'meta' table that may represent Perl structures, but generally don't have to.

    Callers    : Bio::EnsEMBL::Hive::DBSQL::PipelineWideParametersAdaptor   # destringification of general 'meta' params
                 beekeeper.pl script                                        # destringification of the 'pipeline_name' meta param

=cut

sub destringify {
    my $value = pop @_;

    if(defined $value) {
        if($value=~/^'.*'$/s
        or $value=~/^".*"$/s
        or $value=~/^{.*}$/s
        or $value=~/^\[.*\]$/s
        or looks_like_number($value)    # Needed for pipeline_wide_parameters as each value is destringified independently and the JSON writer would otherwise force writing numbers as strings
        or $value eq 'undef') {

            $value = eval($value);
        }
    }

    return $value;
}

=head2 dir_revhash

    Description: This function takes in a string (which is usually a numeric id) and turns its reverse into a multilevel directory hash.
                 Please note that no directory is created at this step - it is purely a string conversion function.

    Callers    : Bio::EnsEMBL::Hive::Worker                 # hashing of the worker output directories
                 Bio::EnsEMBL::Hive::RunnableDB::JobFactory # hashing of an arbitrary id

=cut

sub dir_revhash {
    my $id = pop @_;

    my @dirs = reverse(split(//, $id));
    pop @dirs;  # do not use the first digit for hashing

    return join('/', @dirs);
}


=head2 parse_cmdline_options

    Description: This function reads all options from command line into a key-value hash
                (keys must be prefixed with a single or double dash, the following term becomes the value).
                The rest of the terms go into the list.
                Command line options are not removed from @ARGV, so the same or another parser can be run again if needed.

    Callers    : scripts

=cut

sub parse_cmdline_options {
    my %pairs = ();
    my @list  = ();

    my $temp_key;

    foreach my $arg (@ARGV) {
        if($temp_key) {                     # only the value, get the key from buffer
            $pairs{$temp_key} = destringify($arg);
            $temp_key = '';
        } elsif($arg=~/^--?(\w+)=(.+)$/) {  # both the key and the value
            $pairs{$1} = destringify($2);
        } elsif($arg=~/^--?(\w+)$/) {       # only the key, buffer it and expect the value on the next round
            $temp_key = $1;
        } else {
            push @list, $arg;
        }
    }
    return (\%pairs, \@list);
}


=head2 find_submodules

    Description: This function takes one argument ("prefix" of a module name),
                transforms it into a directory name from the filesystem's point of view
                and finds all module names in these "directories".
                Each module_name found is reported only once,
                even if there are multiple matching files in different directories.

    Callers    : scripts

=cut

sub find_submodules {
    my $prefix = shift @_;

    $prefix=~s{::}{/}g;

    my %seen_module_name = ();

    foreach my $inc (@INC) {
        foreach my $full_module_path (glob("$inc/$prefix/*.pm")) {
            my $module_name = substr($full_module_path, length($inc)+1, -3);    # remove leading "$inc/" and trailing '.pm'
            $module_name=~s{/}{::}g;                                            # transform back to module_name space

            $seen_module_name{$module_name}++;
        }
    }
    return [ keys %seen_module_name ];
}


=head2 load_file_or_module

    Description: This function takes one argument, tries to determine whether it is a module name ('::'-separated)
                or a path to the module ('/'-separated), finds the module_name and dynamically loads it.

    Callers    : scripts

=cut

sub load_file_or_module {
    my $file_or_module = pop @_;

    my $module_name;

    if( $file_or_module=~/^(\w|::)+$/ ) {

        $module_name = $file_or_module;

    } elsif(-r $file_or_module) {

        if(my $package_line = `grep ^package $file_or_module`) {
            if($package_line=~/^\s*package\s+((?:\w|::)+)\s*;/) {

                $module_name = $1;

            } else {
                die "Package line format in '$file_or_module' unrecognized:\n$package_line\n";
            }
        } else {
            die "Could not find the package definition line in '$file_or_module'\n";
        }

    } else {
        die "The parameter '$file_or_module' neither seems to be a valid module nor a valid readable file\n";
    }

    eval "require $module_name;";
    die $@ if ($@);

    return $module_name;
}


=head2 split_for_bash

    Description: This function takes one argument (String) and splits it assuming it represents bash command line parameters.
                 It mainly splits on whitespace, except for cases when spaces are trapped between quotes or apostrophes.
                 In the latter case the outer quotes are removed.
    Returntype : list of Strings

=cut

sub split_for_bash {
    my $cmd = pop @_;

    my @cmd = ();

    if( defined($cmd) ) {
        @cmd = ($cmd =~ /((?:".*?"|'.*?'|\S)+)/g);   # split on space except for quoted strings

        foreach my $syll (@cmd) {                       # remove the outer quotes or apostrophes
            if($syll=~/^(\S*?)"(.*?)"(\S*?)$/) {
                $syll = $1 . $2 . $3;
            } elsif($syll=~/^(\S*?)'(.*?)'(\S*?)$/) {
                $syll = $1 . $2 . $3;
            }
        }
    }

    return @cmd;
}


=head2 go_figure_dbc

    Description: This function tries its best to build a DBConnection from $foo
                 It may need $reg_type if $foo is a Registry key and there are more than 1 DBAdaptors for it

=cut

sub go_figure_dbc {
    my ($foo, $reg_type) = @_;      # NB: the second parameter is used by a Compara Runnable

    require Bio::EnsEMBL::Hive::DBSQL::DBConnection;

#    if(UNIVERSAL::isa($foo, 'Bio::EnsEMBL::DBSQL::DBConnection')) { # already a DBConnection, return it:
    if ( ref($foo) =~ /DBConnection$/ ) {   # already a DBConnection, hive-ify it and return
      return bless $foo, 'Bio::EnsEMBL::Hive::DBSQL::DBConnection';
      
#    } elsif(UNIVERSAL::can($foo, 'dbc') and UNIVERSAL::isa($foo->dbc, 'Bio::EnsEMBL::DBSQL::DBConnection')) {
    } elsif(UNIVERSAL::can($foo, 'dbc') and ref($foo->dbc) =~ /DBConnection$/) {

        return bless $foo->dbc, 'Bio::EnsEMBL::Hive::DBSQL::DBConnection';

#    } elsif(UNIVERSAL::can($foo, 'db') and UNIVERSAL::can($foo->db, 'dbc') and UNIVERSAL::isa($foo->db->dbc, 'Bio::EnsEMBL::DBSQL::DBConnection')) { # another data adaptor or Runnable:
    } elsif(UNIVERSAL::can($foo, 'db') and UNIVERSAL::can($foo->db, 'dbc') and ref($foo->db->dbc) =~ /DBConnection$/) { # another data adaptor or Runnable:

        return bless $foo->db->dbc, 'Bio::EnsEMBL::Hive::DBSQL::DBConnection';

    } elsif(ref($foo) eq 'HASH') {

        return Bio::EnsEMBL::Hive::DBSQL::DBConnection->new( %$foo );

    } elsif($foo =~ m{^(\w*)://(?:(\w+)(?:\:([^/\@]*))?\@)?(?:([\w\-\.]+)(?:\:(\d+))?)?/(\w*)} ) {  # We can probably use a simpler regexp

        return Bio::EnsEMBL::Hive::DBSQL::DBConnection->new( -url => $foo );

    } else {
        unless(ref($foo)) {    # maybe it is simply a registry key?
            my $dba;

            eval {
                require Bio::EnsEMBL::Registry;

                if($foo=~/^(\w+):(\w+)$/) {
                    ($reg_type, $foo) = ($1, $2);
                }

                if($reg_type) {
                    $dba = Bio::EnsEMBL::Registry->get_DBAdaptor($foo, $reg_type);
                } else {
                    my $dbas = Bio::EnsEMBL::Registry->get_all_DBAdaptors(-species => $foo);

                    if( scalar(@$dbas) == 1 ) {
                        $dba = $dbas->[0];
                    } elsif( @$dbas ) {
                        die "The registry contains multiple entries for '$foo', please prepend the reg_alias with the desired type";
                    }
                }
            };

            if(UNIVERSAL::can($dba, 'dbc')) {
                return bless $dba->dbc, 'Bio::EnsEMBL::Hive::DBSQL::DBConnection';
            }
        }
        die "Sorry, could not figure out how to make a DBConnection object out of '$foo'";
    }
}


sub throw {
    my $msg = pop @_;

        # TODO: newer versions of Carp are much more tunable, but I am stuck with v1.08 .
        #       Alternatively, we could implement our own stack reporter instead of Carp::confess.
    confess $msg;
}


=head2 join_command_args

    Argument[0]: String or Arrayref of Strings
    Description: Prepares the command to be executed by system(). It is needed if the
                 command is in fact composed of multiple commands.
    Returns:     Tuple (boolean,string). The boolean indicates whether it was needed to
                 join the arguments. The string is the new command-line string.
                 PS: Shamelessly adapted from http://www.perlmonks.org/?node_id=908096

=cut

my %shell_characters = map {$_ => 1} qw(< > >> 2> 2>&1 | && || ;);

sub join_command_args {
    my $args = shift;
    return (0,$args) unless ref($args);

    # system() can only spawn 1 process. For multiple commands piped
    # together or if redirections are used, it needs a shell to parse
    # a string representing the whole command
    my $join_needed = (grep {$shell_characters{$_}} @$args) ? 1 : 0;

    my @new_args = ();
    foreach my $a (@$args) {
        if ($shell_characters{$a} or $a =~ /^[a-zA-Z0-9_\/\-]+\z/) {
            push @new_args, $a;
        } else {
            # Escapes the single-quotes and protects the arguments
            $a =~ s/'/'\\''/g;
            push @new_args, "'$a'";
        }
    }

    return ($join_needed,join(' ', @new_args));
}


=head2 whoami

    Description: Returns the name of the user who's currently running Perl.
                 $ENV{'USER'} is the most common source but it can be missing
                 so we also default to a builtin method.

=cut

sub whoami {
    return ($ENV{'USER'} || (getpwuid($<))[0]);
}


=head2 timeout

    Argument[0]: (coderef) Callback subroutine
    Argument[1]: (integer) Time to wait (in seconds)
    Description: Calls the callback whilst ensuring it does not take more than the allowed time to run.
    Returns:     The return value (scalar context) of the callback or -2 if the
                 command had to be aborted.
                 FIXME: may need a better mechanism that allows callbacks to return -2 too

=cut

sub timeout {
    my ($callback, $timeout) = @_;
    if (not $timeout) {
        return $callback->();
    }

    my $ret;
    ## Adapted from the TimeLimit pacakge: http://www.perlmonks.org/?node_id=74429
    my $die_text = "_____RunCommandTimeLimit_____\n";
    my $old_alarm = alarm(0);        # turn alarm off and read old value
    {
        local $SIG{ALRM} = 'IGNORE'; # ignore alarms in this scope

        eval
        {
            local $SIG{__DIE__};     # turn die handler off in eval block
            local $SIG{ALRM} = sub { die $die_text };
            alarm($timeout);         # set alarm
            $ret = $callback->();
        };

        # Note the alarm is still active here - however we assume that
        # if we got here without an alarm the user's code succeeded -
        # hence the IGNOREing of alarms in this scope

        alarm 0;                     # kill off alarm
    }

    alarm $old_alarm;                # restore alarm

    if ($@) {
        # the eval returned an error
        die $@ if $@ ne $die_text;
        return -2;
    }
    return $ret;
}


=head2 print_aligned_fields

    Argument[0]: Arrayref of key-value Hashrefs
    Argument[1]: Template string
    Description: For each hashref the template string will be interpolated (replacing
                 each key with its value) and printed, but making sure the same fields
                 are (right) aligned across all lines.
                 The interpolator searches for C<%(key)> patterns and replaces them
                 with the value found in the hashref. The key name can be prefixed with
                 a dash to require a left alignment instead.

=cut

sub print_aligned_fields {
    my $all_fields  = shift;
    my $template    = shift;

    return unless @$all_fields;

    my @field_names = keys %{$all_fields->[0]};
    my @all_widths;
    my %col_width;

    # Get the width of each element
    foreach my $line_fields (@$all_fields) {
        # Remove the ANSI colour codes before getting the length
        my %row_width = map {my $s = $line_fields->{$_}; $s =~ s/\x1b\[[0-9;]*m//g; $_ => length($s)} @field_names;
        push @all_widths, \%row_width;
    }

    # Get the width of each field (across all lines)
    foreach my $field_name (@field_names) {
        $col_width{$field_name} = max(map {$_->{$field_name}} @all_widths);
    }

    # Interpolate and print each line
    foreach my $line_fields (@$all_fields) {
        my $row_width = shift @all_widths;
        my $line = $template;
        $line =~ s/%\((-?)([a-zA-Z_]\w*)\)/
        $1 ?
            $line_fields->{$2} . (' ' x ($col_width{$2}-$row_width->{$2}))
        :
            (' ' x ($col_width{$2}-$row_width->{$2})) . $line_fields->{$2};
        /ge;
        print $line, "\n";
    }
}


1;

