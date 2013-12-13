perl-test-http
==============


request input config
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

result: http://servername/pageview?uid=100&foo=bar

post_data
------------

cookies
------------

user
------------

more_headers
------------

secret_key
------------

depend_request
------------

max_redirect
------------

server_name
------------



Response check
==============

error_code
------------

response_headers
------------

response_headers_like
------------


response_cookies
------------

response_cookies_like
------------

response_body
------------

response_body_like
------------

response_body_json
------------

response_body_json_like
------------


See Also
==============
<http://uncledou.org/archives/50>
