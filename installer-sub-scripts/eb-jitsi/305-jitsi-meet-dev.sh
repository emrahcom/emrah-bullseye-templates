# ------------------------------------------------------------------------------
# JITSI-MEET-DEV.SH
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
[ "$INSTALL_JITSI_MEET_DEV" != true ] && exit

echo
echo "---------------------- JITSI MEET DEV ---------------------"

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
apt-get $APT_PROXY_OPTION -y dist-upgrade
EOS

# packages
lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get $APT_PROXY_OPTION -y install gnupg git build-essential
EOS

# nodejs
cp etc/apt/sources.list.d/nodesource.list $ROOTFS/etc/apt/sources.list.d/
lxc-attach -n $MACH -- zsh <<EOS
set -e
wget -qO /tmp/nodesource.gpg.key \
    https://deb.nodesource.com/gpgkey/nodesource.gpg.key
cat /tmp/nodesource.gpg.key | gpg --dearmor >/usr/share/keyrings/nodesource.gpg
apt-get $APT_PROXY_OPTION update
EOS

lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get $APT_PROXY_OPTION -y install nodejs
npm install npm -g
EOS

# ------------------------------------------------------------------------------
# JITSI-MEET DEV
# ------------------------------------------------------------------------------
# dev user
lxc-attach -n $MACH -- zsh <<EOS
set -e
adduser dev --system --group --disabled-password --shell /bin/zsh --gecos ''
EOS

cp $MACHINE_COMMON/home/user/.tmux.conf $ROOTFS/home/dev/
cp $MACHINE_COMMON/home/user/.zshrc $ROOTFS/home/dev/
cp $MACHINE_COMMON/home/user/.vimrc $ROOTFS/home/dev/

lxc-attach -n $MACH -- zsh <<EOS
set -e
chown dev:dev /home/dev/.tmux.conf
chown dev:dev /home/dev/.vimrc
chown dev:dev /home/dev/.zshrc
EOS

# store folder
mkdir -p /root/eb-store

# lib-jitsi-meet
if [[ ! -d /root/eb-store/lib-jitsi-meet ]]; then
    git clone https://github.com/jitsi/lib-jitsi-meet.git \
        /root/eb-store/lib-jitsi-meet
fi

zsh <<EOS
set -e
cd /root/eb-store/lib-jitsi-meet
git pull
EOS

rm -rf $ROOTFS/home/dev/lib-jitsi-meet
cp -arp /root/eb-store/lib-jitsi-meet $ROOTFS/home/dev/

# jitsi-meet
if [[ ! -d /root/eb-store/jitsi-meet ]]; then
    git clone https://github.com/jitsi/jitsi-meet.git \
        /root/eb-store/jitsi-meet
fi

zsh <<EOS
set -e
cd /root/eb-store/jitsi-meet
git pull
EOS

rm -rf $ROOTFS/home/dev/jitsi-meet
cp -arp /root/eb-store/jitsi-meet $ROOTFS/home/dev/

# ------------------------------------------------------------------------------
# SYSTEM CONFIGURATION
# ------------------------------------------------------------------------------
# nginx
cp $ROOTFS/etc/nginx/sites-available/$JITSI_FQDN.conf \
    $ROOTFS/etc/nginx/sites-available/$JITSI_FQDN-dev.conf
sed -i "s~/usr/share/jitsi-meet~/home/dev/jitsi-meet~g" \
    $ROOTFS/etc/nginx/sites-available/$JITSI_FQDN-dev.conf

# dev tools
cp usr/local/sbin/enable-jitsi-meet-dev $ROOTFS/usr/local/sbin/
cp usr/local/sbin/disable-jitsi-meet-dev $ROOTFS/usr/local/sbin/
sed -i "s/___JITSI_FQDN___/$JITSI_FQDN/" \
    $ROOTFS/usr/local/sbin/enable-jitsi-meet-dev
sed -i "s/___JITSI_FQDN___/$JITSI_FQDN/" \
    $ROOTFS/usr/local/sbin/disable-jitsi-meet-dev
chmod 744 $ROOTFS/usr/local/sbin/enable-jitsi-meet-dev
chmod 744 $ROOTFS/usr/local/sbin/disable-jitsi-meet-dev

# ------------------------------------------------------------------------------
# SYSTEM INFO
# ------------------------------------------------------------------------------
lxc-attach -n $MACH -- zsh <<EOS
set -e
node --version
npm --version
EOS
