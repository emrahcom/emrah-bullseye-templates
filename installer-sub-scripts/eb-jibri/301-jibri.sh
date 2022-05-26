# ------------------------------------------------------------------------------
# JIBRI.SH
# ------------------------------------------------------------------------------
set -e
source $INSTALLER/000-source

# ------------------------------------------------------------------------------
# ENVIRONMENT
# ------------------------------------------------------------------------------
MACH="eb-jibri-template"
cd $MACHINES/$MACH

ROOTFS="/var/lib/lxc/$MACH/rootfs"
JITSI_ROOTFS="/var/lib/lxc/eb-jitsi/rootfs"

# ------------------------------------------------------------------------------
# INIT
# ------------------------------------------------------------------------------
[[ "$DONT_RUN_JIBRI" = true ]] && exit

echo
echo "-------------------------- $MACH --------------------------"

# ------------------------------------------------------------------------------
# CONTAINER SETUP
# ------------------------------------------------------------------------------
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

cat >> /var/lib/lxc/$MACH/config <<EOF
lxc.mount.entry = $SHARED/recordings usr/local/eb/recordings none bind 0 0

# Devices
lxc.cgroup2.devices.allow = c 116:* rwm
lxc.mount.entry = /dev/snd dev/snd none bind,optional,create=dir

# Start options
lxc.start.auto = 1
lxc.start.order = 301
lxc.start.delay = 2
lxc.group = eb-group
lxc.group = eb-jibri
EOF

# start the container
lxc-start -n $MACH -d
lxc-wait -n $MACH -s RUNNING

# wait for the network to be up
for i in $(seq 0 9); do
    lxc-attach -n $MACH -- ping -c1 host.loc && break || true
    sleep 1
done

# ------------------------------------------------------------------------------
# HOSTNAME
# ------------------------------------------------------------------------------
lxc-attach -n $MACH -- zsh <<EOS
set -e
echo $MACH > /etc/hostname
sed -i 's/\(127.0.1.1\s*\).*$/\1$MACH/' /etc/hosts
hostname $MACH
EOS

# ------------------------------------------------------------------------------
# HOST PACKAGES
# ------------------------------------------------------------------------------
zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get $APT_PROXY_OPTION -y install kmod alsa-utils
EOS

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
apt-get $APT_PROXY_OPTION -y install gnupg unzip
apt-get $APT_PROXY_OPTION -y install libnss3-tools
apt-get $APT_PROXY_OPTION -y install va-driver-all vdpau-driver-all
apt-get $APT_PROXY_OPTION -y --install-recommends install ffmpeg
apt-get $APT_PROXY_OPTION -y install x11vnc
EOS

# google chrome
cp etc/apt/sources.list.d/google-chrome.list $ROOTFS/etc/apt/sources.list.d/
lxc-attach -n $MACH -- zsh <<EOS
set -e
wget -qO /tmp/google-chrome.gpg.key \
    https://dl.google.com/linux/linux_signing_key.pub
apt-key add /tmp/google-chrome.gpg.key
apt-get $APT_PROXY_OPTION update
EOS

lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get $APT_PROXY_OPTION -y --install-recommends install google-chrome-stable
EOS

# chromedriver
lxc-attach -n $MACH -- zsh <<EOS
set -e
CHROME_VER=\$(dpkg -s google-chrome-stable | egrep "^Version" | \
    cut -d " " -f2 | cut -d. -f1)
CHROMEDRIVER_VER=\$(curl -s \
    https://chromedriver.storage.googleapis.com/LATEST_RELEASE_\$CHROME_VER)
wget -qO /tmp/chromedriver_linux64.zip \
    https://chromedriver.storage.googleapis.com/\$CHROMEDRIVER_VER/chromedriver_linux64.zip
unzip /tmp/chromedriver_linux64.zip -d /usr/local/bin/
chmod 755 /usr/local/bin/chromedriver
EOS

# jibri
cp etc/apt/sources.list.d/jitsi-stable.list $ROOTFS/etc/apt/sources.list.d/
lxc-attach -n $MACH -- zsh <<EOS
set -e
wget -qO /tmp/jitsi.gpg.key https://download.jitsi.org/jitsi-key.gpg.key
cat /tmp/jitsi.gpg.key | gpg --dearmor >/usr/share/keyrings/jitsi.gpg
apt-get update
EOS

lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get $APT_PROXY_OPTION -y install openjdk-11-jre-headless
apt-get $APT_PROXY_OPTION -y install jibri
EOS

# removed packages
lxc-attach -n $MACH -- zsh <<EOS
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get -y purge upower
EOS

# ------------------------------------------------------------------------------
# SYSTEM CONFIGURATION
# ------------------------------------------------------------------------------
# disable ssh service
lxc-attach -n $MACH -- zsh <<EOS
set -e
systemctl stop ssh.service
systemctl disable ssh.service
EOS

# snd_aloop module
[ -z "$(egrep '^snd_aloop' /etc/modules)" ] && echo snd_aloop >>/etc/modules
cp $MACHINES/eb-jibri-host/etc/modprobe.d/alsa-loopback.conf /etc/modprobe.d/
rmmod -f snd_aloop || true
modprobe snd_aloop || true
[[ "$DONT_CHECK_SND_ALOOP" = true ]] || [[ -n "$(lsmod | ack snd_aloop)" ]]

# google chrome managed policies
mkdir -p $ROOTFS/etc/opt/chrome/policies/managed
cp etc/opt/chrome/policies/managed/eb-policies.json \
    $ROOTFS/etc/opt/chrome/policies/managed/

# ------------------------------------------------------------------------------
# JIBRI
# ------------------------------------------------------------------------------
# jibri groups
lxc-attach -n $MACH -- zsh <<EOS
set -e
usermod -aG adm,audio,video,plugdev jibri
EOS

# jibri ssh
mkdir -p $ROOTFS/home/jibri/.ssh
chmod 700 $ROOTFS/home/jibri/.ssh
cp home/jibri/.ssh/jibri-config $ROOTFS/home/jibri/.ssh/
[[ -f /root/.ssh/jibri ]] && \
    cp /root/.ssh/jibri $ROOTFS/home/jibri/.ssh/ || \
    true

lxc-attach -n $MACH -- zsh <<EOS
set -e
chown jibri:jibri /home/jibri/.ssh -R
EOS

# jibri icewm startup
mkdir -p $ROOTFS/home/jibri/.icewm
cp home/jibri/.icewm/startup $ROOTFS/home/jibri/.icewm/
chmod 755 $ROOTFS/home/jibri/.icewm/startup

# recordings directory
lxc-attach -n $MACH -- zsh <<EOS
set -e
chown jibri:jibri /usr/local/eb/recordings -R
EOS

# pki
lxc-attach -n $MACH -- zsh <<EOS
set -e
mkdir -p /home/jibri/.pki/nssdb
chmod 700 /home/jibri/.pki
chmod 700 /home/jibri/.pki/nssdb
chown jibri:jibri /home/jibri/.pki -R
EOS

# jibri config
cp etc/jitsi/jibri/jibri.conf $ROOTFS/etc/jitsi/jibri/

# the customized scripts
cp usr/local/bin/finalize-recording.sh $ROOTFS/usr/local/bin/
chmod 755 $ROOTFS/usr/local/bin/finalize-recording.sh
cp usr/local/bin/ffmpeg $ROOTFS/usr/local/bin/
chmod 755 $ROOTFS/usr/local/bin/ffmpeg

# jibri ephemeral config service
cp usr/local/sbin/jibri-ephemeral-config $ROOTFS/usr/local/sbin/
chmod 744 $ROOTFS/usr/local/sbin/jibri-ephemeral-config
cp etc/systemd/system/jibri-ephemeral-config.service \
    $ROOTFS/etc/systemd/system/

lxc-attach -n $MACH -- zsh <<EOS
set -e
systemctl daemon-reload
systemctl enable jibri-ephemeral-config.service
EOS

# jibri service
lxc-attach -n $MACH -- zsh <<EOS
set -e
systemctl enable jibri.service
systemctl start jibri.service
EOS

# jibri vnc
lxc-attach -n $MACH -- zsh <<EOS
set -e
mkdir -p /home/jibri/.vnc
x11vnc -storepasswd jibri /home/jibri/.vnc/passwd
chown jibri:jibri /home/jibri/.vnc -R
EOS

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
# EPHEMERAL JIBRI CONTAINERS
# ------------------------------------------------------------------------------
# jibri-ephemeral-container service
cp $MACHINES/eb-jibri-host/usr/local/sbin/jibri-ephemeral-start /usr/local/sbin/
cp $MACHINES/eb-jibri-host/usr/local/sbin/jibri-ephemeral-stop /usr/local/sbin/
chmod 744 /usr/local/sbin/jibri-ephemeral-start
chmod 744 /usr/local/sbin/jibri-ephemeral-stop

cp $MACHINES/eb-jibri-host/etc/systemd/system/jibri-ephemeral-container.service \
    /etc/systemd/system/

systemctl daemon-reload
systemctl enable jibri-ephemeral-container.service
systemctl start jibri-ephemeral-container.service
