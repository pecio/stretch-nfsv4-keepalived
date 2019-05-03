# NFSv4 cluster with Keepalived under Debian Stretch (Proof of Concept)
This is a weekend project for checking if it was possible to set
up an NFSv4 cluster without Pacemaker or similar.

The idea is the following: given we already have a replicated file
system between the two NFS servers, can we set up an otherwise
shared-nothing cluster with them? The answer seems to be yes.

## Disclaimer
This is not a production-ready solution. Think of it as a ready to
use laboratory.

Among other issues:
* everything is intended to run inside a local VirtualBox hypervisor
* backend storage is a 1 GB virtual disk shard through iSCSI
* iSCSI traffic does not use a dedicated network
* no redundancy for the aforementioned virtual disk
* ~~little~~ no security

## Requirements
The setup runs under Vagrant with VirtualBox specific customizations
and uses Ansible for provisioning, so you will need the three of
them. Each of the four machines uses the default 512 MB of RAM.
This has been developed/tested under macOS, but I have no reason to
think it will not work under other operating system (provided it can
run VirtualBox).

## Initial setup
We start with 4 Debian Stretch virtual machines:
* iSCSI target/storage backend ("iscsi")
* 2 NFS servers ("nfs1" and "nfs2")
* a client, so we can check it is working

They run the
[Vanilla Stetch 64 box from Debian](https://app.vagrantup.com/debian/boxes/stretch64)
with the only common customization of adding NTPd and
setting up `/etc/hosts`.

The iSCSI target machine has a second "data.vdi" 1 GB virtual
disk added and the four of them are configured
for a private network with static addresses.

Provision is made with a single run of ansible-playbook inside
of the "client" VM definition that affects all four virtual machines.

## Provisioning
I will try to explain what the Ansible playbook does.

### iSCSI setup
99% of this part is taken from
[a Techmint article](https://www.tecmint.com/setup-iscsi-target-and-initiator-on-debian-9/).
Setting up iSCSI was not the main target of this experiment;
I was gratefully surprised to find it is much easier than I
remembered from previous experiences.

My setup is even simpler than the one in the article, as I
have removed the LVM component and instead offered the whole
disk. Take into account is is a virtual machine and hence a
virtual disk I can choose the size of; in a physical machine
with physical disks it would be highly advisable to use LVM to
generate the iSCSI volumes.

#### iSCSI Target
The configuration of the iSCSI target is almost trivial. We
just install the `tgt` package, install our configuration file
and restart the service.

The configuration file is quite simple:
```
<target iqn.2018-08.es.raulpedroche:lun1>
  backing-store /dev/sdb
  initiator-address 192.168.50.11
  initiator-address 192.168.50.12
  incominguser nfs-iscsi-user secret0
  outgoinguser debian-iscsi-target s3cr3to
</target>
```

We define a single target "iqn.2018-08.es.raulpedroche:lun1"
(actually "lun1" is not too good a name, as this is a target
containing LUNs). For it, we set up:
* a single data LUN backed by the whole `/dev/sdb`
* an access list allowing `192.168.50.11` and `192.168.50.12` (the two NFS servers)
* inbound and outbound shared secrets for challenge/response authentication

#### iSCSI Initiators
The two NFS servers are then set up as iSCSI initiators. We
install the `open-iscsi` package and perform a target discovery
against `192.168.50.20` (the iSCSI target machine above), which
will create the directory and configuration file
`/etc/iscsi/nodes/iqn.2018-08.es.raulpedroche:lun1/192.168.50.20,3260,1/default`.
That is the node name as defined above
(`iqn.2018-08.es.raulpedroche:lun1`), access point address and
port (`192.168.50.20,3260`) and the LUN number (`1`). We then
customize this configuration file adding the CHAP data and
setting it for autostart.

On restart of the `open-iscsi` service, a new `/dev/sdb`
volume becomes available.

### OCFS2 Setup
Now it is time to set up two file systems (yes, two, we will
see below) over the shared disk. I choosed OCFS2 because it
is much more simple to set up than GFS2. As with the iSCSI
setup above, OCFS2 is not the target of the experiment.

I followed the instructions in
[this article](http://realtechtalk.com/configuring_ocfs2_clustered_file_system_on_debian_based_linux_including_ubuntu_and_kubuntu-109-articles)
and everything worked smoothly. Which says something (I am
unsure what) about OCFS2, as the article is 9 years old; the
only caveat was that `ocfs2console` package does no longer
exist but it seems not to be critical.

A limitation of OCFS2 is that it does not support setting up
file systems over logical volumes, only partitions.

#### OCFS2 Cluster itself
We start by installing the `ocfs2-tools` package, then we
enable starting the `O2CB` cluster service and copy a new
`/etc/ocfs2/cluster.conf`:

```
node:
  ip_port = 7777
  ip_address = 192.168.50.11
  number = 1
  name = nfs1
  cluster = ocfs2
node:
  ip_port = 7777
  ip_address = 192.168.50.12
  number = 2
  name = nfs2
  cluster = ocfs2
cluster:
  node_count = 2
  name = ocfs
```

We then restart the `o2cb.service` unit and we are good to go.

#### OCFS2 File Systems creation
We perform this part only in one of the two NFS servers.

First we use a very simple `sfdisk` script to create the
partition table of our shared disk:
* a 64 MB Linux partition
* a Linux partition with the remaining space

This yields the `/dev/sdb1` and `/dev/sdb2` devices. We create
a OCFS2 file system over each of them.

#### OCFS2 File Systems mounting
Now we reload the partition table in the other node and use
the Ansible "mount" module to set up the file systems in
`/etc/fstab` and mount them.

The mount points, `/var/lib/nfs` and `/srv/nfs4/data` are
previously created.

After mounting, ownership of the mounted `/srv/nfs4/data`
directory is given to the `vagrant` user.

### NFSv4 setup
This play has `serial: 1`. Actually only the installation
of the `nfs-kernel-server` package needs being non concurrent
(otherwise both nodes will try to create the same files in
`/var/lib/nfs` simultaneously and fail spectacularly), but
Ansible does not support per-task concurrency limits.

We first make `nfs-mountd.service` dependent on the
`ocfs2.service` that mounts the two filesystems above (it
needs `/var/lib/nfs`).  Then we install the
`nfs-kernel-server` package.

Now a `/var/lib/nfs/nsdcltrack` directory is created to workaround
[Debian bug #867067](https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=867067).

Then we set up the system for NFSv4 by enabling `idmapd`,
disabling NFSv2 and NFSv3 and installing the following
`/etc/exports` file:

```
/srv/nfs4       client(rw,sync,fsid=0,crossmnt,no_subtree_check)
/srv/nfs4/data  client(rw,sync,no_subtree_check)
```

Kernel NFS service will start with the host.

### Keepalived setup
This is the trickiest part.

First, we add a dependency to `keepalived.service` on
`nfs-server.service`. Then we install the `keepalived`
package.

Now we install `/usr/local/sbin/notify.sh`. It will be called by
Keepalived whenever the VRRP instance status changes. It sends a
line to syslog with its parameters and then
* when entering MASTER, restarts `nfs-server.service`
* when entering BACKUP, does nothing
* when entering FAULT, waits 10 seconds, checks status of
  `nfs-server.service` and tries to start it if it is down

We also modify `/etc/default/keepalived` so the system hostname is
passed as "configuration id" to the daemon, so we can use the same
`keepalived.conf` for both hosts.

Now we set the following `/etc/keepalived/keepalived.conf`:

```
global_defs {
  script_user root
}

vrrp_script ping_client {
  script "/bin/ping -c 1 client"
  fall 2
  rise 1
}

vrrp_script check_nfs {
  script "/bin/systemctl status nfs-server.service"
  interval 15
  fall 1
  rise 2
}

vrrp_instance VI_1 {
  state MASTER
  interface eth1
  virtual_router_id 101
@nfs1 priority 101
@nfs2 priority 100
  advert_int 1
  authentication {
    auth_type PASS
    auth_pass s3cr3t0
  }
  virtual_ipaddress {
    192.168.50.10
  }
  notify /usr/local/sbin/notify.sh
  track_script {
    ping_client
    check_nfs
  }
}
```

It specifies `root` as the user to run scripts (actually
redundant) then sets up two scripts that will be used further
below to check the status of the underlying system and
possibly set "FAIL" status:
1. ping the client every second (default) and fail if it does not
   succeed twice in a row, unfail if succeeds
2. Check `nfs-server.service` every 15 seconds, failing the first
   time it is down or in error, unfail if it suceeds twice in a
   row

Then it creates the VRRP instance "`VI_1`".
* it tries to become MASTER
* runs over `eth1`
* has id 101
* different pritority for each server (this is why we set up the
  config id daemon option)
* advertises every second
* sets a shared secret authentication
* controls 192.168.50.10 IP address
* runs the `/usr/local/sbin/notify.sh` script whenever state changes
* tracks the two scripts defined just above

At last, we restart `keepalived.service`. Our NFSv4 cluster is now
running.

### Client setup
In the client, we simply install the `nfs-common` package, create
the `/data` mount point and use the Ansible "mount" module to
mount it.
