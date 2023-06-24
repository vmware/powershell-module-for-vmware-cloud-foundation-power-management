# Limitations

- VMware Cloud Foundation on Dell EMC VxRail is not supported.

- For VMware Cloud Foundation 4.5 and later, lockdown mode must be disabled on each ESXi host before shut down. You can enable lockdown mode after startup is completed.

- For VMware Cloud Foundation 4.4 and earlier, you must shut down the ESXi hosts manually. The scripts only place the ESXi hosts in maintenance mode.

- For VMware Cloud Foundation 4.4 and earlier, the SSH service on the ESXi hosts must be running.

- The sample scripts do not startup ESXi hosts. ESXi hosts must be started before running the scripts.

- The sample script for management domain only works on a management domain with a single cluster.

- If bare-metal NSX Edge nodes are used in your environment, you must stop and start the bare-metal NSX Edge nodes manually.

- Shutdown and startup operations are not support for the following platform extensions: vSphere with Tanzu, vSphere Replication, Site Recovery Manager, Aria Suite (formerly vRealize Suite), and Workspace ONE Access.

- VMware Tools must be running in virtual machines to shut down virtual machines in the management or VI workload domains using the sample script. The virtual machines are shut down in a random order using the "Shutdown Guest OS" command from vCenter Server.

- THe sample scripts cannot handle simultaneous connections to multiple services. In the script's console, all sessions to services that are not used at the moment will be disconnected.
