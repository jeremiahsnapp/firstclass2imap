
# be sure to run this script using 'sudo'

# Ubuntu - install perl modules needed for the migration script
apt-get -y install liblist-compare-perl libhash-case-perl libdate-manip-perl libemail-send-perl libnet-smtp-ssl-perl libobject-realize-later-perl libmail-box-perl libmail-imapclient-perl libmime-types-perl libtimedate-perl libyaml-tiny-perl

# Install tools useful for testing and management of the migration
apt-get -y install vim tmux tree mutt cyrus-clients-2.2 git-core

#--------------------------------------------------------------------------

# install postfix
apt-get -y install postfix
# choose "Internet Site" for Postfix Configuration
# set "System mail name": migrate.schoolname.edu

ufw allow Postfix

# configure postfix
postconf -e 'home_mailbox = Maildir/'
postconf -e 'mailbox_size_limit = 512000000'
postconf -e 'message_size_limit = 102400000'

/etc/init.d/postfix reload

#--------------------------------------------------------------------------

# create a "migrate" user who's mailbox will be used to send and receive scripted migration emails
useradd -m -s /bin/bash migrate


# This will put all of the code into /home/migrate/firstclass2imap/
su -l -c 'git clone https://github.com/jeremiahsnapp/firstclass2imap.git' migrate

# configure git for the migrate user
su -l -c 'git config --global user.email "migrate@tngoogle.com"' migrate
su -l -c 'git config --global user.name "migrate"' migrate


# patch the perl List::Compare module so it can do case insensitive comparisons
apt-get -y install patch
patch -b -d /usr/share/perl5/List/ < /home/migrate/firstclass2imap/SETUP/list_compare_case_insensitive.patch


# create links to some migration management tools
ln -s /home/migrate/firstclass2imap/tools/ilog /usr/local/bin/ilog
ln -s /home/migrate/firstclass2imap/tools/killinstance /usr/local/bin/killinstance
ln -s /home/migrate/firstclass2imap/tools/pmigrate /usr/local/bin/pmigrate
ln -s /home/migrate/firstclass2imap/tools/ulog /usr/local/bin/ulog


# create a place to store migration logs
mkdir /var/log/migration
chown -R migrate:adm /var/log/migration


# make the necessary folders for filtered email
# the rest of the maildir folders will get automatically created by procmail as email is filtered into them
mkdir -p /home/migrate/Maildir/{cur,new,tmp}
chown -R migrate:migrate /home/migrate/Maildir/
chmod -R 700 /home/migrate/Maildir/


# install procmail
apt-get -y install procmail


# forward all email sent to "migrate@migrate.schoolname.edu" to procmail for further processing
cat <<EOF /home/migrate/.forward
|/usr/bin/procmail
EOF


# create a .procmailrc file for the migrate user that will filter email into appropriate folders
cat <<EOF /home/migrate/.procmailrc
##Begin Filter Configuration

LOGFILE=\$HOME/.procmail.log
DEFAULT=\$HOME/Maildir/

# Default mail directory
MAILDIR=\$HOME/Maildir/

:0
* ^Return-Path: <migrate@migrate.schoolname.edu>
{
        :0
        * ^Subject:.*BA Migrate Script 1:
        .ba_sent_1/

        :0
        * ^Subject:.*BA Migrate Script 2:
        .ba_sent_2/

        :0
        * ^Subject:.*BA Migrate Script 3:
        .ba_sent_3/

        :0
        * ^Subject:.*BA Migrate Script 4:
        .ba_sent_4/

        :0
        * ^Subject:.*BA Migrate Script 5:
        .ba_sent_5/

        :0
        * ^Subject:.*BA Migrate Script 6:
        .ba_sent_6/

        :0
        * ^Subject:.*BA Migrate Script 7:
        .ba_sent_7/

        :0
        * ^Subject:.*BA Migrate Script 8:
        .ba_sent_8/

        :0
        * ^Subject:.*BA Migrate Script Usermap:
        .build_usermap_sent/

        :0
        * ^Subject:.*BA Migrate Script switched_user:
        .switched_user_sent/
}

:0
* ^Return-Path: <administrator@schoolname.edu>
{
        :0
        * ^Subject:.*BA Migrate Script 1:
        .ba_rcvd_1/

        :0
        * ^Subject:.*BA Migrate Script 2:
        .ba_rcvd_2/

        :0
        * ^Subject:.*BA Migrate Script 3:
        .ba_rcvd_3/

        :0
        * ^Subject:.*BA Migrate Script 4:
        .ba_rcvd_4/

        :0
        * ^Subject:.*BA Migrate Script 5:
        .ba_rcvd_5/

        :0
        * ^Subject:.*BA Migrate Script 6:
        .ba_rcvd_6/

        :0
        * ^Subject:.*BA Migrate Script 7:
        .ba_rcvd_7/

        :0
        * ^Subject:.*BA Migrate Script 8:
        .ba_rcvd_8/

        :0
        * ^Subject:.*BA Migrate Script Usermap:
        .build_usermap_rcvd/

        :0
        * ^Subject:.*BA Migrate Script switched_user:
        .switched_user_rcvd/
}

##End Filter Configuration
EOF

#--------------------------------------------------------------------------

# create a .muttrc file for the migrate user

cat <<EOF /home/migrate/.muttrc
# reference: http://wiki.mutt.org/?MuttFaq/Maildir
/home/migrate/.muttrc
set read_only
set mail_check = 10

set realname =
set from = "migrate@schoolname.edu"
set use_from = yes
set use_envelope_from = yes

set mbox_type=Maildir

set spoolfile="/home/migrate/Maildir/"
set folder="/home/migrate/Maildir"
set mask="!^\\.[^.]"
set record="+.Sent"
set postponed="+.Drafts"

mailboxes ! + `\
for file in /home/migrate/Maildir/.*; do \
   box=\$(basename "\$file"); \
   if [ ! "\$box" = '.' -a ! "\$box" = '..' -a ! "\$box" = '.customflags' \
       -a ! "\$box" = '.subscriptions' ]; then \
     echo -n "\"+\$box\" "; \
   fi; \
done`

macro index c "<change-folder>?<toggle-mailboxes>" "open a different folder"
macro pager c "<change-folder>?<toggle-mailboxes>" "open a different folder"
macro index C "<copy-message>?<toggle-mailboxes>" "copy a message to a mailbox"
macro index M "<save-message>?<toggle-mailboxes>" "move a message to a mailbox"
EOF

#--------------------------------------------------------------------------

# set proper ownership on everything in the migrate user's home directory
chown -R migrate:migrate /home/migrate

echo if this is the first or the only migration server then be sure to
echo also run the setup_database.sh script to create a master database
