#!/usr/bin/ruby
# This script parses files in app to build up a listing of used translations
# and compare it with your local file
require 'optparse'

module UnusedTranslations
  #RAILS_ROOT = File.join(File.dirname(__FILE__), ['..'] * 4)

  class Translation
    attr_accessor :key, :file

    def to_hash
      k = full_key.split('.')
      hash = nil
      k.reverse.each do |k|
        old_hash = hash ? hash.clone : nil
        hash = {}
        hash[k] = old_hash
      end
      hash
    end

    def initialize(file, key)
      @key = key
      @file = file
    end
    
    def full_key
      if @key[/^\./]
        # @key starts with a '.', we interpolate @file name then
        prefix = @file.clone
        prefix.gsub!(/.*views\//, '')
        prefix.gsub!(/\..*/, '')
        prefix.gsub!("/_", '/')
        prefix.gsub!("/", ".")
        full_key = prefix + @key
      else
        full_key = @key
      end
      full_key
    end
  end

  class Hash
    def deep_merge!(second)
      second.each_pair do |k,v|
        if self[k].is_a?(Hash) and second[k].is_a?(Hash)
          self[k].deep_merge!(second[k])
        else
          self[k] = second[k]
        end
      end
    end
  end

  def self.deep_diff(hash1, hash2, ignore_keys=[])
    #puts "----"
    #puts "hash1: " + hash1.inspect
    #puts "hash2: " + hash2.inspect
    diff = {}
    hash1.keys.each do |key|
      next if ignore_keys.include?(key)
      #puts "key: " + key
      #puts "hash1[key].class: " + hash1[key].class.to_s
      #puts "hash2[key].class: " + hash2[key].class.to_s
      if hash1[key].class.to_s == 'Hash' and hash2[key].class.to_s == 'Hash'
        #puts "hash+hash"
        d = deep_diff(hash1[key], hash2[key], ignore_keys)
        diff.key?(key) ? diff[key].merge!(d) : diff[key] = d unless d.empty?
      end
      if hash1[key].class.to_s == 'Hash' and hash2[key] == nil
        #puts "hash+nil"
        diff.key?(key) ? diff[key].merge!(hash1[key]) : diff[key] = hash1[key]
      end
      if hash1[key].is_a? String and !hash2.key?(key)
        #puts "string+no_key"
        diff.key?(key) ? diff[key].merge!(hash1[key]) : diff[key] = hash1[key]
      end
    end
    diff
  end


  class Translations
    attr_accessor :translations

    def add(file, key)
      t = Translation.new(file, key).to_hash
      @translations.deep_merge!(t)
    end

    def compare(t)
      ht
      t = Hash.new.deep
      t.deep_diff(@translations)
    end

    def initialize
      @translations = {}
    end
  end

  def self.file_list
    Dir[File.join(RAILS_ROOT, 'app', '**', '*.*')] + Dir[File.join(RAILS_ROOT, 'public', 'javascripts', '**', '*.js')]
  end

  def self.parse_source_code(file)
    code = File.read(file)
    keys = code.scan(/\Wt[\( ]?["']([^"']*)["']\)?/)
    keys.flatten
  end

  def self.main
    optparse = OptionParser.new do |opts|
      opts.banner = "Usage: script/unused_translations [options] file1 file2 ..."
      opts.on( '-i', '--ignore-keys a,b,c', Array, "Ignore keys used by built-in helpers or error message generators (ex. datetime, formtastic, authlogic, activerecord...)" ) do |f|
        @ignore_keys = f
      end
      opts.on( '-h', '--help', 'Display this screen' ) do
        puts opts
        exit
      end
    end
    @ignore_keys = []

    begin
      optparse.parse!
    rescue OptionParser::InvalidOption, OptionParser::MissingArgument
      puts $!.to_s
      puts optparse
      exit
    end
    files = file_list

    @translations = Translations.new
    files.each do |f|
      keys = parse_source_code(f)
      keys.each do |k|
        @translations.add(f, k)
      end
    end

    diff = []
    ARGV.each do |f|
      loc = YAML.load_file(f)[File.basename(f, '.yml')]
      diff << deep_diff(loc, @translations.translations, @ignore_keys)
    end
    diff
  end
end