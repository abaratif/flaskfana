## InfluxDB

# docker run -p 8083:8083 -p 8086:8086 \
# --expose 8090 --expose 8099 \
# -v influxdb:/var/lib/influxdb \
# -e PRE_CREATE_DB=telegraf \
# --name influxdb \
#  influxdb:0.13

# Run the app image that includes telegraf
docker build -t flaskfana_image . 
docker run -p 80:80 -p 8125:8125 -t -d --link=influxdb:influxsrv --name flaskfana_container  flaskfana_image

## Run the Grafana image

docker run -d -p 3000:3000 \
-e HTTP_USER=admin \
-e HTTP_PASS=admin \
-e INFLUXDB_HOST=influxsrv \
-e INFLUXDB_PORT=8086 \
-e INFLUXDB_NAME=telegraf \
-e INFLUXDB_USER=root \
-e INFLUXDB_PASS=root \
--link=influxdb:influxsrv  \
--name grafana \
grafana/grafana:4.2.0