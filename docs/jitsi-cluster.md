![Jitsi Cluster](images/jitsi-cluster.png)

# Easy way to create a Jitsi cluster based on Debian 11 Bullseye

- [1. About](#1-about)
- [2. Jitsi Meet Server (JMS)](#2-jitsi-meet-server-jms)
  - [2.1 Prerequisites](#21-prerequisites)
    - [2.1.1 Machine features](#211-machine-features)
    - [2.1.2 DNS record for JMS](#212-dns-record-for-jms)
    - [2.1.3 DNS record for TURN](#213-dns-record-for-turn)
    - [2.1.4 The snd_aloop module](#214-the-snd_aloop-module)
    - [2.1.5 Public ports](#215-public-ports)
  - [2.2 Installing JMS](#22-installing-jms)
    - [2.2.1 Downloading the installer](#221-downloading-the-installer)
    - [2.2.2 Setting the host addresses](#222-setting-the-host-addresses)
    - [2.2.3 Development environment](#223-development-environment-optional)
    - [2.2.4 Running the installer](#224-running-the-installer)
    - [2.2.5 Let's Encrypt certificate](#225-lets-encrypt-certificate)
    - [2.2.6 Reboot](#226-reboot)
- [3. Additional Jitsi Videobridge (JVB) node](#3-additional-jitsi-videobridge-jvb-node)
  - [3.1 Prerequisites](#31-prerequisites)
    - [3.1.1 Machine features](#311-machine-features)
    - [3.1.2 Public ports](#312-public-ports)
  - [3.2 Installing JVB](#32-installing-jvb)
    - [3.2.1 Adding the JMS public key](#321-adding-the-jms-public-key)
    - [3.2.2 Adding the JVB node to the pool](#322-adding-the-jvb-node-to-the-pool)
- [4. Additional Jibri node](#4-additional-jibri-node)
  - [4.1 Prerequisites](#41-prerequisites)
    - [4.1.1 Machine features](#411-machine-features)
    - [4.1.2 The snd_aloop module](#412-the-snd_aloop-module)
    - [4.1.3 Public ports](#413-public-ports)
  - [4.2 Installing Jibri](#42-installing-jibri)
    - [4.2.1 Adding the JMS public key](#421-adding-the-jms-public-key)
    - [4.2.2 Adding the Jibri node to the pool](#422-adding-the-jibri-node-to-the-pool)
- [5- FAQ](#5-faq)

## 1. About

This tutorial provides step by step instructions on how to create a Jitsi
cluster based on `Debian 11 Bullseye`.

Create or install a `Debian 11 Bullseye` server for each node in this tutorial.
Please, don't install a desktop environment, only the standard packages...

Run each command on this tutorial as `root`.

## 2. Jitsi Meet Server (JMS)

`JMS` is a standalone server with conference room, video recording and streaming
features. If the load level is low and simultaneous recording will not be made,
`JMS` can operate without an additional `JVB` or `Jibri` node.

Additional `JVB` and `Jibri` nodes can be added in the future if needed.

#### 2.1 Prerequisites

Complete the following steps before starting the `JMS` installation.

##### 2.1.1 Machine features

At least 4 cores and 8 GB RAM (no recording / no streaming)\
At least 8 cores and 8 GB RAM (with recording/streaming)

##### 2.1.2 DNS record for JMS

A resolvable host address is required for `JMS` and this address should point to
this server. Therefore, create the DNS `A record` for `JMS` before starting the
installation.

Let's say the host address of `JMS` is `jitsi.mydomain.corp` then the following
command should resolv the server IP address:

```bash
host jitsi.mydomain.corp

>>> jitsi.mydomain.corp has address 1.2.3.4
```

##### 2.1.3 DNS record for TURN

A resolvable host address is required for `TURN` and this address should point
to this server. Therefore, create the DNS `CNAME record` for `TURN` before
starting the installation. The `CNAME record` should be an alias for `JMS` which
is `jitsi.mydomain.corp` in our example.

Let's say the host address of `TURN` is `turn.mydomain.corp` then the following
command should resolv the server IP address:

```bash
host turn.mydomain.corp

>>> turn.mydomain.corp is an alias for jitsi.mydomain.corp.
>>> jitsi.mydomain.corp has address 1.2.3.4
```

##### 2.1.4 The snd_aloop module

`JMS` needs the `snd_aloop` kernel module to be able to record/stream a
conference but some cloud computers have a kernel that doesn't support it. In
this case, first install the standart Linux kernel and reboot the node with this
kernel. If you don't know how to do this, check [FAQ](#5-faq).

Run the following command to check the `snd_aloop` support. If the command has
an output, it means that the kernel doesn't support it.

```bash
modprobe snd_aloop
```

##### 2.1.5 Public ports

If the `JMS` server is behind a firewall, open the following ports:

- TCP/80
- TCP/443
- TCP/5222
- UDP/10000

#### 2.2 Installing JMS

Installation will be done with
[emrah-bullseye](https://github.com/emrahcom/emrah-bullseye-templates)
installer.

##### 2.2.1 Downloading the installer

```bash
wget -O eb https://raw.githubusercontent.com/emrahcom/emrah-bullseye-base/main/installer/eb
wget -O eb-jitsi.conf https://raw.githubusercontent.com/emrahcom/emrah-bullseye-templates/main/installer/eb-jitsi.conf
```

##### 2.2.2 Setting the host addresses

Set the host addresses on the installer config file `eb-jitsi.conf`. The host
addresses must be FQDN, not IP address... Let's say the host address of `JMS` is
`jitsi.mydomain.corp` and the host address of TURN is `turn.mydomain.corp`

```bash
echo export TURN_FQDN=turn.mydomain.corp >> eb-jitsi.conf
echo export JITSI_FQDN=jitsi.mydomain.corp >> eb-jitsi.conf
```

##### 2.2.3 Development environment (optional)

This is an advanced option and skip this step if you don't need a development
environment.

To install the development environment:

```bash
echo export INSTALL_JICOFO_DEV=true >> eb-jitsi.conf
echo export INSTALL_JITSI_MEET_DEV=true >> eb-jitsi.conf
```

##### 2.2.4 Running the installer

```bash
bash eb eb-jitsi
```

##### 2.2.5 Let's Encrypt certificate

Let's say the host address of `JMS` is `jitsi.mydomain.corp` and the host
address of `TURN` is `turn.mydomain.corp`. To set the Let's Encrypt certificate:

```bash
set-letsencrypt-cert jitsi.mydomain.corp,turn.mydomain.corp
```

##### 2.2.6 Reboot

Reboot the server

```bash
reboot
```

## 3. Additional Jitsi Videobridge (JVB) node

A standalone `JMS` installation is good for a limited size of concurrent
conferences but the first limiting factor is the `JVB` component, that handles
the actual video and audio traffic. It is easy to scale the `JVB` pool
horizontally by adding as many as `JVB` nodes when needed.

#### 3.1 Prerequisites

Complete the following steps before starting the `JVB` installation.

##### 3.1.1 Machine features

At least 4 cores and 8 GB RAM

##### 3.1.2 Public ports

If the `JVB` server is behind a firewall, open the following ports:

- TCP/22 (at least for `JMS` server)
- TCP/9090 (at least for `JMS` server)
- UDP/10000

#### 3.2 Installing JVB

##### 3.2.1 Adding the JMS public key

If `openssh-server` is not installed on the `JVB` node, install it first!

```bash
apt-get -y update
apt-get install openssh-server curl
```

Add the `JMS` public key to the `JVB` node.

```bash
mkdir -p /root/.ssh
chmod 700 /root/.ssh
curl https://jitsi.mydomain.corp/static/jms.pub >> /root/.ssh/authorized_keys
```

##### 3.2.2 Adding the JVB node to the pool

Let's say the IP address of the `JVB` node is `100.1.2.3`. On the `JMS` server:

```bash
add-jvb-node 100.1.2.3
```

## 4. Additional Jibri node

A standalone `JMS` installation can only record a limited number of concurrent
conferences but the CPU and RAM capacities are the limiting factor for the
`Jibri` component. It is easy to scale the `Jibri` pool horizontally by adding
as many as `Jibri` nodes when needed.

#### 4.1 Prerequisites

Complete the following steps before starting the `Jibri` installation.

##### 4.1.1 Machine features

At least 8 cores and 8 GB RAM

##### 4.1.2 The snd_aloop module

The `Jibri` node needs the `snd_aloop` module too. Therefore check the kernel
first.

##### 4.1.3 Public ports

If the `Jibri` server is behind a firewall, open the following ports:

- TCP/22 (at least for `JMS` server)

#### 4.2 Installing Jibri

##### 4.2.1 Adding the JMS public key

If `openssh-server` is not installed on the `Jibri` node, install it first!

```bash
apt-get -y update
apt-get install openssh-server curl
```

Add the `JMS` public key to the `Jibri` node.

```bash
mkdir -p /root/.ssh
chmod 700 /root/.ssh
curl https://jitsi.mydomain.corp/static/jms.pub >> /root/.ssh/authorized_keys
```

##### 4.2.2 Adding the Jibri node to the pool

Let's say the IP address of the `Jibri` node is `200.7.8.9`. On the `JMS`
server:

```bash
add-jibri-node 200.7.8.9
```

## 5. FAQ

#### 5.1 My kernel has no support for the snd_aloop module. How can I install the standard Linux kernel?

The cloud kernel used in most cloud machines has no support for the `snd_aloop`
module. Execute the following commands as `root` to install the standart Linux
kernel on a Debian system.

```
apt-get update
apt-get install linux-image-amd64
apt-get purge 'linux-image-*cloud*'
# Abort kernel removal? No
reboot
```

Check the active kernel after reboot

```
uname -a
```

#### 5.2 How can I change the Jitsi config on JMS?

First, connect to the Jitsi container `eb-jitsi` then edit the config files.

```bash
lxc-attach -n eb-jitsi
cd /etc/jitsi
ls
```

#### 5.3 How can I change the videobridge config on the additional JVB?

First, connect to the JVB container `eb-jvb` then edit the config files.

```bash
lxc-attach -n eb-jvb
cd /etc/jitsi/videobridge
ls
```

#### 5.4 I’ve setup the initial JMS node successfully, but getting a 'recording unavailable' error when trying to record.

At least 8 cores are required to start a `Jibri` instance. The first 4 cores are
reserved for the base processes. After these 4 cores, one `Jibri` instance is
started for each additional 4 cores.

Just shutdown the machine, increase the number of cores and reboot.

#### 5.5 How can I make a change/addition permanent in Jibri?

All running `Jibri` instances are ephemeral and changes made will disappear
after shutdown. Apply to the `eb-jibri-template` container to make a change
permanent and restart the Jibri instances.

#### 5.6 How can I restart all running Jibri instances?

Use the related `systemd` service.

```bash
systemctl stop jibri-ephemeral-container.service
systemctl start jibri-ephemeral-container.service
```

#### 5.7 Where are the recorded files?

`Jibri` creates a randomly named folder for each recording and puts the MP4 file
in it. The recording folder is `/usr/local/eb/recordings` and the MP4 files are
in the subfolders of this folder.

```bash
ls -alh /usr/local/eb/recordings/*
```
