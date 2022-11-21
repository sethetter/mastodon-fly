## Mastodon on fly.io

[Mastodon](https://github.com/mastodon/mastodon) is a free, open-source social
network server based on ActivityPub.

The Mastodon server is implemented a rails app, which relies on postgres and
redis. It uses sidekiq for background jobs, along with a separate nodejs http
streaming server.

Docker images: https://hub.docker.com/r/tootsuite/mastodon/

Dockerfile: https://github.com/mastodon/mastodon/blob/main/Dockerfile

docker-compose.yml:
https://github.com/mastodon/mastodon/blob/main/docker-compose.yml

### Setup

Decide what your app name will be, and what region you'll deploy to

```
$ export APP_NAME=my-mastodon-instance
$ export REGION=ord
```

#### App

```
$ fly apps create --region $REGION --name $APP_NAME
$ fly scale memory 512 # rails needs more than 256mb
```

#### Secrets

```
$ SECRET_KEY_BASE=$(docker run --rm -it tootsuite/mastodon:latest bin/rake secret)
$ OTP_SECRET=$(docker run --rm -it tootsuite/mastodon:latest bin/rake secret)
$ fly secrets set OTP_SECRET=$OTP_SECRET SECRET_KEY_BASE=$SECRET_KEY_BASE
$ docker run --rm -e OTP_SECRET=$OTP_SECRET -e SECRET_KEY_BASE=$SECRET_KEY_BASE -it tootsuite/mastodon:latest bin/rake mastodon:webpush:generate_vapid_key | fly secrets import
```

#### Redis server

Redis is used to store the home/list feeds, along with the sidekiq queue
information. The feeds can be regenerated using `tootctl`, so persistence is
[not strictly necessary](https://docs.joinmastodon.org/admin/backups/#failure).

```
$ fly apps create --name $APP_NAME-redis
$ fly volumes create -c fly.redis.toml mastodon_redis
$ fly deploy -c fly.redis.toml --build-target redis-server
```

#### Storage (user uploaded photos and videos)

The `fly.toml` uses a `[mounts]` section to connect the
`/opt/mastodon/public/system` folder to a persistent volume.

Create that volume below, or remove the `[mounts]` section and uncomment
`[env] > S3_ENABLED` for S3 storage.

##### Option 1: Local volume

```
$ fly volumes create --region $REGION mastodon_uploads
```

##### Option 2: S3, etc

You can use the `terraform/` folder to provision a user and S3 bucket for this
step.

```
$ cd terraform
$ terraform init
$ terraform apply
```

Then create an access key for that user.

```
$ aws iam create-access-key --username sethetter-social
```

Use the values from the output of the above command to set the AWS credentials
in fly.

```
$ fly secrets set AWS_ACCESS_KEY_ID=xxx AWS_SECRET_ACCESS_KEY=yyy
```

See
[lib/tasks/mastodon.rake](https://github.com/mastodon/mastodon/blob/5ba46952af87e42a64962a34f7ec43bc710bdcaf/lib/tasks/mastodon.rake#L137)
for how to change your `[env]` section for Wasabi, Minio or Google Cloud
Storage.

#### Postgres database

```
$ fly pg create --region $REGION --name $APP_NAME-pg
$ fly pg attach --postgres-app $APP_NAME-pg
$ fly deploy -c fly.setup.toml # run `rails db:setup`
```

### Deploy

```
$ fly deploy
```
