module Rack
  # = Reproxy
  #
  # Allow Rack responses to be proxied from a different URL. It's like
  # Rack::Sendfile, but for any HTTP backend.
  #
  # Rack apps can return a URI as a response body (or an X-Reproxy-Url header)
  # and we pass it upstream to Nginx/Apache/Lighttpd to serve.
  #
  # This is an approach pioneered by MogileFS using perlbal to reproxy file
  # requests to an internal storage backend.
  #
  # === Proxing to an internal app: serving private files
  #
  # Rack::Sendfile can efficiently serve files from the local filesystem.
  # But that means you have to have your files NFS-mounted on all your app
  # servers, and you have to know their physical paths.
  #
  # Instead, you can expose your file server as a private HTTP service and
  # reproxy requests to it. Get rid of fussy NFS mounts and just stream files
  # back from your internal server.
  #
  # === Proxying to yourself
  #
  # You can reproxy requests back to your own app, too. This is useful when you
  # you'd like to HTTP-cache private, authenticated content. You can't put a
  # public HTTP cache in front of your app, but you can put it in the middle!
  #
  # Your app receives a request, authenticates, and proxies its own response
  # via an internal HTTP cache that's backed by... your app.
  #
  # === Nginx
  #
  # # In config.ru
  #   use Rack::Reproxy::Nginx, location: '/reproxy'
  #
  # # Nginx config
  #   location /reproxy {
  #     internal;
  #     set $reproxy_url $upstream_http_x_reproxy_url;
  #     proxy_pass $reproxy_url;
  #   }
  #
  # === Apache with mod_reproxy
  #
  # # In config.ru
  #   use Rack::Reproxy::Apache
  #
  # # Apache config
  #   <Location />
  #     AllowReproxy on
  #     PreserveHeaders Content-Type Content-Disposition ETag Last-Modified
  #   </Location>
  #
  # === Lighttpd
  #
  # # In config.ru
  #   use Rack::Reproxy::Lighttpd
  #
  # # Lighttpd config
  #   proxy-core.allow-x-rewrite = "enable"
  #
  # === Rack
  #
  # Wait, what? Yeah, you can reproxy without doing an HTTP roundtrip by
  # immediately redispatching back to your own app. This only becomes useful
  # when you do something like reproxy through Rack::Cache.
  #
  # # In config.ru
  #   use Rack::Reproxy::Rack
  #
  # # To proxy to a different Rack app
  #   use Rack::Reproxy::Rack, app: SomeInternalApp.new
  #
  module Reproxy
    class Middleware
      def initialize(app, options = {})
        @app = app
        @header = options.fetch(:header, 'X-Reproxy-Url')
        @scrub_reproxy_header = "HTTP_#{@header.gsub('-', '_').upcase}"
      end

      def call(env)
        # Don't let clients ask us to reproxy URLs.
        env.delete(@scrub_reproxy_header)

        # In case the Rack app would like to know which header to set.
        env['rack.reproxy.header'] ||= @header

        status, headers, body = @app.call(env)

        # Reproxy URI response bodies.
        if body.is_a?(URI)
          reproxy env, status, headers.merge(@header => body.to_s), body

        # Reproxy explicit requests to respond with a different URL.
        elsif headers.include?(@header)
          reproxy env, status, headers, body

        # Pass through the response, otherwise.
        else
          [status, headers, body]
        end
      end

      private
      def reproxy(env, status, headers, body)
        [status, headers.merge('X-Reproxied' => '1'), []]
      end
    end

    # Nginx relies on an upstream /reproxy location that proxies to
    # X-Reproxy-Url. So we just return an X-Accel-Redirect: /reproxy header.
    class Nginx < Middleware
      def initialize(app, options = {})
        super
        @location = options.fetch(:location, '/reproxy')
      end

      private
      def reproxy(env, status, headers, body)
        super.tap do |response|
          response[1]['X-Accel-Redirect'] = @location
        end
      end
    end

    # Apache with mod_reproxy uses X-Reproxy-Url directly.
    class Apache < Middleware
    end

    # Lighttpd uses X-Rewrite-URI and X-Rewrite-Host response headers.
    # Be sure to set proxy-core.allow-x-rewrite in your lighty config.
    class Lighttpd < Middleware
      private
      def reproxy(env, status, headers, body)
        super.tap do |response|
          uri = URI(headers[@header])
          response[1]['X-Rewrite-Host'] = uri.hostname
          response[1]['X-Rewrite-URI']  = uri.request_uri
        end
      end
    end

    # Rack dispatches the request again and returns the proxied response
    # with its headers merged onto the original response's.
    class Rack < Middleware
      def initialize(app, options = {})
        super
        @proxy_to = options.fetch(:app, app)
      end

      private
      def reproxy(env, status, headers, body)
        uri = URI(headers.delete(@header))

        proxy_env = env.merge 'HTTP_X_REPROXIED' => '1',
          'HTTP_HOST'     => uri.host,
          'PATH_INFO'     => uri.path,
          'QUERY_STRING'  => uri.query

        proxied_status, proxied_headers, proxied_body = @proxy_to.call(proxy_env)
        [proxied_status, headers.merge(proxied_headers), proxied_body]
      end
    end
  end
end
