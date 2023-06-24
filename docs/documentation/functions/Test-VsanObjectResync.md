# Test-VsanObjectResync

## Synopsis

Test the vSAN object resync status for a cluster.

## Syntax

```powershell
Test-VsanObjectResync [-server] <String> [-user] <String> [-pass] <String> [-cluster] <String> [<CommonParameters>]
```

## Description

The `Test-VsanObjectResync` cmdlet returns the vSAN object resync status for a cluster.

## Examples

### Example 1

```powershell
Test-VsanObjectResync -cluster sfo-m01-cl01 -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1!
```

This example connects to a vCenter Server and checks the status of object syncing for the vSAN cluster.

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

The name of the vSAN cluster on which object resynchronization status has to be checked.

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
