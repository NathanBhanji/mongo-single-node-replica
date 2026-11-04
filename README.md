# MongoDB single node replica set (for local development / testing)

## Maintained by: [Nathan Bhanji](https://github.com/NathanBhanji)

This is a `FORK` of the Git repo of the [Docker "Official Image"](https://github.com/docker-library/official-images#what-are-official-images) for [`mongo`](https://hub.docker.com/_/mongo/) (not to be confused with any official `mongo` image provided by `mongo` upstream) or the Docker Official Image itself.

The usage of this image is the same as the official image, but with one additional argument:

`MONGO_REPLICA_SET_NAME` - This is the name of the replica set to be created. If not specified, no replica set will be created.

This will create a single node replica set with the specified name. The replica set will only be accessible on the docker network.

If you want to connect to the replica set from outside the docker network, you can use the `docker run` command with the `--network=host` option to put the container on the host network.

Or if you're on mac you can use the `directConnection=true` option to connect directly to the database if you absolutely must.

The latest images can be found [here](https://hub.docker.com/r/bhanji/mongo-single-node-replica/tags?name=latest)

Support for this image is not guaranteed. It is a personal project of mine.

Architectures:
- `amd64`
- `arm64`

I do not plan on adding support for windows. It *should* be easy to do this with the official images.

## Replica-set authentication

Replica-set containers generate a private internal-authentication key on first
startup at `<dbPath>/.replica-set-keyfile`. Keep the database volume across
container replacements; the key is reused on restart. An explicit `--keyFile`
(or `security.keyFile` in the configuration file) uses your supplied key instead.
The image no longer includes a shared key.

Set both `MONGO_INITDB_ROOT_USERNAME` and `MONGO_INITDB_ROOT_PASSWORD` when
initializing a replica set with database initialization scripts. Initialization
keeps access control enabled, creates the first root user through the localhost
exception, and runs subsequent initialization scripts with root authentication.
Ordinary, non-replica initialization remains bound to loopback until complete.

Existing single-node database volumes keep their users and data. The first
startup with this change generates an internal key if one has not been saved;
there is no automatic change to user passwords. Deployments that explicitly
supply an internal key retain it. This image is intended for single-node sets;
do not use automatic per-volume keys to join multiple members.
