# frozen_string_literal: true

require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = "proto/spec/**/*_spec.rb"
end

namespace :protos do
  desc "Vendor the .proto sources from the pinned upstream tags"
  task :sync do
    sh "bin/sync_protos"
  end

  desc "Regenerate proto/lib/hiero/proto/** from proto/hapi/"
  task :generate do
    sh "bin/generate_protos"
  end

  desc "Fail if the committed generated output is stale"
  task check: :generate do
    sh "git diff --exit-code -- proto/lib" do |ok, _res|
      unless ok
        abort "generated protobuf output is out of date -- run bin/generate_protos and commit the result"
      end
    end
  end
end

desc "Build the hiero-proto gem"
task :build do
  pkg = File.expand_path("pkg", __dir__)
  mkdir_p pkg

  # The licence files live once at the repository root and are copied into the
  # gem directory at build time. They cannot be symlinks: RubyGems builds a gem
  # containing them happily and then refuses to install it, because the symlink
  # points outside the gem's own directory.
  %w[LICENSE NOTICE].each { |f| cp f, "proto/#{f}" }

  begin
    # RubyGems validates spec.files against the working directory, so the gem has
    # to be built from inside proto/ rather than from the repository root.
    Dir.chdir("proto") do
      sh "gem build hiero-proto.gemspec --output #{pkg}/hiero-proto.gem"
    end
  ensure
    %w[LICENSE NOTICE].each { |f| rm_f "proto/#{f}" }
  end
end

task default: :spec
