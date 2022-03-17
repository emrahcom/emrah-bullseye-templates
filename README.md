# Table of contents

- [About](#about)
- [Usage](#usage)
- [Available templates](#available-templates)
  - [eb-base](#eb-base)
    - [To install eb-base](#to-install-eb-base)
  - [eb-jitsi](#eb-jitsi)
    - [Main components of eb-jitsi](#main-components-of-eb-jitsi)
    - [Before installing eb-jitsi](#before-installing-eb-jitsi)
    - [To install eb-jitsi](#to-install-eb-jitsi)
    - [Let's Encrypt support for eb-jitsi](#lets-encrypt-support-for-eb-jitsi)
    - [Jitsi cluster](#jitsi-cluster)
- [Requirements](#requirements)

# About

`emrah-bullseye` is an installer to create containerized systems on
`Debian 11 Bullseye` host. It built on top of `LXC` (Linux containers). This
repository contains the `emrah-bullseye` templates.

# Usage

Download the installer, run it with a template name as an argument and drink a
coffee. That's it.

```bash
wget https://raw.githubusercontent.com/emrahcom/emrah-bullseye-base/main/installer/eb
wget https://raw.githubusercontent.com/emrahcom/emrah-bullseye-templates/main/installer/<TEMPLATE_NAME>.conf
bash eb <TEMPLATE_NAME>
```

# Available templates

## eb-base

This template installs only a containerized `Debian 11 Bullseye`.

#### To install eb-base

```bash
wget https://raw.githubusercontent.com/emrahcom/emrah-bullseye-base/main/installer/eb
wget https://raw.githubusercontent.com/emrahcom/emrah-bullseye-templates/main/installer/eb-base.conf
bash eb eb-base
```

## eb-jitsi

This template installs a ready-to-use self-hosted `Jitsi`/`Jibri` service.

#### Main components of eb-jitsi

- [Jitsi](https://jitsi.org/)
- [Jibri](https://github.com/jitsi/jibri)
- [Nginx](http://nginx.org/)

#### Before installing eb-jitsi

- Jibri needs `snd_aloop` kernel module, therefore it's not OK with the cloud
  kernel. Install the standard Linux kernel first if this is the case.

- It's needed resolvable host addresses for `Jitsi` and `TURN` which point to
  your server. Therefore add DNS A records first if you didn't add yet. These
  host addresses will be used as `JITSI_FQDN` and `TURN_FQDN` in the installer
  config file.

#### To install eb-jitsi

Download the installer

```bash
wget https://raw.githubusercontent.com/emrahcom/emrah-bullseye-base/main/installer/eb
wget https://raw.githubusercontent.com/emrahcom/emrah-bullseye-templates/main/installer/eb-jitsi.conf
```

Open `eb-jitsi.conf` file with an editor and edit `JITSI_FQDN` and `TURN_FQDN`.

```bash
vim eb-jitsi.conf
```

```
export JITSI_FQDN=jitsi.mydomain.corp
export TURN_FQDN=turn.mydomain.corp
```

And run the installer

```bash
bash eb eb-jitsi
```

#### Let's Encrypt support for eb-jitsi

To set the Let's Encrypt certificate, run the following commands on the host:

```bash
FQDNS="jitsi.mydomain.corp,turn.mydomain.corp"
set-letsencrypt-cert $FQDNS
```

#### Jitsi cluster

See [Jitsi cluster document](docs/jitsi-cluster.md)

# Requirements

`emrah-bullseye` requires a `Debian 11 Bullseye` host with a minimal setup and
the Internet access during the installation. It's not a good idea to use your
desktop machine or an already in-use production server as a host machine.
Please, use one of the followings as a host:

- a cloud computer from a hosting/cloud service
  ([DigitalOcean](https://www.digitalocean.com)'s droplet,
  [Amazon](https://console.aws.amazon.com) EC2 instance etc)

- a virtual machine (VMware, VirtualBox etc)

- a `Debian 11 Bullseye` container (_with the nesting support_)
  ```
  lxc.include = /usr/share/lxc/config/nesting.conf
  lxc.apparmor.profile = unconfined
  lxc.apparmor.allow_nesting = 1
  ```

- a physical machine with a fresh installed
  [Debian 11 Bullseye](https://www.debian.org/releases/bullseye/debian-installer/)
