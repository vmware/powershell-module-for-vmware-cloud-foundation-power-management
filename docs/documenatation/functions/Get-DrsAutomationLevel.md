# Get-DrsAutomationLevel

## Synopsis

Returns the vSphere Distributed Resource Scheduler setting configured on the server for a cluster.

## Syntax

```powershell
Get-DrsAutomationLevel [-server] <String> [-user] <String> [-pass] <String> [-cluster] <String> [<CommonParameters>]
```

## Description

The `Get-DrsAutomationLevel` cmdlet returns the vSphere Distributed Resource Scheduler setting configured on the server for a given cluster.

## Examples

### Example 1

```powershell
Get-DrsAutomationLevel -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -cluster sfo-m01-cl01
```

This example connects to the management vcenter server and returns the drs settings configured on the management cluster.

## Parameters

### -server

The FQDN of the vCenter Server.

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

The username to authenticate to vCenter Server.

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

The password to authenticate to vCenter Server.

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

### -cluster

The name of the cluster.

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
