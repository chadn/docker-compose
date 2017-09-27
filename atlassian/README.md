# Atlassian Apps: Jira, Bitbucket, etc

## Summary

The goal of this docker-compose.yml file is to easily manage several atlassian applications.  You will need

- Machine set up to run dockers (tested on linux)
- Web server to be used as reverse proxy (apache in this example, or nginx)
- Experience with Jira and Bitbucket setup (optional)

When done, you will have your own local running versions of Jira software (Jira core + agile) and Bitbucket server. Optionally you can runa second copy of Jira and  for testing plugins, updates, etc.  

Note Jira is free for 30 days, then to continue you pay $10 once for Jira, $10 for Bitbucket, which covers up to 10 users.

## Background

Previously I had to use github.com to view my private repositories from a web browser. Now I can easily accomplish that using this setup instead.  I use Jira, Bitbucket, and Postgres db, but you could easily add confluence and bamboo to this list.

Initial setup of Jira and Bitbucket can take some time if you've never done it before.  But if you have experience with that, this should be easy.  Once configured, this is an extremely portable setup.  All containers can talk to each other, and its easy to bring the whole thing up and down for backups, restores, testing upgrades, etc. 


## Initial Docker Setup

You will need to edit [.env](.env) and optionally [test/.env](test/.env) files so they contain your domain names, ports that match your apache setup, etc.  

```
git clone https://github.com/chadn/docker-compose
cd docker-compose/atlassian
vi .env
vi test/.env
docker-compose up -d
```
If you haven't configured reverse proxy yet, do that now - see my notes below.  Then go to your browser to complete the setup of jira and bitbucket.  Remember to set up jira with postgres db.

You can verify the services started ok using `docker-compose logs | grep <service-name>`.  For example, to make sure there were no errors in jira, you can do `docker-compose logs | grep jira7 | grep ERROR`.  Or here's an example of checking jira db 

```
[13:36 root@server atlassian] > docker-compose logs |grep jiradb
Attaching to prod_bitbucket5, prod_jira7, prod_jiradb
prod_jiradb   | LOG:  database system was shut down at 2017-09-09 17:06:24 UTC
prod_jiradb   | LOG:  MultiXact member wraparound protections are now enabled
prod_jiradb   | LOG:  database system is ready to accept connections
prod_jiradb   | LOG:  autovacuum launcher started
prod_jira7    |          Database URL                                  : jdbc:postgresql://192.168.1.1:55432/jiradb
prod_jira7    |          Database JDBC config                          : postgres72 jdbc:postgresql://192.168.1.1:55432/jiradb
```

## Reverse Proxy, domains, and SSL certificates

I already have apache set up with ssl certificates, so I'm using that - more details on that setup in my [Apache and Jira dockers](https://chadnorwood.com/2017/09/08/apache-virtual-hosts-https-and-jira-docker-containers/) post.   

If you prefer a docker-compose that includes a service for proxy and certs, you can look at [this idalko docker-builder post](https://idalko.com/atlassian-jira-upgrade-journey-using-docker-and-the-atlassian-docker-builder/). I attempted this, but had some errors while trying to build the atlassian containers using [atlassian-docker-builder](https://bitbucket.org/adockers/atlassian-docker-builder/overview).

Examples from my Apache conf files

```
> grep sites-enabled /etc/apache2/apache2.conf
IncludeOptional sites-enabled/*.conf
```

```
> cat /etc/apache2/sites-enabled/jira.example.com.conf
<IfModule mod_ssl.c>

<VirtualHost *:443>
  ServerName jira.example.com
  ServerAlias j.example.com
  Include conf-available/vhosts-logging.conf
  Include conf-available/certbot.example.com.conf 
  <Proxy *>
      Order allow,deny
      Allow from all
  </Proxy>
  ProxyRequests Off
  ProxyPreserveHost On
  ProxyPass        / http://127.0.0.1:8080/
  ProxyPassReverse / http://127.0.0.1:8080/
</VirtualHost>

<VirtualHost *:443>
  ServerName test-jira.example.com
  Include conf-available/vhosts-logging.conf
  Include conf-available/certbot.example.com.conf 
  <Proxy *>
      Order allow,deny
      Allow from all
  </Proxy>
  ProxyRequests Off
  ProxyPreserveHost On
  ProxyPass        / http://127.0.0.1:18080/
  ProxyPassReverse / http://127.0.0.1:18080/
</VirtualHost>
</IfModule>
```

```
> cat /etc/apache2/sites-enabled/000-default.conf
<VirtualHost *:80>

 DocumentRoot /var/www/html
 Include conf-available/vhost.logging.conf

 # Redirect http (port 80) to https (port 443)
 RewriteEngine on
 RewriteCond "%{SERVER_NAME}" ".*\.example.com$" [OR]
 RewriteCond %{SERVER_NAME} =example.com
 RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,QSA,R=permanent]

</VirtualHost> 
```

```
> cat /etc/apache2/conf-available/certbot.example.com.conf
# added by certbot-auto
SSLCertificateFile /etc/letsencrypt/live/example.com/fullchain.pem
SSLCertificateKeyFile /etc/letsencrypt/live/example.com/privkey.pem
Include /etc/letsencrypt/options-ssl-apache.conf
```
```
> cat /etc/apache2/conf-available/vhost.logging.conf
LogFormat "%{Host}i:%p %h %l %u [%{%d/%b/%Y %T}t.%{msec_frac}t %{%z}t] %{us}T \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\"" vhost_combined2
CustomLog ${APACHE_LOG_DIR}/access.vhosts.log vhost_combined2
ErrorLog ${APACHE_LOG_DIR}/error.log
```

## Test Setup

Optionally you can set up test dockers as well, but since it is trivial to do, it is best to do it while setting up everything else.  You don't need to use the test setup until you've completely set up the prod docker containers - prod is the prefix name in the [.env](.env) file, short for production. 

The included [dc_utils.sh](dc_utils.sh) script will backup the prod docker containers to test docker containers, using the data in [test/.env](test/.env) file. It can be run as much as you want, but best to run it for the first time once the prod containers are set up and working fine. This backup will give your test environment a copy of your current jira project and issues, great for testing against your actual data. 

For example, to test the latest Jira version, first run `dc_utils.sh backup`, then check the latest jira version available to the docker container by looking at [atlassian-jira-software tags](https://hub.docker.com/r/cptactionhank/atlassian-jira-software/tags/), edit test/docker-compose.yml to use that tag, then in test directory run `docker-compose down` then `docker-compose up -d`.

Here's an example output
```
[16:14 root@server docker-compose\atlassian] > time ./dc_utils.sh backup
Stopping all docker containers, replacing all test dockers.
Backup now (y/n)? y
Proceding ...
Stopping test_bitbucket5 ... done
Stopping test_jira7 ... done
Stopping test_jiradb ... done
Removing test_bitbucket5 ... done
Removing test_jira7 ... done
Removing test_jiradb ... done
Removing network test_jira
Stopping prod_bitbucket5 ... done
Stopping prod_jira7 ... done
Stopping prod_jiradb ... done
Removing prod_bitbucket5 ... done
Removing prod_jira7 ... done
Removing prod_jiradb ... done
Removing network atlassian_jira_network
Creating network "atlassian_jira_network" with the default driver
Creating prod_jiradb
Changing jira-home/dbconfig.xml to use jiradb IP: 172.19.0.2:5432
prod_jiradb is up-to-date
Creating prod_jira7
Creating prod_bitbucket5
Creating network "test_jira_network" with the default driver
Creating test_jiradb
Changing jira-home/dbconfig.xml to use jiradb IP: 172.20.0.2:5432
test_jiradb is up-to-date
Creating test_jira7
Creating test_bitbucket5
CONTAINER ID        IMAGE                                         COMMAND                  CREATED             STATUS                     PORTS                                              NAMES
77b644716310        atlassian/bitbucket-server:5.2                "/usr/local/bin/du..."   1 second ago        Up Less than a second      0.0.0.0:17990->7990/tcp, 0.0.0.0:17999->7999/tcp   test_bitbucket5
6c3357bbbbee        cptactionhank/atlassian-jira-software:7.5.0   "/docker-entrypoin..."   2 seconds ago       Up Less than a second      0.0.0.0:18080->8080/tcp                            test_jira7
009055daff20        postgres:9.4                                  "/docker-entrypoin..."   2 seconds ago       Up 1 second                0.0.0.0:15432->5432/tcp                            test_jiradb
a078d6af7ea9        atlassian/bitbucket-server:5.2                "/usr/local/bin/du..."   3 seconds ago       Up 2 seconds               0.0.0.0:7990->7990/tcp, 0.0.0.0:7999->7999/tcp     prod_bitbucket5
c2fb800e7998        cptactionhank/atlassian-jira-software:7.4.4   "/docker-entrypoin..."   3 seconds ago       Up 2 seconds               0.0.0.0:8080->8080/tcp                             prod_jira7
10a6bfc5278b        postgres:9.4                                  "/docker-entrypoin..."   4 seconds ago       Up 2 seconds               0.0.0.0:55432->5432/tcp                            prod_jiradb
8659ee435978        cptactionhank/atlassian-jira-software:7.3.4   "/docker-entrypoin..."   4 months ago        Exited (137) 5 days ago                                                       jira-software
3d7759a45501        hello-world                                   "/hello"                 10 months ago       Exited (0) 10 months ago                                                      silly_hawking

Don't forget to change test GIT Base URL in admin settings as well as update any application links
https://test-jira.example.com/secure/admin/ViewApplicationProperties.jspa
https://test-git.example.com/admin/server-settings
https://test-git.example.com/plugins/servlet/applinks/listApplicationLinks
https://test-jira.example.com/plugins/servlet/applinks/listApplicationLinks

real 27.789 user 1.384  sys 1.704 pcpu 11.11
```

