define :redis_instance, :port => nil, :data_dir => nil, :master => nil do
  raise ::Chef::Exceptions::InvalidResourceSpecification, "redis instance name can't be \"default\"" \
    if params[:name] == "default"
  include_recipe "redis"
  instance_name = "redis_#{params[:name]}"
  # if no explicit replication role was defined, it's a master
  node.default_unless[:redis][:instances][params[:name]][:replication][:role] = "master"

  init_dir = value_for_platform([:debian, :ubuntu] => {:default => "/etc/init.d/"},
                              [:centos, :redhat] => {:default => "/etc/rc.d/init.d/"},
                              :default => "/etc/init.d/")

  # some ugly voodoo to merge attributes with defaults
  conf = ::Mash.new(
    ::Chef::Mixin::DeepMerge.merge(
      node[:redis][:instances][:default].to_hash, node[:redis][:instances][params[:name]].to_hash
    ).merge({:port => params[:port], :data_dir => params[:data_dir]})
  )

  # minimal checks to see data doesn't mix
  if conf[:data_dir] == node[:redis][:instances][:default][:data_dir]
    conf[:data_dir] = ::File.join(node[:redis][:instances][:default][:data_dir], params[:name])
    node.set[:redis][:instances][params[:name]][:data_dir] = conf[:data_dir]
    Chef::Log.warn "Changing data_dir for #{instance_name} because it shouldn't be default." 
  end

  if conf[:vm][:swap_file].nil? or conf[:vm][:swap_file] == node[:redis][:instances][:default][:vm][:swap_file]
    conf[:vm][:swap_file] = ::File.join(
      ::File.dirname(node[:redis][:instances][:default][:vm][:swap_file]), "swap_#{params[:name]}")
    node.set[:redis][:instances][params[:name]][:vm][:swap_file] = conf[:vm][:swap_file]
    Chef::Log.warn "Changing vm.swap_file for #{instance_name} because it shouldn't be default." 
  end

  # the most common use case when using search is to use some attributes of the node object from the search,
  # probably the ipaddress and the port. So to avoid incorrect port in attributes:
  if params[:port] and \
    (not node[:redis][:instances][params[:name]].attribute? :port or \
     params[:port] != node[:redis][:instances][params[:name]][:port])
     raise InvalidResourceSpecification, "#{instance_name} port specified in recipe doesn't match port in attributes. You should avoid setting the port attribute manually if you are setting it via the definition body, otherwise you may break search consistency."
  end

  directory conf[:data_dir] do
    owner node[:redis][:user]
    mode "0750"
  end

  conf_vars = {
    :conf => conf,
    :instance_name => params[:name],
    :master => params[:master],
  }

  template ::File.join(node[:redis][:conf_dir], "#{instance_name}.conf") do
    source "redis.conf.erb"
    cookbook "redis"
    variables conf_vars
    mode "0644"
    notifies :restart, "service[#{instance_name}]"
  end

  runit_service instance_name do
    template_name "redis"
    cookbook "redis"
    options :user => node[:redis][:user],
      :config_file => ::File.join(node[:redis][:conf_dir], "#{instance_name}.conf")
  end

  provide_service instance_name, :replication => node[:redis][:instances][params[:name]][:replication][:role]
end
