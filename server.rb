require 'rack'
require 'rack/server'
require 'pp'
require 'byebug'
require_relative 'node'

class DHTServer
  DB_KEY_REGEX = /\/db\/(.+)/
  REMOVE_PEER_REGEX = /\/dht\/remove_peer\/(.+)/

  def initialize
    @node = DHTNode.new
  end

  def call(env)
    request = Rack::Request.new(env)
    @node.finish_setup!(request) unless @node.setup_complete

    params = request.params
    method = request.request_method
    body = request.body.read
    path = request.path
    @node.response = Rack::Response.new

    case

    when method == "GET"

      if path == "/"
        self.class.say_hello(request)
      elsif path == "/db"
        @node.get_local_keys
      elsif path == "/dht/keyspace" && params.empty?
        @node.get_all_keys_in_network
      elsif path == "/dht/keyspace"
        lower = Integer(params["lower_bound"])
        upper = Integer(params["upper_bound"])
        @node.get_keyspace(lower_bound: lower, upper_bound: upper)
      elsif path =~ DB_KEY_REGEX
        @node.get_val(key: path.scan(DB_KEY_REGEX)[0][0])
      elsif path == "/dht/peers"
        @node.get_peers
      elsif path == "/dht/leave"
        @node.leave_network!
      elsif path == "/debug"
        @node.debug
      else
        self.class.bad_response
      end

    when method == "PUT"

      if path =~ DB_KEY_REGEX
        @node.set!(key: path.scan(DB_KEY_REGEX)[0][0], val: body)
      else
        self.class.bad_response
      end

    when method == "DELETE"

      if path =~ DB_KEY_REGEX
        @node.delete!(key: path.scan(DB_KEY_REGEX)[0][0])
      elsif path =~ REMOVE_PEER_REGEX
        @node.remove_peer!(peer: path.scan(REMOVE_PEER_REGEX)[0][0])
      else
        self.class.bad_response
      end

    when method == "POST"

      if path == "/dht/initialize"
        @node.initialize_network!(peers_list: body)
      elsif path == "/dht/join"
        @node.join_network!(peers_list: body)
      elsif path == "/dht/peers"
        @node.add_peers!(peers_list: body)
      else
        self.class.bad_response
      end

    else
      self.class.bad_response
    end
  end

  def self.bad_response
    response = Rack::Response.new
    response.write("Sorry, your request was not properly formed.\n")
    response.status = 400
    response.finish
  end

  def self.say_hello(request)
    response = Rack::Response.new
    uri = "http://#{request.host}:#{request.port}"
    response.write(<<-STR)
      Hi there! Welcome to my DHT server. Here's how the public API works:

      initialize_dht => POST '#{uri}/dht/initialize', body => host1:port1&&host2:port2&&host3:port3

      get_local_keys: => GET '#{uri}/db'
      get_val => GET '#{uri}/db/\#{key}'
      get_all_keys: => GET '#{uri}/dht/keyspace'

      set => PUT '#{uri}/db/\#{key}', body => \#{val}
      delete_key => DELETE '#{uri}/db/\#{key}'

      peer_list => GET '#{uri}/dht/peers'

      join_dht => POST '#{uri}/dht/join', body => host1:port1&&host2:port2&&host3:port3
      leave_dht => GET '#{uri}/dht/leave'\n
    STR
    response.status = 200
    response.finish
  end
end

port_offset = 0
begin
  Rack::Server.start(app: DHTServer.new, Port: 8000 + port_offset)
rescue RuntimeError => e
  puts "Port #{8000 + port_offset} taken. Trying again."
  port_offset += 1
  retry
end
