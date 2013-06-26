package Bio::EnsEMBL::Hive::Utils::Config;

use JSON;


sub default_config_files {  # a class method, returns a list

    my $system_config   = $ENV{'EHIVE_ROOT_DIR'}.'/hive_config.json';
    my $user_config     = $ENV{'HOME'}.'/.hive_config.json';

    return ($system_config, (-r $user_config) ? ($user_config) : ());
}


sub new {
    my $class = shift @_;

    my $self = bless {}, $class;
    $self->config_hash( {} );

    foreach my $cfg_file ( scalar(@_) ? @_ : $self->default_config_files ) {
        if(my $cfg_hash = $self->load_from_json($cfg_file)) {
            $self->merge($cfg_hash);
        }
    }

    return $self;
}


sub config_hash {
    my $self = shift @_;

    if(@_) {
        $self->{_config_hash} = shift @_;
    }
    return $self->{_config_hash};
}


sub load_from_json {
    my ($self, $filename) = @_;

    if(-r $filename) {
        my $json_text   = `cat $filename`;
        my $json_parser = JSON->new->relaxed;
        my $perl_hash   = $json_parser->decode($json_text);
        
        return $perl_hash;
    } else {
        warn "Can't read from '$filename'";

        return undef;
    }
}


sub merge {
    my $self = shift @_;
    my $from = shift @_;
    my $to   = shift @_ || $self->config_hash;  # only defined in subsequent recursion steps

    while(my ($key,$value) = each %$from) {
        if(exists $to->{$key} and ref($to->{$key})) {
            $self->merge($from->{$key}, $to->{$key});
        } else {
            $to->{$key} = $from->{$key};
        }
    }
}


sub get {
    my $self        = shift @_;
    my $option_name = pop @_;

    my $hash_ptr    = $self->config_hash;
    my $option_value = $hash_ptr->{$option_name};   # not necessatily defined

    foreach my $context_syll (@_) {
        $hash_ptr = $hash_ptr->{$context_syll};
        if(exists $hash_ptr->{$option_name}) {
            $option_value = $hash_ptr->{$option_name};
        }
    }

    return $option_value;
}


sub set {
    my $self        = shift @_;
    my $value       = pop @_;
    my $key         = pop @_;

    my $hash_ptr    = $self->config_hash;

    foreach my $context_syll (@_) {
        unless(exists $hash_ptr->{$context_syll}) {
            $hash_ptr->{$context_syll} = {};
        }
        $hash_ptr = $hash_ptr->{$context_syll};
    }

    if(ref($hash_ptr->{$key}) ne ref($value)) {
        die "Mismatch of types in Config::set(".join(',',@_,$key,$value).") : trying to set a ".(ref($value)||'scalar')." instead of ".ref($hash_ptr->{$key});
    } else {
        $hash_ptr->{$key} = $value;
    }
}

1;
