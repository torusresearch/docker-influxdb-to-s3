FROM influxdb:latest
MAINTAINER Kanishka <kanishkatn@gmail.com>

# Install system dependancies
RUN apk add --no-cache bash py-pip && rm -rf /var/cache/apk/*

# Install aws cli
RUN pip --no-cache-dir install awscli

COPY influxdb-to-s3.sh /usr/bin/influxdb-to-s3

ENTRYPOINT ["/usr/bin/influxdb-to-s3"]
CMD ["cron", "0 1 * * *"]
