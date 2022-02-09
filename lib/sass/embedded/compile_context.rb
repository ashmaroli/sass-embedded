# frozen_string_literal: true

require_relative '../embedded_protocol'
require_relative '../logger/source_span'
require_relative 'observer'

module Sass
  class Embedded
    # The {Observer} for {Embedded#compile}.
    class CompileContext
      include Observer

      def initialize(channel,
                     path:,
                     source:,

                     importer:,
                     load_paths:,
                     syntax:,
                     url:,

                     source_map:,
                     source_map_include_sources:,
                     style:,

                     functions:,
                     importers:,

                     alert_ascii:,
                     alert_color:,
                     logger:,
                     quiet_deps:,
                     verbose:)
        @path = path
        @source = source

        @importer = to_struct(importer)
        @load_paths = load_paths
        @syntax = syntax
        @url = url

        @source_map = source_map
        @source_map_include_sources = source_map_include_sources
        @style = style

        @global_functions = functions.keys.map(&:to_s)

        @functions = functions.transform_keys do |key|
          key.to_s.split('(')[0].chomp
        end
        @importers = importers.map do |obj|
          to_struct(obj)
        end

        @alert_ascii = alert_ascii
        @alert_color = alert_color

        @logger = to_struct(logger)

        @quiet_deps = quiet_deps
        @verbose = verbose

        super(channel)

        send_message compile_request
      end

      def update(error, message)
        raise error unless error.nil?

        case message
        when EmbeddedProtocol::OutboundMessage::CompileResponse
          return unless message.id == id

          Thread.new do
            super(nil, message)
          end
        when EmbeddedProtocol::OutboundMessage::LogEvent
          return unless message.compilation_id == id

          log message
        when EmbeddedProtocol::OutboundMessage::CanonicalizeRequest
          return unless message.compilation_id == id

          Thread.new do
            send_message canonicalize_response message
          end
        when EmbeddedProtocol::OutboundMessage::ImportRequest
          return unless message.compilation_id == id

          Thread.new do
            send_message import_response message
          end
        when EmbeddedProtocol::OutboundMessage::FileImportRequest
          return unless message.compilation_id == id

          Thread.new do
            send_message file_import_response message
          end
        when EmbeddedProtocol::OutboundMessage::FunctionCallRequest
          return unless message.compilation_id == id

          Thread.new do
            send_message function_call_response message
          end
        end
      rescue StandardError => e
        Thread.new do
          super(e, nil)
        end
      end

      private

      def log(event)
        case event.type
        when :DEBUG
          if @logger.respond_to? :debug
            @logger.debug(event.message, span: Logger::SourceSpan.from_proto(event.span))
          else
            Kernel.warn(event.formatted)
          end
        when :DEPRECATION_WARNING
          if @logger.respond_to? :warn
            @logger.warn(event.message, deprecation: true,
                                        span: Logger::SourceSpan.from_proto(event.span),
                                        stack: event.stack_trace)
          else
            Kernel.warn(event.formatted)
          end
        when :WARNING
          if @logger.respond_to? :warn
            @logger.warn(event.message, deprecation: false,
                                        span: Logger::SourceSpan.from_proto(event.span),
                                        stack: event.stack_trace)
          else
            Kernel.warn(event.formatted)
          end
        end
      end

      def compile_request
        EmbeddedProtocol::InboundMessage::CompileRequest.new(
          id: id,
          string: unless @source.nil?
                    EmbeddedProtocol::InboundMessage::CompileRequest::StringInput.new(
                      source: @source,
                      url: @url&.to_s,
                      syntax: to_proto_syntax(@syntax),
                      importer: @importer.nil? ? nil : to_proto_importer(@importer, @importers.length)
                    )
                  end,
          path: @path,
          style: to_proto_output_style(@style),
          source_map: @source_map,
          source_map_include_sources: @source_map_include_sources,
          importers: to_proto_importers(@importers, @load_paths),
          global_functions: @global_functions,
          alert_ascii: @alert_ascii,
          alert_color: @alert_color
        )
      end

      def canonicalize_response(canonicalize_request)
        importer = importer_of_id canonicalize_request.importer_id
        url = importer.canonicalize(canonicalize_request.url, from_import: canonicalize_request.from_import)&.to_s

        EmbeddedProtocol::InboundMessage::CanonicalizeResponse.new(
          id: canonicalize_request.id,
          url: url
        )
      rescue StandardError => e
        EmbeddedProtocol::InboundMessage::CanonicalizeResponse.new(
          id: canonicalize_request.id,
          error: e.message
        )
      end

      def import_response(import_request)
        importer = importer_of_id import_request.importer_id
        importer_result = to_struct importer.load(import_request.url)

        EmbeddedProtocol::InboundMessage::ImportResponse.new(
          id: import_request.id,
          success: EmbeddedProtocol::InboundMessage::ImportResponse::ImportSuccess.new(
            contents: importer_result.contents,
            syntax: to_proto_syntax(importer_result.syntax),
            source_map_url: importer_result.respond_to?(:source_map_url) ? importer_result.source_map_url&.to_s : nil
          )
        )
      rescue StandardError => e
        EmbeddedProtocol::InboundMessage::ImportResponse.new(
          id: import_request.id,
          error: e.message
        )
      end

      def file_import_response(file_import_request)
        importer = importer_of_id file_import_request.importer_id
        file_url = importer.find_file_url(file_import_request.url, from_import: file_import_request.from_import)&.to_s

        raise "file_url must be a file: URL, was \"#{file_url}\"" if !file_url.nil? && !file_url.start_with?('file:')

        EmbeddedProtocol::InboundMessage::FileImportResponse.new(
          id: file_import_request.id,
          file_url: file_url
        )
      rescue StandardError => e
        EmbeddedProtocol::InboundMessage::FileImportResponse.new(
          id: file_import_request.id,
          error: e.message
        )
      end

      def function_call_response(function_call_request)
        EmbeddedProtocol::InboundMessage::FunctionCallResponse.new(
          id: function_call_request.id,
          success: @functions[function_call_request.name].call(*function_call_request.arguments),
          accessed_argument_lists: function_call_request.arguments
          .filter { |argument| argument.value == :argument_list }
          .map { |argument| argument.argument_list.id }
        )
      rescue StandardError => e
        EmbeddedProtocol::InboundMessage::FunctionCallResponse.new(
          id: function_call_request.id,
          error: e.message
        )
      end

      def to_proto_syntax(syntax)
        case syntax&.to_sym
        when :scss
          EmbeddedProtocol::Syntax::SCSS
        when :indented
          EmbeddedProtocol::Syntax::INDENTED
        when :css
          EmbeddedProtocol::Syntax::CSS
        else
          raise ArgumentError, 'syntax must be one of :scss, :indented, :css'
        end
      end

      def to_proto_output_style(style)
        case style&.to_sym
        when :expanded
          EmbeddedProtocol::OutputStyle::EXPANDED
        when :compressed
          EmbeddedProtocol::OutputStyle::COMPRESSED
        else
          raise ArgumentError, 'style must be one of :expanded, :compressed'
        end
      end

      def to_proto_importer(importer, id)
        is_importer = importer.respond_to?(:canonicalize) && importer.respond_to?(:load)
        is_file_importer = importer.respond_to?(:find_file_url)

        if is_importer && !is_file_importer
          EmbeddedProtocol::InboundMessage::CompileRequest::Importer.new(
            importer_id: id
          )
        elsif is_file_importer && !is_importer
          EmbeddedProtocol::InboundMessage::CompileRequest::Importer.new(
            file_importer_id: id
          )
        else
          raise ArgumentError, 'importer must be an Importer or a FileImporter'
        end
      end

      def to_proto_importers(importers, load_paths)
        proto_importers = importers.map.with_index do |importer, id|
          to_proto_importer(importer, id)
        end

        load_paths.each do |load_path|
          proto_importers << EmbeddedProtocol::InboundMessage::CompileRequest::Importer.new(
            path: File.absolute_path(load_path)
          )
        end

        proto_importers
      end

      def importer_of_id(id)
        if id == @importers.length
          @importer
        else
          @importers[id]
        end
      end

      def to_struct(obj)
        return obj unless obj.is_a? Hash

        struct = Object.new
        obj.each do |key, value|
          if value.respond_to? :call
            struct.define_singleton_method key.to_sym do |*args, **kwargs|
              value.call(*args, **kwargs)
            end
          else
            struct.define_singleton_method key.to_sym do
              value
            end
          end
        end
        struct
      end
    end
  end
end
