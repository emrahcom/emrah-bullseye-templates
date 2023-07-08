# ------------------------------------------------------------------------------
# AWS-AUTO-SCALE.SH
# ------------------------------------------------------------------------------
set -e
source $INSTALLER/000-source

# ------------------------------------------------------------------------------
# ENVIRONMENT
# ------------------------------------------------------------------------------
MACH="$TAG-jitsi-host"
cd $MACHINES/$MACH

# ------------------------------------------------------------------------------
# INIT
# ------------------------------------------------------------------------------
[[ "$INSTALL_AWS_AUTO_SCALE" != true ]] && exit

echo
echo "---------------------- AWS AUTO SCALE ---------------------"

# ------------------------------------------------------------------------------
# PACKAGES
# ------------------------------------------------------------------------------
apt-get $APT_PROXY -y --no-install-recommends install awscli
apt-get $APT_PROXY -y install jq

# ------------------------------------------------------------------------------
# SYSTEM CONFIGURATION
# ------------------------------------------------------------------------------
systemctl stop aws-jvb-auto-scale.service || true
systemctl stop aws-jibri-auto-scale.service || true

cp usr/local/sbin/aws-jvb-auto-scale /usr/local/sbin/
cp usr/local/sbin/aws-jibri-auto-scale /usr/local/sbin/
chmod 744 /usr/local/sbin/aws-jvb-auto-scale
chmod 744 /usr/local/sbin/aws-jibri-auto-scale

cp etc/systemd/system/aws-jvb-auto-scale.service /etc/systemd/system/
cp etc/systemd/system/aws-jibri-auto-scale.service /etc/systemd/system/

systemctl daemon-reload
systemctl enable aws-jvb-auto-scale.service
systemctl start aws-jvb-auto-scale.service
systemctl enable aws-jibri-auto-scale.service
systemctl start aws-jibri-auto-scale.service
