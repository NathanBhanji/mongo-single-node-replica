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
