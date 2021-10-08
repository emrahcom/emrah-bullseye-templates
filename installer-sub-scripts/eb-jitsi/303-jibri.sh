# -----------------------------------------------------------------------------
# JIBRI.SH
# -----------------------------------------------------------------------------
set -e
source $INSTALLER/000-source

# -----------------------------------------------------------------------------
# ENVIRONMENT
# -----------------------------------------------------------------------------
MACH="eb-jibri-template"
cd $MACHINES/$MACH

ROOTFS="/var/lib/lxc/$MACH/rootfs"
JITSI_ROOTFS="/var/lib/lxc/eb-jitsi/rootfs"

# -----------------------------------------------------------------------------
# INIT
# -----------------------------------------------------------------------------
[[ "$DONT_RUN_JIBRI" = true ]] && exit

echo
echo "-------------------------- $MACH --------------------------"

# -----------------------------------------------------------------------------
# CONTAINER SETUP
# -----------------------------------------------------------------------------
# stop the template container if it's running
set +e
lxc-stop -n eb-bullseye
lxc-wait -n eb-bullseye -s STOPPED
set -e

# remove the old container if exists
set +e
systemctl stop jibri-ephemeral-container.service

lxc-stop -n $MACH
lxc-wait -n $MACH -s STOPPED
lxc-destroy -n $MACH
rm -rf /var/lib/lxc/$MACH
sleep 1
set -e

# create the new one
lxc-copy -n eb-bullseye -N $MACH -p /var/lib/lxc/

# the shared directories
mkdir -p $SHARED/cache
mkdir -p $SHARED/recordings

# the container config
rm -rf $ROOTFS/var/cache/apt/archives
mkdir -p $ROOTFS/var/cache/apt/archives
rm -rf $ROOTFS/usr/local/eb/recordings
mkdir -p $ROOTFS/usr/local/eb/recordings
sed -i '/^lxc\.net\./d' /var/lib/lxc/$MACH/config
sed -i '/^# Network configuration/d' /var/lib/lxc/$MACH/config

cat >> /var/lib/lxc/$MACH/config <<EOF
lxc.mount.entry = $SHARED/recordings usr/local/eb/recordings none bind 0 0

# Devices
lxc.cgroup2.devices.allow = c 116:* rwm
lxc.mount.entry = /dev/snd dev/snd none bind,optional,create=dir

# Network configuration
lxc.net.0.type = veth
lxc.net.0.link = $BRIDGE
lxc.net.0.name = eth0
lxc.net.0.flags = up
lxc.net.0.ipv4.address = $IP/24
lxc.net.0.ipv4.gateway = auto

# Start options
lxc.start.auto = 1
lxc.start.order = 303
lxc.start.delay = 2
lxc.group = eb-group
lxc.group = onboot
EOF

# dhcp config
cp etc/network/interfaces $ROOTFS/etc/network/

# start the container
lxc-start -n $MACH -d
lxc-wait -n $MACH -s RUNNING

# wait for the network to be up
for i in $(seq 0 9); do
    lxc-attach -n $MACH -- ping -c1 host && break || true
    sleep 1
done

# -----------------------------------------------------------------------------
# HOSTNAME
# -----------------------------------------------------------------------------
lxc-attach -n $MACH -- zsh <<EOS
set -e
echo $MACH > /etc/hostname
sed -i 's/\(127.0.1.1\s*\).*$/\1$MACH/' /etc/hosts
hostname $MACH
EOS

# -----------------------------------------------------------------------------
# PACKAGES
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# CONTAINER SERVICES
# -----------------------------------------------------------------------------
lxc-attach -n $MACH -- systemctl stop jibri-xorg.service
lxc-stop -n $MACH
lxc-wait -n $MACH -s STOPPED

# -----------------------------------------------------------------------------
# CLEAN UP
# -----------------------------------------------------------------------------
find $ROOTFS/var/log/jitsi/jibri -type f -delete
