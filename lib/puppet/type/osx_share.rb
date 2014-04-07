require 'puppet/parameter/boolean'

Puppet::Type.newtype(:osx_share) do
  desc "Manage OS X Shares"

  ensurable

  newparam(:path, :namevar => true) do
    desc "Path to share"
  end

  newproperty(:share_name) do
    desc "Global name of share for all protocols unless overridden"
    defaultto {
      File.basename(@resource[:name])
    }
  end

  newproperty(:guest, :array_matching => :all) do
    desc "List of protocols to enable for guest"
    defaultto []
  end

  newproperty(:over, :array_matching => :all) do
    desc "List of protocols to enable for share ['afp', 'smb', 'ftp']"
    defaultto([])
  end

  newproperty(:afp_name) do
    desc "Specific name for afp protocol"
    #defaultto { @resource[:share_name] }
  end

  newproperty(:smb_name) do
    desc "Specific name for smb protocol"
    #defaultto { @resource[:share_name] }
  end

  newproperty(:ftp_name) do
    desc "Specific name for ftp protocol"
    #defaultto { @resource[:share_name] }
  end

  newproperty(:afp_inherit_perms, :boolean => true) do
    desc "Whether to inherit permissions for afp protocol"
    defaultto false
  end

end

