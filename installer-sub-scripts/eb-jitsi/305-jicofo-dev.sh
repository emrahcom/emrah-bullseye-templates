# ------------------------------------------------------------------------------
# JICOFO_DEV.SH
# ------------------------------------------------------------------------------
set -e
source $INSTALLER/000-source

# ------------------------------------------------------------------------------
# ENVIRONMENT
# ------------------------------------------------------------------------------
MACH="eb-jitsi"
cd $MACHINES/$MACH

ROOTFS="/var/lib/lxc/$MACH/rootfs"

# ------------------------------------------------------------------------------
# INIT
# ------------------------------------------------------------------------------
[ "$INSTALL_JICOFO_DEV" != true ] && exit

echo
echo "------------------------ JICOFO DEV -----------------------"

# ------------------------------------------------------------------------------
# CONTAINER
# ------------------------------------------------------------------------------
# start container
lxc-start -n $MACH -d
lxc-wait -n $MACH -s RUNNING

# wait for the network to be up
for i in $(seq 0 9); do
    lxc-attach -n $MACH -- ping -c1 host && break || true
    sleep 1
done

# ------------------------------------------------------------------------------
# PACKAGES
# ------------------------------------------------------------------------------
# fake install
lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get $APT_PROXY_OPTION -dy reinstall hostname
EOS

# update
lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get $APT_PROXY_OPTION update
EOS

# packages
lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get $APT_PROXY_OPTION -y install gnupg git build-essential
apt-get $APT_PROXY_OPTION -y install maven
EOS

# ------------------------------------------------------------------------------
# JICOFO DEV
# ------------------------------------------------------------------------------
# store folder
mkdir -p /root/eb-store

# dev folder
lxc-attach -n $MACH -- zsh <<EOS
set -e
mkdir -p /home/dev
cd /home/dev
EOS

# jicofo
if [[ ! -d /root/eb-store/jicofo ]]; then
    git clone --depth=200 -b master https://github.com/jitsi/jicofo.git \
        /root/eb-store/jicofo
fi

zsh <<EOS
set -e
cd /root/eb-store/jicofo
git pull
EOS

rm -rf $ROOTFS/home/dev/jicofo
cp -arp /root/eb-store/jicofo $ROOTFS/home/dev/

# ------------------------------------------------------------------------------
# SYSTEM INFO
# ------------------------------------------------------------------------------
lxc-attach -n $MACH -- zsh <<EOS
set -e
mvn --version
EOS
