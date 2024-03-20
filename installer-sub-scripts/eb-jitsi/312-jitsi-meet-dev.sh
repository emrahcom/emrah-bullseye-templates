# ------------------------------------------------------------------------------
# JITSI-MEET-DEV.SH
# ------------------------------------------------------------------------------
set -e
source $INSTALLER/000-source

# ------------------------------------------------------------------------------
# ENVIRONMENT
# ------------------------------------------------------------------------------
MACH="$TAG-jitsi"
MACH_HOST="$MACHINES/$TAG-jitsi-host"
cd $MACHINES/$MACH

ROOTFS="/var/lib/lxc/$MACH/rootfs"

# ------------------------------------------------------------------------------
# INIT
# ------------------------------------------------------------------------------
[[ "$INSTALL_JITSI_MEET_DEV" != true ]] && exit

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
    lxc-attach -n $MACH -- ping -c1 host.loc && break || true
    sleep 1
done

# ------------------------------------------------------------------------------
# PACKAGES
# ------------------------------------------------------------------------------
# fake install
lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get $APT_PROXY -dy reinstall hostname
EOS

# update
lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get $APT_PROXY update
apt-get $APT_PROXY -y dist-upgrade
EOS

# packages
lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get $APT_PROXY -y install gnupg git build-essential
EOS

# nodejs
cp etc/apt/sources.list.d/nodesource.list $ROOTFS/etc/apt/sources.list.d/
lxc-attach -n $MACH -- zsh <<EOS
set -e
wget -T 30 -qO /tmp/nodesource.gpg.key \
    https://deb.nodesource.com/gpgkey/nodesource.gpg.key
cat /tmp/nodesource.gpg.key | gpg --dearmor >/usr/share/keyrings/nodesource.gpg
apt-get $APT_PROXY update
EOS

lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get $APT_PROXY -y install nodejs
npm install npm -g
EOS

# ------------------------------------------------------------------------------
# JITSI-MEET DEV
# ------------------------------------------------------------------------------
# dev user
lxc-attach -n $MACH -- zsh <<EOS
set -e
adduser dev --system --group --disabled-password --shell /bin/zsh \
    --home /home/dev
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
mkdir -p /root/$TAG-store

# lib-jitsi-meet
if [[ ! -d /root/$TAG-store/lib-jitsi-meet ]]; then
    git clone https://github.com/jitsi/lib-jitsi-meet.git \
        /root/$TAG-store/lib-jitsi-meet
fi

zsh <<EOS
set -e
cd /root/$TAG-store/lib-jitsi-meet
git pull
EOS

rm -rf $ROOTFS/home/dev/lib-jitsi-meet
cp -arp /root/$TAG-store/lib-jitsi-meet $ROOTFS/home/dev/

lxc-attach -n $MACH -- zsh <<EOS
set -e
chown dev:dev /home/dev/lib-jitsi-meet -R
EOS

# jitsi-meet
if [[ ! -d /root/$TAG-store/jitsi-meet ]]; then
    git clone https://github.com/jitsi/jitsi-meet.git \
        /root/$TAG-store/jitsi-meet
fi

zsh <<EOS
set -e
cd /root/$TAG-store/jitsi-meet
git pull
EOS

rm -rf $ROOTFS/home/dev/jitsi-meet
cp -arp /root/$TAG-store/jitsi-meet $ROOTFS/home/dev/

lxc-attach -n $MACH -- zsh <<EOS
set -e
chown dev:dev /home/dev/jitsi-meet -R
EOS

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

# ------------------------------------------------------------------------------
# HOST
# ------------------------------------------------------------------------------
cp $MACH_HOST/etc/sysctl.d/eb-inotify-watcher.conf /etc/sysctl.d/
sysctl -p /etc/sysctl.d/eb-inotify-watcher.conf
