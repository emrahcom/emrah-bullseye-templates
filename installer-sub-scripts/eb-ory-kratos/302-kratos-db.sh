# -----------------------------------------------------------------------------
# KRATOS-DB.SH
# -----------------------------------------------------------------------------
set -e
source $INSTALLER/000-source

# -----------------------------------------------------------------------------
# ENVIRONMENT
# -----------------------------------------------------------------------------
MACH="eb-postgres"
cd $MACHINES/$MACH

ROOTFS="/var/lib/lxc/$MACH/rootfs"

# -----------------------------------------------------------------------------
# INIT
# -----------------------------------------------------------------------------
[[ "$DONT_RUN_KRATOS_DB" = true ]] && exit

echo
echo "------------------------ KRATOS DB ------------------------"

# -----------------------------------------------------------------------------
# CONTAINER
# -----------------------------------------------------------------------------
# start the container
lxc-start -n $MACH -d
lxc-wait -n $MACH -s RUNNING

# wait for postgresql
lxc-attach -n eb-postgres -- \
    zsh -c \
    "set -e
     for try in \$(seq 1 9); do
         systemctl is-active postgresql.service && break || sleep 1
     done"

# -----------------------------------------------------------------------------
# BACKUP
# -----------------------------------------------------------------------------
[[ -f $ROOTFS//etc/postgresql/13/main/pg_hba.conf ]] && \
    cp $ROOTFS/etc/postgresql/13/main/pg_hba.conf $OLD_FILES/

# -----------------------------------------------------------------------------
# DROP DATABASE & ROLE
# -----------------------------------------------------------------------------
# drop the old database if RECREATE_KRATOS_DB_IF_EXISTS is set
if [[ "RECREATE_KRATOS_DB_IF_EXISTS" = true ]]; then
    lxc-attach -n eb-postgres -- \
        zsh -c \
        "set -e
         su -l postgres -c \
             'dropdb -f --if-exists kratos'"

    lxc-attach -n eb-postgres -- \
        zsh -c \
        "set -e
         su -l postgres -c \
             'dropuser --if-exists kratos'"
fi

# -----------------------------------------------------------------------------
# EXISTENCE CHECK
# -----------------------------------------------------------------------------
IS_DB_EXIST=$(lxc-attach -n eb-postgres -- \
    zsh -c \
    "set -e
     su -l postgres -c \
         'psql -At <<EOF
\l kratos
EOF
'")

IS_ROLE_EXIST=$(lxc-attach -n eb-postgres -- \
    zsh -c \
    "set -e
     su -l postgres -c \
         'psql -At <<EOF
\dg kratos
EOF
'")

# -----------------------------------------------------------------------------
# CREATE ROLE & DATABASE
# -----------------------------------------------------------------------------
[[ -z "$IS_ROLE_EXIST" ]] && lxc-attach -n eb-postgres -- \
    zsh -c \
    "set -e
     su -l postgres -c \
         'createuser -l kratos'"

[[ -z "$IS_DB_EXIST" ]] && lxc-attach -n eb-postgres -- \
    zsh -c \
    "set -e
     su -l postgres -c \
         'createdb -T template0 -O kratos -E UTF-8 -l en_US.UTF-8 kratos'"

# -----------------------------------------------------------------------------
# UPDATE PASSWD
# -----------------------------------------------------------------------------
DB_PASSWD=$(openssl rand -hex 20)
echo DB_PASSWD="$DB_PASSWD" >> $INSTALLER/000-source

lxc-attach -n eb-postgres -- \
    zsh -c \
    "set -e
     su -l postgres -s /usr/bin/psql -c \
         \"ALTER ROLE kratos WITH PASSWORD '$DB_PASSWD';\""

# -----------------------------------------------------------------------------
# ALLOWED HOSTS
# -----------------------------------------------------------------------------
lxc-attach -n eb-postgres -- \
    zsh -c \
    "set -e
     sed -i '/kratos/d' /etc/postgresql/13/main/pg_hba.conf

     cat >>/etc/postgresql/13/main/pg_hba.conf <<EOF
# ory-kratos database
host    kratos          kratos          172.22.22.0/24          md5
EOF

     systemctl restart postgresql.service"
