# Atlassian Apps: Jira, Bitbucket, etc

## Summary

The goal of this docker-compose.yml file is to easily manage several atlassian applications.  You will need

- Machine setup to run dockers (tested on linux)
- Web server to be used as reverse proxy (apache, nginx)
- Experience with JIRA and Bitbucket setup (optional)

## Background

Previously I had to use github.com to view my private repositories from a web browser. Now I can easily fire up this setup.  I use jira, bitbucket, and postgres db, but you could easily add confluence and bamboo to this list.

Initial setup of Jira and Bitbucket can take some time if you've never done it before.  But if you have experience with that, this should be easy.  Once configured, this is an extremely portable setup.  All containers can talking to each other, and its easy to bring the whole thing up and down for backups, restores, testing upgrades, etc. 

## Reverse Proxy, domains, and SSL certificates

I already have apache setup with ssl certificates, so I'm using that - more details on that setup in my [Apache and JIRA dockers](https://chadnorwood.com/2017/09/08/apache-virtual-hosts-https-and-jira-docker-containers/) post.   

If you prefer a docker-compose that includes a proxy and certs, you can look at [this idalko docker-builder post](https://idalko.com/atlassian-jira-upgrade-journey-using-docker-and-the-atlassian-docker-builder/). I attempted this, but had some errors while trying to build the atlassian containers using [atlassian-docker-builder](https://bitbucket.org/adockers/atlassian-docker-builder/overview).

## Initial Setup

You will need to replace .example.com in the docker-compose.yml file with your domain.  

Optionally you can map ports differently, as long as they match what's defined in your reverse proxy.  For example, before I upgrade to latest JIRA, I take down my existing setup for a minute while I do a backup.  Then I copy it, change domain name and ports in yml, and fire it back up.

```
cd mydockers/atlassian; 
docker-compose stop
tar cvfz ../atlassian.dockers.`date "+%Y-%m-%d"`.tgz *
docker-compose up -d

mkdir ../atlassian.test; cd ../atlassian.test
tar xvfz ../atlassian.dockers.`date "+%Y-%m-%d"`.tgz
vi docker-compose.yml
docker-compose up -d
```

