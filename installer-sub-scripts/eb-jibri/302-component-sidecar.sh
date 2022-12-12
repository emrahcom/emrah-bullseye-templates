# ------------------------------------------------------------------------------
# COMPONENT-SIDECAR.SH
# ------------------------------------------------------------------------------
set -e
source $INSTALLER/000-source

# ------------------------------------------------------------------------------
# ENVIRONMENT
# ------------------------------------------------------------------------------
MACH="$TAG-jibri-template"
cd $MACHINES/$MACH

ROOTFS="/var/lib/lxc/$MACH/rootfs"

# ------------------------------------------------------------------------------
# INIT
# ------------------------------------------------------------------------------
[[ "$DONT_RUN_COMPONENT_SIDECAR" = true ]] && exit

echo
echo "-------------------- COMPONENT SIDECAR --------------------"

# ------------------------------------------------------------------------------
# CONTAINER
# ------------------------------------------------------------------------------
# stop the ephemeral containers
set +e
systemctl stop jibri-ephemeral-container.service
set -e

# start the container
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
apt-get $APT_PROXY -y install redis
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

# jitsi-component-sidecar
cp /root/jitsi-component-sidecar.deb $ROOTFS/tmp/

lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
debconf-set-selections <<< "\
    jitsi-component-sidecar jitsi-component-sidecar/selector-address \
    string $JITSI_FQDN"
dpkg -i /tmp/jitsi-component-sidecar.deb
EOS

# ------------------------------------------------------------------------------
# COMPONENT-SIDECAR
# ------------------------------------------------------------------------------
if [[ -f "/root/.ssh/sidecar.key" ]] && [[ -f "/root/.ssh/sidecar.pem" ]]; then
    cp /root/.ssh/sidecar.key $ROOTFS/etc/jitsi/sidecar/asap.key
    cp /root/.ssh/sidecar.pem $ROOTFS/etc/jitsi/sidecar/asap.pem
fi

if [[ -f "/root/env.sidecar" ]]; then
    cp /root/env.sidecar $ROOTFS/etc/jitsi/sidecar/env
else
    cp etc/jitsi/sidecar/env $ROOTFS/etc/jitsi/sidecar/
fi
sed -i "s/___JITSI_FQDN___/$JITSI_FQDN/" $ROOTFS/etc/jitsi/sidecar/env

lxc-attach -n $MACH -- zsh <<EOS
set -e
chown jitsi-sidecar:jitsi /etc/jitsi/sidecar/*
EOS

lxc-attach -n $MACH -- systemctl restart jitsi-component-sidecar.service

# ------------------------------------------------------------------------------
# CONTAINER SERVICES
# ------------------------------------------------------------------------------
lxc-attach -n $MACH -- systemctl stop jibri-xorg.service
lxc-stop -n $MACH
lxc-wait -n $MACH -s STOPPED

# ------------------------------------------------------------------------------
# CLEAN UP
# ------------------------------------------------------------------------------
find $ROOTFS/var/log/jitsi/jibri -type f -delete

# ------------------------------------------------------------------------------
# ON HOST
# ------------------------------------------------------------------------------
systemctl start jibri-ephemeral-container.service
