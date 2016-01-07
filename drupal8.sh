#!/bin/bash

#test if the script runs as root
if [ "$(whoami)" != root ]; then
	echo "This script needs to be run as root!\n"
	exit 1
fi

#directories
PWD="$(pwd)"
APACHE2=/etc/apache2
SITES_AVAILABLE=$APACHE2/sites-available

#files
HOSTS=/etc/hosts
PORTS=$APACHE2/ports.conf
DEFAULT_CONF=$SITES_AVAILABLE/000-default.conf

function installAll {
	#settings
	read -p "Site name: " SITE
	if [ -z "$SITE" ]; then SITE="mydrupal"; fi

	read -p "Site administrator name: " SITE_ADMIN
	if [ -z "$SITE_ADMIN" ]; then SITE_ADMIN="myadmin"; fi

	read -s -p "Site administrator password: " SITE_ADMIN_PASSWORD
	if [ -z "$SITE_PASSWORD" ]; then SITE_ADMIN_PASSWORD="mypassword"; fi
	echo -e "\r";

	read -p "Site administrator email: " SITE_ADMIN_EMAIL
	if [ -z "$SITE_ADMIN_EMAIL" ]; then SITE_ADMIN_EMAIL="myadmin@example.com"; fi

	read -p "Database name: " DATABASE
	if [ -z "$DATABASE" ]; then DATABASE=$SITE; fi

	read -p "Database user name: " DATABASE_USER
	if [ -z "$DATABASE_USER" ]; then DATABASE_USER=$SITE; fi

	read -s -p "Database user password: " DATABASE_USER_PASSWORD
	if [ -z "$DATABASE_USER_PASSWORD" ]; then DATABASE_USER_PASSWORD="mypassword"; fi
	echo -e "\r";

	while [ -z "$DATABASE_ADMIN" ]; do
		read -p "Database administrator name: " DATABASE_ADMIN
	done

	while [ -z "$DATABASE_ADMIN_PASSWORD" ]; do
		read -s -p "Database administrator password: " DATABASE_ADMIN_PASSWORD
		echo -e "\r";
	done

	read -p "Host: " HOST 
	if [ -z "$HOST" ]; then HOST="127.0.0.1"; fi

	#directories
	ROOT=/var/www/$SITE;
	DEFAULT=$ROOT/web/sites/default
	FILES=$DEFAULT/files

	#files
	SETTINGS=$DEFAULT/settings.php
	SERVICES=$DEFAULT/services.yml
	POST_INSTALL=$ROOT/scripts/composer/post-install.sh
	SITE_CONF=$SITES_AVAILABLE/$SITE.conf
	
	#update distribution
	apt-get -y update && -y apt-get upgrade

	#install mysql database
	debconf-set-selections <<< "mysql-server mysql-server/root_password password $DATABASE_ADMIN_PASSWORD"
	debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $DATABASE_ADMIN_PASSWORD"
	apt-get -y install mysql-server mysql-client

	#install apache web server
	apt-get install apache2

	#install php
	apt-get install php5 php5-mysql libapache2-mod-php5

	#restrict access to localhost
	replace "Listen 80" "Listen $HOST:80" -- "$PORTS"

	#create apache site configuration
	cp $PWD/SITE.conf $SITE_CONF
	replace "SITE" "$SITE" -- "$SITE_CONF"

	#make site accessible from address bar through its name
	echo -e "\n$HOST	$SITE" >> "$HOSTS"

	#enable site
	a2ensite "$SITE"

	#reload apache web server configurations
	service apache2 reload

	#globally install composer
	curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer;

	#create project template
	apt-get -y install git;
	composer create-project drupal-composer/drupal-project:8.x-dev $ROOT --stability dev --no-interaction;

	#install drupal profile
	cd $ROOT
	composer install

	#install website
	cd $ROOT/web
	../vendor/bin/drush -y site-install  --site-name="$SITE" --account-name="$SITE_ADMIN" --account-pass="$SITE_ADMIN_PASSWORD" --account-mail="$SITE_ADMIN_EMAIL" --site-mail="$SITE_ADMIN_EMAIL" --db-su="$DATABASE_ADMIN" --db-su-pw="$DATABASE_ADMIN_PASSWORD" --db-url=mysql://"$DATABASE_USER":"$DATABASE_USER_PASSWORD"@"$HOST"/"$DATABASE";

	#set trusted host pattern
	echo -e "\$settings['trusted_host_patterns'] = array('^$SITE$',);" >> $SETTINGS

	#secure settings.php file
	chmod 444 $SETTINGS

	#secure services.php file
	chmod 444 $SERVICES

	#make files directory globally writable
	chmod -R 777 $FILES

}

function removeAll {
	#settings
	while [ -z "$SITE" ]; do
		read -p "Site name: " SITE
	done

	while [ -z "$DATABASE" ]; do
		read -p "Database name: " DATABASE
	done

	while [ -z "$DATABASE_USER" ]; do
		read -p "Database user name: " DATABASE_USER
	done

	while [ -z "$DATABASE_ADMIN" ]; do
		read -p "Database administrator name: " DATABASE_ADMIN
	done

	while [ -z "$DATABASE_ADMIN_PASSWORD" ]; do
		read -s -p "Database administrator password: " DATABASE_ADMIN_PASSWORD
		echo -e "\r";
	done

	read -p "Host: " HOST 
	if [ -z "$HOST" ]; then HOST="127.0.0.1"; fi

	#directories
	ROOT=/var/www/$SITE;

	#remove mysql user and database
	mysql --user="$DATABASE_ADMIN" --password="$DATABASE_ADMIN_PASSWORD" --execute="DROP USER $DATABASE_USER@'%'; DROP DATABASE $DATABASE;";

	#disable site
	a2dissite "$SITE"

	#remove apache site configuration
	rm $SITES_AVAILABLE/$SITE.conf

	#make site unaccessible from address bar through its name
	replace "$HOST	$SITE" "" -- "$HOSTS"

	#reload apache web server configurations
	service apache2 reload

	#remove project
	rm -r $ROOT;	

}

echo -e "Please enter..."

case "$1" in
	install)
		installAll
		;;
	remove)
		removeAll
		;;
esac
