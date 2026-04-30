#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Get the directory of the script and move into it
dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$dir"

sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
            pkg-config libssl-dev docker.io build-essential python3-dev \
            python3-pip python3-venv tmux cron ufw git net-tools fuse3 \
            unzip wget openssl curl jq
        sudo DEBIAN_FRONTEND=noninteractive apt install -y docker-compose-v2

        sudo usermod -aG docker "$USER"
        sudo systemctl enable --now docker

# --- File System Setup ---
echo "--> Creating directory structure..."
mkdir -p data/share/log temp apps bin

# --- Python Environment Setup ---
echo "--> Setting up Python virtual environment..."
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install --upgrade pip
pip3 install -r requirements.txt

# --- Rust & Monolith Setup ---
echo "--> Installing Rust and monolith..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
cargo install monolith

echo "--> Setup complete!"

# Refresh group membership so the user can use Docker without a logout/reboot
echo "--> Refreshing Docker group permissions..."
exec sg docker "$0"

