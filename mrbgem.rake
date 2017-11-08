MRuby::Gem::Specification.new('mruby-esp32-loop') do |spec|
  spec.license = 'MIT'
  spec.authors = 'ppibburr'

  spec.cc.include_paths << "#{build.root}/src"
end
