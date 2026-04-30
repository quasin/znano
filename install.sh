#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

mkdir -p data/share/log data/.ipfs temp apps
(echo -e "$(date -u) Znano installation started.") >> $PWD/data/log.txt
read -p "Enter IPFS port(default 4002): " IPFSPORT
if [ -z "$IPFSPORT" ]; then
    IPFSPORT=4002
fi


# Get the directory of the script and move into it
dir="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$dir"

sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
            pkg-config libssl-dev docker.io build-essential python3-dev \
            python3-pip python3-venv tmux cron ufw git net-tools fuse3 \
            unzip wget openssl curl jq
        sudo DEBIAN_FRONTEND=noninteractive apt install -y docker-compose-v2 || echo "Package not found, skipping..."

        sudo usermod -aG docker "$USER"
        sudo systemctl enable --now docker

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

arch=$(uname -m)
if [[ "$arch" == "x86_64" ]]; then
    ipfsdistr="https://github.com/ipfs/kubo/releases/download/v0.41.0/kubo_v0.41.0_linux-amd64.tar.gz"
    yggdistr="https://github.com/yggdrasil-network/yggdrasil-go/releases/download/v0.5.13/yggdrasil-0.5.13-amd64.deb"
elif [[ "$arch" == "aarch64" ]]; then
    ipfsdistr="https://github.com/ipfs/kubo/releases/download/v0.41.0/kubo_v0.41.0_linux-arm64.tar.gz"
    yggdistr="https://github.com/yggdrasil-network/yggdrasil-go/releases/download/v0.5.13/yggdrasil-0.5.13-arm64.deb"
elif [[ "$arch" == "riscv64" ]]; then
    ipfsdistr="https://github.com/ipfs/kubo/releases/download/v0.41.0/kubo_v0.41.0_linux-riscv64.tar.gz"
    sudo wget -O /usr/local/bin/yggdrasil https://ipfs.sweb.ru/ipfs/QmZUem3W4YV8R4Zm8xEFfJoyWJskx4nDJ1rpDR6MSoVM3N?filename=yggdrasil
    sudo wget -O /usr/local/bin/yggdrasilctl https://ipfs.sweb.ru/ipfs/QmZUem3W4YV8R4Zm8xEFfJoyWJskx4nDJ1rpDR6MSoVM3N?filename=yggdrasilctl
    sudo chmod +x /usr/local/bin/yggdrasil /usr/local/bin/yggdrasilctl
    sudo mkdir /etc/yggdrasil
    yggdrasil -genconf | sudo tee /etc/yggdrasil/yggdrasil.conf
echo -e "\
[Unit]\n\
Description=Yggdrasil Network Service\n\
After=network.target\n\
\n\
[Service]\n\
Type=simple\n\
User=root\n\
Group=root\n\
ExecStart=/usr/local/bin/yggdrasil -useconffile /etc/yggdrasil/yggdrasil.conf\n\
Restart=on-failure\n\
RestartSec=5s\n\
\n\
[Install]\n\
WantedBy=multi-user.target\n\
" | sudo tee /etc/systemd/system/yggdrasil.service
    sudo systemctl daemon-reload
    sudo systemctl enable --now yggdrasil
else
    echo "Unsupported architecture: $arch"
    exit 1
fi

echo PATH="$PATH:/home/$USER/.local/bin:$PWD/bin" | sudo tee /etc/environment
echo ZNANO="$PWD" | sudo tee -a /etc/environment
echo IPFS_PATH="$PWD/data/.ipfs" | sudo tee -a /etc/environment
echo ". /etc/environment" | tee -a ~/.bashrc
export PATH="$PATH:/home/$USER/.local/bin:$PWD/bin"
export ZNANO="$PWD"
export IPFS_PATH="$PWD/data/.ipfs"
echo -e "PATH=$PATH\nZNANO=$PWD\nIPFS_PATH=$IPFS_PATH\n$(sudo crontab -l)\n" | sudo crontab -
sudo systemctl enable --now cron

sudo mkdir data/ipfs data/ipns data/mfs
sudo chmod 777 data/ipfs
sudo chmod 777 data/ipns
sudo chmod 777 data/mfs
wget -O temp/kubo.tar.gz $ipfsdistr
tar xvzf temp/kubo.tar.gz -C temp
sudo mv temp/kubo/ipfs /usr/local/bin/ipfs
ipfs init --profile server
ipfs config Mounts.IPFS "$dir/data/ipfs"
ipfs config Mounts.IPNS "$dir/data/ipns"
ipfs config Mounts.MFS  "$dir/data/mfs"
ipfs config --json Experimental.FilestoreEnabled true
ipfs config --json Pubsub.Enabled true
ipfs config --json Ipns.UsePubsub true
ipfs config profile apply lowpower
#ipfs config Addresses.Gateway /ip4/127.0.0.1/tcp/8082
#ipfs config Addresses.API /ip4/127.0.0.1/tcp/5002
sed -i "s/4001/$IPFSPORT/g" $PWD/data/.ipfs/config
sed -i "s/104.131.131.82\/tcp\/$IPFSPORT/104.131.131.82\/tcp\/4001/g" $PWD/data/.ipfs/config
sed -i "s/104.131.131.82\/udp\/$IPFSPORT/104.131.131.82\/udp\/4001/g" $PWD/data/.ipfs/config
echo -e "\
[Unit]\n\
Description=InterPlanetary File System (IPFS) daemon\n\
Documentation=https://docs.ipfs.tech/\n\
After=network.target\n\
\n\
[Service]\n\
MemorySwapMax=0\n\
TimeoutStartSec=infinity\n\
Type=simple\n\
User=$USER\n\
Group=$USER\n\
Environment=IPFS_PATH=$PWD/data/.ipfs\n\
ExecStart=/usr/local/bin/ipfs daemon --enable-gc --mount --migrate=true\n\
Restart=on-failure\n\
KillSignal=SIGINT\n\
\n\
[Install]\n\
WantedBy=default.target\n\
" | sudo tee /etc/systemd/system/ipfs.service
sudo systemctl daemon-reload
sudo systemctl enable ipfs
sudo systemctl restart ipfs

cat <<EOF >>$PWD/bin/ipfssub.sh
#!/usr/bin/env bash

/usr/local/bin/ipfs pubsub sub znano >> $PWD/data/sub.txt
EOF
chmod +x $PWD/bin/ipfssub.sh

echo -e "\
[Unit]\n\
Description=InterPlanetary File System (IPFS) subscription\n\
After=network.target\n\
\n\
[Service]\n\
Type=simple\n\
User=$USER\n\
Group=$USER\n\
Environment=IPFS_PATH=$PWD/data/.ipfs\n\
ExecStartPre=/usr/bin/sleep 5\n\
ExecStart=$PWD/bin/ipfssub.sh\n\
Restart=on-failure\n\
KillSignal=SIGINT\n\
\n\
[Install]\n\
WantedBy=default.target\n\
" | sudo tee /etc/systemd/system/ipfssub.service
sudo systemctl daemon-reload
sudo systemctl enable ipfssub
sudo systemctl restart ipfssub
sleep 9

echo -e "$(sudo crontab -l)\n@reboot sleep 9; systemctl restart yggdrasil; echo \"\$(date -u) System is rebooted\" >> $PWD/data/log.txt\n* * * * * su $USER -c \"bash $PWD/bin/cron.sh\"" | sudo crontab -

echo -n -e "\n\nIPFS status:"
ipfs cat QmYwoMEk7EvxXi6LcS2QE6GqaEYQGzfGaTJ9oe1m2RBgfs/test.txt
echo -n "IPFSmount status:"
cat $dir/data/ipfs/QmYwoMEk7EvxXi6LcS2QE6GqaEYQGzfGaTJ9oe1m2RBgfs/test.txt

sudo ufw disable
sudo ufw default deny incoming
sudo ufw allow 22
sudo ufw allow 9001
sudo ufw allow from 200::/7
yes | sudo ufw enable

str=$(ipfs id) && echo $str | cut -c10-61 > $PWD/data/id.txt
wget -O temp/ygg.deb $yggdistr
sudo dpkg -i temp/ygg.deb
sudo sed -i "s/  Peers: \[\]/  Peers: \[\n    tls:\/\/ip4.01.msk.ru.dioni.su:9003\n  \]/g" /etc/yggdrasil/yggdrasil.conf
sudo sed -i "s/  NodeInfo: {}/  NodeInfo: {\n    name: tibidoh$(cat $PWD/data/id.txt)\n}/g" /etc/yggdrasil/yggdrasil.conf
sudo systemctl restart yggdrasil
sudo systemctl enable yggdrasil
sudo chmod u+s $(which ping)
ping -6 -c 5 21e:a51c:885b:7db0:166e:927:98cd:d186

rm -rf temp
mkdir temp
(echo -n "$(date -u) Znano system is installed. ID=" && cat $PWD/data/id.txt) >> $PWD/data/log.txt
ipfspub 'Initial message'
ipfs pubsub pub tibidoh $PWD/data/log.txt
sleep 9
sudo reboot
