#!/usr/bin/perl -w

use warnings;
use strict;
use Getopt::Long;
use FindBin;
use lib "$FindBin::RealBin/inc";
# Modules du repertoire inc/
use Tools;
use Templates;
use Environments;
my $CONFIG = do "$FindBin::RealBin/inc/Config.pl";
set_debug($CONFIG->{DEBUG});

###### GLOBAL VARS  ######

my ($cmd_hostname, $cmd_system, $cmd_root_size, $cmd_swap_size, $cmd_vcpus,
    $cmd_memory, $cmd_public_ip, $cmd_private_ip, $cmd_password, $cmd_help,
    $cmd_ssh_pubkey);
# Default values
$cmd_swap_size   = "1G";

###### PROTOTYPES  ######

# Show help
sub usage();
# Affiche les parametres passes a la commande
sub show_parameters();

# DomU Installation

# Cree le fichier de configuration du domU
# Param : (string) $cfg_file, nom du fichier de configuration
#         (string) $hostname, nom d'hote
#         (string) $vcpus, nombre de cpus
#         (string) $memory, memoire en Mo
#         (string) $cpu_weight
#         (string) $public_ip, ip publique
#         (string) $private_ip, ip privee
sub create_domain_cfg($$$$$$$);

# Cree les volumes logiques LVM $hostname-disk et $hostname-swap et les formatte en ext4
# Param : (string) $hostname, nom d'hote
#         (string) $root_size, taille de la partition racine
#         (string) $swap_size, taille de la swap
sub create_lvm_disks($$$);

# Installe et configure le systeme
# Param : (string) $hostname, nom d'hote
#         (string) $system, nom de l'environnement a installer (repertoire dans env/)
#         (string) $password, mot de passe root
#         (string) $public_ip, ip publique
#         (string) $private_ip, ip privee
sub configure_install($$$$$$);

# Nettoie le systeme et supprime le domU
# Param : (string) $cfg_file, fichier de configuration du domU
#         (string) $hostname, nom d'hote du systeme
sub clean_everything($$);

####### EXECUTION #######

usage() if ( @ARGV < 1 or
           ! GetOptions(
           "hostname=s"  => \$cmd_hostname,
           "system=s"    => \$cmd_system,
           "root_size=s" => \$cmd_root_size,
           "swap_size=s" => \$cmd_swap_size,
           "vcpus=i"     => \$cmd_vcpus,
           "memory=i"    => \$cmd_memory,
           "public_ip=s" => \$cmd_public_ip,
           "private_ip=s"=> \$cmd_private_ip,
           "password=s"  => \$cmd_password,
           "ssh_pubkey=s"=> \$cmd_ssh_pubkey,
           "help|?"      => \$cmd_help
                     )
           or defined $cmd_help);

######## CHECKS

die usage unless ( $cmd_hostname && $cmd_system && $cmd_root_size
                  && $cmd_vcpus && $cmd_memory && $cmd_public_ip
                  && $cmd_private_ip && $cmd_password && $cmd_ssh_pubkey);


set_log_file($CONFIG->{LOG_DIRECTORY} . "/" . $cmd_hostname);

report("----- Nouveau domU  -----");
show_parameters();

report("----- Verifications -----");

eval { syscmd("/sbin/vgdisplay | /bin/grep $CONFIG->{VOLUME_GROUP}"); };
if ($@)
{
  error("LVM Volume Group inexistant : $CONFIG->{VOLUME_GROUP}", 1);
}

if ($cmd_hostname !~ /^[a-z0-9]+$/)
{
  error("Chaine hostname non conforme", 1);
}

eval { syscmd("/usr/sbin/xm list | /bin/grep \"$cmd_hostname \""); };
if (! $@)
{
  error("Hostname deja utilise", 1);
}

eval { syscmd("/sbin/lvdisplay | /bin/grep -e \"$CONFIG->{VOLUME_GROUP}/$cmd_hostname-\\(disk\\|swap\\)\""); };
if (! $@)
{
  error("LVM Volume Logique deja existant : $CONFIG->{VOLUME_GROUP}/$cmd_hostname-(disk|swap)", 1);
}

if ($cmd_public_ip !~ /^[0-9]+.[0-9]+.[0-9]+.[0-9]+$/)
{
  error("Chaine ip publique non conforme.", 1);
}

if ($cmd_private_ip !~ /^[0-9]+.[0-9]+.[0-9]+.[0-9]+$/)
{
  error("Chaine ip privee non conforme.", 1);
}

if (! environment_exists($cmd_system ))
{
  error("System inexistant", 1);
}

if ($cmd_password !~ /^[a-zA-Z0-9]+$/)
{
  error("Password non conforme", 1);
}

if ($cmd_root_size !~ /^[0-9]+[MG]$/)
{
  error("Taille du disque root non conforme", 1);
}

if ($cmd_swap_size !~ /^[0-9]+[MG]$/)
{
  error("Taille du disque swap non conforme", 1);
}

#if ($cmd_memory !~ /^[0-9]+$/)
#{
#  error("Capacite memoire non conforme", 1);
#}
#
#if ($cmd_vcpus !~ /^[0-9]+$/)
#{
#  error("Nombre de CPU non conforme", 1);
#}

####### WORK !

my $ENV = get_environment($cmd_system);
my $DOMU_CFG_FILE = $CONFIG->{XEN_CFG_PATH} . "/domu_" . $cmd_hostname . ".cfg";

eval
{
  report("----- Creation de la configuration du domU -----");
  create_domain_cfg($DOMU_CFG_FILE, $cmd_hostname, $cmd_vcpus, $cmd_memory, $cmd_memory, $cmd_public_ip, $cmd_private_ip);

  report("----- Creation des volumes logiques LVM -----");
  create_lvm_disks($cmd_hostname, $cmd_root_size, $cmd_swap_size);

  ####### Installation du systeme

  # Montage du disque LVM
  syscmd("/bin/mount -t ext4 /dev/$CONFIG->{VOLUME_GROUP}/$cmd_hostname-disk $CONFIG->{MOUNT_POINT}");

  # Installation du systeme dans $CONFIG->{MOUNT_POINT}
  report("----- Configuration de l'installation -----");
  configure_install($cmd_hostname, $cmd_system, $cmd_password, $cmd_public_ip, $cmd_private_ip, $cmd_ssh_pubkey);

  # Lancement du script de post install
  report("----- Lancement du script $ENV->{POST_INSTALL} ------");
  syscmd("$FindBin::RealBin/$ENV->{POST_INSTALL} $CONFIG->{MOUNT_POINT}", 1);

  # Demontage du disque LVM
  syscmd("/bin/umount $CONFIG->{MOUNT_POINT}");


  ###### Lancement du domU
  report("----- Lancement du domU -----");
  syscmd("/usr/sbin/xm create $DOMU_CFG_FILE");

  ###### Lancement du script postboot
  report("----- Lancement du script $ENV->{POST_BOOT} ------");
  # Attente du demarrage du systeme
  syscmd("/bin/sleep 20");
  syscmd("$FindBin::RealBin/$ENV->{POST_BOOT} $cmd_hostname $cmd_private_ip", 1);

  report("----- SUCCES ! -----\n");
  exit(0);
};

if ($@)
{
  report("----- Nettoyage -----");

  ###### Lancement du script clean.pl
  report("----- Lancement du script $ENV->{CLEAN} ------");
  eval { syscmd("$FindBin::RealBin/$ENV->{CLEAN} $cmd_hostname", 1); };

  clean_everything($DOMU_CFG_FILE, $cmd_hostname);

  report("----- ECHEC ! -----\n");
  exit(1);
}

####### FUNCTIONS #######

# show usage
sub usage()
{
  print "Unknown option: @_\n" if ( @_ );

  print "usage: vm_create.pl\n";
  print "";
  print "\t--hostname \t Nom d'hote\n";
  print "\t--system \t Systeme : debian_squeeze|debian_puppet\n";
  print "\t--root_size \t Taille de la partition systeme\n";
  print "\t--swap_size \t Taille de la partition swap - Facultatif, defaut 1G\n";
  print "\t--vcpus \t Nombre de CPUS\n";
  print "\t--memory \t Taille de la memoire\n";
  print "\t--public_ip \t IP publique de la machine virtuelle\n";
  print "\t--private_ip \t IP privee de la machine virtuelle\n";
  print "\t--password \t Mot de passe de l'utilisateur root\n";
  print "\t--ssh_pubkey \t Cle publique SSH\n";
  print "\t--help \t\t Afficher ce message\n";

  exit 0 if ( @_ );
  exit 1;
}

sub show_parameters()
{
  report("Parametres recus");
  report("--hostname $cmd_hostname");
  report("--system $cmd_system");
  report("--root_size $cmd_root_size");
  report("--swap_size $cmd_swap_size");
  report("--vcpus $cmd_vcpus");
  report("--memory $cmd_memory");
  report("--public_ip $cmd_public_ip");
  report("--private_ip $cmd_private_ip");
  report("--password ********");
  report("--ssh_pubkey $cmd_ssh_pubkey");
}

# create domain configuration file
sub create_domain_cfg($$$$$$$)
{
  my ($cfg_file, $hostname, $vcpus, $memory, $cpu_weight, $public_ip, $private_ip) = @_;

  my $tpl_vars = {
        '\$VCPUS'        => $vcpus,
        '\$MEMORY'       => $memory,
        '\$CPU_WEIGHT'   => $cpu_weight,
        '\$VOLUME_GROUP' => $CONFIG->{VOLUME_GROUP},
        '\$HOSTNAME'     => $hostname,
        '\$PUBLIC_IP'    => $public_ip,
        '\$PRIVATE_IP'   => $private_ip,
        };

  register_file("$FindBin::RealBin/$ENV->{DOMU_TPL_FILE}", $cfg_file,  $tpl_vars);

  syscmd("/bin/ln -s ".$cfg_file." ". $CONFIG->{XEN_CFG_PATH} ."/auto/domu_" . $hostname . ".cfg");
}

# create lvm disks
sub create_lvm_disks($$$)
{
  my ($hostname, $root_size, $swap_size) = @_;

  report("Creation des volumes logiques...");
  syscmd("/sbin/lvcreate -L \"$root_size\" -n \"/dev/$CONFIG->{VOLUME_GROUP}/$hostname-disk\"");
  syscmd("/sbin/lvcreate -L \"$swap_size\" -n \"/dev/$CONFIG->{VOLUME_GROUP}/$hostname-swap\"");

  report("Formatage des systemes de fichiers...");
  syscmd("/sbin/mkfs.ext4 /dev/$CONFIG->{VOLUME_GROUP}/$hostname-disk");
  syscmd("/sbin/mkswap /dev/$CONFIG->{VOLUME_GROUP}/$hostname-swap");
}

sub configure_install($$$$$$)
{
  my ($hostname, $system, $password, $public_ip, $private_ip) = @_;
  my $tarball = "$FindBin::RealBin/$ENV->{TARBALL}";
  my $tpl_vars;

  syscmd("/bin/tar xzf $tarball -C $CONFIG->{MOUNT_POINT}");

  ############### Changement du nom d'hote

  # ecriture du hostname, parametre display, syscmd ne fait pas de redirection
  syscmd("/bin/echo $hostname > $CONFIG->{MOUNT_POINT}/etc/hostname", 1);

  ############### Changemet du mot de passe root
  syscmd("/usr/sbin/chroot $CONFIG->{MOUNT_POINT} /usr/sbin/chpasswd -m << EOF
root:$password
EOF", 1);


  register_file($cmd_ssh_pubkey, "$CONFIG->{MOUNT_POINT}/root/.ssh/authorized_keys");

  ############### Fichier hosts

  report("Creation du fichier hosts...");

  $tpl_vars = { '\$PUBLIC_IP'  => $public_ip,
                '\$PRIVATE_IP' => $private_ip,
                '\$HOSTNAME'   => $hostname, };

  register_file("$FindBin::RealBin/$ENV->{HOSTS_FILE}", "$CONFIG->{MOUNT_POINT}/etc/hosts",  $tpl_vars);

  ############### Configuration reseau

  report("Creation du fichier de configuration reseau...");

  $tpl_vars = { '\$PUBLIC_IP'  => $public_ip,
                '\$PRIVATE_IP' => $private_ip, };

  register_file("$FindBin::RealBin/$ENV->{NETWORK_FILE}", "$CONFIG->{MOUNT_POINT}/etc/network/interfaces", $tpl_vars);


  ############### Configuration des serveurs DNS

  # Fichier /etc/resolv.conf
  register_file("/etc/resolv.conf", "$CONFIG->{MOUNT_POINT}/etc/resolv.conf");

}

sub clean_everything($$)
{
  my ($cfg_file, $hostname) = @_;
#  eval { syscmd("/usr/sbin/xm destroy $hostname"); };
#  eval { syscmd("/bin/rm -f ". $CONFIG->{XEN_CFG_PATH} ."/auto/domu_" . $hostname . ".cfg"); };
#  eval { syscmd("/bin/rm -f ". $cfg_file); };
#  eval { syscmd("/bin/umount $CONFIG->{MOUNT_POINT}"); };
#  eval { syscmd("/sbin/lvremove -f $CONFIG->{VOLUME_GROUP}/$hostname-disk"); };
#  eval { syscmd("/sbin/lvremove -f $CONFIG->{VOLUME_GROUP}/$hostname-swap"); };
}
