package Test::Http::Util;
use warnings;
use strict;

use base 'Exporter';

use URI::Escape;
use JSON;
use Crypt::CBC;
use MIME::Base64;

use Digest::MD5 qw(md5_hex);

sub join_arr(@);

our @EXPORT_OK = qw (
    aes_session_cookie
    bail_out
    trim
    encode_args
    expand_env_in_config
    secure_token
    join_arr
    encode_cookies
);


sub encode_cookies(@) {
    my (%args) = @_;
    my @ret = ();

    while ( my ($key, $val) = each %args ) {
        push @ret, uri_escape($key) . "=" . uri_escape($val);
    }

    return join "; ", @ret;
}

sub encode_args(@) {
    my (%args) = @_;
    my @ret = ();

    while ( my ($key, $val) = each %args ) {
        push @ret, uri_escape($key) . "=" . uri_escape($val);
    }

    return join "&", @ret;
}

sub aes_session_cookie($$$$$) {
    my ($sid, $uid, $expt, $key, $iv) = @_;

    $key = defined $key ? $key : $ENV{AES_SESSION_KEY};
    $iv = defined $iv ? $iv : $ENV{AES_SESSION_IV};

    if ( !$key || length($key) != 32 || !$iv || length($iv) != 16 ) {
        bail_out("session key, iv not valid");
        warn $key;
        warn $iv;
        die;
    }

    $expt = $expt ? $expt : 0;
    my $t = time() + $expt;
    $uid = $uid + 0;
    my %sess = ( 'sid' => $sid, 'uid' => $uid, '__expt' => $t );
    my $json = encode_json \%sess;

    #warn $json;

    my $cipher = Crypt::CBC->new(
        -key    => $key,
        -iv     => $iv,
        -header => 'none',
        -cipher => "Crypt::OpenSSL::AES",
        -literal_key => 1,
    );

    my $cookie = encode_base64( $cipher->encrypt($json), '' );

    #warn length($cookie);
    #warn $cookie;

    return $cookie;
}

sub bail_out(@) {
    Test::More::BAIL_OUT(@_);
}

sub trim ($) {
    my $s = shift;
    return undef if !defined $s;
    $s =~ s/^\s+|\s+$//g;
    $s =~ s/\n/ /gs;
    $s =~ s/\s{2,}/ /gs;
    $s;
}

sub expand_env_in_config ($) {
    my $config = shift;

    if ( !defined $config ) {
        return;
    }

    $config =~ s/\$(TEST_HTTP_[_A-Z0-9]+)/
        if (!defined $ENV{$1}) {
            Test::More::BAIL_OUT "No environment $1 defined.\n";
        }
        $ENV{$1}/eg;

    return $config;
}

sub join_arr(@) {
    my (%args) = @_;
    my $str = "";
    foreach my $key (sort keys %args) {
        my $val = $args{$key};
        if ( ref $val && ref $val eq 'ARRAY' ) {
            $str .= "$key";
            $str .= join_arr($val);
        }
        else {
            $str .= "$key$val";
        }
    }
    #warn $str;
    return $str;
}

sub secure_token($@) {
    my ($secret_key, %args) = @_;

    $args{'t'} = time();

    $args{'token'} = uc(md5_hex($secret_key. join_arr(%args) . $secret_key));

    return %args;
}

1;

