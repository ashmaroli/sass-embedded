#!/usr/bin/env ruby
# frozen_string_literal: true

require 'mkmf'
require 'json'
require 'open-uri'
require 'fileutils'
require_relative '../lib/sass/platform'

module Sass
  class Extconf

    def initialize
      get_with_config('sass-embedded', true) do latest_sass_embedded; end
      get_with_config('sass-embedded-protocol', true) do latest_sass_embedded_protocol; end
      get_with_config('protoc', true) do latest_protoc; end
    end

    private

    def get_with_config(config, default)
      val = with_config(config, default)
      case val
      when true
        if block_given?
          get yield
        else
          get default
        end
      when false
      else
        get val
      end
    end

    def get(uri_s)
      uri = URI.parse(uri_s)
      path = File.absolute_path(File.basename(uri.path), __dir__)
      if uri.is_a? URI::File
        FileUtils.copy_file uri.path, path
      else
        uri.open do |source|
          File.open(path, 'wb') do |destination|
            destination.write source.read
          end
        end
      end
    rescue StandardError
      raise "Failed to get: #{uri}"
    end

    def latest_release(repo, include_prerelease = false)
      if include_prerelease
        headers = {}
        headers['Authorization'] = "token #{ENV['GITHUB_TOKEN']}" if ENV['GITHUB_TOKEN']
        URI.parse("https://api.github.com/repos/#{repo}/releases").open(headers) do |file|
          JSON.parse(file.read)[0]['tag_name']
        end
      else
        URI.parse("https://github.com/#{repo}/releases/latest").open do |file|
          File.basename file.base_uri.to_s
        end
      end
    end

    def latest_sass_embedded
      repo = 'sass/dart-sass-embedded'

      # TODO, don't use prerelease once a release is available
      tag_name = latest_release repo, true

      os = case Sass::Platform::OS
           when 'darwin'
             'macos'
           when 'linux'
             'linux'
           when 'windows'
             'windows'
           else
             raise "Unsupported OS: #{Sass::Platform::OS}"
           end

      arch = case Sass::Platform::ARCH
             when 'x86_64'
               'x64'
             when 'i386'
               'ia32'
             else
               raise "Unsupported Arch: #{Sass::Platform::ARCH}"
             end

      ext = case os
            when 'windows'
              'zip'
            else
              'tar.gz'
            end

      "https://github.com/#{repo}/releases/download/#{tag_name}/sass_embedded-#{tag_name}-#{os}-#{arch}.#{ext}"
    end

    def latest_protoc
      repo = 'protocolbuffers/protobuf'

      tag_name = latest_release repo

      os = case Sass::Platform::OS
           when 'darwin'
             'osx'
           when 'linux'
             'linux'
           when 'windows'
             'win'
           else
             raise "Unsupported OS: #{Sass::Platform::OS}"
           end

      arch = case Sass::Platform::ARCH
             when 'aarch64'
               'aarch_64'
             when 'sparcv9'
               's390'
             when 'i386'
               'x86_32'
             when 'x86_64'
               'x86_64'
             when 'powerpc64'
               'ppcle_64'
             else
               raise "Unsupported Arch: #{Sass::Platform::ARCH}"
             end

      os_arch = case os
                when 'win'
                  os + arch.split('_').last
                else
                  "#{os}-#{arch}"
                end

      ext = 'zip'

      "https://github.com/#{repo}/releases/download/#{tag_name}/protoc-#{tag_name[1..-1]}-#{os_arch}.#{ext}"
    end

    def latest_sass_embedded_protocol
      repo = 'sass/embedded-protocol'

      # TODO: use latest release once available
      # tag_name = latest_release repo
      tag_name = 'HEAD'

      "https://raw.githubusercontent.com/#{repo}/#{tag_name}/embedded_sass.proto"
    end
  end
end

Sass::Extconf.new