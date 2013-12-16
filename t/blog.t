# vim:set ft=perl ts=4 sw=4 et:

use Test::Http::LWP;


plan tests => 3 * blocks();


server_name("blog.qinxunw.com");
server_port_for_client(80);


run_tests();


__DATA__

=== TEST 1.0 : login
--- request
POST /user/login
--- post_data
username : douge
password : abc123
--- error_code: 302
--- response_headers_like
Content-Type: text/html.*
--- response_cookies_like
__luasess__ : .{10,}



=== TEST 2.0 : depend on login
--- depend_request
TEST 1.0 : login
--- request
GET /
--- error_code: 200
--- response_headers_like
Content-Type: text/html.*
--- response_body_like
[\s\S]*?douge[\s\S]*



=== TEST 3.0 : not depend on login
--- request
GET /
--- error_code: 200
--- response_headers_like
Content-Type: text/html.*
--- response_body_like
[\s\S]*?Register[\s\S]*
