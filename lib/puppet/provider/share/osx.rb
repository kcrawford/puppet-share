Puppet::Type.type(:share).provide(:osx) do

  # Ensures required command line tools exist and creates a method for calling them within this provider
  commands :sharing => 'sharing'

  # Set use to darwin
  defaultfor :operatingsystem => :darwin
  confine :operatingsystem    => :darwin

  # Create setters and getters for properties
  mk_resource_methods

  # Assigns our providers to resources
  def self.prefetch(resources)
    instances_with_all_values.each do |provider|
      resources[provider.name].provider = provider if resources[provider.name]
    end
  end

  # Returns all instances of the resource type that are
  # discovered on the system.  The self.instances method is used by `puppet
  # resource`, and MUST be implemented for `puppet resource` to work.
  def self.instances
    instances_minus_default_values
  end

  # Used by instances which is called when running `puppet resource`
  # Removes default attributes so puppet resource output is clean and doesn't include default values
  def self.instances_minus_default_values
    all_shares_attributes.values.map do |share_hash|
      share_hash.delete(:afp_name) if share_hash[:afp_name] == share_hash[:share_name]
      share_hash.delete(:smb_name) if share_hash[:smb_name] == share_hash[:share_name]
      share_hash.delete(:ftp_name) if share_hash[:ftp_name] == share_hash[:share_name]
      share_hash.delete(:guest_protocols) if share_hash[:guest_protocols] == []
      share_hash.delete(:protocols) if share_hash[:protocols] == []
      share_hash.delete(:afp_inherit_perms) if share_hash[:afp_inherit_perms] == false
      share_hash.delete(:share_name) if share_hash[:share_name] == File.basename(share_hash[:name])
      new(share_hash)
    end
  end

  # Used by prefetch since it needs all existing values even if they are same as defaults
  def self.instances_with_all_values
    all_shares_attributes.values.map {|share_hash| new(share_hash) }
  end


  # Collects all existing shares and their attributes from the system into a hash
  def self.all_shares_attributes
    SharingOutput.new(sharing("-l")).to_hash
  end


  # override the provider's initialize method so we can instantiate an instance variable to keep state required for later flushing all changes in one step
  def initialize(attributes={})
    super(attributes)
    @share_edit_args = []
  end

  # used by ensure property to see if this share already exists on the system
  # since we use prefetching, we have already determined whether we exist ahead of time, so we can just check our ensure value
  def exists?
    self.ensure == :present
  end

  # called by ensure property when the share should be present, but isn't
  def create
    sharing("-a", name)
    @property_hash[:ensure] = :present

    # Setters are not automatically called on create, so we call them
    resource.properties.each do |property|
      property.sync unless property.name == :ensure
    end
  end

  # called by ensure when the share exists, but should be absent
  def destroy
    sharing("-r", share_name)
  end

  # returns most current share name
  def existing_share_name
    # name is a synonym for path here since that is our namevar.  share_name is the actual share_name
    self.class.all_shares_attributes[name][:share_name] || File.basename(name)
  end

  # flush is called at the end of the process as a hook to save the resource changes
  # Properties will have already been set as having been synced here because setters will have already been called
  # But then how do we know if properties are in actually insync at flush time?
  # Therein lies the problem -> according to puppet, properties are already in sync because the setter was called,
  #   but they weren't actually synced because we were waiting to sync them in a batch here using flush
  #   so that is why people track state separately from puppet's built-in when using flush
  # So what we do is build up our args -- storing them in our instance variable (@share_edit_args) in each setter when the setter is called,
  #   then we use them on flush to actually save our changes
  def flush
    return unless resource.should(:ensure) == :present
    unless @share_edit_args.empty?
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

  # Pads a number with zeros 3 places for use with sharing command flags
  def number_to_flags(number)
    number.to_s.rjust(3, "0")
  end

  # Setter for protocols (called automatically when syncing the resource)
  def protocols=(desired_protocols)
    @share_edit_args += [ "-s", flags_for_protocols(desired_protocols) ]
  end

  # Setter for guest protocols (called automatically when syncing the resource)
  def guest_protocols=(desired_protocols)
    @share_edit_args += [ "-g", flags_for_protocols(desired_protocols) ]
  end

  # Setter for share_name (called automatically when syncing the resource)
  def share_name=(new_name)
    @share_edit_args += [ "-n", new_name ]
  end

  # Setter for afp_name (called automatically when syncing the resource)
  def afp_name=(new_name)
    return if new_name == @resource.should(:share_name)
    @share_edit_args += [ "-A", new_name ]
  end

  # Setter for smb_name (called automatically when syncing the resource)
  def smb_name=(new_name)
    return if new_name == @resource.should(:share_name)
    @share_edit_args += [ "-S", new_name ]
  end

  # Setter for ftp_name (called automatically when syncing the resource)
  def ftp_name=(new_name)
    return if new_name == @resource.should(:share_name)
    @share_edit_args += [ "-F", new_name ]
  end

  # Setter for afp_inherit_perms (called automatically when syncing the resource)
  def afp_inherit_perms=(inherit)
    @share_edit_args += [ "-i", inherit ? "10" : "00" ]
  end

end

class ShareConfigSnippet
  attr_reader :snippet
  def initialize(snippet)
    @snippet = snippet
  end

  def extract_path
    snippet.lines.grep(/^path:/).first.split("\t").last.chomp
  end

  # returns list of supported protocols
  def supported_protocols
    ["afp", "smb", "ftp"]
  end

  # handles the parsing of config string snippet from sharing and returns hash of protocol info
  def extract_protocols
    protocol_info = Hash[*snippet.split(/(#{supported_protocols.join("|")}):\t*[{}]/)[1..-1]]
    supported_protocols.each do |protocol_name|
      protocol_info[protocol_name] = extract_protocol(protocol_info[protocol_name])
    end
    protocol_info
  end

  # extracts the value for a protocol key
  def protocol_value_for_key_in_string(key, string)
    string.split(/#{key}:\t*/)[1].to_s.split("\n").first
  end

  # takes a protocol string snippet and returns a hash of the protocol keys and values
  def extract_protocol(protocol_string)
    ["name", "shared", "guest access", "inherit perms"].inject({}) do |hash, key|
      hash[key] = protocol_value_for_key_in_string(key, protocol_string)
      hash
    end
  end
end

class ShareSnippet
  attr_reader :snippet
  def initialize(snippet)
    @snippet = snippet
  end

  def extract_share_hash
    share_name_snippet, config_snippet_string = snippet.split("\n", 2)
    share_name = share_name_snippet.gsub(/^\t*/, '')
    config_snippet = ShareConfigSnippet.new(config_snippet_string)
    path = config_snippet.extract_path
    protocols = config_snippet.extract_protocols
    { path => 
      {
        :name => path,
        :share_name => share_name,
        :afp_name => protocols["afp"]["name"],
        :smb_name => protocols["smb"]["name"],
        :ftp_name => protocols["ftp"]["name"],
        :ensure => :present,
        :guest_protocols => get_guest_protocols(protocols),
        :protocols => get_enabled_protocols(protocols),
        :afp_inherit_perms => (protocols["afp"]["inherit perms"] == "1")
      }
    }
  end

  # selects only the enabled protocols from a hash of protocols
  def get_enabled_protocols(protocols)
    Hash[ protocols.select {|k,v| v["shared"] == "1" } ].keys
  end

  # selects only the guest enabled protocols from a hash of protocols
  def get_guest_protocols(protocols)
    Hash[ protocols.select {|k,v| v["guest access"] == "1" } ].keys
  end

end

class SharingOutput
  attr_reader :raw_output

  def initialize(raw_output)
    @raw_output = raw_output
  end

  def content
    raw_output.gsub(/.*List of Share Points/,'').lstrip
  end

  def share_snippet_strings
    content.split(/^name:/)[1..-1].to_a
  end

  def to_hash
    all_shares = {}
    share_snippet_strings.each do |share_snippet_string|
      share_hash = ShareSnippet.new(share_snippet_string).extract_share_hash
      all_shares.merge!(share_hash)
    end
    all_shares
  end

end

