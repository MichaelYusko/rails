# frozen_string_literal: true

require "active_support/core_ext/class/attribute"

module ActiveModel
  # == Active \Model \Error
  #
  # Represents one single error
  class Error
    CALLBACKS_OPTIONS = [:if, :unless, :on, :allow_nil, :allow_blank, :strict]
    MESSAGE_OPTIONS = [:message]

    class_attribute :i18n_customize_full_message, default: false

    def self.full_message(attribute, message, base_class) # :nodoc:
      return message if attribute == :base
      attribute = attribute.to_s

      if i18n_customize_full_message && base_class.respond_to?(:i18n_scope)
        attribute = attribute.remove(/\[\d\]/)
        parts = attribute.split(".")
        attribute_name = parts.pop
        namespace = parts.join("/") unless parts.empty?
        attributes_scope = "#{base_class.i18n_scope}.errors.models"

        if namespace
          defaults = base_class.lookup_ancestors.map do |klass|
            [
              :"#{attributes_scope}.#{klass.model_name.i18n_key}/#{namespace}.attributes.#{attribute_name}.format",
              :"#{attributes_scope}.#{klass.model_name.i18n_key}/#{namespace}.format",
            ]
          end
        else
          defaults = base_class.lookup_ancestors.map do |klass|
            [
              :"#{attributes_scope}.#{klass.model_name.i18n_key}.attributes.#{attribute_name}.format",
              :"#{attributes_scope}.#{klass.model_name.i18n_key}.format",
            ]
          end
        end

        defaults.flatten!
      else
        defaults = []
      end

      defaults << :"errors.format"
      defaults << "%{attribute} %{message}"

      attr_name = attribute.tr(".", "_").humanize
      attr_name = base_class.human_attribute_name(attribute, default: attr_name)

      I18n.t(defaults.shift,
        default:  defaults,
        attribute: attr_name,
        message:   message)
    end

    def self.generate_message(attribute, type, base, options) # :nodoc:
      type = options.delete(:message) if options[:message].is_a?(Symbol)
      value = (attribute != :base ? base.send(:read_attribute_for_validation, attribute) : nil)

      options = {
        model: base.model_name.human,
        attribute: base.class.human_attribute_name(attribute),
        value: value,
        object: base
      }.merge!(options)

      if base.class.respond_to?(:i18n_scope)
        i18n_scope = base.class.i18n_scope.to_s
        defaults = base.class.lookup_ancestors.flat_map do |klass|
          [ :"#{i18n_scope}.errors.models.#{klass.model_name.i18n_key}.attributes.#{attribute}.#{type}",
            :"#{i18n_scope}.errors.models.#{klass.model_name.i18n_key}.#{type}" ]
        end
        defaults << :"#{i18n_scope}.errors.messages.#{type}"

        catch(:exception) do
          translation = I18n.translate(defaults.first, **options.merge(default: defaults.drop(1), throw: true))
          return translation unless translation.nil?
        end unless options[:message]
      else
        defaults = []
      end

      defaults << :"errors.attributes.#{attribute}.#{type}"
      defaults << :"errors.messages.#{type}"

      key = defaults.shift
      defaults = options.delete(:message) if options[:message]
      options[:default] = defaults

      I18n.translate(key, **options)
    end

    def initialize(base, attribute, type = :invalid, **options)
      @base = base
      @attribute = attribute
      @raw_type = type
      @type = type || :invalid
      @options = options
    end

    def initialize_dup(other)
      @attribute = @attribute.dup
      @raw_type = @raw_type.dup
      @type = @type.dup
      @options = @options.deep_dup
    end

    attr_reader :base, :attribute, :type, :raw_type, :options

    def message
      case raw_type
      when Symbol
        self.class.generate_message(attribute, raw_type, @base, options.except(*CALLBACKS_OPTIONS))
      else
        raw_type
      end
    end

    def detail
      { error: raw_type }.merge(options.except(*CALLBACKS_OPTIONS + MESSAGE_OPTIONS))
    end

    def full_message
      self.class.full_message(attribute, message, @base.class)
    end

    # See if error matches provided +attribute+, +type+ and +options+.
    def match?(attribute, type = nil, **options)
      if @attribute != attribute || (type && @type != type)
        return false
      end

      options.each do |key, value|
        if @options[key] != value
          return false
        end
      end

      true
    end

    def strict_match?(attribute, type, **options)
      return false unless match?(attribute, type)

      options == @options.except(*CALLBACKS_OPTIONS + MESSAGE_OPTIONS)
    end

    def ==(other)
      other.is_a?(self.class) && attributes_for_hash == other.attributes_for_hash
    end
    alias eql? ==

    def hash
      attributes_for_hash.hash
    end

    protected
      def attributes_for_hash
        [@base, @attribute, @raw_type, @options.except(*CALLBACKS_OPTIONS)]
      end
  end
end
