# Traefik Reverse Proxy Setup with Cloudflare DNS

This configuration is a hardened setup based on the guide [Practical Configuration of Traefik as a Reverse Proxy for Docker](https://www.spad.uk/posts/practical-configuration-of-traefik-as-a-reverse-proxy-for-docker-updated-for-2023/)


## 1. Host Machine Preparation

Run these commands on your server to set up the necessary files, permissions, and network

```sh
# create the dedicated external Docker network
docker network create proxy

# generate a secure basic auth password for the Traefik dashboard
# copy the output to 'auth.txt'
htpasswd -nbB username password
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

## 5. Automated Zero-Bootstrap Setup (Init Service)

To achieve a true "one-click deployment" state, the configuration relies on a short-lived `init` service. This container runs and exits successfully before Traefik is allowed to boot

### What the Init Service Does:
1. **Permissions & File State Enforcement:** verifies that `./traefik/acme.json` exists and applies the strictly required `600` permissions
2. **Initial Config Compilation:** It runs the Cloudflare IP lookup script to compile the actual traefik configuration from the version-controlled `traefik.yml` before Traefik starts up


## 6. Cloudflare IP Auto-Updates & Architectural Choices

To ensure real visitor IPs are preserved and malicious traffic bypassing Cloudflare is rejected, Traefik needs to know Cloudflare's trusted IP ranges. Because these IPs change (rarely), an automated update script (`update-cf-ips.sh`) runs both at boot (via the `init` service) and weekly (via the logrotate/cron sidecar)

The script retrieves Cloudflare’s current public IP ranges via their API, injects the list into the trusted IP markers inside `traefik.yml`, and writes the compiled `traefik.generated.yml`.

Here is the expanded and professionally rewritten section for your README, highlighting the technical and performance reasons for avoiding interpreted middleware plugins like `traefik-plugin-cloudflare`.

***

### Why Avoiding Traefik Plugins

Rather than using dynamic middleware such as the [traefik-plugin-cloudflare](https://github.com/agence-gaya/traefik-plugin-cloudflare) to validate and update trusted IPs in memory. it introduces several technical disadvantages under production conditions:

* **Eliminating Yaegi Interpreter Overhead:** Traefik executes plugins using **Yaegi** (an embedded Go interpreter) at runtime. This means plugins are not compiled to native machine code; instead, they are interpreted on the fly. This compilation and evaluation process significantly increases Traefik's startup memory footprint and CPU overhead
* **Request Latency Under High Traffic:** A middleware plugin must intercept, parse, and evaluate the client’s IP address against a dynamic list **for every single incoming HTTP request**. Under high concurrent traffic, this translation layer introduces measurable latency to the request-response lifecycle. By writing the IP ranges directly to `traefik.yml` instead, Traefik handles the IP matching natively using its compiled Go core (`trustedIPs`), which executes at near-zero latency using optimized CIDR lookup tables


## 7. Log Rotation

This prevents the server's disk space from filling up over time

### Traefik System Logs
Traefik supports native log rotation for its internal system logs `traefik.log` where it can rotate, compress, and prune them.

### Traefik Access Logs (Logrotate Sidecar)
Unlike system logs, Traefik **does not** natively support log rotation for its access logs `access.log`.
To handle this, a lightweight `logrotate` sidecar container runs alongside Traefik:

1. **Logrotate Execution:** A daily cron job runs `logrotate` against the `access.log` file
2. **The Signal:** The sidecar container shares Traefik's PID namespace. Immediately after rotating `access.log`, the sidecar sends a `USR1` signal to Traefik. This signal tells Traefik to gracefully release the old file descriptor and reopen the log files
