#!/usr/bin/env ruby
require 'sinatra'
require 'neography'
require 'net/http'
require 'uri'
require 'json'
require 'constructor'

neo4j_uri = URI(ENV['NEO4J_URL'] || "http://localhost:7474")
neo = Neography::Rest.new(neo4j_uri.to_s) # Neography expects a string

def check_for_neo4j(neo4j_uri)
  begin
    http = Net::HTTP.new(neo4j_uri.host, neo4j_uri.port)
    request = Net::HTTP::Get.new(neo4j_uri.request_uri)
    request.basic_auth(neo4j_uri.user, neo4j_uri.password) if (neo4j_uri.user)
    response = http.request(request)

    if (response.code != "200")
      abort "Sad face. Neo4j does not appear to be running. #{neo4j_uri} responded with code: #{response.code}"
    end
  rescue
    abort "Sad face. Neo4j does not appear to be running at #{neo4j_uri} (" + $!.to_s + ")" 
  end
  puts "Awesome! Neo4j is available at #{neo4j_uri}"
end

class Icd_node
  constructor :index, :icd, :not_header, :short_desc, :long_desc, accessors: true
  def instantiate_on_graph(neo)
    neo.create_node("index" => index,
      "icd" => icd,
      "not_header" => not_header,
      "short_desc" => short_desc,
      "long_desc" => long_desc)
  end
end

check_for_neo4j(neo4j_uri)
root_node = neo.get_root

# Array of graph instances
graph_indices = Array.new
graph_indices << root_node

# Abstract array of nodes
node_indices = Array.new
node_indices << Icd_node.new(index: "0", icd: "0",not_header: "0",short_desc: "Root Node",long_desc: "Root Node")
puts node_indices[0].short_desc + ' created.'

get '/load' do
  File.open('icd10cm.txt').each do |line|
    index = line[0..4].rstrip
    icd = line[6..10].rstrip
    not_header = line[14].rstrip
    short_desc = line[16..59].rstrip
    long_desc = line[77..299].rstrip

    this_node = Icd_node.new(
      index: index, 
      icd: icd, 
      not_header: not_header, 
      short_desc: short_desc,
      long_desc: long_desc)
    node_indices << this_node

    this_graphed_node = this_node.instantiate_on_graph(neo)
    graph_indices << this_graphed_node

    if this_node.icd.length > node_indices[-2].icd.length
      puts "#{node_indices.count}:\t" + this_node.icd + "\tis a CHILD of " + node_indices[-2].icd
      puts "\t\t\tParent index: ." + node_indices[-2].icd + "."
      if node_indices[-2].icd.eql? "0"
        neo.create_relationship("icd_parent", this_graphed_node, root_node)
      else
        neo.create_relationship("icd_parent", this_graphed_node, graph_indices[-2])
      end
    else
      node_index = node_indices.count
      node_indices.reverse_each do |prior_node|
        if prior_node.icd.length < this_node.icd.length
          puts "#{node_indices.count}:\t#{this_node.icd}\tis a child of " + prior_node.icd
          neo.create_relationship("icd_parent", this_graphed_node, graph_indices[node_index-1])
          break
        end
        node_index -= 1;
      end

    end

  end
end

get '/'  do
  "Load Graph!"
end