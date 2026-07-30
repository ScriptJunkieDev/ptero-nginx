# Pterodactyl Egg and Container

This repository contains **Pterodactyl eggs** maintained by **Towncraft**, providing preconfigured setups for **NGinx Web Hosting**.

---

### 1. 🌐 Pterodactyl Webhost Egg
Easily deploy a web server with optional support for WordPress and Laravel Apps.

#### 🔧 How to Use:
1. Download the JSON egg file from the releases page.
2. Import the egg into your **Pterodactyl panel**.
3. Create a new server and configure variables.
   - Optionally, enable **WordPress** during setup for automatic installation.
4. Install **Composer** packages either during setup or afterward.
5. Access your server via the assigned IP and port.  
   - For WordPress: `http://ip:port/wp-admin`

---

## 📄 License

- Webhost Egg originally forked & edited from [tenten8401/pterodactyl-nginx](https://gitlab.com/tenten8401/pterodactyl-nginx)  
- Provided under the [MIT License](LICENSE).  

© 2024–2025 **Sigma Productions**. All rights reserved.  
---

## Multi-architecture images

The GitHub Actions workflow publishes each PHP image tag for both:

- `linux/amd64`
- `linux/arm64`

After the workflow completes, verify the manifest with:

```bash
docker buildx imagetools inspect ghcr.io/scriptjunkiedev/ptero-nginx:8.4
```

The output should include both platforms. On a Pterodactyl node, remove the old single-architecture image before restarting the server:

```bash
docker image rm ghcr.io/scriptjunkiedev/ptero-nginx:8.4 || true
docker pull ghcr.io/scriptjunkiedev/ptero-nginx:8.4
```
