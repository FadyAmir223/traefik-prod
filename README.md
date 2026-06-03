## hands on based on this article
https://www.spad.uk/posts/practical-configuration-of-traefik-as-a-reverse-proxy-for-docker-updated-for-2023


## steps
### create two proxied cloudflare A records for DDOS protection

### create api token
https://dash.cloudflare.com/profile/api-tokens

#### Permissions section
Zone -> DNS -> Edit
Zone -> Zone -> Read

#### Zone Resources section
Include -> Specific Zone -> novex-dev.com

### run
```sh
touch data/acme.json
sudo chown root:root data/acme.json
sudo chmod 600 data/acme.json

docker network create proxy2

htpasswd -nbB user password
```


## urls
- http://hello.novex-dev.com:8080
- http://world.novex-dev.com:8080
- https://hello.novex-dev.com:8443
- https://world.novex-dev.com:8443


## note
ports 8080 and 8443 are used instead of standard 80 and 443,  
network proxy2 is used instead of standard proxy,  
as they are already used

## advanced
activate DNSSEC via
https://developers.cloudflare.com/dns/dnssec
https://dash.cloudflare.com/someHash/novex-dev.com/dns/settings
https://hpanel.hostinger.com/domain/novex-dev.com/dns?tab=dns_sec
