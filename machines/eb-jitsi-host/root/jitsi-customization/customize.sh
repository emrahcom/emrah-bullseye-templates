#!/usr/bin/bash
set -e

# ------------------------------------------------------------------------------
# This script customizes the Jitsi installation. Run it on the host machine.
#
# usage:
#     bash customize.sh
# ------------------------------------------------------------------------------
BASEDIR=$(dirname $0)
JITSI_ROOTFS="/var/lib/lxc/eb-jitsi/rootfs"
JITSI_MEET_CONFIG="$JITSI_ROOTFS/etc/jitsi/meet/___JITSI_FQDN___-config.js"
JITSI_MEET_INTERFACE="$JITSI_ROOTFS/usr/share/jitsi-meet/interface_config.js"
JITSI_MEET_APP="$JITSI_ROOTFS/usr/share/jitsi-meet"

# ------------------------------------------------------------------------------
# config.js
# ------------------------------------------------------------------------------
[[ -f "$BASEDIR/files/___JITSI_FQDN___-config.js" ]] && \
    cp $BASEDIR/files/___JITSI_FQDN___-config.js $JITSI_MEET_CONFIG

# ------------------------------------------------------------------------------
# interface_config.js
# ------------------------------------------------------------------------------
[[ -f "$BASEDIR/files/interface_config.js" ]] && \
    cp $BASEDIR/files/interface_config.js $JITSI_MEET_INTERFACE

# ------------------------------------------------------------------------------
# custom files
# ------------------------------------------------------------------------------
[[ -f "$BASEDIR/files/favicon.ico" ]] && \
    cp $BASEDIR/files/favicon.ico $JITSI_MEET_APP/
[[ -f "$BASEDIR/files/favicon.ico" ]] && \
    cp $BASEDIR/files/favicon.ico $JITSI_MEET_APP/images/
[[ -f "$BASEDIR/files/watermark.svg" ]] && \
    cp $BASEDIR/files/watermark.svg $JITSI_MEET_APP/images/
