# == Class: python::install
#
# Installs core python packages,
#
# === Examples
#
# include python::install
#
# === Authors
#
# Sergey Stankevich
# Ashley Penney
# Fotis Gimian
# Garrett Honeycutt <code@garretthoneycutt.com>
#
class python::install {

  $python = $::python::version ? {
    'system' => 'python',
    'pypy'   => 'pypy',
    default  => "python${python::version}",
  }

  $pip = $::python::version ? {
    'system' => 'pip',
    /^2.*/ => 'pip',
    /^3.*/ => 'pip3',
    default => 'pip'
  }

  $pythondev = $::osfamily ? {
    'RedHat' => "${python}-devel",
    'Debian' => "${python}-dev",
    'Suse'   => "${python}-devel",
  }

  $dev_ensure = $python::dev ? {
    true    => 'present',
    false   => 'absent',
    default => $python::dev,
  }

  $pip_ensure = $python::pip ? {
    true    => 'present',
    false   => 'absent',
    default => $python::pip,
  }

  $venv_ensure = $python::virtualenv ? {
    true    => 'present',
    false   => 'absent',
    default => $python::virtualenv,
  }

  package { 'python':
    ensure => $python::ensure,
    name   => $python,
  }

  # Python 3.x on RHEL includes virtualenv as part of the main python package.
  if $::osfamily != 'RedHat' or $python::version !~ /^3.*/ {
    package { 'virtualenv':
      ensure  => $venv_ensure,
      require => Package['python'],
    }
  }

  case $python::provider {
    pip: {

      package { 'pip':
        ensure  => $pip_ensure,
        require => Package['python'],
      }

      package { 'python-dev':
        ensure => $dev_ensure,
        name   => $pythondev,
      }

      # Install pip without pip, see https://pip.pypa.io/en/stable/installing/.
      exec { 'bootstrap pip':
        command => "/usr/bin/curl https://bootstrap.pypa.io/get-pip.py | ${python}",
        creates => '/usr/local/bin/pip',
        require => Package['python'],
      }

      # Puppet is opinionated about the pip command name
      file { 'pip-python':
        ensure  => link,
        path    => '/usr/bin/pip-python',
        target  => '/usr/bin/pip',
        require => Exec['bootstrap pip'],
      }

      Exec['bootstrap pip'] -> File['pip-python'] -> Package <| provider == pip |>

      Package <| title == 'pip' |> {
        name     => 'pip',
        provider => 'pip',
      }
      Package <| title == 'virtualenv' |> {
        name     => 'virtualenv',
        provider => 'pip',
      }
    }
    scl: {
      # SCL is only valid in the RedHat family. If RHEL, package must be
      # enabled using the subscription manager outside of puppet. If CentOS,
      # the centos-release-SCL will install the repository.
      $install_scl_repo_package = $::operatingsystem ? {
        'CentOS' => 'present',
        default  => 'absent',
      }

      package { 'centos-release-SCL':
        ensure => $install_scl_repo_package,
        before => Package['scl-utils'],
      }
      package { 'scl-utils':
        ensure => 'latest',
        before => Package['python'],
      }

      # This gets installed as a dependency anyway
      # package { "${python::version}-python-virtualenv":
      #   ensure  => $venv_ensure,
      #   require => Package['scl-utils'],
      # }
      package { "${python}-scldevel":
        ensure  => $dev_ensure,
        require => Package['scl-utils'],
      }
      if $pip_ensure != 'absent' {
        exec { 'python-scl-pip-install':
          command => "${python::exec_prefix}easy_install pip",
          path    => ['/usr/bin', '/bin'],
          creates => "/opt/rh/${python::version}/root/usr/bin/pip",
          require => Package['scl-utils'],
        }
      }
    }
    rhscl: {
      # rhscl is RedHat SCLs from softwarecollections.org
      $scl_package = "rhscl-${::python::version}-epel-${::operatingsystemmajrelease}-${::architecture}"
      package { $scl_package:
        source   => "https://www.softwarecollections.org/en/scls/rhscl/${::python::version}/epel-${::operatingsystemmajrelease}-${::architecture}/download/${scl_package}.noarch.rpm",
        provider => 'rpm',
        tag      => 'python-scl-repo',
      }

      Package <| title == 'python' |> {
        tag => 'python-scl-package',
      }

      package { "${python}-scldevel":
        ensure => $dev_ensure,
        tag    => 'python-scl-package',
      }

      if $pip_ensure != 'absent' {
        exec { 'python-scl-pip-install':
          command => "${python::exec_prefix}easy_install pip",
          path    => ['/usr/bin', '/bin'],
          creates => "/opt/rh/${python::version}/root/usr/bin/pip",
        }
      }

      Package <| tag == 'python-scl-repo' |> ->
      Package <| tag == 'python-scl-package' |> ->
      Exec['python-scl-pip-install']
    }

    default: {

      if $::osfamily != 'RedHat' or $python::version !~ /^3.*/ {
        package { 'pip':
          ensure  => $pip_ensure,
          require => Package['python'],
        }
      }

      package { 'python-dev':
        ensure => $dev_ensure,
        name   => $pythondev,
      }

      if $::osfamily == 'RedHat' and $python::version !~ /^3.*/ {
        if $pip_ensure != 'absent' {
          if $python::use_epel == true {
            include 'epel'
            Class['epel'] -> Package['pip']
          }
        }
        if ($venv_ensure != 'absent') and ($::operatingsystemrelease =~ /^6/) {
          if $python::use_epel == true {
            include 'epel'
            Class['epel'] -> Package['virtualenv']
          }
        }

        $virtualenv_package = "${python}-virtualenv"
      } else {
        $virtualenv_package = $::lsbdistcodename ? {
          'jessie' => 'virtualenv',
          default  => 'python-virtualenv',
        }
      }

      $pip_package = 'python-pip'

      if $::osfamily == 'RedHat' and $python::version =~ /^3.*/ {
        # Install pip without pip, see https://pip.pypa.io/en/stable/installing/.
        exec { 'bootstrap pip':
          command => "/usr/bin/curl https://bootstrap.pypa.io/get-pip.py | /usr/bin/python3",
          creates => '/usr/bin/pip3',
          require => Package['python'],
        }
      } else {
        Package <| title == 'pip' |> {
          name => $pip_package,
        }
      }

      if $::osfamily != 'RedHat' or $python::version !~ /^3.*/ {
        Package <| title == 'virtualenv' |> {
          name => $virtualenv_package,
        }
      }
    }
  }

  if $python::manage_gunicorn {
    $gunicorn_ensure = $python::gunicorn ? {
      true    => 'present',
      false   => 'absent',
      default => $python::gunicorn,
    }

    package { 'gunicorn':
      ensure => $gunicorn_ensure,
    }
  }
}
