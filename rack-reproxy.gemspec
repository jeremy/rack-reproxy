Gem::Specification.new do |s|
  s.name    = 'rack-reproxy'
  s.version = '1.0.0'
  s.author  = 'Jeremy Kemper'
  s.email   = 'jeremy@bitsweat.net'
  s.summary = 'Your Rack app can redispatch a response to a different URL, kind of like doing an internal redirect.'
  s.license = 'MIT'

  s.required_ruby_version = '>= 1.9'

  s.add_dependency 'rack'

  s.add_development_dependency 'rake'
  s.add_development_dependency 'minitest'

  s.files = Dir["#{File.dirname(__FILE__)}/**/*"]
end
