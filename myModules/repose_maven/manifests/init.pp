#Installs maven and settings for uploading to our repo
class repose_maven(
  $maven_version = "3.3.3",
  $user = undef,
  $user_home = "/home/${user}"
) {

  #Installs maven
  class{ "maven::maven":
    version => "${maven_version}",
  }

  #Installs settings and sets up maven opts
  maven::environment { 'maven-jenkins':
    user       => "${user}",
    home       => "${user_home}",
    maven_opts => '-Xms512m -Xmx1024m -XX:PermSize=256m -XX:MaxPermSize=512m -XX:-UseConcMarkSweepGC -XX:+CMSClassUnloadingEnabled',
    require    => Class['java'],
  }

  #Link to the common spot for ease of use
  file{ "/opt/maven":
    ensure  => link,
    target  => "/opt/apache-maven-${maven_version}",
    require => Class['java'],
  }

}