Puppet::Type.type(:osx_share).provide(:share) do

  commands :sharing => 'sharing'

  defaultfor :operatingsystem => :darwin
  confine :operatingsystem    => :darwin

  # Create setters and getters for properties
  mk_resource_methods


  # Assigns our providers to resources
  def self.prefetch(resources)
    instances.each do |provider|
      resources[provider.name].provider = provider if resources[provider.name]
    end
  end

  # self.instances returns all instances of the resource type that are
  # discovered on the system.  The self.instances method is used by `puppet
  # resource`, and MUST be implemented for `puppet resource` to work. The
  # self.instances method is also frequently used by self.prefetch (which is
  # also the case for this provider class).
  def self.instances
    all_shares_attributes.values.map {|share_hash| new(share_hash) }
  end

  def self.all_shares_attributes
    sharing_info = sharing("-l").gsub(/.*List of Share Points/,'').lstrip
    all_shares = {}
    sharing_info.split(/^name:/)[1..-1].each do |share_info|
      share_name, config = share_info.split("\n", 2)
      share_name.gsub!(/^\t*/, '')
      path = config.lines.grep(/^path:/).first.split("\t").last.chomp
      protocols = extract_protocols(config)
      share_attributes = {
        :name => path,
        :share_name => share_name,
        :ensure => :present,
        :guest => get_guest_protocols(protocols),
        :over => get_enabled_protocols(protocols),
        :afp_inherit_perms => protocols["afp"]["inherit perms"] == "1"
      }
      share_attributes[:afp_name] = protocols["afp"]["name"] if protocols["afp"]["name"] != share_name
      share_attributes[:smb_name] = protocols["smb"]["name"] if protocols["smb"]["name"] != share_name
      share_attributes[:ftp_name] = protocols["ftp"]["name"] if protocols["ftp"]["name"] != share_name
      all_shares[path] = share_attributes
    end
    all_shares
  end

  def self.get_enabled_protocols(protocols)
    Hash[ protocols.select {|k,v| v["shared"] == "1" } ].keys
  end

  def self.get_guest_protocols(protocols)
    Hash[ protocols.select {|k,v| v["guest access"] == "1" } ].keys
  end

  def self.supported_protocols
    ["afp", "smb", "ftp"]
  end

  def self.extract_protocols(config)
    protocol_info = Hash[*config.split(/(#{supported_protocols.join("|")}):\t*[{}]/)[1..-1]]
    supported_protocols.each do |protocol_name|
      protocol_info[protocol_name] = extract_protocol(protocol_info[protocol_name])
    end
    protocol_info
  end

  def self.protocol_value_for_key_in_string(key, string)
    string.split(/#{key}:\t*/)[1].to_s.split("\n").first
  end

  def self.extract_protocol(protocol_string)
    ["name", "shared", "guest access", "inherit perms"].inject({}) do |hash, key|
      hash[key] = protocol_value_for_key_in_string(key, protocol_string)
      hash
    end
  end

  def initialize(attributes={})
    super(attributes)
    @share_edit_args = []
  end

  def exists?
    self.ensure == :present
  end

  def create
    sharing("-a", name)
    @property_hash[:ensure] = :present

    # Setters are not automatically called on create, so we call them
    resource.properties.each do |property|
      property.sync unless property.name == :ensure
    end
  end

  def destroy
    sharing("-r", share_name)
  end

  # @resource.should(:property_name) is what we want the resource to have applied
  #   @resource.should(:ensure) for example
  # self.property_name is what we currently have applied
  #   self.ensure for example
  # TODO figure out how to manage all shares so ones that shouldn't exist are purged
  #    look at how File ensure directory purge works
  #    or look at how apache sites directory is purged
  #    maybe need to look at autorequire?
  #
  # TODO autorequire the path for file
  # autorequire(:file) do
  #   [name]
  # end
  #
  # Note that properties will have already been set as having been synced here because setters will have been called
  # But parameters don't call setters so those can be used as expected in a flush
  # But how do we know if we are in sync or not if we dont' use properties?
  # Therein lies the problem
  #   and that is why people track state separately from puppet's built-in when using flush
  # So what we do is build up our args in each setter, then use them on flush
  def flush
    return unless resource.should(:ensure) == :present
    unless @share_edit_args.empty?
      # Ensure we have an up-to-date share name before attempting to edit
      existing_share_name = self.class.all_shares_attributes[name][:share_name]
      sharing(["-e", existing_share_name] + @share_edit_args)
    end
  end


  # Takes a list of protocols and returns the share/guest access flags
  # These take the form of 100, 101, 001, where each place enables or disables for that protocol
  # As of 10.9, these are the keys and values are the same for setting guest access and for enabling sharing
  def flags_for_protocols(protocols)
    flag_keys = {:afp => 100, :ftp => 10, :smb => 1 }

    # Start with no flags (0) and add each protocol's flag
    flags_number = 0
    protocols.each {|protocol| flags_number += flag_keys[protocol.downcase.to_sym] }
    number_to_flags(flags_number)
  end

  # Pads a number with zeros 3 places
  def number_to_flags(number)
    number.to_s.rjust(3, "0")
  end

  def over=(desired_protocols)
    @share_edit_args += [ "-s", flags_for_protocols(desired_protocols) ]
  end

  def guest=(desired_protocols)
    @share_edit_args += [ "-g", flags_for_protocols(desired_protocols) ]
  end

  def share_name=(new_name)
    @share_edit_args += [ "-n", new_name ]
  end

  def afp_name=(new_name)
    return if afp_name == share_name
    @share_edit_args += [ "-A", new_name ]
  end

  def smb_name=(new_name)
    return if smb_name == share_name
    @share_edit_args += [ "-S", new_name ]
  end

  def ftp_name=(new_name)
    return if ftp_name == share_name
    @share_edit_args += [ "-F", new_name ]
  end

  def afp_inherit_perms=(inherit)
    @share_edit_args += [ "-i", inherit ? "10" : "00" ]
  end

end
