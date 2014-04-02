Rack::Reproxy [![Build Status](https://secure.travis-ci.org/jeremy/rack-reproxy.png)](http://travis-ci.org/jeremy/rack-reproxy)
=============

Allow Rack responses to be proxied from a different URL. It's like
Rack::Sendfile, but for any HTTP backend.

Rack apps can return a `URI` as a response body (or an `X-Reproxy-Url` header)
and we pass it upstream to Nginx/Apache/Lighttpd to serve.

This is an approach pioneered by MogileFS using perlbal to reproxy file
requests to an internal storage backend.


Proxing to an internal app: serving private files
-------------------------------------------------

Rack::Sendfile can efficiently serve files from the local filesystem.
But that means you have to have your files NFS-mounted on all your app
servers, and you have to know their physical paths.

Instead, you can expose your file server as a private HTTP service and
reproxy requests to it. Get rid of fussy NFS mounts and just stream files
back from your internal server.


Proxying to yourself
--------------------

You can reproxy requests back to your own app, too. This is useful when you
you'd like to HTTP-cache private, authenticated content. You can't put a
public HTTP cache in front of your app, but you can put it in the middle!

Your app receives a request, authenticates, and proxies its own response
via an internal HTTP cache that's backed by... your app.

Nginx
-----

In config.ru

```ruby
use Rack::Reproxy::Nginx, location: '/reproxy'
```

Nginx config

    location /reproxy {
      internal;
      set $reproxy_url $upstream_http_x_reproxy_url;
      proxy_pass $reproxy_url;
    }


Apache with mod\_reproxy
------------------------

In config.ru

```ruby
use Rack::Reproxy::Apache
```

Apache config. Requires the [mod_reproxy](https://github.com/jamis/mod_reproxy) module.

    <Location />
      AllowReproxy on
      PreserveHeaders Content-Type Content-Disposition ETag Last-Modified
    </Location>


Lighttpd
--------

In config.ru

```ruby
use Rack::Reproxy::Lighttpd
```

Lighttpd config

    proxy-core.allow-x-rewrite = "enable"


Rack
----

Wait, what? Yeah, you can reproxy without doing an HTTP roundtrip by
immediately redispatching back to your own app. This becomes useful
when you do something like reproxy through Rack::Cache or want to
emulate your nginx/apache reproxies in dev/test with Rack only.

In config.ru

```ruby
# To proxy to self
use Rack::Reproxy::Rack

# To proxy to a different Rack app
use Rack::Reproxy::Rack, app: SomeInternalApp.new
```
