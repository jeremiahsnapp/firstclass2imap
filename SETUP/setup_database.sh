
# be sure to run this script using 'sudo'

# Install LAMP stack on first migration server

# The LAMP stack is only needed on the first migration server so don’t install it on subsequent migration servers.
# Subsequent migration servers will be configured to point to the master database on the first migration server.
# This is necessary for correct migration instance control.  It also makes overall progress reporting easier.

# for a mysql server i'd also like to have phpmyadmin so go ahead and install the lamp-server task


apt-get -y install lamp-server^ php5-cli
# you will be asked to enter a root password for the mysql server


# configure mysql to listen on all interfaces
sed -r 's/^(bind-address.*=).*/\1 0.0.0.0/' /etc/mysql/my.cnf
service mysql restart


# open ports 80 and 443 in the firewall
ufw allow 'Apache Full'

#--------------------------------------------------------------------------

apt-get -y install phpmyadmin

# Require https when accessing phpmyadmin
a2enmod rewrite
a2enmod ssl
a2ensite default-ssl

sed -i '/<Directory \/usr\/share\/phpmyadmin>/ a\#       Require https when accessing phpmyadmin\n        RewriteEngine On\n        RewriteCond %{HTTPS} =off\n        RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [NS,R,L]\n' /etc/apache2/conf.d/phpmyadmin.conf

/etc/init.d/apache2 reload

# Web server to reconfigure automatically:
# Choose: apache2


# Configure database for phpmyadmin with dbconfig-common:  true


# Password of the database's administrative user:  i think this needs to be the root password you chose for mysql

# MySQL application password for phpmyadmin:  can leave this blank to choose random password

# copy the following lines and enter them directly into a shell prompt
cat <<EOF >> /etc/phpmyadmin/config.inc.php
// Display the PHP information link
\$cfg['ShowPhpInfo'] = TRUE;
// Allow editing of all fields including BLOB or BINARY fields
\$cfg['ProtectBinary'] = FALSE;
EOF


#--------------------------------------------------------------------------

echo use the usermap.sql file to create the “migrate” database with “usermap” table and fields and
echo a “migrate” user with a password set to “password”
echo that has global "Select, Insert, Update, Delete" permissions
echo
echo mysql -u root -p \< /home/migrate/firstclass2imap/SETUP/usermap.sql
echo
echo
echo you should be able to browse to https://server.ip.address/phpmyadmin
echo login to phpmyadmin with root and password
echo change the password of the “migrate” user to something more secure
echo
echo if you are going to have other migration servers connect to this database then also
echo change the “Host” field for the “migrate” user to “%” so any host can connect

#--------------------------------------------------------------------------

