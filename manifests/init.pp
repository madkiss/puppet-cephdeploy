class cephdeploy(
  $user = $::ceph_deploy_user,
  $pass = $::ceph_deploy_password,
  $has_compute = false,
){

  include pip

  user {$user:
    ensure => present,
    password => $pass,
    home     => "/home/$user",
    shell    => '/bin/bash',
  }

  file {"/home/$user":
    ensure => directory,
    owner  => $user,
    group  => $user,
    mode   => 0755,
    require => User[$user],
  }
  
  file {"/home/$user/.ssh":
    ensure => directory,
    owner  => $user,
    group  => $user,
    mode   => 0700,
    require => File["/home/$user"],
  }

  file {"/home/$user/.ssh/id_rsa":
    content => template('cephdeploy/id_rsa.erb'),
    owner  => $user,
    group  => $user,
    mode   => 0600,
    require => File["/home/$user/.ssh"],
  }

  file {"/home/$user/.ssh/id_rsa.pub":
    content => template('cephdeploy/id_rsa.pub.erb'),
    owner  => $user,
    group  => $user,
    mode   => 0644,
    require => File["/home/$user/.ssh"],
  }

  file {"/home/$user/.ssh/authorized_keys":
    content => template('cephdeploy/id_rsa.pub.erb'),
    owner  => $user,
    group  => $user,
    mode   => 0600,
    require => File["/home/$user/.ssh"],
  }

  file {"/home/$user/.ssh/config":
    content => template('cephdeploy/config.erb'),
    owner  => $user,
    group  => $user,
    mode   => 0600,
    require => File["/home/$user/.ssh"],
  }

  file { "/home/$user/zapped":
    ensure => directory,
  }

  exec {'passwordless sudo for ceph deploy user':
    command => "/bin/echo \"$user ALL = (root) NOPASSWD:ALL\" | sudo tee /etc/sudoers.d/$user",
  }
 
  file {"/etc/sudoers.d/$user":
    mode    => 0440,
    require => Exec['passwordless sudo for ceph deploy user'],
  }

  exec {'install ceph-deploy':
    command => '/usr/bin/pip install ceph-deploy', 
    require => Package['python-pip'],
    unless  => '/usr/bin/pip install ceph-deploy | /bin/grep satisfied',
  }

  $cephdirs = ['/etc/ceph', '/etc/ceph/bootstrap']
  file {$cephdirs:
    ensure => directory,
    owner  => 'root',
    mode   => '0777',
  }

  file {'/etc/ceph/bootstrap/ceph.log':
    mode => 0777,
  }

  file { "ceph.conf":
    path    => '/etc/ceph/bootstrap/ceph.conf',
    content => template('cephdeploy/ceph.conf.erb'),
    require => File[$cephdirs],
  }

  file { "ceph.mon.keyring":
    path    => '/etc/ceph/bootstrap/ceph.mon.keyring',
    content => template('cephdeploy/ceph.mon.keyring.erb'),
    require => File['ceph.conf'],
  }

  exec { "install ceph":
    cwd     => '/etc/ceph/bootstrap',
    command => "/usr/local/bin/ceph-deploy install $::hostname",
    unless  => '/usr/bin/dpkg -l | grep ceph-common',
    require => [ Exec['install ceph-deploy'], File['ceph.mon.keyring'], File[$cephdirs] ],
  }

  if $has_compute {

    package {'libvirt-bin':
      ensure => present,
    }

    file { '/etc/ceph/secret.xml':
      content => template('cephdeploy/secret.xml-compute.erb'),
    }

    exec { 'get-or-set virsh secret':
      command => '/usr/bin/virsh secret-define --file /etc/ceph/secret.xml | /usr/bin/awk \'{print $2}\' | sed \'/^$/d\' > /etc/ceph/virsh.secret',
      creates => "/etc/ceph/virsh.secret",
      require => [ File['ceph.conf'], Package['libvirt-bin'] ],
    }

    exec { 'set-secret-value virsh':
      command => "/usr/bin/virsh secret-set-value --secret $(cat /etc/ceph/virsh.secret) --base64 $(ceph auth get-key client.admin)",
      require => [ Exec['get-or-set virsh secret'], Exec['install ceph'] ],
    }

  }


}