#!/bin/bash

.PHONY: build-gluster clean-gluster install-packages test

test:
	cd ansible && \
	ansible-playbook -i inventory/hosts.yml 50-configure-cluster.yaml \
		--tags networking-test

install-packages:
	sudo apt-get update && \
	sudo apt-get install -y make automake autoconf libtool flex bison  \
  	pkg-config libssl-dev libxml2-dev python3-dev libaio-dev       \
	libibverbs-dev librdmacm-dev libreadline-dev liblvm2-dev      \
	libglib2.0-dev liburcu-dev libcmocka-dev libsqlite3-dev       \
	libacl1-dev liburing-dev google-perftools libgoogle-perftools-dev

clean-gluster:
	rm -rf build/*
	
build-gluster:
	cd build && \
	wget https://github.com/gluster/glusterfs/archive/refs/tags/v11.1.zip && \
	unzip v11.1.zip && \
	cd glusterfs-11.1 && \
	./autogen.sh && \
	./configure --prefix=/workspaces/cluster/ansible/files/bin && \
	make -j8 && \
	sudo make install
