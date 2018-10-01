#!/bin/bash

# Shares
SHARE_HOME=/share/home
SHARE_SCRATCH=/share/scratch
NFS_SERVER_NAME=pttnas
NFS_ON_MASTER=/nxsdo01pool/nxsdo01pool/data
NFS_MOUNT=/scratch


# User
HPC_USER=hpcuser
HPC_UID=7007
HPC_GROUP=hpc
HPC_GID=7007

#############################################################################
log()
{
	echo "$1"	
}

usage() { echo "Usage: $0 [-m <masterName>] [-x <nasname>] [-y <nasdevice>] [-z <nasmount>] [-f <dnsServerName>] [-g <dnsServerIP>] [-h <nisDomainName>] [-i <nisDomainIP>] [-s <pbspro>] [-q <queuename>] [-S <beegfs, nfsonmaster, otherstorage>] [-n <ganglia>] [-c <postInstallCommand>] [-k <nfsservername>]" 1>&2; exit 1; }

while getopts :m:S:s:q:n:c:x:y:z:f:g:h:i:k: optname; do
  log "Option $optname set with value ${OPTARG}"
  
  case $optname in
    m)  # master name
		export MASTER_NAME=${OPTARG}
		;;
    S)  # Shared Storage (beegfs, nfsonmaster, otherstorage)
		export SHARED_STORAGE=${OPTARG}
		;;
    s)  # Scheduler (pbspro)
		export SCHEDULER=${OPTARG}
		;;
	k)  # NFSserver name
		export NFS_SERVER_NAME=${OPTARG}
		;;
    n)  # monitoring
		export MONITORING=${OPTARG}
		;;
    c)  # post install command
		export POST_INSTALL_COMMAND=${OPTARG}
		;;
	x)  # nas name
		export NAS_NAME=${OPTARG}
		;;
	y)  # nas device
		export NAS_DEVICE=${OPTARG}
		;;
	z)  # mount point
		export NAS_MOUNT=${OPTARG}
		;;
	f)  # dns name
		export DNS_NAME=${OPTARG}
		;;
	g)  # dns ip
		export DNS_IP=${OPTARG}
		;;
	h)  # NIS serve domain name
		export NIS_SERVER_DOMAIN=${OPTARG}
		;;
	i)  # NIS server ip
		export NIS_SERVER_IP=${OPTARG}
		;;
    q)  # queue name
		export QNAME=${OPTARG}
		;;
	*)
		usage
		;;
  esac
done

is_centos()
{
	python -mplatform | grep -qi CentOS
	return $?
}

is_suse()
{
	python -mplatform | grep -qi Suse
	return $?
}

is_ubuntu()
{
	python -mplatform | grep -qi Ubuntu
	return $?
}

install_beegfs_client()
{
	bash install_beegfs.sh ${MASTER_NAME} "client"
}
install_otherstorage()
{
	bash other_nas.sh ${NAS_NAME} ${NAS_DEVICE} ${NAS_MOUNT}
	echo "other storage is installed"
}

install_ganglia()
{
	bash install_ganglia.sh ${MASTER_NAME} "Cluster" 8649
}

install_pbspro()
{
	bash install_pbspro.sh ${MASTER_NAME} ${QNAME} ${DNS_NAME} ${DNS_IP}
}

install_blobxfer()
{
	if is_centos; then
		yum install -y gcc openssl-devel libffi-devel python-devel
		curl https://bootstrap.pypa.io/get-pip.py | python
		pip install --upgrade blobxfer
	fi
}
echo "${NAS_NAME} ${NAS_DEVICE} ${NAS_MOUNT}"
setup_nisdns()
{
	sed -i  "s/PEERDNS=yes/PEERDNS=no/g" /etc/sysconfig/network-scripts/ifcfg-eth0   
    sed -i  "s/search/#search/g" /etc/resolv.conf
	echo "search ${NIS_SERVER_DOMAIN}">>/etc/resolv.conf	
	echo "domain ${NIS_SERVER_DOMAIN}">>/etc/resolv.conf
	echo "nameserver ${NIS_SERVER_IP}">>/etc/resolv.conf
    echo "in set_DNS, updated resolv.conf"

    echo "in set_DNS, starting to write dhclient-exit-hooks"
    cat > /etc/dhcp/dhclient-exit-hooks << EOF
		str1="$(grep -x "search ${NIS_SERVER_DOMAIN}" /etc/resolv.conf)"
		str2="$(grep -x "#search ${NIS_SERVER_DOMAIN}" /etc/resolv.conf)"
		str3="search ${NIS_SERVER_DOMAIN}"
		str4="#search ${NIS_SERVER_DOMAIN}"
		if [ "$str1" == *"$str3"* && "$str2" != *"$str4"* ]; then
		    :
		else
		    echo "$str3" >>/etc/resolv.conf
		fi		
EOF

    echo "in set_DNS, written dhclient-exit-hooks"
    #sed -i 's/required_domain="mydomain.local"/required_domain="nxad01.pttep.local"/g' /etc/dhcp/dhclient-exit-hooks.d/azure-cloud.sh
    chmod 755 /etc/dhcp/dhclient-exit-hooks
    echo "in set_DNS, updated Execute permission for dhclient-exit-hooks"
	sed -i  "s/hosts:      files dns/hosts:      files dns nis/g"  /etc/nsswitch.conf
	sed -i  "s/passwd:     files/passwd:     files nis/g"  /etc/nsswitch.conf
	sed -i  "s/shadow:     files/shadow:     files nis/g"  /etc/nsswitch.conf
	sed -i  "s/group:      files/group:      files nis/g"  /etc/nsswitch.conf
	
	#sed -i  "s/networks:   files/networks:   files nis [NOTFOUND=return]/g"  /etc/nsswitch.conf
	#sed -i  "s/hosts:      files dns/hosts: files dns [NOTFOUND=return]/g"  /etc/nsswitch.conf
    echo "in set_DNS, updated nsswitch resolv.conf, restarting network service"
	service network restart
}

start_networkservice_in_cron()
{
	cat >  /root/start_networknamager.sh << "EOF"
#!/bin/bash
service NetworkManager stop
systemctl restart ypbind
mount -a
systemctl start NetworkManager.service
/etc/init.d/pbs start

EOF
	chmod 700 /root/start_networknamager.sh
	crontab -l > Networkcron
	echo "@reboot /root/start_networknamager.sh >>/root/log.txt" >> Networkcron
	crontab Networkcron
	rm Networkcron
}

setup_nisclient()
{
	yum -y install rpcbind ypbind
	ypdomainname ${NAS_NAME}
	echo "NISDOMAIN=${NIS_SERVER_DOMAIN}" >> /etc/sysconfig/network
	echo "${NIS_SERVER_IP} main.${NIS_SERVER_DOMAIN} main" >> /etc/hosts
	echo "domain ${NIS_SERVER_DOMAIN} server main.${NIS_SERVER_DOMAIN}" >> /etc/yp.conf	
	setup_nisdns
	systemctl start rpcbind ypbind 
	systemctl enable rpcbind ypbind
	service NetworkManager stop		
	systemctl restart ypbind	
	service NetworkManager start
	start_networkservice_in_cron
	
}

setup_user()
{
	if is_centos; then
		yum -y install nfs-utils nfs-utils-lib
	elif is_suse; then
		zypper -n install nfs-client
	elif is_ubuntu; then
		apt-get -qy install nfs-common 
	fi

    mkdir -p $SHARE_HOME
    mkdir -p $SHARE_SCRATCH
    mkdir -p $NFS_MOUNT

	echo "$MASTER_NAME:$SHARE_HOME $SHARE_HOME    nfs    rw,vers=3,auto,_netdev 0 0" >> /etc/fstab
    echo "$NFS_SERVER_NAME:$NAS_DEVICE $NAS_MOUNT nfs rsize=65536,wsize=65536,_netdev,nofail 0 0" >> /etc/fstab
	mount -a
	mount
   
    groupadd -g $HPC_GID $HPC_GROUP

    # Don't require password for HPC user sudo
    echo "$HPC_USER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    
    # Disable tty requirement for sudo
    sed -i 's/^Defaults[ ]*requiretty/# Defaults requiretty/g' /etc/sudoers

	useradd -c "HPC User" -g $HPC_GROUP -d $SHARE_HOME/$HPC_USER -s /bin/bash -u $HPC_UID $HPC_USER

    chown $HPC_USER:$HPC_GROUP $SHARE_SCRATCH	
}
setup_intel_mpi()
{
	if is_suse; then
		if [ -d "/opt/intelMPI" ]; then
			rpm -v -i --nodeps /opt/intelMPI/intel_mpi_packages/*.rpm
			impi_version=`ls /opt/intel/impi`
			ln -s /opt/intel/impi/${impi_version}/intel64/bin/ /opt/intel/impi/${impi_version}/bin
			ln -s /opt/intel/impi/${impi_version}/lib64/ /opt/intel/impi/${impi_version}/lib
		fi		
	fi
}

mkdir -p /var/local
SETUP_MARKER=/var/local/cn-setup.marker
if [ -e "$SETUP_MARKER" ]; then
    echo "We're already configured, exiting..."
    exit 0
fi

if is_centos; then
	# disable selinux
	sed -i 's/enforcing/disabled/g' /etc/selinux/config
	setenforce permissive
fi

if is_ubuntu; then
	# there is an issue here because apt may be already running the first time the machine is booted
	while true;
	do
		if [[ $(ps -A | grep -c apt)  -ne 1 ]]; then
			echo "apt is running, wait 1m"
		else
			break
		fi
		sleep 1m
	done
fi
setup_nisclient
setup_user
if [ "$MONITORING" == "ganglia" ]; then
	install_ganglia
fi

if [ "$SCHEDULER" == "pbspro" ]; then
	install_pbspro
fi

if [ "$SHARED_STORAGE" == "beegfs" ]; then
	install_beegfs_client
elif [ "$SHARED_STORAGE" == "nfsonmaster" ]; then
		mount_nfs
elif [ "$SHARED_STORAGE" == "otherstorage" ]; then
		echo "other storage is installing"
		install_otherstorage
fi

setup_intel_mpi
#systemctl stop NetworkManager.service
#systemctl disable NetworkManager.service
#install_blobxfer

if [ -n "$POST_INSTALL_COMMAND" ]; then
	echo "running $POST_INSTALL_COMMAND"
	eval $POST_INSTALL_COMMAND
fi
# Create marker file so we know we're configured
touch $SETUP_MARKER
systemctl stop NetworkManager.service
systemctl disable NetworkManager.service
shutdown -r +1 &
exit 0
