# -----------------------------------------------------------------------------
# JITSI-CUSTOMIZATION.SH
# -----------------------------------------------------------------------------
set -e
source $INSTALLER/000-source

# -----------------------------------------------------------------------------
# ENVIRONMENT
# -----------------------------------------------------------------------------
MACH="eb-jitsi-host"
cd $MACHINES/$MACH

# -----------------------------------------------------------------------------
# INIT
# -----------------------------------------------------------------------------
[ "$DONT_RUN_JITSI_CUSTOMIZATION" = true ] && exit

echo
echo "------------------- JITSI CUSTOMIZATION -------------------"

# -----------------------------------------------------------------------------
# CUSTOMIZATION
# -----------------------------------------------------------------------------
JITSI_MEET="/var/lib/lxc/eb-jitsi/rootfs/usr/share/jitsi-meet"

if [[ ! -d "/root/jitsi-customization" ]]; then
    cp -arp root/jitsi-customization /root/
    cp $JITSI_MEET/images/favicon.ico /root/jitsi-customization/
    cp $JITSI_MEET/images/watermark.svg /root/jitsi-customization/

    sed -i "s/___TURN_FQDN___/$TURN_FQDN/g" \
        /root/jitsi-customization/README.md
    sed -i "s/___JITSI_FQDN___/$JITSI_FQDN/g" \
        /root/jitsi-customization/README.md
    sed -i "s/___JITSI_FQDN___/$JITSI_FQDN/g" \
        /root/jitsi-customization/customize.sh

    bash /root/jitsi-customization/customize.sh
else
    echo "There is already an old customization folder."
    echo "Automatic customization skipped."
    echo "Run your own customization script manually."
fi
