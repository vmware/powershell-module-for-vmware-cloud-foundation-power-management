# Known Issues

- For VMware Cloud Foundation 4.5 and later, if you have multiple clusters in a single workload domain manual intervention is required during startup. Clusters should be put in the correct status (shutdown). See Scenario 3 in [KB 87350][vmware-kb-87350].

- From all service virtual machines deployed by vSphere ESX Agent Manager, automated shutdown will only be performed on the vCLS virtual machines. All other service virtual machines (_e.g._, vSAN File Service nodes) will lead to an error in the script. Clusters with such virtual machines should be stopped through vCenter Server.

- For workload domains with multiple clusters, if you do not specify shut down order the clusters will be stopped in the order returned from SDDC Manager API. For granular control, please use the `-vsanCluster` parameter.

- Workspace ONE Access that is integrated with NSX, should be started manually. For VMware Cloud Foundation 4.5 and later, this can be done before using the script for starting the management domain.

- All vCenter Server instances for workload domains will be started with the first workload domain in order to get full inventory information in SDDC Manager.

[vmware-kb-87350]: https://kb.vmware.com/s/article/87350
