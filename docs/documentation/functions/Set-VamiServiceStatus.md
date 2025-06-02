# Set-VamiServiceStatus

## Synopsis

Starts, stops, or restarts a service on a vCenter instance.

## Syntax

```powershell
Set-VamiServiceStatus [-server] <String> [-user] <String> [-pass] <String> [-state] <String> [-nolog] [-service] <String> [<CommonParameters>]
```

## Description

The `Set-VamiServiceStatus` cmdlet starts, stops, or restarts a specified management appliance service on a specified vCenter instance.

## Examples

### Example 1

```powershell
Set-VamiServiceStatus -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -service [service_name] -state [service_state]
```

This example connects to a vCenter instance and puts the specified service in a specified service state.

``` powershell
Set-VamiServiceStatus -server [vcenter_fqdn] -user [admin_username] -pass [admin_password] -service [service_name] -state [service_state] -nolog
```

This example connects to a vCenter instance and puts the specified service in a specified service state without log messages in the output.

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

### -state

The state of the servcie.
The value can be one of the following ("start", "stop", "restart").

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

The name of the service.
The values can be one amongst ("analytics", "applmgmt", "certificateauthority", "certificatemanagement", "cis-license", "content-library", "eam", "envoy", "hvc", "imagebuilder", "infraprofile", "lookupsvc", "netdumper", "observability-vapi", "perfcharts", "pschealth", "rbd", "rhttpproxy", "sca", "sps", "statsmonitor", "sts", "topologysvc", "trustmanagement", "updatemgr", "vapi-endpoint", "vcha", "vlcm", "vmcam", "vmonapi", "vmware-postgres-archiver", "vmware-vpostgres", "vpxd", "vpxd-svcs", "vsan-health", "vsm", "vsphere-ui", "vstats", "vtsdb", "wcp").

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 5
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### Common Parameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).
