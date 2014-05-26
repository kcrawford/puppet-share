# The baseline for module testing used by Puppet Labs is that each manifest
# should have a corresponding test manifest that declares that class or defined
# type.
#
# Tests are then run by using puppet apply --noop (to check for compilation
# errors and view a log of events) or by fully applying the test in a virtual
# environment (to compare the resulting system state to the desired state).
#
# Learn more about module testing here:
# http://docs.puppetlabs.com/guides/tests_smoke.html
#

resources { 'share': purge => true }

share { '/Groupszz': }

share { '/Groups':
  guest_protocols => ['afp', 'smb'],
  protocols       => ['afp', 'smb'],
  share_name      => 'Groups',
}
share { '/Users/Shared/TestShare':
  ensure     => 'present',
  afp_name   => 'TestShare One',
  ftp_name   => 'TestShare Uno',
  share_name => 'TestShere',
  smb_name   => 'TestShare 1',
}
share { '/Users/Shared/TestShare2':
  ensure     => 'absent',
  afp_name   => 'TestShare Two',
  ftp_name   => 'TestShare Dos',
  share_name => 'TestShare2',
  smb_name   => 'TestShare 2',
}
