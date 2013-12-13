# vim:set ft=perl ts=4 sw=4 et:

use Test::Http::LWP @skip;


plan tests => 3 * blocks() + 1;


server_name("www.baidu.com");
server_port_for_client(80);


run_tests();


__DATA__

=== TEST 1.0 : index
--- request
GET /
--- error_code: 200
--- response_headers
Content-Type: text/html
--- response_body_like
.*?京ICP证030173号.*


=== TEST 2.0 : search 妈妈网
--- request
GET /s
wd: 妈妈网
--- error_code: 200
--- response_headers_like
Server: BWS.*
--- response_body_like
[\s\S]*?gzmama.com[\s\S]*
--- response_cookies_like
BAIDUID: .{10,}
