Gem::Specification.new do |s|
  s.name    = 'rack-reproxy'
  s.version = '1.0.1'
  s.author  = 'Jeremy Kemper'
  s.email   = 'jeremy@bitsweat.net'
  s.summary = 'Redispatch your response via another URL. Like a transparent, internal HTTP redirect.'
  s.license = 'MIT'

  s.required_ruby_version = '>= 1.9'

  s.add_runtime_dependency 'rack'

  s.add_development_dependency 'rake', '~> 10.2'
  s.add_development_dependency 'minitest', '~> 5.3'

  s.files = Dir["#{File.dirname(__FILE__)}/lib/**/*.rb"]
end
