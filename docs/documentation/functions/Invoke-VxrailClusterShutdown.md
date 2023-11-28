# Invoke-VxrailClusterShutdown

## Synopsis

Invoke shut down command on a VxRail Cluster

## Syntax

```powershell
Invoke-VxrailClusterShutdown [-server] <String> [-user] <String> [-pass] <String>
```

## Description

The `Invoke-VxrailClusterShutdown` cmdlet powers off a VxRail cluster.
The cmdlet will perform a dry run test prior to initiate a shutdown command on a VxRail cluster.

## Examples

### Example 1

```powershell
Invoke-VxrailClusterShutdown -server sfo-w01-vxrm.sfo.rainpole.io -user administrator@vsphere.local  -Pass VMw@re1!
```
This example powers off a Vxrail Cluster cluster which the VxRail server sfo-w01-vxrm.sfo.rainpole.io controls. 

## Parameters

### -server

The FQDN of the VxRail Manager.

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

The username to authenticate to SSO service in which the VxRail is registered to.

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

The password to authenticate to SSO service in which the VxRail is registered to.

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

### Common Parameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable, -InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose, -WarningAction, and -WarningVariable. For more information, see [about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).
