# DOSUE
Docker compose SUper Express deployment tool

## INSTALL
```
curl -L -o /usr/local/bin/dosue https://github.com/garicchi/dosue/releases/download/1.1/dosue.sh&&chmod u+x /usr/local/bin/dosue
```

## UNINSTALL
```
rm /usr/local/bin/dosue
```

## REQUIREMENTS
- `aws` command and login using `aws configure`
- enable ssh access to remote server and run `ssh-add <key>` with ssh-agent
- enable to run `docker` and `docker-compose` command in remote server by normal user

## DEPLOY CONTAINER

```
cd <path to docker-compose.yml dir>

# push image to registory
docker-compose push

# deploy container
dosue -s <user@host> deploy
```
