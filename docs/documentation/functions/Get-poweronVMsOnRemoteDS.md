# Get-poweronVMsOnRemoteDS

## Synopsis

Returns a list of virtual machines that reside on a vSAN HCI Mesh datastore hosted in a cluster.

## Syntax

```powershell
Get-poweronVMsOnRemoteDS [-server] <String> [-user] <String> [-pass] <String> [-clustertocheck] <String> [<CommonParameters>]
```

## Description

The `Get-poweronVMsOnRemoteDS` cmdlet returns a list of virtual machines that reside on a vSAN HCI Mesh datastore hosted in a specified cluster.

## Examples

### Example 1

```powershell
Get-poweronVMsOnRemoteDS -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -Pass VMw@re1! -clustertocheck sfo-m01-cl01
```

This example returns the list of virtual machines that reside on a vSAN HCI Mesh datastore hosted in cluster sfo-m01-cl01.

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

### -clustertocheck

The name of the remote cluster on which virtual machines are hosted.

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
