# Unit tests for Test::Http::LWP::parse_request
use Test::Http::LWP tests => 1;

my $name = "GET /foo only";
my %empty_hash = ();
my %result = ( 'foo' => 'bar' );

is_deeply( Test::Http::LWP::parse_data("foo:bar"),
    \%result, $name );
