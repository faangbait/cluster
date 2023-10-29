## Create single partition on disk
```
sudo fdisk /dev/sdx1
d # delete existing partitions
g # make gpt
n # make new partition
w # write
```

## Create physical volume
`sudo pvcreate --dataalignment 256K /dev/sdx1`

# Adding a new server as a Gluster node (Rocky 8.7)
This documentation details installing gluster and creating a new brick.

---
## Installation

### Configure CentOS Release of Gluster
```sh
sudo dnf install -y centos-release-gluster10 centos-release-nfs-ganesha4
```

### /etc/yum.repos.d/CentOS-Gluster-9.repo
```ini
[centos-gluster9]
name=CentOS-$releasever - Gluster 9
baseurl=https://dl.rockylinux.org/vault/centos/8.5.2111/storage/x86_64/gluster-9/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-SIG-Storage
```

### Configure Firewall and Install Gluster
```sh
sudo firewall-cmd --zone=public --add-service=glusterfs --permanent
sudo firewall-cmd --reload
sudo yum install -y glusterfs glusterfs-libs glusterfs-server glusterfs-client glusterfs-ganesha nfs-ganesha-gluster --enablerepo=devel
sudo systemctl enable glusterd --now

```

### Peer new server
```sh
# from an existing node
sudo gluster peer probe <hostname>
```

### Add client mount points
```sh
sudo mkdir -p /mnt/replicated /mnt/bulk
sudo chattr +i /mnt/replicated /mnt/bulk

echo "localhost:/glass_cfg /mnt/replicated glusterfs defaults,_netdev,x-systemd.requires=glusterd.service,x-systemd.automount 0 0" | sudo tee -a /etc/fstab

echo "localhost:/glass_bulk /mnt/bulk glusterfs defaults,_netdev,x-systemd.requires=glusterd.service,x-systemd.automount 0 0" | sudo tee -a /etc/fstab
```

### /etc/lvm/lvm.conf
```conf
thin_pool_autoextend_threshold = 70
```
```sh
sudo sed -i 's/# thin_pool_autoextend_threshold = 70$/thin_pool_autoextend_threshold = 70/' /etc/lvm/lvm.conf

```
---

## Build a new Brick
This converts /dev/sdx into a brick named gluster5. The resulting brick can be combined with other bricks to form a gluster volume.

### Nuke existing drive (__DANGEROUS__)
```sh
dd if=/dev/zero of=/dev/sdx bs=1k count=1
```

### Create volume group
```sh
sudo vgcreate gluster5 /dev/sdx1
```

### Create thinpool
```sh
sudo lvcreate --thinpool gluster5/thin_pool --size 1T  --chunksize 256K --poolmetadatasize 16G --zero n
```

### Create thin logical volume
```sh
sudo lvcreate -V 1G -T gluster5/thin_pool -n brickvol
```

### Extend the LV to the full size of disk
```sh
sudo lvextend /dev/gluster5/brickvol /dev/sdx1
```

### Make XFS filesystem
```sh
sudo mkfs.xfs -i size=512 -n size=8192 /dev/gluster5/brickvol
```

### Add to /etc/fstab
```sh
echo "/dev/mapper/gluster5-brickvol /data/glusterfs/glass5 xfs rw,inode64,noatime,nouuid 1 2" | sudo tee -a /etc/fstab
```

### Mount and create folder for brick
```sh
sudo mount -a
sudo mkdir -p /data/glusterfs/glass5/brick5
```
