# -*- mode: ruby -*-
# vi: set ft=ruby :

ENV["LC_ALL"] = "C"

Vagrant.configure("2") do |config|
  config.vm.define "iscsi" do |iscsi|
    iscsi.vm.box = "debian/stretch64"
    iscsi.vm.hostname = 'iscsi'
    iscsi.vm.network "private_network", ip: "192.168.50.20", virtualbox__intnet: true
    iscsi.vm.provider "virtualbox" do |vb|
      # For the name, we emulate Vagrant name generation
      # Note that Vagrant will execute this code at start, not
      # on actual provision, final name for code just below
      vb.name = 'nfs_iscsi_'+Time.now.strftime('%s%L')+'_'+Process.pid.to_s

      # https://stackoverflow.com/a/31177761/706716
      line = `VBoxManage list systemproperties`.split(/\n/).grep(/Default machine folder/).first
      vb_machine_folder = line.split(':')[1].strip()
      disk = File.join(vb_machine_folder, vb.name, 'data.vdi')
      unless File.exist?(disk)
        vb.customize ['createhd', '--filename', disk, '--variant', 'Fixed', '--size', 1024]
      end
      vb.customize ['storagectl', :id, '--name', 'SATA Controller', '--portcount', 2]
      vb.customize ['storageattach', :id, '--storagectl', 'SATA Controller', '--port', 1, '--device', 0, '--type', 'hdd', '--medium', disk]
    end
  end

  config.vm.define "nfs1" do |nfs1|
    nfs1.vm.box = "debian/stretch64"
    nfs1.vm.hostname = 'nfs1'
    nfs1.vm.network "private_network", ip: "192.168.50.11", virtualbox__intnet: true
  end

  config.vm.define "nfs2" do |nfs2|
    nfs2.vm.box = "debian/stretch64"
    nfs2.vm.hostname = 'nfs2'
    nfs2.vm.network "private_network", ip: "192.168.50.12", virtualbox__intnet: true
  end

  config.vm.define "client" do |client|
    client.vm.box = "centos/7"
    client.vm.hostname = 'client'
    client.vm.network "private_network", ip: "192.168.50.100", virtualbox__intnet: true

    # We provision all environment inside "client" so it is
    # done once in parallel at end
    config.vm.provision :ansible do |ansible|
      ansible.compatibility_mode = "2.0"
      ansible.playbook = "nfs.yml"
      ansible.limit = "all"
    end
  end
end
