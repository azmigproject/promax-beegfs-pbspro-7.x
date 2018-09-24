#!/bin/bash

set -x

if [[ $(id -u) -ne 0 ]] ; then
    echo "Must be run as root"
    exit 1
fi

if [ $# -lt 1 ]; then
    echo "Usage: $0 <MasterHostname> <queueName>"
    exit 1
fi

# Set user args
MASTER_HOSTNAME=$1
DNS_SERVER_NAME=$3
DNS_SERVER_IP=$4
QNAME=workq
PBS_MANAGER=hpcuser

if [ -n "$2" ]; then
	#enforce qname to be lowercase
	QNAME="$(echo ${2,,})"
fi

# Returns 0 if this node is the master node.
#
is_master()
{
    hostname | grep "$MASTER_HOSTNAME"
    return $?
}
set_DNS()
{
    sed -i  "s/PEERDNS=yes/PEERDNS=no/g" /etc/sysconfig/network-scripts/ifcfg-eth0
    echo "in set_DNS, updating resolv.conf"
    #sed -i  "s/search/#search/g" /etc/resolv.conf
	echo "search $DNS_SERVER_NAME">>/etc/resolv.conf	
	echo "domain $DNS_SERVER_NAME">>/etc/resolv.conf
	echo "nameserver $DNS_SERVER_IP">>/etc/resolv.conf
    echo "in set_DNS, updated resolv.conf"

    echo "in set_DNS, starting to write dhclient-exit-hooks"
    cat > /etc/dhcp/dhclient-exit-hooks_dns << EOF
		str1="$(grep -x "search $DNS_SERVER_NAME" /etc/resolv.conf)"
		str2="$(grep -x "#search $DNS_SERVER_NAME" /etc/resolv.conf)"
		str3="search $DNS_SERVER_NAME"
		str4="#search $DNS_SERVER_NAME"
		if [ "$str1" == *"$str3"* && "$str2" != *"$str4"* ]; then
		    :
		else
		    echo "$str3" >>/etc/resolv.conf
		fi		
EOF

    echo "in set_DNS, written dhclient-exit-hooks_dns"
    #sed -i 's/required_domain="mydomain.local"/required_domain="nxad01.pttep.local"/g' /etc/dhcp/dhclient-exit-hooks.d/azure-cloud.sh
    chmod 755 /etc/dhcp/dhclient-exit-hooks_dns
    echo "in set_DNS, updated Execute permission for dhclient-exit-hooks_dns"

	sed -i  "s/networks:   files/networks:   files dns [NOTFOUND=return]/g"  /etc/nsswitch.conf
	sed -i  "s/hosts:      files dns nis/hosts: files nis dns [NOTFOUND=return]/g"  /etc/nsswitch.conf
    echo "in set_DNS, updated nsswitch resolv.conf, restarting network service"
	service network restart
}
#set_DNS
enable_kernel_update()
{
	# enable kernel update
	sed -i.bak -e '28d' /etc/yum.conf 
	sed -i '28i#exclude=kernel*' /etc/yum.conf 

}
# Installs all required packages.
#
install_pkgs()
{
    yum -y install epel-release
    yum -y install zlib zlib-devel bzip2 bzip2-devel bzip2-libs openssl openssl-devel openssl-libs gcc gcc-c++ nfs-utils rpcbind mdadm wget python-pip
}
# set hostname in the form host-10-0-0-0
set-hostname()
{
	SERVER_IP="$(ip addr show eth0 | grep 'inet ' | cut -f2 | awk '{ print $2}')"
    ip="$(echo ${SERVER_IP} | sed 's\/.*\\g')"
	hostip="$(echo ${ip} | sed 's/[.]/-/g')"
	hostname host-"${hostip}"
}

# Downloads and installs PBS Pro OSS on the node.
# Starts the PBS Pro control daemon on the master node and
# the mom agent on worker nodes.
#
install_pbspro()
{
 
	yum install -y libXt-devel libXext


     wget -O /mnt/CentOS_7.zip  http://wpc.23a7.iotacdn.net/8023A7/origin2/rl/PBS-Open/CentOS_7.zip
    unzip /mnt/CentOS_7.zip -d /mnt
       
    if is_master; then

		enable_kernel_update
		install_pkgs

		yum install -y gcc make rpm-build libtool hwloc-devel libX11-devel libedit-devel libical-devel ncurses-devel perl postgresql-devel python-devel tcl-devel tk-devel swig expat-devel openssl-devel libXft autoconf automake expat libedit postgresql-server python sendmail tcl tk libical perl-Env perl-Switch
    
		# Required on 7.2 as the libical lib changed
		ln -s /usr/lib64/libical.so.1 /usr/lib64/libical.so.0

	    rpm -ivh --nodeps /mnt/CentOS_7/pbspro-server-14.1.0-13.1.x86_64.rpm


        cat > /etc/pbs.conf << EOF
PBS_SERVER=$MASTER_HOSTNAME
PBS_START_SERVER=1
PBS_START_SCHED=1
PBS_START_COMM=1
PBS_START_MOM=0
PBS_EXEC=/opt/pbs
PBS_HOME=/var/spool/pbs
PBS_CORE_LIMIT=unlimited
PBS_SCP=/bin/scp
EOF
    
        /etc/init.d/pbs start
        
        # Enable job history
        /opt/pbs/bin/qmgr -c "s s job_history_enable = true"
        /opt/pbs/bin/qmgr -c "s s job_history_duration = 336:0:0"

		# change job scheduler iteration from 10 minutes to 2
        /opt/pbs/bin/qmgr -c "set server scheduler_iteration = 120"

		# add hpcuser as manager
        /opt/pbs/bin/qmgr -c "s s managers = hpcuser@*"

		# list settings
		/opt/pbs/bin/qmgr -c 'list server'
    else

		set-hostname

        yum install -y hwloc-devel expat-devel tcl-devel expat

        
	    rpm -ivh --nodeps /mnt/CentOS_7/pbspro-execution-14.1.0-13.1.x86_64.rpm

        cat > /etc/pbs.conf << EOF
PBS_SERVER=$MASTER_HOSTNAME
PBS_START_SERVER=0
PBS_START_SCHED=0
PBS_START_COMM=0
PBS_START_MOM=1
PBS_EXEC=/opt/pbs
PBS_HOME=/var/spool/pbs
PBS_CORE_LIMIT=unlimited
PBS_SCP=/bin/scp
EOF

		echo '$clienthost '$MASTER_HOSTNAME > /var/spool/pbs/mom_priv/config
        /etc/init.d/pbs start

		# setup the self register script
		cp pbs_selfregister.sh /etc/init.d/pbs_selfregister
		chmod +x /etc/init.d/pbs_selfregister
		chown root /etc/init.d/pbs_selfregister
		chkconfig --add pbs_selfregister

		# if queue name is set update the self register script
		#if [ -n "$QNAME" ]; then
			sed -i '/qname=/ s/=.*/='workq'/' /etc/init.d/pbs_selfregister
		#fi

		# register node
		/etc/init.d/pbs_selfregister start

    fi

    echo 'export PATH=/opt/pbs/bin:$PATH' >> /etc/profile.d/pbs.sh
    echo 'export PATH=/opt/pbs/sbin:$PATH' >> /etc/profile.d/pbs.sh

    cd ..
}

mkdir -p /var/local
SETUP_MARKER=/var/local/install_pbspro.marker
if [ -e "$SETUP_MARKER" ]; then
    echo "We're already configured, exiting..."
    exit 0
fi

#set-hostname
install_pbspro

# Create marker file so we know we're configured
touch $SETUP_MARKER
