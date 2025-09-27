# 🛡️ Fortify

**Fortify** is a Linux-based security hardening tool that protects you and your machine from hackers.  
It runs checks, applies fixes, and gives you a **gamified report** with scores, badges, and even Octocat approval 🐙.

---

## ✨ Features
- 🔒 Run security checks on your Linux machine  
- 🔧 Auto-fix common misconfigurations (with backups)  
- 📊 Generate JSON + HTML reports  
- 🎮 Gamified UI — scores, XP, badges, ranks  
- 🐙 Octocat Security Review for extra fun  

---

## 🚀 Quick Start

```bash
# Clone the repo
git clone https://github.com/<your-username>/fortify.git
cd fortify/scripts

# Run with default profile
sudo ./fortify.sh

# Run with server profile
sudo ./fortify.sh -p profiles/server.profile


-- Reports will be saved under the reports/ folder.
HTML reports auto-open in your browser if available.
```

## 🏆 Badges & Ranks
- 🥉 Bronze Security Explorer

- 🥈 Silver Security Defender

- 🥇 Gold Security Master

- 💎 Diamond Security Champion (100% score)

- 🐙 Octocat Approval (special)

## 📦 Installation
# Optional: make it global
sudo cp scripts/fortify.sh /usr/local/bin/fortify
sudo chmod +x /usr/local/bin/fortify

# Now you can run it anywhere
fortify


## License
MIT License © 2025 Megane Alexis

See [LICENSE] for details.