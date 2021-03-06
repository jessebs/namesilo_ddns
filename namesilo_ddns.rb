#!/usr/bin/env ruby

Dir.chdir File.dirname(__FILE__)
require 'bundler/setup'

require 'rest-client'
require 'json'
require 'nori'
require 'ipaddress'

puts "Beginning execution at #{Time.now}"

CONFIG_FILE = '/etc/namesilo_ddns/config.json'
LOCAL_CONFIG = File.join(__dir__, 'config.json')
REQUIRED_KEYS = %W(domains ttl api_key)
REPLACEMENT_TYPES = %w(A AAAA CNAME)

XML_PARSER = Nori.new(:parser => :rexml)

raise "Unable to find config file at #{CONFIG_FILE}.  Copy #{LOCAL_CONFIG} to #{CONFIG_FILE}" unless File.file? CONFIG_FILE

CONFIG = JSON.parse(File.read(CONFIG_FILE))
undefined_keys = (REQUIRED_KEYS - CONFIG.keys)

raise "The following config keys are required but not set: #{undefined_keys}.  Please check config." unless undefined_keys.empty?

API_KEY = CONFIG['api_key']
TTL = CONFIG['ttl']

def get(url, data: {}, type: :xml)
  tries = 0
  raw_response = RestClient.get url, data

  response = case type
             when :json
               JSON.parse(raw_response)
             when :xml
               XML_PARSER.parse(raw_response)
             end
  raise "Unsuccessful response #{response}" unless raw_response.code == 200
  response
rescue
  tries += 1
  if tries < 3
    sleep(tries * 10)
    retry
  else
    raise
  end
end

def get_record_type(value)
  IPAddress(value).is_a?(IPAddress::IPv4) ? 'A' : 'AAAA'
rescue ArgumentError
  'CNAME'
end

def get_records(domain)
  puts "Getting records for #{domain}"
  get 'https://www.namesilo.com/api/dnsListRecords', data: {params: {version: 1, type: 'xml', key: API_KEY, domain: domain}}
end

def create_record(domain, subdomain, type, value)
  puts "Creating Record #{type}: #{subdomain}.#{domain} => #{value}"
  get 'https://www.namesilo.com/api/dnsAddRecord', data: {params: {
    version: 1,
    type: 'xml',
    key: API_KEY,
    domain: domain,
    rrtype: type,
    rrhost: subdomain,
    rrvalue: value,
    rrttl: TTL
  }}
end

def replace_record(current_record, domain, subdomain, value)
  if current_record['value'] == value
    puts "Record #{subdomain}.#{domain} is already up to date"
    return
  end

  puts "Replacing Record #{subdomain}.#{domain} with #{value}"

  get 'https://www.namesilo.com/api/dnsUpdateRecord', data: {params: {
    version: 1,
    type: 'xml',
    key: API_KEY,
    domain: domain,
    rrid: current_record['record_id'],
    rrhost: subdomain,
    rrvalue: value,
    rrttl: TTL
  }}
end

def delete_record(record, domain)
  puts "Deleting Record #{record}"
  get 'https://www.namesilo.com/api/dnsDeleteRecord', data: {params: {
    version: 1,
    type: 'xml',
    key: API_KEY,
    domain: domain,
    rrid: record['record_id'],
  }}
end


#### EXECUTION ####
response = get 'https://api.ipify.org', data: {params: {format: 'json'}}, type: :json

ip = response['ip']
raise "No IP provided.  #{response}" unless ip

puts "IP Address: #{ip}"

target_type = get_record_type(ip)

CONFIG['domains'].each do |domain, subdomains|
  subdomains = [subdomains] unless subdomains.is_a? Array

  records = get_records(domain)
  resource_records = records.dig('namesilo', 'reply', 'resource_record')

  raise 'Namesilo Response Invalid.' unless resource_records

  subdomains.each do |subdomain|
    current_record = resource_records.select { |r| r['host'] == "#{subdomain}.#{domain}" && (REPLACEMENT_TYPES.include?(r['type'])) }.first

    if current_record
      if current_record['type'] == target_type
        replace_record(current_record, domain, subdomain, ip)
      else
        delete_record(current_record, domain)
        create_record(domain, subdomain, target_type, ip)
      end
    else
      create_record(domain, subdomain, target_type, ip)
    end
  end
end

puts "Completed execution at #{Time.now}"

