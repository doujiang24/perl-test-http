package Test::Http::LWP;

use strict;
use warnings;
use JSON;

use Test::Base -Base;
use Test::LongString;

use LWP::UserAgent;

use URI::Escape;
use Digest::MD5 qw(md5_hex);

our $test_dir = "t/";
our $ServerName = "localhost";
our $ServerPortForClient = "80";
our $NoLongString = undef;

our %TestBlocksCache = ();
our %depend_resp = ();

our $UserAgent = LWP::UserAgent->new;
$UserAgent->agent('Perl testing');

sub join_arr(@);
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

sub encode_args(@) {
    my (%args) = @_;
    my @ret = ();

    while ( my ($key, $val) = each %args ) {
        push @ret, uri_escape($key) . "=" . uri_escape($val);
    }

    return join "&", @ret;
}

sub set_url($@) {
    my ($uri, %gets) = @_;

    my $get_data = encode_args(%gets);

    if ( index( $uri, "?" ) ge 0 ) {
        $uri .= "&" . $get_data;
    }
    else {
        $uri .= "?" . $get_data;
    }

    my $url = "http://$ServerName:$ServerPortForClient" . $uri;
    return $url;
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
    $uri = eval_str($uri);

    my @rest_lines = <$in>;
    close $in;

    my $data = join("", @rest_lines);
    #warn $data;
    my %gets = parse_data($data);

    return ( $method, $uri, %gets );
}

sub parse_data($) {
    my ($file) = @_;
    my %data = ();

    if ( ! defined $file ) {
        return %data;
    }

    open my $in, "<", \$file or die "can not open file;";

    while (<$in>) {
        s/^\s+|\s+$//g;
        my ($key, $val) = split /\s*:\s*/, expand_env_in_config($_), 2;
        $data{$key} = eval_str($val);
    }

    return %data;
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

            my %empty_hash = ();
            my $json = \%empty_hash;

            my $content = $resp->content();
            if ($content) {
                $content =~ m/({.*})/;

                if (defined $1) {
                    $json = decode_json $1;
                }
            }

            my %resp_data = ( 'resp' => $resp, 'json' => $json );
            $depend_resp{$i} = \%resp_data;

        #warn 'debug';
        }

        close $in;
    }

    my ($request_method, $request_uri, %gets) = parse_request($name, \$block->request);

    my %posts = parse_data($block->post_data);

    if ( defined $block->secret_key) {
        chomp( my $secret_key = $block->secret_key );
        if ( $request_method eq "GET" ) {
            %gets = secure_token($secret_key, %gets);
        }
        else {
            %posts = secure_token($secret_key, %posts);
        }
    }

    my $url = set_url($request_uri, %gets);

    my %headers = parse_data($block->more_headers);
    if ( %posts and ! $headers{'Content-Type'} ) {
        $headers{'Content-Type'} = 'application/x-www-form-urlencoded';
    }

    my $max_redirect = defined $block->max_redirect ? $block->max_redirect : 0;
    my $res =
      http_curl( $request_method, $url, encode_args(%posts),
        $max_redirect, %headers );
    return $res;
}

sub trim ($) {
    my $s = shift;
    return undef if !defined $s;
    $s =~ s/^\s+|\s+$//g;
    $s =~ s/\n/ /gs;
    $s =~ s/\s{2,}/ /gs;
    $s;
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
        my %headers = parse_data( $block->response_headers );
        while ( my ( $key, $val ) = each %headers ) {
            my $expected_val = $res->header($key);
            if ( !defined $expected_val ) {
                $expected_val = '';
            }
            is $expected_val, $val, "$name - header $key ok";
        }
    }
    elsif ( defined $block->response_headers_like ) {
        my %headers = parse_data( $block->response_headers_like );
        while ( my ( $key, $val ) = each %headers ) {
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
        my $expected = $block->response_body;
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
        my $expected_pat = $block->response_body_like;
        $expected_pat =~ s/\$ServerPortForClient\b/$ServerPortForClient/g;
        my $summary = trim($content);

        like( $content, qr/$expected_pat/s,
            "$name - response_body_like - response is expected ($summary)" );
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
