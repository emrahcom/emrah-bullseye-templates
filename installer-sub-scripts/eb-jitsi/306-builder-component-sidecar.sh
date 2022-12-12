# ------------------------------------------------------------------------------
# COMPONENT-SIDECAR.SH
# ------------------------------------------------------------------------------
set -e
source $INSTALLER/000-source

# ------------------------------------------------------------------------------
# ENVIRONMENT
# ------------------------------------------------------------------------------
MACH="$TAG-builder"
cd $MACHINES/$MACH

ROOTFS="/var/lib/lxc/$MACH/rootfs"
PROJECT_REPO="https://github.com/jitsi/jitsi-component-sidecar.git"
DEBFULLNAME="EB Jitsi Team"
DEBEMAIL="emrah.com@gmail.com"

# ------------------------------------------------------------------------------
# INIT
# ------------------------------------------------------------------------------
[[ "$DONT_BUILD_COMPONENT_SIDECAR" = true ]] && exit

echo
echo "-------------------- COMPONENT SIDECAR --------------------"

# ------------------------------------------------------------------------------
# CONTAINER
# ------------------------------------------------------------------------------
# start the container
lxc-start -n $MACH -d
lxc-wait -n $MACH -s RUNNING

# wait for the network to be up
for i in $(seq 0 9); do
    lxc-attach -n $MACH -- ping -c1 host.loc && break || true
    sleep 1
done

# ------------------------------------------------------------------------------
# JITSI-COMPONENT-SIDECAR
# ------------------------------------------------------------------------------
# build
lxc-attach -n $MACH -- zsh <<EOS
set -e
mkdir -p /home/dev/src
chown dev:dev /home/dev/src
rm -rf /home/dev/src/jitsi-component-sidecar* || true
EOS

lxc-attach -n $MACH -- zsh <<EOS
set -e
su -l dev <<EOSS
    set -e

    cd ~/src
    git clone $PROJECT_REPO
    cd ~/src/jitsi-component-sidecar/resources

    export DEBFULLNAME=$DEBFULLNAME
    export DEBEMAIL=$DEBEMAIL
    bash build_deb_package.sh
EOSS
EOS

# store
mkdir -p /root/$TAG-store
cp $ROOTFS/home/dev/src/jitsi-component-sidecar_*_all.deb \
    /root/$TAG-store/jitsi-component-sidecar.deb

# ------------------------------------------------------------------------------
# CONTAINER SERVICES
# ------------------------------------------------------------------------------
lxc-stop -n $MACH
lxc-wait -n $MACH -s STOPPED
