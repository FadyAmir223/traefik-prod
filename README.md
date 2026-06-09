# Traefik Reverse Proxy Setup with Cloudflare DNS

This configuration is a hardened setup based on the guide [Practical Configuration of Traefik as a Reverse Proxy for Docker](https://www.spad.uk/posts/practical-configuration-of-traefik-as-a-reverse-proxy-for-docker-updated-for-2023/)


## 1. Host Machine Preparation

Run these commands on your server to set up the necessary files, permissions, and network

```sh
cd traefik
touch traefik.yml

# create and secure the ACME certificate storage file
touch acme.json
sudo chown root:root acme.json
sudo chmod 600 acme.json

# create the dedicated external Docker network
docker network create proxy

# generate a secure basic auth password for the Traefik dashboard
# copy the output to 'auth.txt'
htpasswd -nbB your_username your_password
```


## 2. Cloudflare Setup

### Step A: DNS Records
In your Cloudflare dashboard, create two **A records** pointing to your origin server's public IP
* Name: `hello` (For the Traefik dashboard)
* Name: `world` (For the testing service)
* **Proxy Status:** Set to **Proxied (Orange Cloud)**. This hides your server's real IP and enables Cloudflare's DDoS protection

### Step B: Create an API Token
Go to your [Cloudflare Profile API Tokens](https://dash.cloudflare.com/profile/api-tokens) page and create a custom token.

* **Permissions:**
  * `Zone` -> `DNS` -> `Edit`
  * `Zone` -> `Zone` -> `Read`
* **Zone Resources:**
  * `Include` -> `Specific Zone` -> `example.com`


## 3. Verification URLs

Once your containers are running, you can access your test services at these endpoints:

* **Traefik Dashboard:**  `http://hello.example.com` (Redirects to HTTPS)
* **Logo Service:**  `http://world.example.com` (Redirects to HTTPS)


## 4. Advanced Hardening

### DNSSEC Activation
DNSSEC prevents DNS spoofing and spoofed DNS records.
1. Enable DNSSEC in your [Cloudflare DNS Settings](https://dash.cloudflare.com/someHash/example.com/dns/settings)
2. Cloudflare will generate a set of DS records
3. Copy these values and paste them into the DNSSEC management section of your registrar, such as the [Hostinger DNSSEC Panel](https://hpanel.hostinger.com/domain/example.com/dns?tab=dns_sec)

### IP Protection & Origin Shielding
If an attacker discovers your server's public IP, they can connect directly to it, bypassing Cloudflare's DDoS protection and firewall rules. You can prevent this with a two-step IP strategy:

1. **UFW (Host Firewall):** Configure your system's firewall to block all traffic on ports `80` and `443` unless it originates from a [Cloudflare IP Range](https://developers.cloudflare.com/fundamentals/concepts/cloudflare-ip-addresses/)
2. **Traefik `trustedIPs`:** Add those same Cloudflare IP ranges to the `trustedIPs` list in `traefik.yml`. This allows Traefik to trust the forwarded headers and pass the visitor's real IP address down to your backend applications

**Note on Integrations:** Because incoming webhooks from third-party services (like Stripe, Twilio, and Mailjet) are routed through your Cloudflare-proxied subdomains, they will arrive at your server from a Cloudflare IP. This means you do not need to track down or whitelist the dynamic IP ranges of these third-party services in your system firewall

## 5. Log Management & Rotation

This prevent server's disk space from filling up over time

### Traefik System Logs
Traefik supports native log rotation for its internal system logs `traefik.log` where it can rotate, compress, and prune them


### Traefik Access Logs (Logrotate Sidecar)
Unlike system logs, Traefik **does not** natively support log rotation for its access logs `access.log`.
To handle this, a lightweight `logrotate` sidecar container runs alongside Traefik:

1. **Logrotate Execution:** A daily cron job runs `logrotate` against the `access.log` file
2. **The Signal:** the sidecar container shares Traefik's PID namespace. Immediately after rotating `access.log`, the sidecar sends a `USR1` signal to Traefik. This signal tells Traefik to gracefully release the old file descriptor and reopen the log files
