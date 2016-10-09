#!/usr/bin/env ruby

require 'rest-client'
require 'json'
require 'nori'
require 'ipaddress'

puts "Beginning execution at #{Time.now}"

GLOBAL_CONFIG = '/etc/namesilo_ddns/config.json'
LOCAL_CONFIG = File.join(__dir__, 'config.json')
REQUIRED_KEYS = %W(domain subdomain ttl api_key)

config_file = nil
config_file ||= GLOBAL_CONFIG if File.file? GLOBAL_CONFIG
config_file ||= LOCAL_CONFIG if File.file? LOCAL_CONFIG

raise "Unable to find config file at #{GLOBAL_CONFIG} or #{LOCAL_CONFIG}" unless config_file

puts "Using config file #{config_file}"

CONFIG = JSON.parse(File.read(config_file))
undefined_keys = (REQUIRED_KEYS - CONFIG.keys)

raise "The following config keys are required but not set: #{undefined_keys}.  Please check config." unless undefined_keys.empty?

def create_record(type, value)
  puts "Creating Record #{type}: #{value}"
  raw_response = RestClient.get 'https://www.namesilo.com/api/dnsAddRecord', {params: {
    version: 1,
    type: 'xml',
    key: CONFIG['api_key'],
    domain: CONFIG['domain'],
    rrtype: type,
    rrhost: CONFIG['subdomain'],
    rrvalue: value,
    rrttl: CONFIG['ttl']
  }}
  response = xml_parser.parse(raw_response)
  raise "Unsuccessful response #{response}" unless raw_response.code == 200
end

def replace_record(record, value)
  puts "Replacing Record #{record} with #{value}"
  raw_response = RestClient.get 'https://www.namesilo.com/api/dnsUpdateRecord', {params: {
    version: 1,
    type: 'xml',
    key: CONFIG['api_key'],
    domain: CONFIG['domain'],
    rrid: record['record_id'],
    rrhost: CONFIG['subdomain'],
    rrvalue: value,
    rrttl: CONFIG['ttl']
  }}
  response = xml_parser.parse(raw_response)
  raise "Unsuccessful response #{response}" unless raw_response.code == 200
end

def delete_record(record)
  puts "Deleting Record #{record}"
  raw_response = RestClient.get 'https://www.namesilo.com/api/dnsDeleteRecord', {params: {
    version: 1,
    type: 'xml',
    key: CONFIG['api_key'],
    domain: CONFIG['domain'],
    rrid: record['record_id'],
  }}
  response = xml_parser.parse(raw_response)
  raise "Unsuccessful response #{response}" unless raw_response.code == 200
end

response = RestClient.get 'https://api.ipify.org', {params: {format: 'json'}}
response = JSON.parse(response)

ip = response['ip']
raise "No IP provided.  #{response}" unless ip

if IPAddress(ip).is_a?(IPAddress::IPv4)
  target_type = 'A'
else
  target_type = 'AAAA'
end

puts "IP Address: #{ip}"

xml_parser = Nori.new(:parser => :rexml)

raw_response = RestClient.get 'https://www.namesilo.com/api/dnsListRecords', {params: {version: 1, type: 'xml', key: CONFIG['api_key'], domain: CONFIG['domain']}}
response = xml_parser.parse(raw_response)
raise "Unsuccessful response #{response}" unless raw_response.code == 200



resource_records = response.dig('namesilo', 'reply', 'resource_record')

raise "No resource records provided: #{response}" unless resource_records

current_record = nil

resource_records.each do |record|
  if record['host'] == "#{CONFIG['subdomain']}.#{CONFIG['domain']}" && (record['type'] == 'CNAME' || record['type'] == 'A' || record['type'] == 'AAAA')
    current_record = record
    break
  end
end

if current_record
  if current_record['type'] == target_type
    replace_record(current_record, ip) unless current_record['value'] == ip
  else
    delete_record(current_record)
    create_record(target_type, ip)
  end
else
  create_record(target_type, ip)
end

puts "Completed execution at #{Time.now}"
