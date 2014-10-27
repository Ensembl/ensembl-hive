
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

    Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

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
use Bio::EnsEMBL::Hive::Version;
use Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor;
#use Bio::EnsEMBL::Hive::DBSQL::DBConnection;   # causes warnings that all exported functions have been redefined

use Exporter 'import';
our @EXPORT_OK = qw(stringify destringify dir_revhash parse_cmdline_options find_submodules load_file_or_module script_usage url2dbconn_hash go_figure_dbc report_versions throw);

no warnings ('once');   # otherwise the next line complains about $Carp::Internal being used just once
$Carp::Internal{ (__PACKAGE__) }++;


=head2 stringify

    Description: This function takes in a Perl data structure and stringifies it using specific configuration
                 that allows us to store/recreate this data structure according to our specific storage/communication requirements.

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

    return Dumper($structure);
}

=head2 destringify

    Description: This function takes in a string that may or may not contain a stingified Perl structure.
                 If it seems to contain a hash/array/quoted_string, the contents is evaluated, otherwise it is returned "as is".
                 This function is mainly used to read values from 'meta' table that may represent Perl structures, but generally don't have to.

    Callers    : Bio::EnsEMBL::Hive::DBSQL::MetaContainer           # destringification of general 'meta' params
                 beekeeper.pl script                                # destringification of the 'pipeline_name' meta param

=cut

sub destringify {
    my $value = pop @_;

    if($value) {
        if($value=~/^'.*'$/
        or $value=~/^".*"$/
        or $value=~/^{.*}$/
        or $value=~/^\[.*\]$/
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
        foreach my $full_module_path (<$inc/$prefix/*.pm>) {
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
                warn "Package line format unrecognized:\n$package_line\n";
                script_usage(1);
            }
        } else {
            warn "Could not find the package definition line in '$file_or_module'\n";
            script_usage(1);
        }

    } else {
        warn "The parameter '$file_or_module' neither seems to be a valid module nor a valid readable file\n";
        script_usage(1);
    }

    eval "require $module_name;";
    die $@ if ($@);

    return $module_name;
}


=head2 script_usage

    Description: This function takes one argument (return value).
                It attempts to run perldoc on the current script, and if perldoc is not present, emulates its behaviour.
                Then it exits with the return value given.

    Callers    : scripts

=cut

sub script_usage {
    my $retvalue = pop @_;

    if(`which perldoc`) {
        system('perldoc', $0);
    } else {
        foreach my $line (<main::DATA>) {
            if($line!~s/\=\w+\s?//) {
                $line = "\t$line";
            }
            print $line;
        }
        <main::DATA>;   # this is just to stop the 'used once' warnings
    }
    exit($retvalue);
}


sub url2dbconn_hash {
    my $url = pop @_;

    if( my ($driver, $user, $pass, $host, $port, $dbname) =
        $url =~ m{^(\w*)://(?:(\w+)(?:\:([^/\@]*))?\@)?(?:([\w\-\.]+)(?:\:(\d+))?)?/(\w*)} ) {

        return {
            '-driver' => $driver    || 'mysql',
            '-host'   => $host      || 'localhost',
            '-port'   => $port      || 3306,
            '-user'   => $user      || '',
            '-pass'   => $pass      || '',
            '-dbname' => $dbname,
        };
    } else {
        return 0;
    }
}


sub go_figure_dbc {
    my ($foo, $schema_type) = @_;

#    if(UNIVERSAL::isa($foo, 'Bio::EnsEMBL::DBSQL::DBConnection')) { # already a DBConnection, return it:
    if ( ref($foo) =~ /DBConnection$/ ) {   # already a DBConnection, return it:

        return $foo;

#    } elsif(UNIVERSAL::can($foo, 'dbc') and UNIVERSAL::isa($foo->dbc, 'Bio::EnsEMBL::DBSQL::DBConnection')) {
    } elsif(UNIVERSAL::can($foo, 'dbc') and ref($foo->dbc) =~ /DBConnection$/) {

        return $foo->dbc;

#    } elsif(UNIVERSAL::can($foo, 'db') and UNIVERSAL::can($foo->db, 'dbc') and UNIVERSAL::isa($foo->db->dbc, 'Bio::EnsEMBL::DBSQL::DBConnection')) { # another data adaptor or Runnable:
    } elsif(UNIVERSAL::can($foo, 'db') and UNIVERSAL::can($foo->db, 'dbc') and ref($foo->db->dbc) =~ /DBConnection$/) { # another data adaptor or Runnable:

        return $foo->db->dbc;

    } elsif(my $db_conn = (ref($foo) eq 'HASH') ? $foo : url2dbconn_hash( $foo ) ) {  # either a hash or a URL that translates into a hash

        return Bio::EnsEMBL::Hive::DBSQL::DBConnection->new( %$db_conn );

    } else {
        unless(ref($foo)) {    # maybe it is simply a registry key?
            my $dba;
            eval {
                $schema_type ||= 'hive';
                require Bio::EnsEMBL::Registry;
                $dba = Bio::EnsEMBL::Registry->get_DBAdaptor($foo, $schema_type);
            };
            if(UNIVERSAL::can($dba, 'dbc')) {
                return $dba->dbc;
            }
        }
        die "Sorry, could not figure out how to make a DBConnection object out of '$foo'";
    }
}


sub report_versions {
    print "CodeVersion\t".Bio::EnsEMBL::Hive::Version->get_code_version()."\n";
    print "CompatibleHiveDatabaseSchemaVersion\t".Bio::EnsEMBL::Hive::DBSQL::SqlSchemaAdaptor->get_code_sql_schema_version()."\n";
}


sub throw {
    my $msg = pop @_;

        # TODO: newer versions of Carp are much more tunable, but I am stuck with v1.08 .
        #       Alternatively, we could implement our own stack reporter instead of Carp::confess.
    confess $msg;
}


1;

