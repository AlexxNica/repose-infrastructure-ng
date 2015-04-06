# Actually installs jenkins, rather than waiting for the master to push the JAR
# Using installed will not automatically update jenkins for us, just make sure it's actually there.
# Since the apt-repo doesn't keep around older versions it makes for a mess, using installed will keep puppet from
# doing silly things
class repose_jenkins::master(
    $jenkins_version = "installed"
) {
    include repose_jenkins

    $jenkins_home = '/var/lib/jenkins'


# This is kind of nasty hax.
# The repose-jenkins puppet module gets a little too restart happy, which causes our builds to be terminated
# every single time the puppet agent runs, that's no good.
# this takes a much larger hammer to it, by replacing the original jenkins init script with one that does nothing
# creating a second jenkins-real that is the one we actually want.
    file{ '/etc/init.d/jenkins':
        ensure  => file,
        owner   => root,
        group   => root,
        mode    => 0754,
        source  => 'puppet:///modules/repose_jenkins/jenkins-fake',
        require => Package['jenkins'],
        before  => Service['jenkins'],
    }

    file{ '/etc/init.d/jenkins-real':
        ensure  => file,
        owner   => root,
        group   => root,
        mode    => 0754,
        source  => 'puppet:///modules/repose_jenkins/jenkins-real',
        require => Package['jenkins'],
    }

    service{ 'jenkins-real':
        ensure  => running,
        enable  => true,
        require => [
            File['/etc/init.d/jenkins-real'],
            Class['jenkins'],
        ],
    }

# this class already explicitly uses the jenkins repo, so I'm not sure why versions are vanishing
# switching to the LTS version of jenkins for less irritating updates
    class{ 'jenkins':
        lts                => true,
        version            => "${jenkins_version}",
        configure_firewall => false,
        install_java       => false,
        repo               => true,
        require            => [
            Class['java'],
            File["${jenkins_home}/.gitconfig"]
        ],
        config_hash        => {
            'JENKINS_HOME' => { 'value' => "${jenkins_home}" },
            'JENKINS_USER' => { 'value' => 'jenkins' },
            'JENKINS_JAVA_OPTIONS' =>
            { 'value' => "-Djava.awt.headless=true -Xms2048m -Xmx4096m -XX:PermSize=512m -XX:MaxPermSize=1024m -XX:-UseConcMarkSweepGC -XX:+CMSClassUnloadingEnabled" }
        },
    }

    include base::nginx::autohttps

    file{ "/etc/nginx/conf.d/jenkins.conf":
        ensure  => file,
        mode    => 0644,
        owner   => root,
        group   => root,
        content => template("repose_jenkins/nginx.conf.erb"),
        require => Package['nginx'],
        notify  => Service['nginx'],
    }

# define our jenkins SCM config sync plugin
# I think this is the only one we need, as it manages all the other configs
# the base class provides the ssh key for github.com, so it should be good to go
    jenkins::plugin{ 'scm-sync-configuration':
        version         => '0.0.7.3',
        manage_config   => true,
        config_filename => "scm-sync-configuration.xml",
        config_content  => template("repose_jenkins/scm-sync-configuration.xml.erb"),
    }

    file{ "${jenkins_home}/log":
        ensure  => directory,
        mode    => 0755,
        owner   => jenkins,
        group   => jenkins,
        require => Class['jenkins'],
    }

    file{ "${jenkins_home}/log/scm_sync_configuration.xml":
        ensure  => file,
        mode    => 0644,
        owner   => jenkins,
        group   => jenkins,
        source  => "puppet:///modules/repose_jenkins/scm_sync_configuration.xml",
        require => File["${jenkins_home}/log"],
    }

    jenkins::plugin{ 'dashboard-view':
        version => '2.9.4'
    }
    jenkins::plugin{ 'github-api':
        version => '1.59'
    }
    jenkins::plugin{ 'github':
        version => '1.10'
    }
    jenkins::plugin{ 'ssh-agent':
        version => '1.5'
    }
    jenkins::plugin{ 'ghprb':
        version => '1.16-8'
    }
    jenkins::plugin{ 'git-client':
        version => '1.15.0'
    }
    jenkins::plugin{ 'git':
        version => '2.3.4'
    }
#https://issues.jenkins-ci.org/browse/JENKINS-23426
# 1.0.15 has failure problems, and it blows up all over the place :(
# 1.0.16 should be mush batter
    jenkins::plugin{ 'jacoco':
        version => '1.0.18'
    }
    jenkins::plugin{ 'jquery':
        version => '1.7.2-1'
    }
    jenkins::plugin{ 'm2release':
        version => '0.14.0'
    }
    jenkins::plugin{ 'parameterized-trigger':
        version => '2.25'
    }
    jenkins::plugin{ 'ssh':
        version => '2.4'
    }
    jenkins::plugin{ 'publish-over-ssh':
        version => '1.12'
    }
    jenkins::plugin{ 'simple-theme-plugin':
        version => '0.3'
    }
    jenkins::plugin{ 'join':
        version => '1.15'
    }
    jenkins::plugin{ 'conditional-buildstep':
        version => '1.3.3'
    }
    jenkins::plugin{ 'run-condition':
        version => '1.0'
    }
    jenkins::plugin{ 'token-macro':
        version => '1.10'
    }
    jenkins::plugin{ 'scm-api':
        version => '0.2'
    }
# oops, somehow I forgot that sonar needed to exist :(
    jenkins::plugin{ 'sonar':
        version => '2.1'
    }
# also forgot that we need the copy-artifact plugin to get artifacts smartly
    jenkins::plugin{ 'copyartifact':
        version => '1.33'
    }

# adding a plugin to deal with multijob stuff
    jenkins::plugin{ 'envinject':
        version => '1.90'
    }

    jenkins::plugin { 'jenkins-multijob-plugin':
        version => '1.16'
    }


# to use the slave logic that the jenkins puppet module uses, we need the swarm plugin
    jenkins::plugin{ 'swarm':
        version => '1.22',
    }

# Need to have this to be able to mask passwords from the jenkins output
    jenkins::plugin { 'mask-passwords':
        version => '2.7.2'
    }


#lets add back in my hax
# Explicitly not including the jenkins access logs, because they're chatty.
    $papertrail_port = hiera("base::papertrail_port", 1)
    class{ 'remotesyslog':
        port => $papertrail_port,
        logs => [
            '/var/log/jenkins/jenkins.log',
            '/var/log/nginx/error.log'
        ],
    }
}
