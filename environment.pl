# Environnement propre au systeme Debian
return {
  # Fichiers obligatoires
  TARBALL      => "env/vds/template-xenvmhostname.tar.gz",
  DOMU_TPL_FILE=> "env/vds/files/template-xenvmhostname.cfg",
  NETWORK_FILE => "env/vds/files/interfaces",
  HOSTS_FILE   => "env/vds/files/hosts",
  # Script execute apres configuration
  POST_INSTALL => "env/vds/postinstall.pl",
  # Script execute apres lancement du domU
  POST_BOOT    => "env/vds/postboot.pl",
  # Script execute avant la suppression du domU
  CLEAN        => "env/vds/clean.pl"
}
