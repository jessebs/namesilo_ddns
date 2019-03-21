# namesilo_ddns

Tested in
* 2.3
* 2.6

## Downloading
Either clone the repository through git or download the zip file through github

## Setup
> bundle install --deployment

Modify the copy config.json file that was provided to /etc/namesile_ddns/config.json and modify it
with your configuration


```
{
    "api_key": "your_namesilo_api_key",
    "ttl": 3600,
  
    "domains": {
      "domain.com": "subdomain",
      "domain2.com": ["subdomain1", "subdomain2"]
    }
  }
```


## Running Automatically
Setup a cron 

`*/20 * * * * ~/.rvm/rubies/ruby-2.6.2/bin/ruby ~/namesilo_ddns/namesilo_ddns.rb 2>&1 >> ~/namesilo_ddns.log`

