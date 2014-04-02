require 'rubygems'
require 'bundler/setup'
require 'minitest/autorun'

require 'rack/reproxy'

class ReproxyTest < Minitest::Test
  def setup
    @app = ->(env) { [200, { 'X-Reproxy-Url' => uri }, URI(uri)] }
  end

  def test_normal_responses_pass_through
    assert_equal [200, {}, []], Rack::Reproxy::Middleware.new(->(env) { [200, {}, []] }).call({})
  end

  def test_scrubs_incoming_reproxy_header
    assert_equal [''], Rack::Reproxy::Middleware.new(->(env) { [200, {}, [env['HTTP_X_REPROXY_URL'].to_s]] }).call({ 'HTTP_X_REPROXY_URL' => 'malicious' })[2]
  end

  def test_informs_app_of_the_reproxy_header
    assert_equal ['X-Reproxy-Url'], Rack::Reproxy::Middleware.new(->(env) { [200, {}, [env['rack.reproxy.header']]] }).call({})[2]
  end

  def test_reproxies_uri_bodies
    status, headers, body = Rack::Reproxy::Middleware.new(->(env) { [200, {}, URI('foo')] }).call({})
    assert_equal 200, status
    assert_equal 'foo', headers['X-Reproxy-Url']
    assert_equal '1', headers['X-Reproxied']
    assert_equal [], body
  end

  def test_reproxies_response_header
    status, headers, body = Rack::Reproxy::Middleware.new(->(env) { [200, { 'X-Reproxy-Url' => 'foo' }, []] }).call({})
    assert_equal 200, status
    assert_equal 'foo', headers['X-Reproxy-Url']
    assert_equal '1', headers['X-Reproxied']
    assert_equal [], body
  end

  def test_reproxies_to_nginx
    status, headers, body = Rack::Reproxy::Nginx.new(->(env) { [200, { 'X-Reproxy-Url' => 'foo' }, []] }).call({})
    assert_equal 200, status
    assert_equal 'foo', headers['X-Reproxy-Url']
    assert_equal '1', headers['X-Reproxied']
    assert_equal '/reproxy', headers['X-Accel-Redirect']
    assert_equal [], body
  end

  def test_reproxies_to_lighttpd
    status, headers, body = Rack::Reproxy::Lighttpd.new(->(env) { [200, { 'X-Reproxy-Url' => 'http://foo/bar?a=b' }, []] }).call({})
    assert_equal 200, status
    assert_equal 'http://foo/bar?a=b', headers['X-Reproxy-Url']
    assert_equal '1', headers['X-Reproxied']
    assert_equal 'foo', headers['X-Rewrite-Host']
    assert_equal '/bar?a=b', headers['X-Rewrite-URI']
    assert_equal [], body
  end
end

class RackReproxyTest < Minitest::Test
  def test_reproxies_to_rack
    app   = ->(env) { [200, { 'foo' => 'a', 'bar' => 'baz', 'X-Reproxy-Url' => 'http://foo/bar?a=b' }, ['original']] }
    proxy = ->(env) { [204, { 'foo' => 'bar' }, env.values_at('HTTP_X_REPROXIED', 'HTTP_HOST', 'PATH_INFO', 'QUERY_STRING', 'HTTP_X_REPROXY_URL')] }
    status, headers, body = Rack::Reproxy::Rack.new(app, app: proxy).call({})
    assert_equal 204, status
    assert_equal 'bar', headers['foo']
    assert_equal 'baz', headers['bar']
    assert_equal ['1', 'foo', '/bar', 'a=b', nil], body
  end

  def test_respects_existing_script_name
    app   = ->(env) { [200, { 'X-Reproxy-Url' => 'http://foo/bar/baz' }, ['original']] }
    proxy = ->(env) { [200, {}, env.values_at('SCRIPT_NAME', 'PATH_INFO')] }
    status, headers, body = Rack::Reproxy::Rack.new(app, app: proxy).call({ 'SCRIPT_NAME' => '/bar' })
    assert_equal ['/bar', '/baz'], body
  end

  def test_chained_reproxy
    app = ->(env) do
      case env['PATH_INFO']
      when '/one'
        [200, { 'X-Reproxy-Url' => 'http://foo/two' }, []]
      when '/two'
        env['HTTP_X_REPROXIED'] = nil
        [200, { 'X-Reproxy-Url' => 'http://foo/three' }, []]
      else
        [200, {}, env['PATH_INFO']]
      end
    end
    status, headers, body = Rack::Reproxy::Rack.new(app).call({ 'PATH_INFO' => '/one' })
    assert_equal '/three', body
  end
end
