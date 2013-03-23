Gem::Specification.new do |s|
  s.name = 'lrun-ruby'
  s.version = '0.1.1'
  s.date = Date.civil(2013,3,23)
  s.summary = 'Ruby binding for lrun'
  s.description = 'Ruby binding for lrun, a standalone executable designed to run programs with limited resources under Linux.'
  s.authors = ["Wu Jun"]
  s.email = 'quark@zju.edu.cn'
  s.homepage = 'https://github.com/quark-zju/lrun-ruby'
  s.require_paths = ['lib']
  s.licenses = ['MIT']
  s.has_rdoc = 'yard'
  s.files = %w(LICENSE README.md Rakefile lrun-ruby.gemspec)
  s.files += Dir.glob("lib/**/*.rb")
  s.files += Dir.glob("spec/**/*.rb")
  s.add_development_dependency 'rake', '>= 10.0'
  s.add_development_dependency 'rspec', '>= 2.13'
  s.add_development_dependency 'yard', '>= 0.8'
  s.test_files = Dir['spec/**/*.rb']
end
