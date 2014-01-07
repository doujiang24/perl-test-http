package Test::Http::LWP;

use strict;
use warnings;
use JSON;

use URI::Escape;
use Test::Base -Base;
use Test::LongString;

use LWP::UserAgent;
use Test::HTTP::Response;

use Digest::MD5 qw(md5_hex);


use Test::Http::Util qw(
    bail_out
    trim
    aes_session_cookie
    encode_args
    expand_env_in_config
    secure_token
    join_arr
    encode_cookies
    parse_body_json
    deep_hash_val
);

our $test_dir = "t/";
our $ServerName = "localhost";
our $ServerPortForClient = "80";
our $NoLongString = undef;

our %TestBlocksCache = ();
our %depend_resp = ();
our %empty_hash = ();

our $UserAgent = LWP::UserAgent->new;
$UserAgent->agent('Perl testing');

sub query_request($);

our @EXPORT = qw(
    NoLongString
    run_tests
    plan
    server_name
    server_port_for_client
);

sub server_name (@) {
    if (@_) {
        $ServerName = shift;
    } else {
        return $ServerName;
    }
}

sub server_port_for_client (@) {
    if (@_) {
        $ServerPortForClient = shift;
    } else {
        return $ServerPortForClient;
    }
}

sub set_url($$$) {
    my ($server_name, $uri, $gets) = @_;

    chomp( $server_name = $server_name ? $server_name : $ServerName );
    my $get_data = encode_args(%$gets);

    if ( index( $uri, "?" ) ge 0 ) {
        $uri .= "&" . $get_data;
    }
    else {
        $uri .= "?" . $get_data;
    }

    my $url = "http://$server_name:$ServerPortForClient" . $uri;
    return $url;
}

sub eval_str($) {
    my $_ = shift;
    if ( !defined $_ ) {
        return '';
    }

    if ( m/^!eval/ ) {
        my $str = substr $_, 6;
        #warn $str;
        return eval $str;
    }
    return $_;
}

sub parse_request($$) {
    my ($name, $rrequest) = @_;

    open my $in, "<", $rrequest;
    my $first = <$in>;
    if (! $first) {
        Test::More::BAIL_OUT("$name - Request line shoud not be empty");
        die;
    }

    $first =~ s/^\s+|\s+$//g;
    my ($method, $uri) = split /\s+/, $first, 2;
    #warn $uri;
    $uri = eval_str($uri);

    my @rest_lines = <$in>;
    close $in;

    my $data = join("", @rest_lines);
    #warn $data;
    my $gets = parse_data($data);

    return ( $method, $uri, $gets );
}

sub parse_cookies($) {
    my $block = shift;

    my $cookies = parse_data($block->cookies);

    if ( defined $block->depend_request ) {
        while ( my($i, $resp_ref) = each %depend_resp ) {
            my $cookies_ref = $resp_ref->{'cookies'};

            while ( my ($k, $v) = each %$cookies_ref ) {
                $k = uri_unescape($k);
                $cookies->{$k} = uri_unescape($v->{'value'});
            }
        }
    }

    if ( !defined $block->user ) {
        return %$cookies;
    }

    open my $in, "<", \$block->user or die "can not open file";
    my $line = <$in>;
    close $in;

    my ($sid, $uid, $expt) = split /\s+/, expand_env_in_config($line), 3;

    my $user_cookie_key = $ENV{AES_COOKIE_KEY};
    my $user_cookie_val = aes_session_cookie($sid, $uid, $expt, $block->aes_session_key, $block->aes_session_iv);

    $cookies->{$user_cookie_key} = $user_cookie_val;

    return %$cookies;
}

# always return hash
sub parse_data($) {
    my ($file) = @_;
    my %data = ();

    if ( ! defined $file ) {
        return \%data;
    }

    open my $in, "<", \$file or die "can not open file;";

    while (<$in>) {
        s/^\s+|\s+$//g;
        my ($key, $val) = split /\s*:\s*/, expand_env_in_config($_), 2;
        $data{$key} = eval_str($val);
    }

    return \%data;
}

sub http_curl($$$$@) {
    my ($method, $url, $body, $max_redirect, %headers) = @_;

    #warn $method, $url, $body, $max_redirect, encode_args(%headers);
    my $req = HTTP::Request->new($method);

    while ( my ( $key, $val ) = each %headers ) {
        $req->header( $key => $val );
    }

    $req->url($url);

    $req->content($body);

    $UserAgent->max_redirect($max_redirect);

    my $res = $UserAgent->request($req);

    return $res;
}

sub query_request($) {
    my $block = shift;
    my $name = $block->name;

    if ( defined $block->depend_request ) {
        open my $in, "<", \$block->depend_request or die "can not open file";

        my $i = 1;
        while (<$in>) {
            chomp;
            my $block = $TestBlocksCache{$_};
            my $resp = query_request($block);

            my $content = $resp->content();
            my $json = parse_body_json($content);

            my $cookies = extract_cookies($resp) || \%empty_hash;
            my %resp_data = ( 'resp' => $resp, 'json' => $json, 'cookies' => $cookies );
            $depend_resp{$i} = \%resp_data;

            #warn 'debug';
        }

        close $in;
    }

    my ($request_method, $request_uri, $gets) = parse_request($name, \$block->request);

    my $posts = parse_data($block->post_data);

    my $headers = parse_data($block->more_headers);
    if ( $posts and ! $headers->{'Content-Type'} ) {
        $headers->{'Content-Type'} = 'application/x-www-form-urlencoded';
    }

    my %cookies = parse_cookies($block);
    if (%cookies) {
        $headers->{'Cookie'} = encode_cookies(%cookies);
        #warn encode_cookies(%cookies);
    }

    if ( defined $block->secret_key) {
        chomp( my $secret_key = $block->secret_key );
        if ( $request_method eq "GET" ) {
            $headers->{'Access-Token'} = secure_token($secret_key, $gets);
        }
        else {
            $headers->{'Access-Token'} = secure_token($secret_key, $posts);
        }
    }

    my $url = set_url($block->server_name, $request_uri, $gets);

    my $max_redirect = defined $block->max_redirect ? $block->max_redirect : 0;
    my $res =
      http_curl( $request_method, $url, encode_args(%$posts),
        $max_redirect, %$headers );
    return $res;
}

sub check_resp($$) {
    my ($block, $res) = @_;
    my $name = $block->name;

    #warn $res->code;
    #warn $res->content;
    if ( defined $block->error_code ) {
        is( $res->code, $block->error_code, "$name - status code ok" );
    }
    else {
        is( $res->code, 200, "$name - status code ok" );
    }

    if ( defined $block->response_headers ) {
        my $headers = parse_data( $block->response_headers );
        while ( my ( $key, $val ) = each %$headers ) {
            my $expected_val = $res->header($key);
            if ( !defined $expected_val ) {
                $expected_val = '';
            }
            is $expected_val, $val, "$name - header $key ok";
        }
    }
    elsif ( defined $block->response_headers_like ) {
        my $headers = parse_data( $block->response_headers_like );
        while ( my ( $key, $val ) = each %$headers ) {
            my $expected_val = $res->header($key);
            if ( !defined $expected_val ) {
                $expected_val = '';
            }
            like $expected_val, qr/^$val$/, "$name - header $key like ok";
        }
    }

    if ( defined $block->response_body ) {
        my $content = $res->content;
        if ( defined $content ) {
            $content =~ s/^TE: deflate,gzip;q=0\.3\r\n//gms;
        }

        $content =~ s/^Connection: TE, close\r\n//gms;
        chomp( my $expected = $block->response_body );
        $expected =~ s/\$ServerPortForClient\b/$ServerPortForClient/g;

        if ($NoLongString) {
            is( $content, $expected,
                "$name - response_body - response is expected" );
        }
        else {
            is_string( $content, $expected,
                "$name - response_body - response is expected" );
        }
    }
    elsif ( defined $block->response_body_like ) {
        my $content = $res->content;
        if ( defined $content ) {
            $content =~ s/^TE: deflate,gzip;q=0\.3\r\n//gms;
        }
        $content =~ s/^Connection: TE, close\r\n//gms;
        chomp( my $expected_pat = $block->response_body_like);
        $expected_pat =~ s/\$ServerPortForClient\b/$ServerPortForClient/g;
        my $summary = trim($content);

        like( $content, qr/$expected_pat/s,
            "$name - response_body_like - response is expected ($summary)" );
    }

    if (   defined $block->response_body_json
        || defined $block->response_body_json_like )
    {
        my $resp_json = parse_body_json( $res->content );
        my $json      = parse_data(
            defined $block->response_body_json
            ? $block->response_body_json
            : $block->response_body_json_like );

        while ( my ( $key, $val ) = each %$json ) {
            my @keys = split /\s*,\s*/, $key;
            my $expected_val = deep_hash_val($resp_json, \@keys);

            if ( !defined $expected_val ) {
                $expected_val = '';
            }

            if ( defined $block->response_body_json ) {
                is $expected_val, $val, "$name - body json $key ok";
            }
            else {
                like $expected_val, qr/^$val$/,
                  "$name - body json $key like ok";
            }
        }
    }

    my $resp_cookies_ref = extract_cookies($res) || \%empty_hash;
    my %resp_cookies = %$resp_cookies_ref;

    if ( defined $block->response_cookies ) {
        my $cookies = parse_data( $block->response_cookies );
        while ( my ( $key, $val ) = each %$cookies ) {
            my $expected_val = $resp_cookies{$key}{'value'};
            if ( !defined $expected_val ) {
                $expected_val = '';
            }
            is $expected_val, $val, "$name - cookie $key ok";
        }
    }
    elsif ( defined $block->response_cookies_like ) {
        my $cookies = parse_data( $block->response_cookies_like );
        while ( my ( $key, $val ) = each %$cookies ) {
            my $expected_val = $resp_cookies{$key}{'value'};
            if ( !defined $expected_val ) {
                $expected_val = '';
            }
            like $expected_val, qr/^$val$/, "$name - cookie $key like ok";
        }
    }
}

sub run_test ($) {
    my $block = shift;

    my $resp = query_request($block);

    check_resp($block, $resp);
}

sub run_tests () {
    %TestBlocksCache = ();

    my @blocks = Test::Base::blocks();
    for my $block (@blocks) {
        chomp(my $name = $block->name);
        $TestBlocksCache{$name} = $block;
    }

    for my $block (@blocks) {
        run_test($block);
    }

}
