# frozen_string_literal: true

module Sass
  # The {Embedded} host for using dart-sass-embedded. Each instance creates
  # its own communication {Channel} with a dedicated compiler process.
  #
  # @example
  #   embedded = Sass::Embedded.new
  #   result = embedded.compile_string('h1 { font-size: 40px; }')
  #   result = embedded.compile('style.scss')
  #   embedded.close
  class Embedded
    def initialize
      @channel = Channel.new
    end

    # The {Embedded#compile} method.
    #
    # @return [CompileResult]
    # @raise [CompileError]
    def compile(path,
                load_paths: [],

                source_map: false,
                source_map_include_sources: false,
                style: :expanded,

                functions: {},
                importers: [],

                alert_ascii: false,
                alert_color: $stderr.tty?,
                logger: nil,
                quiet_deps: false,
                verbose: false)

      raise ArgumentError, 'path must be set' if path.nil?

      Protofier.from_proto_compile_response(
        Host.new(@channel).compile_request(
          path: path,
          source: nil,
          importer: nil,
          load_paths: load_paths,
          syntax: nil,
          url: nil,
          source_map: source_map,
          source_map_include_sources: source_map_include_sources,
          style: style,
          functions: functions,
          importers: importers,
          alert_color: alert_color,
          alert_ascii: alert_ascii,
          logger: logger,
          quiet_deps: quiet_deps,
          verbose: verbose
        )
      )
    end

    # The {Embedded#compile_string} method.
    #
    # @return [CompileResult]
    # @raise [CompileError]
    def compile_string(source,
                       importer: nil,
                       load_paths: [],
                       syntax: :scss,
                       url: nil,

                       source_map: false,
                       source_map_include_sources: false,
                       style: :expanded,

                       functions: {},
                       importers: [],

                       alert_ascii: false,
                       alert_color: $stderr.tty?,
                       logger: nil,
                       quiet_deps: false,
                       verbose: false)
      raise ArgumentError, 'source must be set' if source.nil?

      Protofier.from_proto_compile_response(
        Host.new(@channel).compile_request(
          path: nil,
          source: source,
          importer: importer,
          load_paths: load_paths,
          syntax: syntax,
          url: url,
          source_map: source_map,
          source_map_include_sources: source_map_include_sources,
          style: style,
          functions: functions,
          importers: importers,
          alert_color: alert_color,
          alert_ascii: alert_ascii,
          logger: logger,
          quiet_deps: quiet_deps,
          verbose: verbose
        )
      )
    end

    # The {Embedded#info} method.
    def info
      @info ||= "sass-embedded\t#{Host.new(@channel).version_request.implementation_version}"
    end

    def close
      @channel.close
    end

    def closed?
      @channel.closed?
    end
  end
end
