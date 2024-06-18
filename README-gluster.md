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

# Adding a new server as a Gluster node (Rocky 9.4)
This documentation details installing gluster and creating a new brick.

---
## Installation

### Configure CentOS Release of Gluster
```sh
sudo dnf install -y centos-release-gluster11 centos-release-nfs-ganesha4

# Recommended for package stability:
# sudo sed -i -e "s/enabled=1/enabled=0/g" /etc/yum.repos.d/CentOS-Gluster-11.repo
# sudo sed -i -e "s/enabled=1/enabled=0/g" /etc/yum.repos.d/CentOS-NFS-Ganesha-4.repo
```

### Install Gluster and NFS-Ganesha
```sh
sudo dnf install -y --enablerepo=centos-nfs-ganesha-4 --enablerepo=devel \
glusterfs glusterfs-libs glusterfs-server glusterfs-client nfs-ganesha-gluster nfs-ganesha
```

### Configure NFS-Ganesha
#### /etc/ganesha/ganesha.conf
```sh
NFS_CORE_PARAM {
        mount_path_pseudo = true;
        Protocols = 3,4;
}

EXPORT_DEFAULTS {
        Access_Type = RW;
}


EXPORT
{
        Export_Id = 1;
        Path = "/bulk";

        FSAL {
                name = GLUSTER;
                hostname = "10.0.8.254";
                volume = "glass_bulk";
        }

        Squash = No_root_squash;
        Pseudo = "/bulk";
        SecType = "sys";
}

EXPORT
{
        Export_Id = 2;
        Path = "/cfg"; 

        FSAL {
                name = GLUSTER;
                hostname = "10.0.8.254";
                volume = "glass_cfg";
        }

        Squash = No_root_squash;
        Pseudo = "/cfg";
        SecType	= "sys";
}

LOG {
        Default_Log_Level = WARN;
}
```

### Configure Firewall
```sh
sudo firewall-cmd --zone=public --add-service=glusterfs --permanent
sudo firewall-cmd --add-service=nfs
sudo firewall-cmd --reload
```

### Enable Gluster and NFS-Ganesha
```sh
sudo systemctl enable glusterd --now
sudo systemctl disable nfs-server --now
sudo systemctl enable nfs-ganesha --now
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
