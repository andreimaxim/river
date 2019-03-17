$LOAD_PATH.unshift(File.expand_path('../lib', File.dirname(__FILE__)))

require 'bundler/setup'

require 'sequel'
require 'pg'
require 'oj'

class River


  CHANNEL = 'rvr_events'.freeze

  attr_reader :client

  def initialize
    uri = 'postgres://river:river@db:5432/river'

    @client = Sequel.connect(uri)

    listen
  end

  def listen
    @client.listen(:river_events, loop: true) do |_channel, _pid, payload|
      p = River::Payload.new(Oj.load(payload))

      if p.updated?
        puts p
      else
        puts 'Nothing new...'
      end
    end
  end

  class Payload

    def initialize(payload = {})
      @meta = payload['meta']
      @data = payload['data']
    end

    def table
      @meta['table']
    end

    def action
      @meta['action']
    end

    def timestamp
      @meta['timestamp']
    end

    def curr
      @data['curr']
    end

    def prev
      @data['prev']
    end

    def delta
      if curr.empty?
        prev
      elsif prev.empty?
        curr
      else
        curr.dup.keep_if { |k, v| prev[k] != v }
      end
    end

    def updated?
      !delta.empty?
    end

    def to_s
      str = <<~STR

NEW CHANGE DETECTED ON #{table}!
=========================================
New value: #{curr}
Old value: #{prev}

Changed values: #{delta}\n\n
STR
    end

  end
end
