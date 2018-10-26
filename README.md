Compute Grid Infra => all you need to build an HPC cluster in Azure with PBS Pro, BeeGFS, Ganglia.
Compute Grid Infra => all you need to build an HPC cluster in Azure with PBS Pro, BeeGFS, Ganglia.

Table of Contents
=================
* [Summary](#summary)
* [Compute grid in Azure](#compute-grid-in-azure)
* [VM Infrastructure](#vm-infrastructure)
  * [Network](#network)
  * [Compute](#compute)
  * [Storage](#storage)
  * [Management](#management)
* [Deployment steps](#deployment-steps)
  * [Deploying using Azure CLI](#deploying-using-azure-cli)
  * [Create the networking infrastructure and the jumpbox](#create-the-networking-infrastructure-and-the-jumpbox)
  * [Optionally deploy the BeeGFS nodes](#optionally-deploy-the-beegfs-nodes)
  * [Provision the compute nodes](#provision-the-compute-nodes)
* [Running Applications](#running-applications)
  * [Validating MPI](#validating-mpi)
  * [Running a Pallas job with PBS Pro](#running-a-pallas-job-with-pbs-pro)

# Summary
Theese templates setup a cluster associated with a master node and compute nodes for CentOS_7x, to setup the cluster, shell scripts are being used for required softaware installations.
* In this template there is two way to resolve hostname one is Windows DNS Server and another one is NIS.
* The master VM has no public ip it has private static ip (10.0.0.135). To change the fixed ip as per requierment change [here](https://github.com/azmigproject/promax-beegfs-pbspro-6.x/blob/mastercopyv1/Compute-Grid-Infra/master-shared-resources.json#L64).
* To install the PBS pro __install-pbspro.sh__ script being used which is placed in PBSPro folder.
* To register the compute nodes in pbs manager __pbs_selfregister.sh__ script is used and run at compute node and placed in PBSpro folder.
* On master and compute nodes a user called __hpcuser__ is created to do ssh across the node by passwordless login. We used NFS for passwordless login.
* We are using a pattren for hostname of the compute node pattern is host-<ip with '-' sepration> for example if ip is 10.0.0.0 the hostname would be host-10-0-0-0.
# Compute grid in Azure

These templates will build a compute grid made by a single master VMs running the management services, multiple VM Scaleset for deploying compute nodes, and optionally a set of nodes to run [BeeGFS](http://www.beegfs.com/) as a parallel shared file system. Ganglia is an option for monitoring the cluster load, and [PBS Pro](http://www.pbspro.org/) can optionally be setup for job scheduling.
Below is the details of shell scripts :
* __master-setup.sh__ script runs at master node, placed in __Compute-Grid-Infra__ folder, It setups softwares like NIS server, PBS pro server. To run the script following parameter is required:
  * __AddressSpaceList__ It is required to create NIS map for the hostname and IP pair in hosts.byname file. basically it is used for hostname resolution because we can use NIS server as DNS server.
  * __NISDomain__ It is used for the provid NIS domain name.
* __cn-setup.sh__ script runs on the compute nodes, placed in __Compute-Grid-Infra__ folder. It is used  for setup PBS pro execute node, NIS client, ganglia monitoring tool, BeeGFS file System and NFS share mounts.To run this script following parameter must be provided:
  * __Master Name__ It would be used in mounting NFS share from master for pass login.
  * __Shared Storage__ It could be beegfs or otherstorage
  * __Schedular_ In our the template is can setup only PBSpro.  
  * __Monitoring__ Templa can setup Ganglia only.
  * __NAS Device Name__ This is the NFS server name where NFS Share exists.
  * __NAS Device__ It is the NAS device name like /share/Home/Data.
  * __NAS Mount__ It should be an existing path on compute nodes like /scratch where NAS device wo be monuted.
  * __DNS Server Name__ It is the DNS server name.
  * __DNS IP__ It the DNS server IP.
  * __NIS server domain__ It should be the same server domain name which is setup on NIS domain.
  * __NIS server IP__ It should be the NIS server IP.




# VM Infrastructure
The following diagram shows the overall Compute, Storage and Network infrastructure which is going to be provisioning within Azure to support running HPC applications.

![Grid Infrastructure](doc/Infra.PNG)

### Network
A single VNET (__grid-vnet__) is used in which four subnets are created, one for the infrastructure (__infra-subnet__), one for the compute nodes (__compute-subnet__), one for the storage (__storage-subnet__) and one for the VPN Gateway (__GatewaySubnet__). The following addresses range is used :
* __grid-vnet 10.0.0.0/20__ allowing 4091 private IPs from 10.0.0.4 to 10.0.15.255
* __compute-subnet 10.0.0.0/21__ allowing 2043 private IPs from 10.0.0.4 to 10.0.7.255
* __infra-subnet 10.0.8.0/28__ allowing 11 private IPs from 10.0.8.4 to 10.0.8.15
* __gatewaysubnet 10.0.9.0/29__ allowing 3 private IPs from 10.0.9.4 to 10.0.9.7
* __storage-subnet 10.0.10.0/25__ allowing 251 private IPs from 10.0.10.4 to 10.0.10.255

Notice that Azure Network start each range at the x.x.x.4 address, reducing by 3 the number of available IPs in a subnet. So, this must be taken in account when designing your virtual network architecture.
Infiniband is automatically provided when HPC Azure nodes are provisioned.

For DNS, the Azure DNS is used for name resolution on the private IPs.

### Compute
Compute nodes are deployed thru VM Scale sets and Managed Disks, made each by up to 100 VMs instances. They are all inside the compute-subnet.

### Storage
Depending on the workload to run on the cluster, there may be a need to build a scalable file system. BeeGFS is proposed as an option, each storage node will host the storage and metadata services. Several Premium Disks are configured in RAID0 to store the metadata in addition to the real store.
For a small size cluster, there is an option to use the master machine as an NFS server with data disk attached in a RAID0 volume.

### Management
A dedicated VM (the master node) is used as a jumpbox, exposing an SSH endpoint, and hosting these services :
* __Ganglia__ metadata service and monitoring web site
* __PBS Pro__ job scheduler
* __BeeGFS__ management services

# Deployment steps
To build the compute grid, three main steps need to be executed :
1. Create the networking infrastructure and the jumpbox
2. Optionally deploy the BeeGFS nodes
3. Provision the compute nodes

_The OS for this solution is CentOS 7.4. All scripts have been tested only for that version. 

> Starting on February 22, 2017 Master, Compute nodes and BeeGFS nodes are all provisioned using Managed Disks.


## Deploying using Azure CLI
Azure CLI 2.0 setup instruction can be found [here](https://docs.microsoft.com/en-us/cli/azure/install-az-cli2)

Below is an example on how to provision the templates. First you have to login with your credentials. If you have several subscriptions, make sure to make the one you want to deploy in the default. Then create a resource group providing the region and a name for it, and finally invoke the template passing your local parameter file. In the template URI make sure to use the RAW URI https://raw.githubusercontent.com/tonywu70/promax-beegfs-pbspro/azure-hpc/master/*** and not the github HTML link.

    az login
    az account set --subscription [subscriptionId]
    az group create -l "West Europe" -n rg-master
    az group deployment create -g rg-master --template-uri https://raw.githubusercontent.com/xpillons/azure-hpc/master/Compute-Grid-Infra/deploy-master.json --parameters @myparams.json



## Create the networking infrastructure and the jumpbox
The template __deploy-master.json__ will provision the networking infrastructure as well as a master VM exposing an SSH endpoint for remote connection.   

You have to provide these parameters to the template :
* _VMSku_ : This is to specify the instance size of the master VM. For example Standard_DS3_v2
* _masterImage_ : the OS to be used. Should be CentOS_6.x
* _sharedStorage_ : to specify the shared storage to use. Allowed values are : none, beegfs, nfsonmaster
* _nasName_ : the name of the NAS server.
* _nasDevice_ : the name of the NAS device which would be share.
* _nasMountPoint_ : the name of the NAS mount point which should be exist on compute nodes.
* _dnsServerName_ : the name of the DNS server.
* _dnsServerIp_ : the IP of the DNS server.
* _nisDomainName_ : the domain name for the NIS server by using it a NIS domain would be created.
* _SubnetAddressRanges_ : The subnet ranges with comma separted like 10.0.0.0/21,10.0.0.0.22. It would be use to create NIS map.
* _dataDiskSize_ :  the size of the data disks to attached. Allowed values are : none, P10 (128GB), P20 (512GB), P30 (1023GB)
* _nbDataDisks_ : Number of data disks to attach. Default is **2**, maximum is **16**.
* _monitoring_ : the monitoring tools to be setup. Allowed values are : none, ganglia
* _scheduler_ : the job scheduler to be setup. Allowed values are : none, pbspro
* _vmPrefix_ : a 8 characters prefix to be used to name your objects. The master VM will be named as **\[prefix\]master**
* _adminUsername_ : This is the name of the administrator account to create on the VM
* _adminPassword_ : Password to associate to the administrator account. It is highly encourage to use SSH authentication and passwordless instead.
* __VnetName__: the name of the Virtual Network is being used for cluster.
* __ComputeSubnet__ : the name of the compute Subnet is being used for cluster.
* __StorageSubnet__ : the name of the storage Subnet is being used for cluster.
* __InfraSubnet__ : the name of the infra Subnet is being used for cluster.
* __GatewaySubnet__ : the name of the Gateway Subnet is being used for cluster.
* _RGName_ : the name of the resource group where Virtual Network is created.
* _sshKeyData_ : The public SSH key to associate with the administrator user. Format has to be on a single line 'ssh-rsa key'

[![Click to deploy template on Azure](http://azuredeploy.net/deploybutton.png "Click to deploy template on Azure")](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fazmigproject%2Fpromax-beegfs-pbspro-7.x%2Fmaster%2FCompute-Grid-Infra%2Fdeploy-master.json)  

### Check your deployment
Once the deployment succeed, use the output **masterFQDN** to retrieve the master name and SSH on it. The output **GangliaURI** contains the URI of the Ganglia monitoring page, which should display after few minutes graphs of the current load.

To check if PBSPro is installed, run the command **pbsnodes -a** this should return no available nodes, but the command should run successfully.

If **otherstorage** is choosen, an NFS mount point named **/scratch** will be created.

BeeGFS will be checked later once the storage nodes will be deployed.

## Optionally deploy the BeeGFS nodes

If your compute cluster require a scalable shared file storage, you can deploy BeeGFS nodes to create a unique namespace. Prior doing your deployment you will have to decide how much storage nodes you will require and for each how much data disks you will provide for the storage and metadata services.
Data disks are based on Premium Storage and can have three different sizes :
* P10 : 128 GB
* P20 : 512 GB
* P30 : 1023 GB

The storage nodes will be included in the VNET created in the previous step, and all inside the *storage-subnet* .

The template __BeeGFS/deploy-beegfs-vmss.json__ will provision the storage nodes with CentOS 7.4 and BeeGFS version 7.

You have to provide these parameters to the template :
* _nodeType_ : Default value is **both** and should be kept as is. Other values *meta* and *storage* are allowed for advanced scenarios in which meta data services and storage services are deployed on dedicated nodes.
* _nodeCount_ : Total number of storage nodes to deploy. Maximum is 100.
* _VMsku_ : The VM instance type to be used in the Standard_DSx_v2 series. Default is **Standard_DS3_v2**.
* _RGvnetName_ : The name of the Resource Group used to deploy the Master VM and the VNET.
* _adminUsername_ : This is the name of the administrator account to create on the VM. It is recommended to use the same than for the Master VM.
* _sshKeyData_ : The public SSH key to associate with the administrator user. Format has to be on a single line 'ssh-rsa key'
* _masterName_ : The short name of the Master VM, on which the BeeGFS management service is installed
* _storageDiskSize_ : Size of the Data Disk to be used for the storage service (P10, P20, P30). Default is **P10**.
* _nbStorageDisks_ : Number of data disks to be attached to a single VM. Min is 2, Max is 8, Default is **2**.
* _metaDiskSize_ :  Size of the Data Disk to be used for the metadata service (P10, P20, P30). Default is **P10**.
* _nbMetaDisks_ : Number of data disks to be attached to a single VM. Min is 2, Max is 8, Default is **2**.
* _customDomain_ : If the VNET is configure to use a custom domain, specify the name of this custom domain to be used

[![Click to deploy template on Azure](http://azuredeploy.net/deploybutton.png "Click to deploy template on Azure")](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fazmigproject%2Fpromax-beegfs-pbspro-7.x%2Fmaster%2FCompute-Grid-Infra%2FBeeGFS%2Fdeploy-beegfs-vmss.json)  

### Check your deployment
Storage nodes will be named _beegfs000000 beegfs000001 ..._ .
After few minutes, they should appear in the Ganglia monitoring web page if setup.

To check that the nodes are well registered into the BeeGFS management service, SSH on the master VM and then run these commands :
* to list the storage nodes : *beegfs-ctl --listnodes --nodetype=storage*
* to list the metadata nodes : *beegfs-ctl --listnodes --nodetype=metadata*
* to display the BeeGFS file system : *beegfs-df*
* to display the BeeGFS network : *beegfs-net*

The mount point to use is **/share/scratch** , and it should already be mounted on the master VM.

## Provision the compute nodes
Compute nodes are provisioned using VM Scalesets, each set can have up to 100 VMs. You will have to provide the number of VM per scalesets and how many sets you want to create. All scalesets will contains the same VM instances.

You have to provide these parameters to the template :
* _VMsku_ : Instance type to provision. Default is **Standard_D3_v2**
* _sharedStorage_ : default is **none**. Allowed values are (nfsonmaster, beegfs, none)
* _nasName_ : the name of the NAS server.
* _nasDevice_ : the name of the NAS device which would be share.
* _nasMountPoint_ : the name of the NAS mount point which should be exist on compute nodes.
* _dnsServerName_ : the name of the DNS server.
* _dnsServerIp_ : the IP of the DNS server.
* _NISDomainName_ : the IP of the NIS domain which was setup on master node.
* _NISDOmainIp_ : the IP of the NIS Server name.
* _scheduler_ : default is **none**. Allowed values are (pbspro, none)
* _monitoring_ : default is **ganglia**. Allowed values are (ganglia, none)
* _computeNodeImage_ : OS to use for compute nodes. Default and recommended value is **CentOS_7.2**
* _vmSSPrefix_ : 8 characters prefix to use to name the compute nodes. The naming pattern will be **prefixAABBBBBB** where _AA_ is two digit number of the scaleset and _BBBBBB_ is the 8 hexadecimal value inside the Scaleset
* _instanceCountPerVMSS_ : number of VMs instance inside a single scaleset. Default is 2, maximum is 100
* _numberOfVMSS_ : number of VM scaleset to create. Default is 1, maximum is 100
* _RGvnetName_ : The name of the Resource Group used to deploy the Master VM and the VNET.
* _adminUsername_ : This is the name of the administrator account to create on the VM. It is recommended to use the same than for the Master VM.
* _sshKeyData_ : The public SSH key to associate with the administrator user. Format has to be on a single line 'ssh-rsa key'
* _masterName_ : The name of the Master VM
* _Vnet Name_ : The name of the Virtual Network.
* _ComputeSubnet_ : The name of the subnet want to use for compute node.
* _NFS Server Name_ : The name of the NFS server.
* _adminPassword_ : Password to associate to the administrator account. It is highly encourage to use SSH authentication and passwordless instead.
* _postInstallCommand_ : a post installation command to launch after povisioning. This command needs to be encapsulated in quotes, for example **'bash /data/postinstall.sh'**.
* _imageId_ : Specify the resource ID of the image to be used in the format **/subscriptions/{SubscriptionId}/resourceGroups/{ResourceGroup}/providers/Microsoft.Compute/images/{ImageName}** this value is only used when the _computeNodeImage_ is set to **CustomLinux** or **CustomWindows**


[![Click to deploy template on Azure](http://azuredeploy.net/deploybutton.png "Click to deploy template on Azure")](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fazmigproject%2Fpromax-beegfs-pbspro-7.x%2Fmaster%2FCompute-Grid-Infra%2Fdeploy-nodes.json)  

### Check your deployment
After few minutes, once the provision succeed, you should see the new hosts added on the Ganglia monitoring page if setup.

If PBS Pro is used, SSH on the master and run the **pbsnodes -a** command to list all the registered nodes.

If **otherstorage** is choosen the NFS mount point **/scratch** is automatically mounted.

**Your cluster is now ready to host applications and run jobs**

# Running applications

## Validating MPI
Intel MPI and Infiniband are only available for A8/A9 and H16r instances. A default user named **hpcuser** has been created on the compute nodes and on the master node with passwordless access so it can be immediately used to run MPI across nodes.

To begin, you need first to ssh on the master and then switch to the **hpcuser** user. From there, ssh one one of the compute nodes, and configure MPI by following the instructions from [here](https://docs.microsoft.com/en-us/azure/virtual-machines/virtual-machines-linux-classic-rdma-cluster#configure-intel-mpi)

To run the 2 node pingpong test, execute the following command

    impi_version=`ls /opt/intel/impi`
    source /opt/intel/impi/${impi_version}/bin64/mpivars.sh

    mpirun -hosts <host1>,<host2> -ppn 1 -n 2 -env I_MPI_FABRICS=shm:dapl -env I_MPI_DAPL_PROVIDER=ofa-v2-ib0 -env I_MPI_DYNAMIC_CONNECTION=0 -env I_MPI_FALLBACK_DEVICE=0 IMB-MPI1 pingpong

You should expect an output as the one below

    #------------------------------------------------------------
    #    Intel (R) MPI Benchmarks 4.1 Update 1, MPI-1 part
    #------------------------------------------------------------
    # Date                  : Thu Jan 26 02:16:14 2017
    # Machine               : x86_64
    # System                : Linux
    # Release               : 3.10.0-229.20.1.el7.x86_64
    # Version               : #1 SMP Tue Nov 3 19:10:07 UTC 2015
    # MPI Version           : 3.0
    # MPI Thread Environment:

    # New default behavior from Version 3.2 on:

    # the number of iterations per message size is cut down
    # dynamically when a certain run time (per message size sample)
    # is expected to be exceeded. Time limit is defined by variable
    # "SECS_PER_SAMPLE" (=> IMB_settings.h)
    # or through the flag => -time



    # Calling sequence was:

    # IMB-MPI1 pingpong

    # Minimum message length in bytes:   0
    # Maximum message length in bytes:   4194304
    #
    # MPI_Datatype                   :   MPI_BYTE
    # MPI_Datatype for reductions    :   MPI_FLOAT
    # MPI_Op                         :   MPI_SUM
    #
    #

    # List of Benchmarks to run:

    # PingPong

    #---------------------------------------------------
    # Benchmarking PingPong
    # #processes = 2
    #---------------------------------------------------
           #bytes #repetitions      t[usec]   Mbytes/sec
                0         1000         3.37         0.00
                1         1000         3.40         0.28
                2         1000         3.69         0.52
                4         1000         3.39         1.13
                8         1000         3.41         2.24
               16         1000         3.38         4.51
               32         1000         2.78        10.99
               64         1000         2.79        21.90
              128         1000         3.12        39.09
              256         1000         3.34        73.13
              512         1000         3.79       128.87
             1024         1000         4.85       201.48
             2048         1000         5.74       340.21
             4096         1000         7.06       552.98
             8192         1000         8.51       917.87
            16384         1000        10.86      1438.11
            32768         1000        16.55      1888.21
            65536          640        28.15      2220.37
           131072          320        53.47      2337.75
           262144          160        84.07      2973.66
           524288           80       148.77      3360.92
          1048576           40       284.91      3509.84
          2097152           20       546.43      3660.15
          4194304           10      1077.75      3711.45


    # All processes entering MPI_Finalize

## Running a Pallas job with PBS Pro

ssh on the master node and switch to the **hpcuser** user. Then change directory to home

    sudo su hpcuser
    cd

create a shell script named **pingpong.sh** with the content listed below

    #!/bin/bash

    # set the number of nodes and processes per node
    #PBS -l nodes=2:ppn=1

    # set name of job
    #PBS -N mpi-pingpong
    source /opt/intel/impi/5.1.3.181/bin64/mpivars.sh

    mpirun -env I_MPI_FABRICS=dapl -env I_MPI_DAPL_PROVIDER=ofa-v2-ib0 -env I_MPI_DYNAMIC_CONNECTION=0 IMB-MPI1 pingpong

Then submit a job

    qsub pingpong.sh

The job output will be written in the current directory in files named **mpi-pingpong.e*** and **mpi-pingpong.o***

The **mpi-pingpong.o*** file should contains the MPI pingpong output as shown above when doing the manual test.


____



This project has adopted the [Microsoft Open Source Code of
Conduct](https://opensource.microsoft.com/codeofconduct/). For more information
see the [Code of Conduct
FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact
[opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional
questions or comments.


