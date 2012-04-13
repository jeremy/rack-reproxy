require 'rubygems'
require 'bundler/setup'
require 'minitest/unit'
MiniTest::Unit.autorun

require 'rack/reproxy'

class ReproxyTest < MiniTest::Unit::TestCase
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

  def test_reproxies_to_rack
    app   = ->(env) { [200, { 'foo' => 'a', 'bar' => 'baz', 'X-Reproxy-Url' => 'http://foo/bar?a=b' }, ['original']] }
    proxy = ->(env) { [204, { 'foo' => 'bar' }, env.values_at('HTTP_X_REPROXIED', 'HTTP_HOST', 'PATH_INFO', 'QUERY_STRING', 'HTTP_X_REPROXY_URL')] }
    status, headers, body = Rack::Reproxy::Rack.new(app, app: proxy).call({})
    assert_equal 204, status
    assert_equal 'bar', headers['foo']
    assert_equal 'baz', headers['bar']
    assert_equal ['1', 'foo', '/bar', 'a=b', nil], body
  end
end
