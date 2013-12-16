Name
==============
Test::HTTP - Testing modules for http api


Synopsis
==============
```perl
use Test::Http::LWP;
plan tests => 3 * blocks() + 1;

server_name("www.baidu.com");
server_port_for_client(80);

$ENV{TEST_HTTP_UA} = "Test::Http";

run_tests();

__DATA__

=== TEST 1.0 : index
--- request
GET /
--- more_headers
User-Agent : $TEST_HTTP_UA
--- error_code: 200
--- response_headers
Content-Type: text/html
--- response_body_like
.*?京ICP证030173号.*
```

it will http request http://www.baidu.com/ with user-agent: Test::Http

and check the http response:

    1. http status code = 200
    2. http header, Content-Type = "text/html"
    3. http body, like /^.*?京ICP证030173号.*$/



Standard Macro Variables
==============


$ENV{TEST_HTTP_var_name}
------------
the env variables that will auto replace the ```$TEST_HTTP_var_name```


key => value data
------------
we mostly use this way to express key => value data
```
foo: bar
key : $TEST_HTTP_KEY
key2: !eval return md5('abc')
```
it means the hash ( key => value in perl )
```perl
(
    'foo' => 'bar',
    'key' => $ENV{TEST_HTTP_KEY},
    'key2' => md5(abc)
)
```


request input command
=============

request
------------
example:
```perl
--- request
GET /pageview
uid : 100
foo : bar
```
will run : ```GET /pageview?uid=100&foo=bar```


post_data
------------
example:
```perl
--- post_data
uid : 100
foo : bar
```

will send http body: ```uid=100&foo=bar```

and http header:
```
Content-Type:application/x-www-form-urlencoded
```

cookies
------------
example:
```perl
--- cookies
key : foo+bar
key2: val2
```

it will send http header:
```
Cookie:key=foo%2Bbar; key2=val2
```

user
------------
this command will auto encrypt (aes-256-cbc) and add to cookie

example:
```perl
--- user
sid uid expt
```
will add to the cookie key => value:

$ENV{AES_COOKIE_KEY} => encrypt(sid, uid, expt)

you may change to own way in sub parse_cookies (lib/Test/Http/LWP.pm)

more_headers
------------
this command will set http header

example:
```
--- more_headers
User-Agent: BaiduSpider
Referer : http://www.baidu.com/
```

secret_key
------------
this will auto send the auth token encrypt by secret_key

the token is encrypt by the most popular way (sub secure_token in lib/Test/Http/Util.pm)

example:
```
--- secret_key
abc
--- request
GET /pv
hello:world
foo:bar
```
will send:
```
GET /pv?hello=world&foo=bar&t=TIME&token=TOKEN
TIME = time()
TOKEN = md5(securehelloworldfoobartTIMEsecure)
```

depend_request
------------
this command means the depend request will done before the current

and the http response will be store in ```$depend_resp```

that can be used as Macro Variables

hash value ```( cookies => hash, json => encode_json(http body), resp => http response )```

And the Set-cookie will be used in the current request as cookie


example:
```
--- depend_request
TEST NAME
```
it means depend another request in the test case named "TEST NAME"


max_redirect
------------
the max redirect num to follow http redirect, default 0

server_name
------------
the value for the http header Host


Response check
==============

error_code
------------
check the HTTP Status Code, default 200


response_headers
------------
example:
```
Content-Type: text/html
Server: openresty
```
will check the http Response header, by ```is``` in Test::Base

    Content-Type = "text/html"
    Server = "openresty"


response_headers_like
------------
example:
```
Server: openresty.*
```

will check the http Response header, by ```like``` in Test::Base

Server like /^openresty.*$/



response_cookies
------------
check the Response cookies values

response_cookies_like
------------
check the Response cookies values

response_body
------------
check the Response http body

response_body_like
------------
check the Response http body

response_body_json
------------
check the response http body

this will json_decode the body first
```
[callback]{"status":1,"data":{"uid":"helloworld"}}
```
will decode to key => value
```
{
    "status" => 1,
    "data" => (
        "uid" => "helloworld",
    ),
}
```
we can check the values specified by key

```
--- response_body_json
data,uid : helloworld
```
```data, uid``` means ```$json_hash->{'data'}->{'uid'}```

response_body_json_like
------------
check the http response body json


See Also
==============
<https://github.com/doujiang24/perl-test-http/tree/master/t>

<http://uncledou.org/archives/50>
