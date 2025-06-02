# Get-VamiServiceStatus

## Synopsis

Returns the status of a specified service on a vCenter instance.

## Syntax

```powershell
Get-VamiServiceStatus [-server] <String> [-user] <String> [-pass] <String> [-nolog] [-service] <String> [<CommonParameters>]
```

## Description

The `Get-VamiServiceStatus` cmdlet returns the status of a specified service on a vCenter instance. The status returns either STARTED/STOPPED.

## Examples

### Example 1

```powershell
Get-VAMIServiceStatus -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -service [service_name]
```

This example connects to the specified vCenter instance and returns the status of the specified service.

### Example 2

```powershell
Get-VAMIServiceStatus -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -service [service_name] -nolog
```

This example connects to the specified vCenter instance and returns the status of the specified service without log messages in the output.

## Parameters

### -server

The FQDN of the vCenter.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -user

The username to authenticate to vCenter.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -pass

The password to authenticate to vCenter.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 3
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -nolog

The switch to supress selected log messages.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -service

The name of the service to check status for.
The value can be one of the following ("analytics", "applmgmt", "certificateauthority", "certificatemanagement", "cis-license", "content-library", "eam", "envoy", "hvc", "imagebuilder", "infraprofile", "lookupsvc", "netdumper", "observability-vapi", "perfcharts", "pschealth", "rbd", "rhttpproxy", "sca", "sps", "statsmonitor", "sts", "topologysvc", "trustmanagement", "updatemgr", "vapi-endpoint", "vcha", "vlcm", "vmcam", "vmonapi", "vmware-postgres-archiver", "vmware-vpostgres", "vpxd", "vpxd-svcs", "vsan-health", "vsm", "vsphere-ui", "vstats", "vtsdb", "wcp").

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 4
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### Common Parameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).
