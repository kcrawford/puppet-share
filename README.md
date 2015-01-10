# puppet-share
Puppet module to create and manage file shares

To collect all existing shares use:
```
puppet resource share
```

 To manage all shares removing unspecified shares use:
 ```puppet
 resources { 'osx_share': purge => true }
 ```
 
 ```puppet
 
# Simple share with defaults
share { '/Shares/Product_Team': }
 
# Share with full options 
share { '/Shares/Development_Team':
  ensure     => 'present',
  afp_name   => 'Development Team',
  smb_name   => 'Development Team',
  ftp_name   => 'devteam',
  share_name => 'Development_Team',
  protocols       => ['afp', 'smb'],
  guest_protocols => ['afp', 'smb'],
}
```
