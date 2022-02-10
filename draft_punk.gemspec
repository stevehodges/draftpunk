# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'draft_punk/version'

Gem::Specification.new do |spec|
  spec.name          = "draft_punk"
  spec.version       = DraftPunk::VERSION
  spec.authors       = ["Steve Hodges"]
  spec.email         = ["steve.hodges@localstake.com"]

  spec.summary       = %q{Easy editing of a draft version of an ActiveRecord model and its associations, and publishing said draft's changes back to the original models.}
  spec.description   = <<-EOF
DraftPunk allows editing of a draft version of an ActiveRecord model and its associations.

When it's time to edit, a draft version is created in the same table as the object. You can specify which associations should also be edited and stored with that draft version. All associations are stored in their native table.

When it's time to publish, any attributes changed on your draft object persist to the original object. All associated objects behave the same way. Any associated have_many objects which are deleted on the draft are deleted on the original object.

This gem doesn't rely on a versioning gem and doesn't store incremental diffs of the model. It simply works with your existing database (plus one new column on your original object).
EOF
  spec.homepage      = "https://github.com/stevehodges/draftpunk"
  spec.license       = "MIT"
  spec.has_rdoc      = 'yard'


  spec.required_ruby_version  = ">= 2.0.0"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency     "amoeba",    "~> 3.1"
  spec.add_runtime_dependency     "differ",    "< 0.2"
  spec.add_runtime_dependency     'rails',     ">= 5.0", "< 6.1"

  spec.add_development_dependency "bundler",   "~> 1.9"
  spec.add_development_dependency "rake",      "~> 10.0"
  spec.add_development_dependency "rspec",     "~> 2.0"
  spec.add_development_dependency 'appraisal', '~> 2.2'
  spec.add_development_dependency "timecop",   "~> 0.1"
  spec.add_development_dependency "sqlite3",   "~> 1.0"
  spec.add_development_dependency "yard",      "< 1.0"

end
